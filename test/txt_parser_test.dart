import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shijuan_reader/data/txt/parser.dart';

ParsedNovel _parse(String text, {String fileName = '测试小说.txt'}) =>
    TxtParser.parse(
      Uint8List.fromList(utf8.encode(text)),
      fileName: fileName,
    );

void main() {
  test('splits Chinese chapter headings and extracts metadata', () {
    final parsed = _parse(
      '''
序言内容。

第一章 起点
　　第一段。

第二章 转折
　　第二段。
''',
      fileName: '《测试小说》作者：张三.txt',
    );

    expect(parsed.title, '测试小说');
    expect(parsed.author, '张三');
    expect(parsed.encoding, 'UTF-8');
    expect(parsed.chapters.map((chapter) => chapter.title).toList(), [
      '第一章 起点',
      '第二章 转折',
    ]);
    expect(parsed.content, contains('第一段。'));
    expect(parsed.content, isNot(contains('第一章 起点')));
    expect(parsed.chapters.first.start, 0);
    expect(parsed.chapters.first.end, parsed.chapters.last.start);
  });

  test('supports numbered headings without mistaking body lines', () {
    final parsed = _parse(
      '''
001 一切都那么美好
　　正文一。

002 起猛了
　　正文二。

7点06分，水果玲姐：订了
　　正文三。

003 第三个
　　正文四。

2、陷阱系统，分为防范丧尸和防范人类入侵……
''',
      fileName: '[sxsy.org]末世第一狠人.txt',
    );

    expect(parsed.title, '末世第一狠人');
    expect(parsed.author, isEmpty);
    expect(parsed.chapters, hasLength(3));
    expect(parsed.chapters[0].title, '001 一切都那么美好');
    expect(parsed.chapters[2].title, '003 第三个');
    expect(parsed.content, contains('7点06分'));
    expect(parsed.content, contains('2、陷阱系统'));
  });

  test('splits a long book without headings into sections', () {
    final buffer = StringBuffer();
    for (var i = 0; i < 500; i++) {
      buffer.writeln('　　第$i段，夜色渐深，风从窗缝里钻进来，书页轻轻翻动。');
      buffer.writeln();
    }
    final parsed = _parse(buffer.toString());
    expect(parsed.chapters.length, greaterThan(1));
    expect(parsed.chapters.first.title, '第 1 节');
    expect(parsed.content.length, greaterThan(8000));
  });

  test('joins hard-wrapped lines inside blank-line separated paragraphs', () {
    final parsed = _parse('这是第一行被硬换行\n接着第二行内容\n\n新的段落\n');
    expect(parsed.content, contains('这是第一行被硬换行接着第二行内容'));
    expect(parsed.content, contains('新的段落'));
  });

  test('drops site watermark lines', () {
    final parsed = _parse('第一章 起点\n　　www.sxsy.org\n　　正文。');
    expect(parsed.content, isNot(contains('sxsy.org')));
    expect(parsed.content, contains('正文。'));
  });

  test('keeps a chapter title that ends with a full stop', () {
    final parsed = _parse('''
421 前情
　　正文。

422 请确认收获地址，亲。
　　正文二。

423 后续
　　正文三。
''');
    expect(parsed.chapters.map((chapter) => chapter.title), contains('422 请确认收获地址，亲。'));
  });

  test('supports English chapter headings', () {
    final parsed = _parse('''
Chapter 1 Beginning
Body one.

Chapter 2 Ending
Body two.
''');
    expect(parsed.chapters.map((chapter) => chapter.title).toList(), [
      'Chapter 1 Beginning',
      'Chapter 2 Ending',
    ]);
  });

  test('cleans common file names into titles', () {
    expect(TxtParser.titleFromFileName('[sxsy.org]末世第一狠人.txt'), '末世第一狠人');
    expect(TxtParser.titleFromFileName('《长夜》作者：李四.txt'), '长夜');
    expect(TxtParser.titleFromFileName('无名小说（完本）.txt'), '无名小说');
  });

  test('handles CRLF and empty chapters without crashing', () {
    final parsed = _parse('第一章 只有标题\r\n\r\n第二章 正文\r\n　　内容。\r\n');
    expect(parsed.chapters, hasLength(1));
    expect(parsed.chapters.single.title, '第二章 正文');
    expect(parsed.content, contains('内容。'));
  });
}
