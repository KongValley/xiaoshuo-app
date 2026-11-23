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
}
