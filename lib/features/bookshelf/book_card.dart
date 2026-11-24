import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/models/book.dart';

enum BookCardAction { open, info, resetProgress, delete }

/// Reusable tactile book cover art with hardcover spine groove, subtle
/// bookmark/stamp details, and serif typography.
class BookCoverArt extends StatelessWidget {
  const BookCoverArt({
    super.key,
    required this.book,
    this.compact = false,
    this.showWatermark = true,
    this.showTag = true,
    this.showTitle = true,
    this.borderRadius = 14,
  });

  final Book book;
  final bool compact;
  final bool showWatermark;
  final bool showTag;
  final bool showTitle;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final cover = coverPaletteFor('${book.title}|${book.id}');
    final progress = book.progress.percent.clamp(0.0, 1.0);
    final isFinished = book.progress.isStarted && progress >= 0.999;

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.hasBoundedWidth && constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : (compact ? 64.0 : 196.0);
        // Smoothly scale typography & spine proportions between narrow phones (~140px)
        // and larger tablet/desktop cover tiles (~220px).
        final scale = compact ? 1.0 : (w / 196.0).clamp(0.76, 1.12);
        final watermarkSize = compact ? 74.0 : (144.0 * scale);
        final spineLeft = compact ? 6.0 : (10.0 * scale);
        final innerLeft = compact ? 13.0 : (18.0 * scale);
        final innerRight = compact ? 8.0 : (15.0 * scale);
        final tagTop = compact ? 10.0 : (14.0 * scale);
        final titleBottom = compact ? 10.0 : (17.0 * scale);
        final titleSize = compact ? 11.5 : (19.0 * scale).clamp(14.5, 21.0);

