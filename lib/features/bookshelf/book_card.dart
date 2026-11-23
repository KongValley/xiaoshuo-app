import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/theme.dart';
import '../../data/models/book.dart';

enum BookCardAction { open, info, delete }

class BookCard extends StatefulWidget {
  const BookCard({
    super.key,
    required this.book,
    required this.onOpen,
    required this.onInfo,
    required this.onDelete,
  });

  final Book book;
  final VoidCallback onOpen;
  final VoidCallback onInfo;
  final VoidCallback onDelete;

  @override
  State<BookCard> createState() => _BookCardState();
}

class _BookCardState extends State<BookCard> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final book = widget.book;
    final cover = coverPaletteFor('${book.title}|${book.id}');
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
          behavior: HitTestBehavior.opaque,
          child: AnimatedScale(
            scale: _hovering ? 1.018 : 1,
            duration: const Duration(milliseconds: 170),
            curve: Curves.easeOutCubic,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 170),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(15),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: _hovering ? 0.20 : 0.13,
                          ),
                          blurRadius: _hovering ? 24 : 14,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(15),
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
                          Positioned(
                            right: -10,
                            bottom: -24,
                            child: Text(
                              _watermark(book.title),
                              style: TextStyle(
                                fontSize: 150,
                                height: 1,
                                fontWeight: FontWeight.w700,
                                fontFamily: 'Modu WenKai',
                                fontFamilyFallback: const [
                                  'Modu Song',
                                  'serif',
                                ],
                                color: cover.ink.withValues(alpha: 0.075),
                              ),
                            ),
                          ),
                          Positioned.fill(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(15),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.09),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            left: 17,
                            top: 15,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: cover.ink.withValues(alpha: 0.35),
                                ),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'TXT',
                                style: TextStyle(
                                  fontSize: 8.5,
                                  letterSpacing: 1.2,
                                  fontWeight: FontWeight.w600,
                                  color: cover.ink.withValues(alpha: 0.85),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            left: 18,
                            right: 18,
                            bottom: 18,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  book.title,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTheme.serif(
                                    20,
                                    color: cover.ink,
                                    height: 1.32,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Container(
                                  width: 24,
                                  height: 2,
                                  color: cover.ink.withValues(alpha: 0.45),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  book.displayAuthor,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    letterSpacing: 0.5,
                                    color: cover.ink.withValues(alpha: 0.72),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Positioned(
                            right: 8,
                            top: 8,
                            child: _MenuButton(
                              book: book,
                              onOpen: widget.onOpen,
                              onInfo: widget.onInfo,
                              onDelete: widget.onDelete,
                            ),
                          ),
                        ],
                      ),
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
                const SizedBox(height: 5),
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
                          color: theme
                              .extension<AppSurface>()!
                              .muted,
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
                          color: theme.colorScheme.primary,
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
                    minHeight: 3.5,
                    backgroundColor:
                        theme.colorScheme.primary.withValues(alpha: 0.10),
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _watermark(String title) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return '书';
    return String.fromCharCode(trimmed.runes.first);
  }
}

class _MenuButton extends StatelessWidget {
  const _MenuButton({
    required this.book,
    required this.onOpen,
    required this.onInfo,
    required this.onDelete,
  });

  final Book book;
  final VoidCallback onOpen;
  final VoidCallback onInfo;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopupMenuButton<BookCardAction>(
      tooltip: '更多操作',
      padding: EdgeInsets.zero,
      color: theme.colorScheme.surface,
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      onSelected: (action) {
        switch (action) {
          case BookCardAction.open:
            onOpen();
            break;
          case BookCardAction.info:
            onInfo();
            break;
          case BookCardAction.delete:
            onDelete();
            break;
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: BookCardAction.open,
          child: _MenuRow(icon: Icons.play_arrow_rounded, label: '继续阅读'),
        ),
        const PopupMenuItem(
          value: BookCardAction.info,
          child: _MenuRow(icon: Icons.info_outline_rounded, label: '书籍信息'),
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
      ],
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withValues(alpha: 0.18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
        ),
        child: Icon(
          Icons.more_horiz_rounded,
          size: 17,
          color: Colors.white.withValues(alpha: 0.92),
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
