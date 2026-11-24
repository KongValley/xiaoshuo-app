import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Visual variant of the ShiJuan Reader brand mark.
enum ShijuanLogoVariant {
  /// Full rounded-square obsidian ink badge with bronze hairline and ivory folio.
  emblem,

  /// Standalone open-folio mark without the outer badge background.
  mark,
}

/// Vector brand mark for 拾卷 (ShiJuan Reader):
/// an open parchment folio anchored by a soft ink spine, cinnabar seal stamp,
/// and folded silk bookmark ribbon.
class ShijuanLogo extends StatelessWidget {
  const ShijuanLogo({
    super.key,
    this.size = 40,
    this.variant = ShijuanLogoVariant.emblem,
    this.pageColor,
    this.inkColor,
    this.accentColor,
  });

  final double size;
  final ShijuanLogoVariant variant;
  final Color? pageColor;
  final Color? inkColor;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final scheme = Theme.of(context).colorScheme;
    final resolvedPage = pageColor ??
        (variant == ShijuanLogoVariant.emblem
            ? const Color(0xFFFAF3E6)
            : (brightness == Brightness.dark
                ? const Color(0xFFEDE2D0)
                : const Color(0xFFFFFCF6)));
    final resolvedInk = inkColor ??
        (variant == ShijuanLogoVariant.emblem
            ? const Color(0xFF211A14)
            : scheme.onSurface);
    final resolvedAccent = accentColor ??
        (brightness == Brightness.dark
            ? const Color(0xFFD66048)
            : const Color(0xFFC4462E));

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: ShijuanLogoPainter(
          variant: variant,
          pageColor: resolvedPage,
          inkColor: resolvedInk,
          accentColor: resolvedAccent,
          isDarkHost: brightness == Brightness.dark,
        ),
      ),
    );
  }
}

class ShijuanLogoPainter extends CustomPainter {
  const ShijuanLogoPainter({
    this.variant = ShijuanLogoVariant.emblem,
    this.pageColor = const Color(0xFFFAF3E6),
    this.inkColor = const Color(0xFF211A14),
    this.accentColor = const Color(0xFFC4462E),
    this.isDarkHost = false,
    this.transparentBackdrop = false,
  });

