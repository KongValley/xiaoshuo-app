import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// A page is a range of UTF-16 offsets inside a chapter's body text.
class PageSlice {
  const PageSlice(this.start, this.end);

  final int start;
  final int end;

  int get length => end - start;

  @override
  String toString() => 'PageSlice($start..$end)';
}

/// Splits chapter text into pages using exactly the same text styles that the
/// reader paints with.
class Paginator {
  Paginator._();

  static const Locale _locale = Locale('zh', 'CN');
  static const double titleMetaGap = 10;
  static const double defaultHeadingGap = 26;

  static List<PageSlice> paginate({
    required String text,
    required TextStyle bodyStyle,
    required double width,
    required double height,
    String? heading,
    TextStyle? headingStyle,
    String? headingMeta,
    TextStyle? metaStyle,
    double headingGap = defaultHeadingGap,
  }) {
    if (text.isEmpty) return const [];

    var firstPageHeight = height;
    if (heading != null && heading.isNotEmpty && headingStyle != null) {
      final titlePainter = TextPainter(
        text: TextSpan(text: heading, style: headingStyle),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.left,
        maxLines: 3,
        ellipsis: '…',
        locale: _locale,
      )..layout(maxWidth: width);
      var headerHeight = titlePainter.height;
      if (headingMeta != null &&
          headingMeta.isNotEmpty &&
          metaStyle != null) {
        final metaPainter = TextPainter(
          text: TextSpan(text: headingMeta, style: metaStyle),
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.left,
          locale: _locale,
        )..layout(maxWidth: width);
        headerHeight += titleMetaGap + metaPainter.height;
      }
      firstPageHeight = height - headerHeight - headingGap;
    }

    final pages = <PageSlice>[];
    var start = 0;
    var first = true;

    while (start < text.length) {
      final available =
          (first ? firstPageHeight : height).clamp(24.0, height).toDouble();
      final remainingLength = text.length - start;
      var windowLength = math.min(remainingLength, 12000);
      late TextPainter painter;
      late String window;

      while (true) {
        window = text.substring(start, start + windowLength);
        painter = TextPainter(
          text: TextSpan(text: window, style: bodyStyle),
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.left,
          locale: _locale,
        )..layout(maxWidth: width);
        if (painter.height > available + 0.5 ||
            windowLength >= remainingLength ||
            windowLength >= 48000) {
          break;
        }
        windowLength = math.min(remainingLength, windowLength * 2);
      }

      int end;
      if (painter.height <= available + 0.5) {
        end = start + windowLength;
      } else {
        final metrics = painter.computeLineMetrics();
        var top = 0.0;
        var lastTop = 0.0;
        var lastHeight = 0.0;
        var found = false;
        for (final metric in metrics) {
          if (top + metric.height <= available + 0.5) {
            lastTop = top;
            lastHeight = metric.height;
            found = true;
            top += metric.height;
          } else {
            break;
          }
        }
        if (!found) {
          end = start + _fallbackBreak(window);
        } else {
          final position = painter.getPositionForOffset(
            Offset(width - 0.5, lastTop + lastHeight * 0.5),
          );
          end = start + position.offset;
          if (end <= start) end = start + _fallbackBreak(window);
        }
      }

      if (end <= start) end = math.min(text.length, start + 1);
      if (end > text.length) end = text.length;
      pages.add(PageSlice(start, end));

      var next = end;
      while (next < text.length) {
        final unit = text.codeUnitAt(next);
        if (unit == 0x0A || unit == 0x20 || unit == 0x3000) {
          next++;
        } else {
          break;
        }
      }
      if (next <= start) next = end;
      start = next;
      first = false;
    }

    if (pages.isEmpty) pages.add(PageSlice(0, text.length));
    return pages;
  }

  static int _fallbackBreak(String text) {
    final limit = math.min(text.length, 240);
    final newline = text.lastIndexOf('\n', limit - 1);
    if (newline > 0) return newline + 1;
    return limit;
  }
}
