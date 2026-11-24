import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/models/reader_settings.dart';
import '../../data/models/reading_stats.dart';
import 'reader_controller.dart';

const double _sheetRadius = 22;

class ReaderTocSelection {
  const ReaderTocSelection({
    required this.chapterIndex,
    this.charOffset,
  });

  final int chapterIndex;
  final int? charOffset;
}

class ReaderTocSheet extends StatefulWidget {
  const ReaderTocSheet({
    super.key,
    required this.controller,
    required this.palette,
    this.bookmarks = const [],
    this.onRemoveBookmark,
    this.asSideDrawer = false,
  });

  final ReaderController controller;
  final ReaderPalette palette;
  final List<BookBookmark> bookmarks;
  final ValueChanged<String>? onRemoveBookmark;
  final bool asSideDrawer;

  @override
  State<ReaderTocSheet> createState() => _ReaderTocSheetState();
}

class _ReaderTocSheetState extends State<ReaderTocSheet> {
  static const double _itemExtent = 56;

  late final ScrollController _scrollController;
  late final TextEditingController _searchController;
  late List<BookBookmark> _bookmarks;
  String _query = '';
  bool _reversed = false;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _bookmarks = List<BookBookmark>.from(widget.bookmarks);
    _scrollController = ScrollController(
      initialScrollOffset: ((widget.controller.chapterIndex - 4) * _itemExtent)
          .clamp(0.0, double.infinity),
    );
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  List<int> get _filtered {
    final query = _query.trim().toLowerCase();
    final chapters = widget.controller.chapters;
    final indices = <int>[];
    if (query.isEmpty) {
      for (var i = 0; i < chapters.length; i++) {
        indices.add(i);
      }
    } else {
      for (var i = 0; i < chapters.length; i++) {
        if (chapters[i].title.toLowerCase().contains(query)) indices.add(i);
      }
    }
    if (_reversed) {
      return indices.reversed.toList();
    }
    return indices;
  }