  final ShijuanLogoVariant variant;
  final Color pageColor;
  final Color inkColor;
  final Color accentColor;
  final bool isDarkHost;
  final bool transparentBackdrop;

  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width, size.height);
    if (side <= 0) return;

    canvas.save();
    canvas.translate((size.width - side) / 2, (size.height - side) / 2);
    final s = side / 100.0;
    canvas.scale(s, s);

    if (variant == ShijuanLogoVariant.emblem && !transparentBackdrop) {
      _paintEmblemBackdrop(canvas);
    }

    _paintFolio(canvas);

    canvas.restore();
  }

  void _paintEmblemBackdrop(Canvas canvas) {
    const outerRect = Rect.fromLTWH(0, 0, 100, 100);
    final outerRRect = RRect.fromRectAndRadius(
      outerRect,
      const Radius.circular(23),
    );

    final bgPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF2C231B),
          Color(0xFF1D1712),
          Color(0xFF120E0B),
        ],
        stops: [0.0, 0.56, 1.0],
      ).createShader(outerRect);
    canvas.drawRRect(outerRRect, bgPaint);

    // Subtle warm lamp halo centered slightly above the open folio.
    final glowPaint = Paint()
      ..shader = const RadialGradient(
        center: Alignment(0.0, -0.35),
        radius: 0.85,
        colors: [
          Color(0x28DFB47C),
          Color(0x00DFB47C),
        ],
      ).createShader(outerRect);
    canvas.drawRRect(outerRRect, glowPaint);

    // Delicate bronze inner frame.
    final frameRRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(4.5, 4.5, 91, 91),
      const Radius.circular(19),
    );
    final framePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.15
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0x52E6C798),
          Color(0x16B7915F),
          Color(0x36D1AA74),
        ],
      ).createShader(outerRect);
    canvas.drawRRect(frameRRect, framePaint);
  }

  void _paintFolio(Canvas canvas) {
    final isEmblem = variant == ShijuanLogoVariant.emblem;

    canvas.save();
    if (!isEmblem) {
      canvas.translate(50, 50);
      canvas.scale(1.20, 1.20);
      canvas.translate(-50, -50);
    } else {
      canvas.translate(0, -1.5);
    }

    // Subtle warm ink-wash ring centered behind the folio (no handle illusion).
    if (isEmblem && !transparentBackdrop) {
      final haloPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.85
        ..color = const Color(0x1EE3C496);
      canvas.drawCircle(const Offset(50, 50), 37.5, haloPaint);
    }

    // Hardcover / thick outer deck edge beneath the pages.
    final coverPath = Path()
      ..moveTo(15.5, 31.5)
      ..quadraticBezierTo(15.5, 28.0, 19.0, 28.5)
      ..quadraticBezierTo(36.5, 30.2, 50.0, 35.8)
      ..quadraticBezierTo(63.5, 30.2, 81.0, 28.5)
      ..quadraticBezierTo(84.5, 28.0, 84.5, 31.5)
      ..lineTo(84.5, 73.5)
      ..quadraticBezierTo(84.5, 77.0, 80.5, 76.6)
      ..quadraticBezierTo(63.5, 75.2, 50.0, 80.6)
      ..quadraticBezierTo(36.5, 75.2, 19.5, 76.6)
      ..quadraticBezierTo(15.5, 77.0, 15.5, 73.5)
      ..close();

    if (isEmblem) {
      canvas.drawPath(
        coverPath.shift(const Offset(0, 2.6)),
        Paint()..color = const Color(0x62000000),
      );
    }

    final deckColor = isEmblem
        ? const Color(0xFFA88C67)
        : (isDarkHost ? const Color(0xFF8C775E) : const Color(0xFFCBB89D));
    canvas.drawPath(coverPath, Paint()..color = deckColor);

    // Middle layered page deck edge.
    final midDeckPath = Path()
      ..moveTo(17.8, 28.8)
      ..quadraticBezierTo(17.8, 25.5, 21.2, 26.0)
      ..quadraticBezierTo(37.0, 27.5, 50.0, 33.4)
      ..quadraticBezierTo(63.0, 27.5, 78.8, 26.0)
      ..quadraticBezierTo(82.2, 25.5, 82.2, 28.8)
      ..lineTo(82.2, 71.2)
      ..quadraticBezierTo(82.2, 74.2, 78.8, 73.9)
      ..quadraticBezierTo(63.0, 72.6, 50.0, 78.2)
      ..quadraticBezierTo(37.0, 72.6, 21.2, 73.9)
      ..quadraticBezierTo(17.8, 74.2, 17.8, 71.2)
      ..close();
    final midDeckColor = isEmblem
        ? const Color(0xFFD2BE9F)
        : (isDarkHost ? const Color(0xFFAA957B) : const Color(0xFFE0D1BA));
    canvas.drawPath(midDeckPath, Paint()..color = midDeckColor);

    // Left page (brighter lit side).
    final leftPage = Path()
      ..moveTo(50.0, 31.2)
      ..quadraticBezierTo(37.5, 23.0, 22.5, 23.0)
      ..quadraticBezierTo(19.8, 23.0, 19.8, 25.8)
      ..lineTo(19.8, 68.4)
      ..quadraticBezierTo(19.8, 71.2, 22.6, 70.9)
      ..quadraticBezierTo(37.8, 69.4, 50.0, 76.0)
      ..close();

    final leftEnd = Color.lerp(pageColor, const Color(0xFFDDCBB0), 0.22)!;
    canvas.drawPath(
      leftPage,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [pageColor, leftEnd],
        ).createShader(const Rect.fromLTWH(19, 23, 31, 53)),
    );

    // Right page (soft shaded side).
    final rightPage = Path()
      ..moveTo(50.0, 31.2)
      ..quadraticBezierTo(62.5, 23.0, 77.5, 23.0)
      ..quadraticBezierTo(80.2, 23.0, 80.2, 25.8)
      ..lineTo(80.2, 68.4)
      ..quadraticBezierTo(80.2, 71.2, 77.4, 70.9)
      ..quadraticBezierTo(62.2, 69.4, 50.0, 76.0)
      ..close();

    final rightStart = Color.lerp(pageColor, const Color(0xFFE5D4BA), 0.34)!;
    final rightEnd = Color.lerp(pageColor, const Color(0xFFCBB596), 0.52)!;
    canvas.drawPath(
      rightPage,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [rightStart, rightEnd],
        ).createShader(const Rect.fromLTWH(50, 23, 31, 53)),
    );

    if (!isEmblem) {
      final outline = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.35
        ..color = inkColor.withValues(alpha: isDarkHost ? 0.36 : 0.22);
      canvas.drawPath(leftPage, outline);
      canvas.drawPath(rightPage, outline);
    }

    // Center gutter shadow & delicate paper fold crease, clipped cleanly to the pages.
    final pagesUnion = Path.combine(PathOperation.union, leftPage, rightPage);
    canvas.save();
    canvas.clipPath(pagesUnion);
    const gutterRect = Rect.fromLTWH(43.5, 23.0, 13.0, 55.0);
    canvas.drawRect(
      gutterRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Colors.transparent,
            Color(0x2221160E),
            Color(0x46180F09),
            Color(0x2021160E),
            Colors.transparent,
          ],
          stops: [0.0, 0.35, 0.5, 0.65, 1.0],
        ).createShader(gutterRect),
    );
    canvas.restore();

    canvas.drawLine(
      const Offset(50.0, 31.6),
      const Offset(50.0, 75.5),
      Paint()
        ..strokeWidth = 0.85
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFF4A3A2B).withValues(alpha: 0.42),
    );

    // Delicate typography lines on left page.
    final textStroke = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.75
      ..color = (isEmblem ? const Color(0xFF3E3024) : inkColor)
          .withValues(alpha: 0.24);
    canvas.drawLine(const Offset(26.0, 35.0), const Offset(43.2, 36.6), textStroke);
    canvas.drawLine(const Offset(26.0, 41.6), const Offset(43.2, 43.2), textStroke);
    canvas.drawLine(const Offset(26.0, 48.2), const Offset(38.5, 49.4), textStroke);

    // Subtle right-page colophon lines neatly below the bookmark ribbon.
    final rightStroke = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.6
      ..color = (isEmblem ? const Color(0xFF3E3024) : inkColor)
          .withValues(alpha: 0.14);
    canvas.drawLine(const Offset(56.8, 55.8), const Offset(72.8, 54.6), rightStroke);
    canvas.drawLine(const Offset(56.8, 61.8), const Offset(68.0, 61.0), rightStroke);

    // Cinnabar red chop seal with delicate carved strokes on lower-left page.
    final sealRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(26.0, 56.2, 7.6, 7.6),
      const Radius.circular(1.4),
    );
    canvas.drawRRect(
      sealRect,
      Paint()..color = accentColor.withValues(alpha: 0.90),
    );
    final sealCarve = Paint()
      ..strokeWidth = 0.9
      ..strokeCap = StrokeCap.round
      ..color = pageColor.withValues(alpha: 0.88);
    canvas.drawLine(const Offset(28.0, 58.6), const Offset(31.6, 58.6), sealCarve);
    canvas.drawLine(const Offset(29.8, 57.8), const Offset(29.8, 62.0), sealCarve);
    canvas.drawLine(const Offset(27.8, 61.4), const Offset(31.8, 61.4), sealCarve);

    // Folded cinnabar silk bookmark ribbon draping over top-right page edge.
    // Tiny dark fold lip peeking over the page top edge.
    final ribbonFoldBack = Path()
      ..moveTo(64.5, 22.8)
      ..lineTo(72.5, 22.2)
      ..lineTo(72.5, 24.4)
      ..lineTo(64.5, 24.8)
      ..close();
    canvas.drawPath(
      ribbonFoldBack,
      Paint()..color = Color.lerp(accentColor, Colors.black, 0.35)!,
    );

    final ribbon = Path()
      ..moveTo(64.5, 23.8)
      ..lineTo(72.5, 23.0)
      ..lineTo(72.5, 48.5)
      ..lineTo(68.5, 44.0)
      ..lineTo(64.5, 48.5)
      ..close();
    canvas.drawPath(
      ribbon.shift(const Offset(-0.7, 1.0)),
      Paint()..color = const Color(0x1E000000),
    );
    canvas.drawPath(
      ribbon,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(accentColor, Colors.white, 0.14)!,
            accentColor,
            Color.lerp(accentColor, Colors.black, 0.16)!,
          ],
        ).createShader(const Rect.fromLTWH(64, 23, 9, 26)),
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant ShijuanLogoPainter oldDelegate) =>
      oldDelegate.variant != variant ||
      oldDelegate.pageColor != pageColor ||
      oldDelegate.inkColor != inkColor ||
      oldDelegate.accentColor != accentColor ||
      oldDelegate.isDarkHost != isDarkHost ||
      oldDelegate.transparentBackdrop != transparentBackdrop;
}

/// Brand lockup displaying the vector mark alongside the serif wordmark.
class ShijuanBrandLockup extends StatelessWidget {
  const ShijuanBrandLockup({
    super.key,
    this.logoSize = 34,
    this.compact = false,
  });

  final double logoSize;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ShijuanLogo(size: logoSize, variant: ShijuanLogoVariant.emblem),
        SizedBox(width: compact ? 10 : 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '拾卷',
              style: TextStyle(
                fontFamily: 'Modu WenKai',
                fontFamilyFallback: const ['Modu Song', 'serif'],
                fontSize: compact ? 18 : 21,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface,
                height: 1.1,
                letterSpacing: 1.4,
              ),
            ),
            if (!compact) ...[
              const SizedBox(height: 2),
              Text(
                'SHIJUAN READER',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 2.0,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.48),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
