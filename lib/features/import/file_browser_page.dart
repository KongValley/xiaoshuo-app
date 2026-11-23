import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../core/formatters.dart';
import '../../core/theme.dart';

/// A self-contained local file browser used for importing TXT novels.
///
/// The app intentionally has no native file-picker plugin, so it ships this
/// small browser. It supports multiple selection across folders, direct path
/// entry, quick-access locations and double-click import.
class FileBrowserPage extends StatefulWidget {
  const FileBrowserPage({super.key, this.initialDirectory});

  final String? initialDirectory;

  @override
  State<FileBrowserPage> createState() => _FileBrowserPageState();
}

class _FileBrowserPageState extends State<FileBrowserPage> {
  static const Set<String> _hiddenFolderNames = {
    r'$RECYCLE.BIN',
    'System Volume Information',
    'Recovery',
    'Config.Msi',
    'Documents and Settings',
  };

  final TextEditingController _pathController = TextEditingController();
  final Set<String> _selected = <String>{};
  final List<String> _history = <String>[];
  final List<_QuickLink> _quickLinks = [];
  final List<String> _drives = [];

  Directory? _current;
  List<Directory> _folders = const [];
  List<_FileEntry> _files = const [];
  bool _loading = true;
  String? _error;
  int _loadToken = 0;

  @override
  void initState() {
    super.initState();
    _buildLocations();
    final initial = _resolveInitialDirectory();
    _load(initial, pushHistory: false);
  }

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  void _buildLocations() {
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        '';
    final candidates = <_QuickLink>[
      if (Platform.isWindows)
        _QuickLink('桌面', p.join(home, 'Desktop'), Icons.desktop_windows_outlined),
      if (Platform.isWindows)
        _QuickLink('文档', p.join(home, 'Documents'), Icons.description_outlined),
      if (Platform.isWindows)
        _QuickLink('下载', p.join(home, 'Downloads'), Icons.download_outlined),
      if (Platform.isMacOS)
        _QuickLink('桌面', p.join(home, 'Desktop'), Icons.desktop_mac_outlined),
      if (Platform.isMacOS)
        _QuickLink('文稿', p.join(home, 'Documents'), Icons.description_outlined),
      if (Platform.isMacOS)
        _QuickLink('下载', p.join(home, 'Downloads'), Icons.download_outlined),
      if (Platform.isLinux)
        _QuickLink('桌面', p.join(home, 'Desktop'), Icons.desktop_windows_outlined),
      if (Platform.isLinux)
        _QuickLink('文档', p.join(home, 'Documents'), Icons.description_outlined),
      if (Platform.isLinux)
        _QuickLink('下载', p.join(home, 'Downloads'), Icons.download_outlined),
      if (home.isNotEmpty)
        _QuickLink('主目录', home, Icons.home_outlined),
      if (Platform.isAndroid) ...[
        const _QuickLink('内部存储', '/storage/emulated/0', Icons.smartphone_outlined),
        const _QuickLink(
          '下载',
          '/storage/emulated/0/Download',
          Icons.download_outlined,
        ),
      ],
    ];
    final seen = <String>{};
    for (final link in candidates) {
      if (link.path.isEmpty) continue;
      final normalized = p.normalize(link.path);
      if (!seen.add(normalized)) continue;
      if (Directory(normalized).existsSync()) {
        _quickLinks.add(_QuickLink(link.label, normalized, link.icon));
      }
    }

    if (Platform.isWindows) {
      for (var code = 0x43; code <= 0x5A; code++) {
        final root = '${String.fromCharCode(code)}:\\';
        if (Directory(root).existsSync()) _drives.add(root);
      }
    } else {
      final root = Directory(p.separator).path;
      if (Directory(root).existsSync()) _drives.add(root);
    }
  }

  Directory _resolveInitialDirectory() {
    final initial = widget.initialDirectory;
    if (initial != null && initial.trim().isNotEmpty) {
      final dir = Directory(initial.trim());
      if (dir.existsSync()) return dir;
    }
    for (final link in _quickLinks) {
      final dir = Directory(link.path);
      if (dir.existsSync()) return dir;
    }
    for (final drive in _drives) {
      final dir = Directory(drive);
      if (dir.existsSync()) return dir;
    }
    return Directory.current;
  }

