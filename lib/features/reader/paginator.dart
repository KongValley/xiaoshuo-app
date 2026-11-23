import 'dart:math' as math;

import 'package:flutter/foundation.dart';
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

  /// Lower bound for the text examined for a single page. A phone page holds a
  /// few hundred characters, so this is already a page plus the line that has
  /// to follow it.
  static const int _minWindow = 600;

  /// Safety net for unusually tall layouts.
  static const int _maxWindow = 48000;

  /// Characters laid out by the most recent [paginate] call. Tests use it to
  /// guard the cost of long chapters without relying on timing.
  @visibleForTesting
  static int lastLaidOutChars = 0;

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
    if (text.isEmpty) {
      lastLaidOutChars = 0;
      return const [];
    }

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
      titlePainter.dispose();
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
        metaPainter.dispose();
      }
      firstPageHeight = height - headerHeight - headingGap;
    }

    final pages = <PageSlice>[];
    var start = 0;
    var first = true;
    // Examining a fixed 12,000-character window for every page made long
    // chapters take seconds to lay out. A page only needs to look a little
    // past its own length, so the window follows the previous page and keeps
    // doubling whenever the whole window still fits.
    var windowHint = _minWindow;
    var laidOut = 0;

    while (start < text.length) {
      final available =
          (first ? firstPageHeight : height).clamp(24.0, height).toDouble();
      final remainingLength = text.length - start;
      var windowLength = math.min(remainingLength, windowHint);
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
        laidOut += windowLength;
        if (painter.height > available + 0.5 ||
            windowLength >= remainingLength ||
            windowLength >= _maxWindow) {
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
      painter.dispose();

      if (end <= start) end = math.min(text.length, start + 1);
      if (end > text.length) end = text.length;
      pages.add(PageSlice(start, end));
      final pageLength = end - start;
      if (pageLength > 0) {
        windowHint = math.max(_minWindow, (pageLength * 1.6).ceil());
      }

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

    lastLaidOutChars = laidOut;
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