        return ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius),
          child: Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [cover.start, cover.end],
                  ),
                ),
              ),
              // Soft warm sheen from top-right.
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0.85, -0.85),
                    radius: 1.25,
                    colors: [
                      Colors.white.withValues(alpha: 0.09),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
              if (showWatermark)
                Positioned(
                  right: compact ? -6 : (-10 * scale),
                  bottom: compact ? -14 : (-22 * scale),
                  child: Text(
                    _watermark(book.title),
                    style: TextStyle(
                      fontSize: watermarkSize,
                      height: 1,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Modu WenKai',
                      fontFamilyFallback: const ['Modu Song', 'serif'],
                      color: cover.ink.withValues(alpha: 0.075),
                    ),
                  ),
                ),
              // Bookbinding spine groove along left edge.
              Positioned(
                left: spineLeft,
                top: 0,
                bottom: 0,
                child: Row(
                  children: [
                    Container(
                      width: 1.2,
                      color: Colors.black.withValues(alpha: 0.24),
                    ),
                    Container(
                      width: 1,
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                  ],
                ),
              ),
              // Subtle inner framing line.
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(borderRadius),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.11),
                    ),
                  ),
                ),
              ),
              if (showTag)
                Positioned(
                  left: innerLeft,
                  top: tagTop,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: compact ? 4.5 : 6,
                          vertical: compact ? 2 : 3,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: cover.ink.withValues(alpha: 0.34),
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'TXT',
                          style: TextStyle(
                            fontSize: compact ? 7.5 : 8.5,
                            letterSpacing: 1.1,
                            fontWeight: FontWeight.w600,
                            color: cover.ink.withValues(alpha: 0.86),
                          ),
                        ),
                      ),
                      if (!compact && isFinished) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: cover.accent.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            '已读完',
                            style: TextStyle(
                              fontSize: 8.5,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              if (showTitle)
                Positioned(
                  left: innerLeft,
                  right: innerRight,
                  bottom: titleBottom,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        book.title,
                        maxLines: compact ? 2 : 3,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.serif(
                          titleSize,
                          color: cover.ink,
                          height: 1.28,
                          letterSpacing: 0.4,
                        ),
                      ),
                      SizedBox(height: compact ? 5 : (9 * scale)),
                      Container(
                        width: compact ? 14 : (22 * scale),
                        height: compact ? 1.5 : 2,
                        decoration: BoxDecoration(
                          color: cover.accent.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                      if (!compact) ...[
                        SizedBox(height: 7 * scale),
                        Text(
                          book.displayAuthor,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: (11.5 * scale).clamp(10.0, 12.0),
                            letterSpacing: 0.5,
                            color: cover.ink.withValues(alpha: 0.74),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  String _watermark(String title) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return '书';
    return String.fromCharCode(trimmed.runes.first);
  }
}

class BookCard extends StatefulWidget {
  const BookCard({
    super.key,
    required this.book,
    required this.onOpen,
    required this.onInfo,
    required this.onResetProgress,
    required this.onDelete,
  });

  final Book book;
  final VoidCallback onOpen;
  final VoidCallback onInfo;
  final VoidCallback onResetProgress;
  final VoidCallback onDelete;

  @override
  State<BookCard> createState() => _BookCardState();
}

class _BookCardState extends State<BookCard> {
  bool _hovering = false;

  Future<void> _showContextMenu(Offset globalPosition) async {
    HapticFeedback.selectionClick();
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    final theme = Theme.of(context);
    final selected = await showMenu<BookCardAction>(
      context: context,
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 1, 1),
        Offset.zero & overlay.size,
      ),
      items: _buildBookMenuItems(theme, widget.book),
    );
    if (!mounted || selected == null) return;
    _handleAction(selected);
  }

  void _handleAction(BookCardAction action) {
    switch (action) {
      case BookCardAction.open:
        widget.onOpen();
        break;
      case BookCardAction.info:
        widget.onInfo();
        break;
      case BookCardAction.resetProgress:
        widget.onResetProgress();
        break;
      case BookCardAction.delete:
        widget.onDelete();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = theme.extension<AppSurface>()!;
    final book = widget.book;
    final progress = book.progress.percent.clamp(0.0, 1.0);

    return Semantics(
      button: true,
      label: '打开《${book.title}》',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          onTap: widget.onOpen,
          onSecondaryTapDown: (details) =>
              _showContextMenu(details.globalPosition),
          onLongPressStart: (details) =>
              _showContextMenu(details.globalPosition),
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            transform: Matrix4.translationValues(0, _hovering ? -4.0 : 0.0, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(15),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: _hovering ? 0.24 : 0.13,
                          ),
                          blurRadius: _hovering ? 26 : 14,
                          offset: Offset(0, _hovering ? 12 : 7),
                        ),
                      ],
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        BookCoverArt(book: book, borderRadius: 15),
                        Positioned(
                          right: 8,
                          top: 8,
                          child: AnimatedOpacity(
                            opacity: _hovering ? 1.0 : 0.78,
                            duration: const Duration(milliseconds: 140),
                            child: _MenuButton(
                              book: book,
                              onSelected: _handleAction,
                            ),
                          ),
                        ),
                        // Subtle reading action pill revealed on desktop hover.
                        Positioned(
                          right: 12,
                          bottom: 14,
                          child: IgnorePointer(
                            child: AnimatedOpacity(
                              opacity: _hovering ? 1 : 0,
                              duration: const Duration(milliseconds: 150),
                              child: AnimatedSlide(
                                offset: _hovering
                                    ? Offset.zero
                                    : const Offset(0, 0.2),
                                duration: const Duration(milliseconds: 160),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 9,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.42),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color:
                                          Colors.white.withValues(alpha: 0.22),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        book.progress.isStarted ? '续读' : '阅读',
                                        style: const TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(width: 2),
                                      const Icon(
                                        Icons.arrow_forward_rounded,
                                        size: 11,
                                        color: Colors.white,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  book.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                    letterSpacing: 0.1,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        book.progress.isStarted
                            ? '第 ${book.progress.chapterIndex + 1} / ${book.chapterCount} 章'
                            : '${book.chapterCount} 章 · 未读',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: surface.muted,
                        ),
                      ),
                    ),
                    if (book.progress.isStarted) ...[
                      const SizedBox(width: 6),
                      Text(
                        Fmt.percent(progress),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: progress >= 0.999
                              ? surface.seal
                              : theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 7),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 3.5,
                    backgroundColor:
                        theme.colorScheme.primary.withValues(alpha: 0.10),
                    color: progress >= 0.999
                        ? surface.seal
                        : theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Editorial list representation of a book for larger collections.
class BookListTile extends StatefulWidget {
  const BookListTile({
    super.key,
    required this.book,
    required this.onOpen,
    required this.onInfo,
    required this.onResetProgress,
    required this.onDelete,
  });

  final Book book;
  final VoidCallback onOpen;
  final VoidCallback onInfo;
  final VoidCallback onResetProgress;
  final VoidCallback onDelete;

  @override
  State<BookListTile> createState() => _BookListTileState();
}

class _BookListTileState extends State<BookListTile> {
  bool _hovering = false;

  Future<void> _showContextMenu(Offset globalPosition) async {
    HapticFeedback.selectionClick();
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;
    final theme = Theme.of(context);
    final selected = await showMenu<BookCardAction>(
      context: context,
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 1, 1),
        Offset.zero & overlay.size,
      ),
      items: _buildBookMenuItems(theme, widget.book),
    );
    if (!mounted || selected == null) return;
    _handleAction(selected);
  }

  void _handleAction(BookCardAction action) {
    switch (action) {
      case BookCardAction.open:
        widget.onOpen();
        break;
      case BookCardAction.info:
        widget.onInfo();
        break;
      case BookCardAction.resetProgress:
        widget.onResetProgress();
        break;
      case BookCardAction.delete:
        widget.onDelete();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = theme.extension<AppSurface>()!;
    final book = widget.book;
    final progress = book.progress.percent.clamp(0.0, 1.0);
    final remainingChars =
        ((1.0 - progress) * book.charCount).round().clamp(0, book.charCount);

    return Semantics(
      button: true,
      label: '打开《${book.title}》',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          onSecondaryTapDown: (details) =>
              _showContextMenu(details.globalPosition),
          onLongPressStart: (details) =>
              _showContextMenu(details.globalPosition),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            decoration: BoxDecoration(
              color: _hovering ? surface.elevated : surface.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _hovering
                    ? theme.colorScheme.primary.withValues(alpha: 0.35)
                    : surface.hairline,
              ),
              boxShadow: [
                if (_hovering)
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.onOpen,
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 56,
                        height: 76,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(9),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.14),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: BookCoverArt(
                            book: book,
                            compact: true,
                            showWatermark: false,
                            showTitle: false,
                            borderRadius: 9,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    book.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTheme.serif(
                                      17,
                                      color: theme.colorScheme.onSurface,
                                      height: 1.25,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if (book.progress.isStarted)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: progress >= 0.999
                                          ? surface.sealSoft
                                          : theme.colorScheme.primary
                                              .withValues(alpha: 0.10),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      progress >= 0.999
                                          ? '已读完'
                                          : Fmt.percent(progress),
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: progress >= 0.999
                                            ? surface.seal
                                            : theme.colorScheme.primary,
                                      ),
                                    ),
                                  )
                                else
                                  Text(
                                    '未读',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: surface.muted,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            Text(
                              '${book.displayAuthor} · ${book.chapterCount} 章 · ${Fmt.charCount(book.charCount)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: surface.muted,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    book.progress.isStarted
                                        ? (book.lastChapterTitle.isEmpty
                                            ? '第 ${book.progress.chapterIndex + 1} 章'
                                            : book.lastChapterTitle)
                                        : '点击开始阅读',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: book.progress.isStarted
                                          ? theme.colorScheme.onSurface
                                              .withValues(alpha: 0.78)
                                          : surface.muted,
                                    ),
                                  ),
                                ),
                                if (book.progress.isStarted &&
                                    progress < 0.999) ...[
                                  const SizedBox(width: 10),
                                  Text(
                                    '还需${Fmt.remainingTime(remainingChars)}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: surface.muted,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: LinearProgressIndicator(
                                value: progress,
                                minHeight: 3,
                                backgroundColor: theme.colorScheme.primary
                                    .withValues(alpha: 0.10),
                                color: progress >= 0.999
                                    ? surface.seal
                                    : theme.colorScheme.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      _MenuButton(
                        book: book,
                        onSelected: _handleAction,
                        lightHost: true,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

List<PopupMenuEntry<BookCardAction>> _buildBookMenuItems(
  ThemeData theme,
  Book book,
) =>
    [
      PopupMenuItem(
        value: BookCardAction.open,
        child: _MenuRow(
          icon: Icons.play_arrow_rounded,
          label: book.progress.isStarted ? '继续阅读' : '开始阅读',
        ),
      ),
      const PopupMenuItem(
        value: BookCardAction.info,
        child: _MenuRow(icon: Icons.info_outline_rounded, label: '书籍信息'),
      ),
      if (book.progress.isStarted)
        const PopupMenuItem(
          value: BookCardAction.resetProgress,
          child: _MenuRow(icon: Icons.restart_alt_rounded, label: '重置进度'),
        ),
      const PopupMenuDivider(),
      PopupMenuItem(
        value: BookCardAction.delete,
        child: _MenuRow(
          icon: Icons.delete_outline_rounded,
          label: '移出书架',
          color: theme.colorScheme.error,
        ),
      ),
    ];

class _MenuButton extends StatelessWidget {
  const _MenuButton({
    required this.book,
    required this.onSelected,
    this.lightHost = false,
  });

  final Book book;
  final ValueChanged<BookCardAction> onSelected;
  final bool lightHost;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = theme.extension<AppSurface>()!;
    return PopupMenuButton<BookCardAction>(
      tooltip: '更多操作',
      padding: EdgeInsets.zero,
      color: theme.colorScheme.surface,
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      onSelected: onSelected,
      itemBuilder: (context) => _buildBookMenuItems(theme, book),
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: lightHost
              ? surface.tint.withValues(alpha: 0.7)
              : Colors.black.withValues(alpha: 0.22),
          border: Border.all(
            color: lightHost
                ? surface.hairline
                : Colors.white.withValues(alpha: 0.18),
          ),
        ),
        child: Icon(
          Icons.more_horiz_rounded,
          size: 17,
          color: lightHost
              ? theme.colorScheme.onSurface.withValues(alpha: 0.75)
              : Colors.white.withValues(alpha: 0.94),
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effective = color ?? theme.colorScheme.onSurface;
    return Row(
      children: [
        Icon(icon, size: 18, color: effective),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(fontSize: 13, color: effective),
        ),
      ],
    );
  }
}