  void _jumpListToCurrent(List<int> filtered) {
    final pos = filtered.indexOf(widget.controller.chapterIndex);
    if (pos < 0 || !_scrollController.hasClients) return;
    final target = ((pos - 3) * _itemExtent)
        .clamp(0.0, _scrollController.position.maxScrollExtent);
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final controller = widget.controller;
    final filtered = _filtered;
    final sideDrawer = widget.asSideDrawer;
    final height =
        sideDrawer ? double.infinity : MediaQuery.sizeOf(context).height * 0.84;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Material(
        color: palette.chrome,
        elevation: sideDrawer ? 16 : 0,
        shadowColor: Colors.black.withValues(alpha: 0.24),
        borderRadius: sideDrawer
            ? const BorderRadius.horizontal(left: Radius.circular(_sheetRadius))
            : const BorderRadius.vertical(top: Radius.circular(_sheetRadius)),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          height: height,
          child: Column(
            children: [
              if (!sideDrawer) ...[
                const SizedBox(height: 10),
                Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: palette.muted.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
              Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  sideDrawer ? 18 : 14,
                  10,
                  6,
                ),
                child: Row(
                  children: [
                    Text(
                      '目录',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: palette.text,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _tab == 0
                          ? '共 ${controller.chapters.length} 章'
                          : '${_bookmarks.length} 处书签',
                      style: TextStyle(fontSize: 12, color: palette.muted),
                    ),
                    const Spacer(),
                    if (_tab == 0) ...[
                      IconButton(
                        onPressed: () {
                          setState(() => _reversed = !_reversed);
                          if (_scrollController.hasClients) {
                            _scrollController.jumpTo(0);
                          }
                        },
                        tooltip: _reversed ? '切换为正序' : '切换为倒序',
                        icon: Icon(
                          Icons.swap_vert_rounded,
                          size: 20,
                          color: _reversed ? palette.accent : palette.muted,
                        ),
                      ),
                      IconButton(
                        onPressed: () => _jumpListToCurrent(filtered),
                        tooltip: '定位到当前章',
                        icon: Icon(
                          Icons.my_location_rounded,
                          size: 19,
                          color: palette.muted,
                        ),
                      ),
                    ],
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(Icons.close_rounded, color: palette.muted),
                      tooltip: '关闭',
                    ),
                  ],
                ),
              ),
              // Segmented tabs: 章节目录 / 书签摘录
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: Row(
                  children: [
                    _SheetTabPill(
                      label: '章节',
                      selected: _tab == 0,
                      palette: palette,
                      onTap: () => setState(() => _tab = 0),
                    ),
                    const SizedBox(width: 8),
                    _SheetTabPill(
                      label: _bookmarks.isEmpty
                          ? '书签'
                          : '书签 (${_bookmarks.length})',
                      selected: _tab == 1,
                      palette: palette,
                      onTap: () => setState(() => _tab = 1),
                    ),
                  ],
                ),
              ),
              if (_tab == 0) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                  child: TextField(
                    controller: _searchController,
                    style: TextStyle(fontSize: 14, color: palette.text),
                    cursorColor: palette.accent,
                    onChanged: (value) {
                      setState(() => _query = value);
                      if (_scrollController.hasClients) {
                        _scrollController.jumpTo(0);
                      }
                    },
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: '搜索章节名称…',
                      hintStyle: TextStyle(fontSize: 13.5, color: palette.muted),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        size: 19,
                        color: palette.muted,
                      ),
                      suffixIcon: _query.isNotEmpty
                          ? IconButton(
                              tooltip: '清空',
                              icon: Icon(
                                Icons.close_rounded,
                                size: 18,
                                color: palette.muted,
                              ),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _query = '');
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: palette.divider.withValues(alpha: 0.22),
                      contentPadding: const EdgeInsets.symmetric(vertical: 11),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: palette.divider),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: palette.divider),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: palette.accent, width: 1.3),
                      ),
                    ),
                  ),
                ),
                // Current chapter summary strip.
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  decoration: BoxDecoration(
                    color: palette.accent.withValues(alpha: 0.06),
                    border: Border.symmetric(
                      horizontal: BorderSide(color: palette.divider),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.bookmark_rounded, size: 14, color: palette.accent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '当前：${controller.chapterHeaderTitle}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: palette.accent,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        Fmt.percent(controller.percent),
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: palette.accent,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Text(
                            '没有找到相关章节',
                            style: TextStyle(fontSize: 13.5, color: palette.muted),
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          itemExtent: _itemExtent,
                          itemCount: filtered.length,
                          padding: const EdgeInsets.only(bottom: 12),
                          itemBuilder: (context, position) {
                            final index = filtered[position];
                            return _TocItem(
                              controller: controller,
                              palette: palette,
                              chapterIndex: index,
                              query: _query.trim(),
                              onTap: () => Navigator.of(context).pop(
                                ReaderTocSelection(chapterIndex: index),
                              ),
                            );
                          },
                        ),
                ),
              ] else ...[
                Divider(height: 1, color: palette.divider),
                Expanded(
                  child: _bookmarks.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.bookmark_border_rounded,
                                size: 40,
                                color: palette.muted.withValues(alpha: 0.6),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                '还没有夹存书签',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: palette.text,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '阅读时轻点页眉右上角的书签丝带即可夹存精彩段落',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: palette.muted,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
                          itemCount: _bookmarks.length,
                          separatorBuilder: (context, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final bm = _bookmarks[index];
                            return _BookmarkCard(
                              bookmark: bm,
                              palette: palette,
                              onTap: () => Navigator.of(context).pop(
                                ReaderTocSelection(
                                  chapterIndex: bm.chapterIndex,
                                  charOffset: bm.charOffset,
                                ),
                              ),
                              onDelete: () {
                                setState(() => _bookmarks.removeAt(index));
                                widget.onRemoveBookmark?.call(bm.id);
                              },
                            );
                          },
                        ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetTabPill extends StatelessWidget {
  const _SheetTabPill({
    required this.label,
    required this.selected,
    required this.palette,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final ReaderPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? palette.accent.withValues(alpha: 0.14)
              : palette.divider.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? palette.accent.withValues(alpha: 0.45)
                : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? palette.accent : palette.muted,
          ),
        ),
      ),
    );
  }
}

class _BookmarkCard extends StatelessWidget {
  const _BookmarkCard({
    required this.bookmark,
    required this.palette,
    required this.onTap,
    required this.onDelete,
  });

