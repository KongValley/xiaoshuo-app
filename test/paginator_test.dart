import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modu_reader/features/reader/paginator.dart';

void main() {
  testWidgets('paginates a long chapter into ordered pages', (tester) async {
    final text = List<String>.generate(
      240,
      (i) => '第$i段：夜色渐深，风从窗缝里钻进来，书页轻轻翻动，远处传来几声犬吠。',
    ).join('\n');

    final pages = Paginator.paginate(
      text: text,
      bodyStyle: const TextStyle(fontSize: 19, height: 1.8),
      width: 460,
      height: 620,
      heading: '第一章 起点',
      headingStyle: const TextStyle(
        fontSize: 27,
        height: 1.25,
        fontWeight: FontWeight.w600,
      ),
      headingMeta: '共 6,000 字',
      metaStyle: const TextStyle(fontSize: 13, height: 1.3),
    );

    expect(pages.length, greaterThan(1));
    expect(pages.first.start, 0);
    expect(pages.last.end, text.length);
    for (var i = 0; i < pages.length; i++) {
      expect(pages[i].end, greaterThan(pages[i].start));
      if (i > 0) {
        expect(pages[i].start, greaterThanOrEqualTo(pages[i - 1].end));
      }
    }
    // The heading occupies room on the first page, so it holds less text.
    expect(pages.first.length, lessThan(pages[1].length));
  });

  testWidgets('keeps a short chapter on a single page', (tester) async {
    final pages = Paginator.paginate(
      text: '很短的一章正文。',
      bodyStyle: const TextStyle(fontSize: 19, height: 1.8),
      width: 460,
      height: 620,
      heading: '第一章',
      headingStyle: const TextStyle(fontSize: 27, height: 1.25),
    );
    expect(pages, hasLength(1));
    expect(pages.single.start, 0);
    expect(pages.single.end, '很短的一章正文。'.length);
  });

  testWidgets('never returns an empty page for tight layouts', (tester) async {
    final pages = Paginator.paginate(
      text: '第一段。\n第二段。\n第三段。',
      bodyStyle: const TextStyle(fontSize: 19, height: 1.8),
      width: 120,
      height: 30,
    );
    expect(pages, isNotEmpty);
    for (final page in pages) {
      expect(page.end, greaterThan(page.start));
    }
  });

  testWidgets('fills every page of a long chapter without overrunning it', (
    tester,
  ) async {
    const width = 312.0;
    const height = 528.0;
    const bodyStyle = TextStyle(fontSize: 19, height: 1.8);
    final text = List<String>.generate(
      400,
      (i) => '第$i段：夜色渐深，风从窗缝里钻进来，书页轻轻翻动，远处传来几声犬吠。',
    ).join('\n');

    final pages = Paginator.paginate(
      text: text,
      bodyStyle: bodyStyle,
      width: width,
      height: height,
      heading: '第一章 起点',
      headingStyle: const TextStyle(
        fontSize: 27,
        height: 1.25,
        fontWeight: FontWeight.w600,
      ),
      headingMeta: '共 9,000 字',
      metaStyle: const TextStyle(fontSize: 13, height: 1.3),
    );

    double heightOf(String slice) {
      final painter = TextPainter(
        text: TextSpan(text: slice, style: bodyStyle),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.left,
      )..layout(maxWidth: width);
      final value = painter.height;
      painter.dispose();
      return value;
    }

    // The first page gives up this much room to the heading, like the reader.
    const header = 27 * 1.25 +
        Paginator.titleMetaGap +
        13 * 1.3 +
        Paginator.defaultHeadingGap;

    expect(pages.length, greaterThan(10));
    expect(pages.first.start, 0);
    expect(pages.last.end, text.length);
    for (var i = 0; i < pages.length; i++) {
      final page = pages[i];
      final available = i == 0 ? height - header : height;
      // Nothing may spill past the bottom of the page.
      expect(
        heightOf(text.substring(page.start, page.end)),
        lessThanOrEqualTo(available + 0.5),
      );
      if (i > 0) {
        // A page starts at real text, never at the indent of a paragraph.
        expect(text.codeUnitAt(page.start), isNot(anyOf(0x0A, 0x20, 0x3000)));
      }
      if (i == pages.length - 1) continue;
      // ...and there was no room for the first line of the next page.
      final extended = text.substring(
        page.start,
        math.min(pages[i + 1].start + 30, text.length),
      );
      expect(heightOf(extended), greaterThan(available + 0.5));
    }
  });

  testWidgets('lays out little more text than the chapter contains', (
    tester,
  ) async {
    final text = List<String>.generate(
      1500,
      (i) => '第$i段：夜色渐深，风从窗缝里钻进来，书页轻轻翻动，远处传来几声犬吠。',
    ).join('\n');

    final pages = Paginator.paginate(
      text: text,
      bodyStyle: const TextStyle(fontSize: 19, height: 1.8),
      width: 312,
      height: 528,
    );

    expect(pages.length, greaterThan(100));
    // The fixed 12,000-character window this replaced laid the chapter out
    // about fifty times over.
    expect(Paginator.lastLaidOutChars, lessThan(text.length * 4));
  });
}
