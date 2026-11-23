import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/library_repository.dart';
import '../../data/models/book.dart';
import '../../data/settings_repository.dart';
import '../import/file_browser_page.dart';
import '../reader/reader_page.dart';
import 'book_card.dart';

class BookshelfPage extends StatefulWidget {
  const BookshelfPage({
    super.key,
    required this.library,
    required this.settings,
  });

  final LibraryRepository library;
  final SettingsRepository settings;

  @override
  State<BookshelfPage> createState() => _BookshelfPageState();
}

class _BookshelfPageState extends State<BookshelfPage> {
  late final Listenable _listenable;
  bool _importing = false;
  String _importStatus = '';
  double? _importProgress;

  @override
  void initState() {
    super.initState();
    _listenable = Listenable.merge([widget.library, widget.settings]);
  }

  List<Book> _sortedBooks() {
    final books = List<Book>.from(widget.library.books);
    switch (widget.settings.settings.bookSort) {
      case BookSort.recent:
        books.sort((a, b) => b.lastOpenedAt.compareTo(a.lastOpenedAt));
        break;
      case BookSort.imported:
        books.sort((a, b) => b.importedAt.compareTo(a.importedAt));
        break;
      case BookSort.title:
        books.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        break;
    }
    return books;
  }

  Future<void> _openImportBrowser() async {
    if (_importing) return;
    final paths = await Navigator.of(context).push<List<String>>(
      PageRouteBuilder<List<String>>(
        transitionDuration: const Duration(milliseconds: 260),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (context, animation, secondaryAnimation) => FileBrowserPage(
          initialDirectory: widget.settings.settings.lastImportDir,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.025),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
    if (!mounted || paths == null || paths.isEmpty) return;
    await _importFiles(paths);
  }

  Future<void> _importFiles(List<String> paths) async {
    setState(() {
      _importing = true;
      _importProgress = 0;
      _importStatus = paths.length == 1
          ? '正在解析 ${p.basename(paths.first)}'
          : '准备解析 ${paths.length} 个文件';
    });

    try {
      final summary = await widget.library.importPaths(
        paths,
        onProgress: (completed, total, fileName) {
          if (!mounted) return;
          setState(() {
            _importProgress = total == 0 ? null : completed / total;
            _importStatus = fileName.isEmpty
                ? '正在写入书库…'
                : '正在解析 $fileName';
          });
        },
      );
      if (!mounted) return;
      widget.settings.updateImportDir(p.dirname(paths.last));
      setState(() => _importing = false);

      if (summary.added.length == 1 && summary.failures.isEmpty && summary.skipped.isEmpty) {
        await Future<void>.delayed(const Duration(milliseconds: 180));
        if (!mounted) return;
        await _openBook(summary.added.first);
        return;
      }

      final parts = <String>[];
      if (summary.added.isNotEmpty) parts.add('已导入 ${summary.added.length} 本');
      if (summary.skipped.isNotEmpty) parts.add('${summary.skipped.length} 本已在书架');
      if (summary.failures.isNotEmpty) parts.add('${summary.failures.length} 个文件失败');
      if (parts.isNotEmpty) _showSnack(parts.join(' · '));

      if (summary.failures.isNotEmpty) {
        unawaited(_showFailures(summary.failures));
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _importing = false);
      _showSnack('导入失败：$error');
    }
  }

  Future<void> _openBook(Book book) async {
    final latest = widget.library.bookById(book.id) ?? book;
    await Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 300),
        reverseTransitionDuration: const Duration(milliseconds: 240),
        pageBuilder: (context, animation, secondaryAnimation) => ReaderPage(
          book: latest,
          library: widget.library,
          settingsRepo: widget.settings,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.988, end: 1).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }

  Future<void> _showBookInfo(Book book) async {
    final latest = widget.library.bookById(book.id) ?? book;
    final startReading = await showDialog<bool>(
      context: context,
      builder: (context) => _BookInfoDialog(
        book: latest,
        onRead: () => Navigator.of(context).pop(true),
      ),
    );
    if (startReading == true && mounted) {
      await _openBook(latest);
    }
  }

  Future<void> _confirmDelete(Book book) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return AlertDialog(
          backgroundColor: theme.colorScheme.surface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text('移出书架'),
          content: Text(
            '将从本地书库删除《${book.title}》及应用内的副本。\n原始 TXT 文件不会被删除。',
            style: const TextStyle(fontSize: 13.5, height: 1.6),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;
    await widget.library.deleteBook(book);
    if (!mounted) return;
    _showSnack('已将《${book.title}》移出书架');
  }

  Future<void> _showFailures(List<ImportFailure> failures) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) {
        final surface = Theme.of(context).extension<AppSurface>()!;
        return AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text('部分文件未能导入'),
          content: SizedBox(
            width: 440,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: failures.length,
                separatorBuilder: (context, index) =>
                    Divider(height: 16, color: surface.hairline),
                itemBuilder: (context, index) {
                  final failure = failures[index];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        failure.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        failure.message,
                        style: TextStyle(fontSize: 11.5, color: surface.muted),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('知道了'),
            ),
          ],
        );
      },
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _listenable,
      builder: (context, _) {
        final theme = Theme.of(context);
        final surface = theme.extension<AppSurface>()!;
        final books = _sortedBooks();
        final totalChars = books.fold<int>(0, (sum, book) => sum + book.charCount);
        final windowWidth = MediaQuery.sizeOf(context).width;
        final gridWidth = math.max(320.0, windowWidth - 52);
        final columns = (gridWidth / 232).floor().clamp(2, 7);

        return Scaffold(
          body: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [surface.canvasTop, surface.canvasBottom],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: -170,
                right: -110,
                child: IgnorePointer(
                  child: Container(
                    width: 440,
                    height: 440,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          theme.colorScheme.primary.withValues(alpha: 0.07),
                          theme.colorScheme.primary.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: _buildHeader(theme, surface, books, totalChars),
                    ),
                    if (books.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _EmptyShelf(
                          surface: surface,
                          onImport: _openImportBrowser,
                        ),
                      )
                    else ...[
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(26, 22, 26, 34),
                        sliver: SliverGrid(
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: columns,
                            mainAxisSpacing: 26,
                            crossAxisSpacing: 22,
                            childAspectRatio: 0.63,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final book = books[index];
                              return BookCard(
                                key: ValueKey(book.id),
                                book: book,
                                onOpen: () => _openBook(book),
                                onInfo: () => _showBookInfo(book),
                                onDelete: () => _confirmDelete(book),
                              );
                            },
                            childCount: books.length,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (_importing)
                Positioned.fill(
                  child: _ImportOverlay(
                    status: _importStatus,
                    progress: _importProgress,
                    surface: surface,
                    theme: theme,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(
    ThemeData theme,
    AppSurface surface,
    List<Book> books,
    int totalChars,
  ) {
    final currentSort = widget.settings.settings.bookSort;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 26, 28, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '书架',
                      style: AppTheme.serif(
                        36,
                        color: theme.colorScheme.onSurface,
                        letterSpacing: 1.5,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      books.isEmpty
                          ? '你的私人书库'
                          : '${books.length} 本藏书 · 共 ${Fmt.charCount(totalChars)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: surface.muted,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<BookSort>(
                tooltip: '排序',
                initialValue: currentSort,
                position: PopupMenuPosition.under,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                onSelected: widget.settings.updateSort,
                itemBuilder: (context) => [
                  for (final sort in BookSort.values)
                    PopupMenuItem<BookSort>(
                      value: sort,
                      child: Row(
                        children: [
                          Text(
                            sort.label,
                            style: TextStyle(
                              fontSize: 13,
                              color: sort == currentSort
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurface,
                            ),
                          ),
                          const Spacer(),
                          if (sort == currentSort)
                            Icon(
                              Icons.check_rounded,
                              size: 17,
                              color: theme.colorScheme.primary,
                            ),
                        ],
                      ),
                    ),
                ],
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: surface.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: surface.hairline),
                  ),
                  child: Icon(
                    Icons.swap_vert_rounded,
                    size: 19,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: _openImportBrowser,
                icon: const Icon(Icons.add_rounded, size: 19),
                label: const Text('导入 TXT'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Divider(height: 1, color: surface.hairline),
        ],
      ),
    );
  }
}

class _EmptyShelf extends StatelessWidget {
  const _EmptyShelf({required this.surface, required this.onImport});

  final AppSurface surface;
  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: surface.tint.withValues(alpha: 0.7),
                border: Border.all(color: surface.hairline),
              ),
              child: Icon(
                Icons.auto_stories_outlined,
                size: 40,
                color: theme.colorScheme.primary.withValues(alpha: 0.75),
              ),
            ),
            const SizedBox(height: 22),
            Text(
              '书架还是空的',
              style: AppTheme.serif(
                23,
                color: theme.colorScheme.onSurface,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '导入本地 TXT 小说，自动识别编码与章节\n阅读进度会一直保留在书库中',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.7,
                color: surface.muted,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onImport,
              icon: const Icon(Icons.folder_open_rounded, size: 18),
              label: const Text('选择 TXT 文件'),
            ),
            const SizedBox(height: 12),
            Text(
              '支持一次选择多个文件 · UTF-8 / GBK / UTF-16',
              style: TextStyle(fontSize: 10.5, color: surface.muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImportOverlay extends StatelessWidget {
  const _ImportOverlay({
    required this.status,
    required this.progress,
    required this.surface,
    required this.theme,
  });

  final String status;
  final double? progress;
  final AppSurface surface;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: ModalBarrier(
            dismissible: false,
            color: Colors.black.withValues(alpha: 0.22),
          ),
        ),
        Center(
          child: Material(
            color: surface.card,
            elevation: 14,
            shadowColor: Colors.black.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(18),
            child: SizedBox(
              width: math.min(340, MediaQuery.sizeOf(context).width - 48),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary
                                .withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: Icon(
                            Icons.auto_stories_rounded,
                            size: 19,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '正在导入',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: surface.muted),
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 3,
                        backgroundColor:
                            theme.colorScheme.primary.withValues(alpha: 0.12),
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '解析章节并复制到本地书库，较大的文件需要几秒钟',
                      style: TextStyle(
                        fontSize: 10.5,
                        height: 1.5,
                        color: surface.muted.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _BookInfoDialog extends StatelessWidget {
  const _BookInfoDialog({required this.book, required this.onRead});

  final Book book;
  final VoidCallback onRead;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = theme.extension<AppSurface>()!;
    final cover = coverPaletteFor('${book.title}|${book.id}');
    final progress = book.progress.percent.clamp(0.0, 1.0);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      backgroundColor: surface.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 58,
                    height: 78,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [cover.start, cover.end],
                      ),
                    ),
                    child: Center(
                      child: Text(
                        'TXT',
                        style: TextStyle(
                          fontSize: 9,
                          letterSpacing: 1.4,
                          fontWeight: FontWeight.w600,
                          color: cover.ink.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          book.title,
                          style: AppTheme.serif(
                            20,
                            color: theme.colorScheme.onSurface,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          book.displayAuthor,
                          style: TextStyle(fontSize: 12, color: surface.muted),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '${book.chapterCount} 章 · ${Fmt.charCount(book.charCount)}',
                          style: TextStyle(fontSize: 11.5, color: surface.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Divider(height: 1, color: surface.hairline),
              const SizedBox(height: 14),
              _InfoRow(label: '阅读进度', value: book.progress.isStarted
                  ? '${Fmt.percent(progress)} · ${book.lastChapterTitle.isEmpty ? '未知章节' : book.lastChapterTitle}'
                  : '未开始'),
              _InfoRow(label: '编码', value: book.encoding),
              _InfoRow(label: '原始文件', value: book.fileName),
              _InfoRow(label: '文件大小', value: Fmt.fileSize(book.fileSize)),
              _InfoRow(label: '导入时间', value: Fmt.dateTime(book.importedAt)),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('关闭'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: onRead,
                    child: const Text('开始阅读'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).extension<AppSurface>()!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 68,
            child: Text(
              label,
              style: TextStyle(fontSize: 11.5, color: surface.muted),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