  Future<void> _load(Directory dir, {bool pushHistory = true}) async {
    final token = ++_loadToken;
    if (pushHistory && _current != null && _current!.path != dir.path) {
      _history.add(_current!.path);
    }
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final entities = await dir.list(followLinks: false).toList();
      if (!mounted || token != _loadToken) return;
      final folders = <Directory>[];
      final files = <_FileEntry>[];
      for (final entity in entities) {
        final name = p.basename(entity.path);
        if (name.isEmpty || name.startsWith('.') || _hiddenFolderNames.contains(name)) {
          continue;
        }
        if (entity is Directory) {
          folders.add(entity);
        } else if (entity is File && Fmt.isTxtFile(name)) {
          int size = 0;
          DateTime? modified;
          try {
            final stat = entity.statSync();
            size = stat.size;
            modified = stat.modified;
          } catch (_) {
            // Keep the file even if its stat fails.
          }
          files.add(_FileEntry(entity, size, modified));
        }
      }
      folders.sort(
        (a, b) => p.basename(a.path).toLowerCase().compareTo(
              p.basename(b.path).toLowerCase(),
            ),
      );
      files.sort(
        (a, b) => p.basename(a.file.path).toLowerCase().compareTo(
              p.basename(b.file.path).toLowerCase(),
            ),
      );
      if (!mounted || token != _loadToken) return;
      setState(() {
        _current = dir;
        _folders = folders;
        _files = files;
        _loading = false;
        _pathController.text = dir.path;
        _pathController.selection = TextSelection.collapsed(
          offset: _pathController.text.length,
        );
      });
    } catch (error) {
      if (!mounted || token != _loadToken) return;
      setState(() {
        _current = dir;
        _loading = false;
        _error = error is FileSystemException
            ? '没有权限访问这个文件夹'
            : '无法读取这个文件夹';
        _pathController.text = dir.path;
      });
    }
  }

  void _goBack() {
    if (_history.isEmpty) return;
    final path = _history.removeLast();
    _load(Directory(path), pushHistory: false);
  }

  void _goUp() {
    final current = _current;
    if (current == null) return;
    final parent = current.parent;
    if (parent.path == current.path) return;
    _load(parent);
  }

  Future<void> _goPath(String rawValue) async {
    var value = rawValue.trim();
    if (value.length >= 2 &&
        ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'")))) {
      value = value.substring(1, value.length - 1).trim();
    }
    if (value.isEmpty) return;

    final file = File(value);
    if (await file.exists()) {
      if (!mounted) return;
      await _load(file.parent);
      if (!mounted) return;
      setState(() => _selected.add(file.path));
      return;
    }
    final dir = Directory(value);
    if (await dir.exists()) {
      if (!mounted) return;
      await _load(dir);
      return;
    }
    if (!mounted) return;
    setState(() => _error = '路径不存在：$value');
  }

  void _toggleSelection(File file) {
    setState(() {
      if (!_selected.add(file.path)) _selected.remove(file.path);
    });
  }

  void _finish(List<String> paths) {
    if (paths.isEmpty) return;
    Navigator.of(context).pop(paths);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = theme.extension<AppSurface>()!;

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (_selected.isNotEmpty) {
            setState(_selected.clear);
          } else {
            Navigator.of(context).maybePop();
          }
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: theme.scaffoldBackgroundColor,
          body: SafeArea(
            child: Column(
              children: [
                _buildHeader(theme, surface),
                _buildPathBar(theme, surface),
                Divider(height: 1, color: surface.hairline),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 900;
                      final body = _buildFileArea(theme, surface);
                      if (!wide) {
                        return Column(
                          children: [
                            _buildQuickChips(theme, surface),
                            Expanded(child: body),
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: 214,
                            child: _buildSidebar(theme, surface),
                          ),
                          VerticalDivider(width: 1, color: surface.hairline),
                          Expanded(child: body),
                        ],
                      );
                    },
                  ),
                ),
                _buildBottomBar(theme, surface),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, AppSurface surface) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 16, 10),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            tooltip: '返回书架',
            icon: Icon(Icons.close_rounded, color: theme.colorScheme.onSurface),
          ),
          const SizedBox(width: 4),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '导入 TXT',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '选择本地小说，支持一次导入多个文件',
                style: TextStyle(fontSize: 11.5, color: surface.muted),
              ),
            ],
          ),
          const Spacer(),
          if (_current != null)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Text(
                '仅显示 .txt 文件',
                style: TextStyle(fontSize: 11, color: surface.muted),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPathBar(ThemeData theme, AppSurface surface) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
      child: Row(
        children: [
          IconButton(
            onPressed: _history.isEmpty ? null : _goBack,
            tooltip: '后退',
            icon: const Icon(Icons.arrow_back_rounded, size: 20),
          ),
          IconButton(
            onPressed: _goUp,
            tooltip: '上一级',
            icon: const Icon(Icons.drive_folder_upload_outlined, size: 20),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: TextField(
              controller: _pathController,
              style: TextStyle(fontSize: 12.5, color: theme.colorScheme.onSurface),
              onSubmitted: _goPath,
              decoration: InputDecoration(
                isDense: true,
                hintText: '输入文件夹路径后回车',
                prefixIcon: Icon(
                  Icons.folder_open_rounded,
                  size: 18,
                  color: surface.muted,
                ),
                suffixIcon: IconButton(
                  tooltip: '跳转',
                  icon: Icon(
                    Icons.subdirectory_arrow_left_rounded,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  onPressed: () => _goPath(_pathController.text),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              ),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            onPressed: () {
              final current = _current;
              if (current != null) _load(current, pushHistory: false);
            },
            tooltip: '刷新',
            icon: const Icon(Icons.refresh_rounded, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar(ThemeData theme, AppSurface surface) {
    return Container(
      color: surface.tint.withValues(alpha: 0.35),
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Text(
              '快捷访问',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
                color: surface.muted,
              ),
            ),
          ),
          for (final link in _quickLinks)
            _QuickTile(
              link: link,
              currentPath: _current?.path,
              onTap: () => _load(Directory(link.path)),
            ),
          if (_drives.isNotEmpty) ...[
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(
                '磁盘',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                  color: surface.muted,
                ),
              ),
            ),
            for (final drive in _drives)
              _QuickTile(
                link: _QuickLink(drive, drive, Icons.storage_rounded),
                currentPath: _current?.path,
                onTap: () => _load(Directory(drive)),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildQuickChips(ThemeData theme, AppSurface surface) {
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
        children: [
          for (final link in _quickLinks)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ActionChip(
                avatar: Icon(link.icon, size: 15, color: surface.muted),
                label: Text(link.label),
                labelStyle: TextStyle(
                  fontSize: 11.5,
                  color: _current?.path == link.path
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface,
                ),
                backgroundColor: _current?.path == link.path
                    ? surface.tint
                    : surface.card,
                side: BorderSide(color: surface.hairline),
                onPressed: () => _load(Directory(link.path)),
              ),
            ),
          if (_drives.isNotEmpty)
            for (final drive in _drives)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ActionChip(
                  avatar: Icon(Icons.storage_rounded, size: 15, color: surface.muted),
                  label: Text(drive),
                  labelStyle: TextStyle(
                    fontSize: 11.5,
                    color: theme.colorScheme.onSurface,
                  ),
                  backgroundColor: surface.card,
                  side: BorderSide(color: surface.hairline),
                  onPressed: () => _load(Directory(drive)),
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildFileArea(ThemeData theme, AppSurface surface) {
    if (_loading) {
      return Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: theme.colorScheme.primary,
          ),
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.folder_off_outlined, size: 40, color: surface.muted),
              const SizedBox(height: 14),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: surface.muted),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  final current = _current;
                  if (current != null) _load(current, pushHistory: false);
                },
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    if (_folders.isEmpty && _files.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_open_rounded, size: 44, color: surface.muted),
            const SizedBox(height: 14),
            Text(
              '这个文件夹里没有 TXT 文件',
              style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface),
            ),
            const SizedBox(height: 6),
            Text(
              '可以返回上一级，或在左侧换一个位置',
              style: TextStyle(fontSize: 11.5, color: surface.muted),
            ),
          ],
        ),
      );
    }

    final total = _folders.length + _files.length;
    return Scrollbar(
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 8, 16, 20),
        itemCount: total,
        itemBuilder: (context, index) {
          if (index < _folders.length) {
            final folder = _folders[index];
            return _FolderTile(
              folder: folder,
              theme: theme,
              surface: surface,
              onTap: () => _load(folder),
            );
          }
          final entry = _files[index - _folders.length];
          final selected = _selected.contains(entry.file.path);
          return _FileTile(
            entry: entry,
            selected: selected,
            theme: theme,
            surface: surface,
            onTap: () => _toggleSelection(entry.file),
            onDoubleTap: () => _finish([entry.file.path]),
          );
        },
      ),
    );
  }

  Widget _buildBottomBar(ThemeData theme, AppSurface surface) {
    final count = _selected.length;
    final names = _selected.map((path) => p.basename(path)).join('、');
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      decoration: BoxDecoration(
        color: surface.card,
        border: Border(top: BorderSide(color: surface.hairline)),
      ),
      child: Row(
        children: [
          Icon(
            count > 0 ? Icons.check_circle_rounded : Icons.info_outline_rounded,
            size: 18,
            color: count > 0 ? theme.colorScheme.primary : surface.muted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Tooltip(
              message: names,
              waitDuration: const Duration(milliseconds: 700),
              child: Text(
                count > 0 ? '已选择 $count 个文件' : '请选择一个或多个 TXT 文件',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  color: count > 0
                      ? theme.colorScheme.onSurface
                      : surface.muted,
                ),
              ),
            ),
          ),
          if (count > 0)
            TextButton(
              onPressed: () => setState(_selected.clear),
              child: const Text('清空'),
            ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: count > 0 ? () => _finish(_selected.toList()) : null,
            icon: const Icon(Icons.download_done_rounded, size: 18),
            label: Text(count > 0 ? '导入 $count 个' : '导入'),
          ),
        ],
      ),
    );
  }
}

