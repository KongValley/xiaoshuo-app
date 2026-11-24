import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/models/book.dart';
import '../data/models/reading_stats.dart';
import '../features/bookshelf/book_card.dart';
import 'formatters.dart';
import 'theme.dart';

/// Hand-carved Chinese chop-seal badge representing an offline reading milestone.
class SealStampBadge extends StatefulWidget {
  const SealStampBadge({
    super.key,
    required this.stamp,
    required this.unlocked,
    this.size = 56,
    this.interactive = false,
    this.onTap,
  });

  final StampId stamp;
  final bool unlocked;
  final double size;
  final bool interactive;
  final VoidCallback? onTap;

  @override
  State<SealStampBadge> createState() => _SealStampBadgeState();
}

class _SealStampBadgeState extends State<SealStampBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pressController;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
  }

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (widget.interactive) {
      HapticFeedback.selectionClick();
      _pressController.forward(from: 0);
    }
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final badge = AnimatedBuilder(
      animation: _pressController,
      builder: (context, child) {
        final t = _pressController.value;
        final bounce = t == 0
            ? 1.0
            : (1.0 - 0.14 * math.sin(t * math.pi)) +
                0.04 * math.sin(t * math.pi * 2);
        return Transform.scale(scale: bounce, child: child);
      },
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: CustomPaint(
          painter: _SealPainter(
            stamp: widget.stamp,
            unlocked: widget.unlocked,
            isDark: isDark,
          ),
        ),
      ),
    );

    if (!widget.interactive && widget.onTap == null) return badge;
    return GestureDetector(
      onTap: _handleTap,
      behavior: HitTestBehavior.opaque,
      child: badge,
    );
  }
}

class _SealPainter extends CustomPainter {
  const _SealPainter({
    required this.stamp,
    required this.unlocked,
    required this.isDark,
  });

  final StampId stamp;
  final bool unlocked;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width, size.height);
    if (side <= 0) return;

    canvas.save();
    canvas.translate((size.width - side) / 2, (size.height - side) / 2);
    final rect = Rect.fromLTWH(2, 2, side - 4, side - 4);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(side * 0.22));

    if (unlocked) {
      final base = stamp.accent;
      final darkTone = Color.lerp(base, Colors.black, 0.22)!;
      final lightTone = Color.lerp(base, Colors.white, 0.10)!;
      canvas.drawRRect(
        rrect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [lightTone, base, darkTone],
          ).createShader(rect),
      );

      // Subtle inner carved border frame.
      final innerRect = rect.deflate(side * 0.085);
      canvas.drawRRect(
        RRect.fromRectAndRadius(innerRect, Radius.circular(side * 0.15)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.0, side * 0.028)
          ..color = const Color(0xFFFFF4E4).withValues(alpha: 0.42),
      );

      // Organic stone-seal ink micro-speckles.
      final rng = math.Random(stamp.index * 97 + 13);
      final specklePaint = Paint()
        ..color = const Color(0xFFFFF6E9).withValues(alpha: 0.18);
      for (var i = 0; i < 8; i++) {
        final dx = rect.left + rng.nextDouble() * rect.width;
        final dy = rect.top + rng.nextDouble() * rect.height;
        canvas.drawCircle(Offset(dx, dy), side * 0.015, specklePaint);
      }

      // Carved glyph in center.
      final tp = TextPainter(
        text: TextSpan(
          text: stamp.glyph,
          style: TextStyle(
            fontFamily: 'Modu WenKai',
            fontFamilyFallback: const ['Modu Song', 'serif'],
            fontSize: side * 0.46,
            fontWeight: FontWeight.w700,
            color: const Color(0xFFFFF7EC),
            height: 1.0,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset((side - tp.width) / 2, (side - tp.height) / 2),
      );
      tp.dispose();
    } else {
      final ghostColor =
          (isDark ? Colors.white : const Color(0xFF4A3D30)).withValues(alpha: 0.16);
      canvas.drawRRect(
        rrect,
        Paint()..color = ghostColor.withValues(alpha: 0.06),
      );
      canvas.drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.0, side * 0.028)
          ..color = ghostColor,
      );
      final tp = TextPainter(
        text: TextSpan(
          text: stamp.glyph,
          style: TextStyle(
            fontFamily: 'Modu WenKai',
            fontFamilyFallback: const ['Modu Song', 'serif'],
            fontSize: side * 0.44,
            fontWeight: FontWeight.w600,
            color: ghostColor.withValues(alpha: 0.42),
            height: 1.0,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset((side - tp.width) / 2, (side - tp.height) / 2),
      );
      tp.dispose();
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SealPainter oldDelegate) =>
      oldDelegate.stamp != stamp ||
      oldDelegate.unlocked != unlocked ||
      oldDelegate.isDark != isDark;
}

/// Physical silk bookmark ribbon hanging from the top-right reading edge.
class BookmarkRibbonMarker extends StatelessWidget {
  const BookmarkRibbonMarker({
    super.key,
    required this.bookmarked,
    required this.accentColor,
    required this.onTap,
  });