  final BookBookmark bookmark;
  final ReaderPalette palette;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: palette.top.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: palette.divider),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  Icons.bookmark_rounded,
                  size: 16,
                  color: palette.accent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bookmark.chapterTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: palette.text,
                      ),
                    ),
                    if (bookmark.excerpt.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        bookmark.excerpt,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.5,
                          color: palette.muted,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      Fmt.dateTime(bookmark.createdAt),
                      style: TextStyle(
                        fontSize: 10.5,
                        color: palette.muted.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '删除书签',
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  Icons.delete_outline_rounded,
                  size: 18,
                  color: palette.muted,
                ),
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TocItem extends StatelessWidget {
  const _TocItem({
    required this.controller,
    required this.palette,
    required this.chapterIndex,
    required this.query,
    required this.onTap,
  });

  final ReaderController controller;
  final ReaderPalette palette;
  final int chapterIndex;
  final String query;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final chapter = controller.chapters[chapterIndex];
    final current = chapterIndex == controller.chapterIndex;
    return Semantics(
      button: true,
      selected: current,
      label: '${chapter.title}，${_shortChars(chapter.length)}'
          '${current ? '，当前章节' : ''}',
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: current ? palette.accent.withValues(alpha: 0.09) : null,
            border: Border(
              bottom: BorderSide(color: palette.divider.withValues(alpha: 0.5)),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 22,
                decoration: BoxDecoration(
                  color: current ? palette.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _HighlightedTitle(
                  title: chapter.title,
                  query: query,
                  baseStyle: TextStyle(
                    fontSize: 14,
                    fontWeight: current ? FontWeight.w600 : FontWeight.w400,
                    color: current ? palette.accent : palette.text,
                  ),
                  highlightColor: palette.accent,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _shortChars(chapter.length),
                style: TextStyle(fontSize: 11, color: palette.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _shortChars(int chars) {
    if (chars >= 10000) {
      return '${(chars / 10000).toStringAsFixed(1)} 万字';
    }
    if (chars >= 1000) {
      return '${(chars / 1000).toStringAsFixed(1)} 千字';
    }
    return '$chars 字';
  }
}

class _HighlightedTitle extends StatelessWidget {
  const _HighlightedTitle({
    required this.title,
    required this.query,
    required this.baseStyle,
    required this.highlightColor,
  });

  final String title;
  final String query;
  final TextStyle baseStyle;
  final Color highlightColor;

  @override
  Widget build(BuildContext context) {
    if (query.isEmpty) {
      return Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: baseStyle,
      );
    }
    final lower = title.toLowerCase();
    final match = lower.indexOf(query.toLowerCase());
    if (match < 0) {
      return Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: baseStyle,
      );
    }
    return Text.rich(
      TextSpan(
        style: baseStyle,
        children: [
          if (match > 0) TextSpan(text: title.substring(0, match)),
          TextSpan(
            text: title.substring(match, match + query.length),
            style: baseStyle.copyWith(
              color: highlightColor,
              fontWeight: FontWeight.w700,
              backgroundColor: highlightColor.withValues(alpha: 0.14),
            ),
          ),
          if (match + query.length < title.length)
            TextSpan(text: title.substring(match + query.length)),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class ReaderSettingsSheet extends StatefulWidget {
  const ReaderSettingsSheet({
    super.key,
    required this.settings,
    required this.onChanged,
    this.asDialog = false,
  });

  final ReaderSettings settings;
  final ValueChanged<ReaderSettings> onChanged;
  final bool asDialog;

  @override
  State<ReaderSettingsSheet> createState() => _ReaderSettingsSheetState();
}

class _ReaderSettingsSheetState extends State<ReaderSettingsSheet> {
  late ReaderSettings _settings;

  @override
  void initState() {
    super.initState();
    _settings = widget.settings;
  }

  void _update(ReaderSettings settings) {
    setState(() => _settings = settings);
    widget.onChanged(settings);
  }

  @override
  Widget build(BuildContext context) {
    final palette = ReaderPalette.of(_settings.theme);
    final asDialog = widget.asDialog;
    final isDesktop = switch (defaultTargetPlatform) {
      TargetPlatform.windows ||
      TargetPlatform.macOS ||
      TargetPlatform.linux =>
        true,
      _ => false,
    };

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Material(
        color: palette.chrome,
        elevation: asDialog ? 16 : 0,
        shadowColor: Colors.black.withValues(alpha: 0.22),
        borderRadius: asDialog
            ? BorderRadius.circular(_sheetRadius)
            : const BorderRadius.vertical(top: Radius.circular(_sheetRadius)),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final widePanel = constraints.maxWidth >= 520;
              final compactSwatches = constraints.maxWidth < 370;

              final marginSection = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionLabel('版心留白', palette),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      for (var i = 0; i < ReaderMarginLevel.values.length; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        Expanded(
                          child: _OptionPill(
                            label: ReaderMarginLevel.values[i].label,
                            selected:
                                ReaderMarginLevel.values[i] == _settings.margin,
                            palette: palette,
                            onTap: () => _update(
                              _settings.copyWith(
                                margin: ReaderMarginLevel.values[i],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              );

              final layoutSection = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionLabel('页面布局', palette),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      for (var i = 0; i < ReaderPageLayout.values.length; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        Expanded(
                          child: _OptionPill(
                            label: ReaderPageLayout.values[i].label,
                            subtitle: ReaderPageLayout.values[i].description,
                            selected: ReaderPageLayout.values[i] ==
                                _settings.pageLayout,
                            palette: palette,
                            onTap: () => _update(
                              _settings.copyWith(
                                pageLayout: ReaderPageLayout.values[i],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              );

              return SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  20,
                  asDialog ? 16 : 10,
                  20,
                  22,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!asDialog) ...[
                      Center(
                        child: Container(
                          width: 38,
                          height: 4,
                          decoration: BoxDecoration(
                            color: palette.muted.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    Row(
                      children: [
                        Text(
                          '排版工坊',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: palette.text,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => _update(const ReaderSettings()),
                          style: TextButton.styleFrom(
                            foregroundColor: palette.muted,
                          ),
                          child: const Text('恢复默认'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: TextButton.styleFrom(
                            foregroundColor: palette.accent,
                          ),
                          child: const Text('完成'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // Live typography preview card.
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: double.infinity,
                      padding: EdgeInsets.symmetric(
                        horizontal: switch (_settings.margin) {
                          ReaderMarginLevel.compact => 12,
                          ReaderMarginLevel.standard => 18,
                          ReaderMarginLevel.relaxed => 26,
                        },
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [palette.top, palette.bottom],
                        ),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: palette.divider),
                      ),
                      child: Text(
                        '　　夜色渐深，风从窗缝里钻进来，桌案上的宣纸书页轻轻翻动，墨香与灯影沉入寂静之中。',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: ReaderTypography.body(_settings, palette),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _sectionLabel('阅读纸色', palette),
                    const SizedBox(height: 10),
                    if (compactSwatches)
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          for (final option in ReaderPalette.all)
                            _ThemeSwatch(
                              palette: option,
                              selected: option.id == _settings.theme,
                              onTap: () => _update(
                                _settings.copyWith(theme: option.id),
                              ),
                            ),
                        ],
                      )
                    else
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          for (final option in ReaderPalette.all)
                            _ThemeSwatch(
                              palette: option,
                              selected: option.id == _settings.theme,
                              onTap: () => _update(
                                _settings.copyWith(theme: option.id),
                              ),
                            ),
                        ],
                      ),
                    const SizedBox(height: 18),
                    _sectionLabel('字体风格', palette),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        for (var i = 0; i < ReaderFontId.values.length; i++) ...[
                          if (i > 0) const SizedBox(width: 10),
                          Expanded(
                            child: _FontChip(
                              font: ReaderFontId.values[i],
                              selected:
                                  ReaderFontId.values[i] == _settings.font,
                              palette: palette,
                              onTap: () => _update(
                                _settings.copyWith(font: ReaderFontId.values[i]),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 18),
                    _StepperSliderRow(
                      label: '字号',
                      valueLabel: '${_settings.fontSize.toStringAsFixed(0)} pt',
                      palette: palette,
                      value: _settings.fontSize,
                      min: 14,
                      max: 32,
                      step: 1,
                      divisions: 18,
                      onChanged: (value) =>
                          _update(_settings.copyWith(fontSize: value)),
                    ),
                    const SizedBox(height: 10),
                    _StepperSliderRow(
                      label: '行距',
                      valueLabel: '${_settings.lineHeight.toStringAsFixed(1)}×',
                      palette: palette,
                      value: _settings.lineHeight,
                      min: 1.4,
                      max: 2.2,
                      step: 0.1,
                      divisions: 8,
                      onChanged: (value) => _update(
                        _settings.copyWith(
                          lineHeight: double.parse(value.toStringAsFixed(1)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (widePanel)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 10, child: marginSection),
                          const SizedBox(width: 14),
                          Expanded(flex: 11, child: layoutSection),
                        ],
                      )
                    else ...[
                      marginSection,
                      const SizedBox(height: 16),
                      layoutSection,
                    ],
                    const SizedBox(height: 16),
                    _sectionLabel('翻页手感', palette),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        for (var i = 0; i < PageTurnMode.values.length; i++) ...[
                          if (i > 0) const SizedBox(width: 8),
                          Expanded(
                            child: _OptionPill(
                              label: PageTurnMode.values[i].label,
                              subtitle: PageTurnMode.values[i].description,
                              selected:
                                  PageTurnMode.values[i] == _settings.pageTurn,
                              palette: palette,
                              onTap: () => _update(
                                _settings.copyWith(
                                  pageTurn: PageTurnMode.values[i],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (isDesktop) ...[
                      const SizedBox(height: 16),
                      Text(
                        '快捷键：← → / 空格 翻页 · M 菜单 · T 目录 · S 排版 · N 日夜 · H 帮助',
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.6,
                          color: palette.muted,
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text, ReaderPalette palette) => Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: palette.muted,
          letterSpacing: 1,
        ),
      );
}

class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({
    required this.palette,
    required this.selected,
    required this.onTap,
  });

  final ReaderPalette palette;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '${palette.label}主题',
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [palette.top, palette.bottom],
                  ),
                  border: Border.all(
                    color: selected
                        ? palette.accent
                        : palette.muted.withValues(alpha: 0.28),
                    width: selected ? 2.4 : 1,
                  ),
                  boxShadow: [
                    if (selected)
                      BoxShadow(
                        color: palette.accent.withValues(alpha: 0.22),
                        blurRadius: 10,
                      ),
                  ],
                ),
                child: Center(
                  child: selected
                      ? Icon(Icons.check_rounded, size: 19, color: palette.accent)
                      : Text(
                          '文',
                          style: TextStyle(
                            fontFamily: 'Modu WenKai',
                            fontFamilyFallback: const ['Modu Song', 'serif'],
                            fontSize: 15,
                            color: palette.isDark
                                ? palette.text.withValues(alpha: 0.96)
                                : palette.text.withValues(alpha: 0.84),
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                palette.label,
                style: TextStyle(
                  fontSize: 11,
                  color: selected ? palette.accent : palette.muted,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FontChip extends StatelessWidget {
  const _FontChip({
    required this.font,
    required this.selected,
    required this.palette,
    required this.onTap,
  });

  final ReaderFontId font;
  final bool selected;
  final ReaderPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '${font.label}字体',
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? palette.accent.withValues(alpha: 0.12)
                : palette.top.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? palette.accent : palette.divider,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Column(
            children: [
              Text(
                font.label,
                style: TextStyle(
                  fontFamily: font.family,
                  fontFamilyFallback: font.fallback,
                  fontSize: 15.5,
                  color: selected ? palette.accent : palette.text,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                font.subtitle,
                style: TextStyle(
                  fontSize: 10,
                  color: selected ? palette.accent : palette.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OptionPill extends StatelessWidget {
  const _OptionPill({
    required this.label,
    this.subtitle,
    required this.selected,
    required this.palette,
    required this.onTap,
  });

  final String label;
  final String? subtitle;
  final bool selected;
  final ReaderPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(11),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.symmetric(
          horizontal: 8,
          vertical: subtitle == null ? 10 : 8,
        ),
        decoration: BoxDecoration(
          color: selected
              ? palette.accent.withValues(alpha: 0.12)
              : palette.top.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: selected ? palette.accent : palette.divider,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? palette.accent : palette.text,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9.5,
                  color: selected ? palette.accent : palette.muted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StepperSliderRow extends StatelessWidget {
  const _StepperSliderRow({
    required this.label,
    required this.valueLabel,
    required this.palette,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.divisions,
    required this.onChanged,
  });

  final String label;
  final String valueLabel;
  final ReaderPalette palette;
  final double value;
  final double min;
  final double max;
  final double step;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Text(label, style: TextStyle(fontSize: 13, color: palette.muted)),
            const Spacer(),
            Text(
              valueLabel,
              style: TextStyle(
                fontSize: 12,
                color: palette.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            _StepButton(
              icon: Icons.remove_rounded,
              enabled: value > min + 0.001,
              palette: palette,
              onTap: () => onChanged((value - step).clamp(min, max)),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: palette.accent,
                  inactiveTrackColor: palette.accent.withValues(alpha: 0.14),
                  thumbColor: palette.accent,
                  overlayColor: palette.accent.withValues(alpha: 0.12),
                  trackHeight: 2.5,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 6.5),
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 15),
                ),
                child: Slider(
                  value: value.clamp(min, max),
                  min: min,
                  max: max,
                  divisions: divisions,
                  onChanged: onChanged,
                ),
              ),
            ),
            _StepButton(
              icon: Icons.add_rounded,
              enabled: value < max - 0.001,
              palette: palette,
              onTap: () => onChanged((value + step).clamp(min, max)),
            ),
          ],
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.enabled,
    required this.palette,
    required this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final ReaderPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 30,
        height: 28,
        decoration: BoxDecoration(
          color: palette.top.withValues(alpha: enabled ? 0.7 : 0.3),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: palette.divider),
        ),
        child: Icon(
          icon,
          size: 16,
          color: enabled ? palette.text : palette.muted.withValues(alpha: 0.4),
        ),
      ),
    );
  }
}