class _QuickLink {
  const _QuickLink(this.label, this.path, this.icon);

  final String label;
  final String path;
  final IconData icon;
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({
    required this.link,
    required this.currentPath,
    required this.onTap,
  });

  final _QuickLink link;
  final String? currentPath;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = theme.extension<AppSurface>()!;
    final active = currentPath == link.path;
    return Semantics(
      button: true,
      selected: active,
      label: '打开 ${link.label}',
      onTap: onTap,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
        child: Material(
          color: active
              ? theme.colorScheme.primary.withValues(alpha: 0.09)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(
                children: [
                  Icon(
                    link.icon,
                    size: 17,
                    color: active ? theme.colorScheme.primary : surface.muted,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      link.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                        color: active
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FileEntry {
  const _FileEntry(this.file, this.size, this.modified);

  final File file;
  final int size;
  final DateTime? modified;
}

class _FolderTile extends StatelessWidget {
  const _FolderTile({
    required this.folder,
    required this.theme,
    required this.surface,
    required this.onTap,
  });

  final Directory folder;
  final ThemeData theme;
  final AppSurface surface;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = p.basename(folder.path);
    return Semantics(
      button: true,
      label: '打开文件夹 ${name.isEmpty ? folder.path : name}',
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: surface.tint,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.folder_rounded,
                    size: 19,
                    color: theme.colorScheme.secondary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    name.isEmpty ? folder.path : name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 19,
                  color: surface.muted.withValues(alpha: 0.7),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FileTile extends StatelessWidget {
  const _FileTile({
    required this.entry,
    required this.selected,
    required this.theme,
    required this.surface,
    required this.onTap,
    required this.onDoubleTap,
  });

  final _FileEntry entry;
  final bool selected;
  final ThemeData theme;
  final AppSurface surface;
  final VoidCallback onTap;
  final VoidCallback onDoubleTap;

  @override
  Widget build(BuildContext context) {
    final name = p.basename(entry.file.path);
    final meta = <String>[
      Fmt.fileSize(entry.size),
      if (entry.modified != null) Fmt.date(entry.modified!),
    ].join('  ·  ');

    return Semantics(
      button: true,
      selected: selected,
      label: '${selected ? '取消选择' : '选择'} $name，$meta',
      onTap: onTap,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Material(
          color: selected
              ? theme.colorScheme.primary.withValues(alpha: 0.07)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: onTap,
            onDoubleTap: onDoubleTap,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: selected
                          ? theme.colorScheme.primary.withValues(alpha: 0.14)
                          : surface.tint,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.article_outlined,
                      size: 18,
                      color: selected
                          ? theme.colorScheme.primary
                          : surface.muted,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w500,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          meta,
                          style: TextStyle(fontSize: 10.5, color: surface.muted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 18,
                    color: selected
                        ? theme.colorScheme.primary
                        : surface.muted.withValues(alpha: 0.5),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