  final bool bookmarked;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: bookmarked,
      label: bookmarked ? '取消本页书签' : '夹存本页书签',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Tooltip(
          message: bookmarked ? '本页已夹书签（点击取下）' : '轻点夹存书签',
          child: SizedBox(
            width: 38,
            height: 54,
            child: Align(
              alignment: Alignment.topCenter,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 340),
                curve: bookmarked ? Curves.elasticOut : Curves.easeInCubic,
                width: 22,
                height: bookmarked ? 44 : 14,
                child: CustomPaint(
                  painter: _BookmarkRibbonPainter(
                    bookmarked: bookmarked,
                    color: accentColor,
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

class _BookmarkRibbonPainter extends CustomPainter {
  const _BookmarkRibbonPainter({
    required this.bookmarked,
    required this.color,
  });

  final bool bookmarked;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (h <= 2 || w <= 2) return;

    final notch = math.min(7.0, h * 0.25);
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(w, 0)
      ..lineTo(w, h)
      ..lineTo(w / 2, h - notch)
      ..lineTo(0, h)
      ..close();

    if (bookmarked) {
      canvas.drawPath(
        path.shift(const Offset(0, 2)),
        Paint()..color = Colors.black.withValues(alpha: 0.16),
      );
    }

    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: bookmarked
              ? [
                  Color.lerp(color, Colors.white, 0.14)!,
                  color,
                  Color.lerp(color, Colors.black, 0.16)!,
                ]
              : [
                  color.withValues(alpha: 0.28),
                  color.withValues(alpha: 0.18),
                ],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );
  }

  @override
  bool shouldRepaint(covariant _BookmarkRibbonPainter oldDelegate) =>
      oldDelegate.bookmarked != bookmarked || oldDelegate.color != color;
}

/// Non-blocking celebratory toast banner displayed when a chop-seal unlocks.
class StampUnlockBanner extends StatelessWidget {
  const StampUnlockBanner({
    super.key,
    required this.stamp,
    required this.palette,
  });

  final StampId stamp;
  final ReaderPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 16, 10),
      decoration: BoxDecoration(
        color: palette.chrome,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: stamp.accent.withValues(alpha: 0.45)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SealStampBadge(stamp: stamp, unlocked: true, size: 38),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '解锁阅历印记 · ${stamp.title}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: palette.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  stamp.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: palette.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum BookCompletionAction { keepReading, restartBook, backToShelf }

/// Celebratory modal displayed upon completing the final page of a book.
class BookCompletionDialog extends StatelessWidget {
  const BookCompletionDialog({
    super.key,
    required this.book,
    required this.sessionSeconds,
    required this.finishedBooksCount,
    required this.palette,
  });

  final Book book;
  final int sessionSeconds;
  final int finishedBooksCount;
  final ReaderPalette palette;

  String _honorTitle() {
    if (book.charCount >= 1500000) return '万卷行者';
    if (book.charCount >= 300000) return '长卷知音';
    return '素卷清客';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      backgroundColor: palette.chrome,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: palette.divider),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(26, 26, 26, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 62,
                    height: 84,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.22),
                            blurRadius: 14,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: BookCoverArt(
                        book: book,
                        compact: true,
                        showWatermark: false,
                        showTitle: false,
                        borderRadius: 10,
                      ),
                    ),
                  ),
                  const SizedBox(width: 18),
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 1.45, end: 1.0),
                    duration: const Duration(milliseconds: 420),
                    curve: Curves.elasticOut,
                    builder: (context, scale, child) =>
                        Transform.scale(scale: scale, child: child),
                    child: const SealStampBadge(
                      stamp: StampId.bookFinished,
                      unlocked: true,
                      size: 66,
                      interactive: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: StampId.bookFinished.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '圆满合卷 · ${_honorTitle()}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: StampId.bookFinished.accent,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '《${book.title}》',
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.serif(
                  21,
                  color: palette.text,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '全卷 ${book.chapterCount} 章 · ${Fmt.charCount(book.charCount)} 已尽览\n'
                '这是你合卷读完的第 $finishedBooksCount 本藏书',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.6,
                  color: palette.muted,
                ),
              ),
              if (sessionSeconds >= 60) ...[
                const SizedBox(height: 8),
                Text(
                  '本次静读：${Fmt.readingDuration(sessionSeconds)}',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: palette.accent,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context)
                          .pop(BookCompletionAction.restartBook),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: palette.text,
                        side: BorderSide(color: palette.divider),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('重温开篇'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context)
                          .pop(BookCompletionAction.backToShelf),
                      style: FilledButton.styleFrom(
                        backgroundColor: palette.accent,
                        foregroundColor: palette.chrome,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('合卷回书架'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: () => Navigator.of(context)
                    .pop(BookCompletionAction.keepReading),
                style: TextButton.styleFrom(foregroundColor: palette.muted),
                child: const Text('留在末页'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
