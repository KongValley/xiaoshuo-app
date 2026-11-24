import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shijuan_reader/data/txt/parser.dart';
import 'package:path/path.dart' as p;

/// Integration check against the novel that ships in the project root.
void main() {
  test('parses the bundled test novel', () {
    const path = '[sxsy.org]末世第一狠人.txt';
    final file = File(path);
    if (!file.existsSync()) {
      // The sample is intentionally not part of the repository's package.
      return;
    }

    final parsed = TxtParser.parse(
      file.readAsBytesSync(),
      fileName: p.basename(path),
    );

    expect(parsed.title, '末世第一狠人');
    expect(parsed.encoding, 'UTF-8');
    expect(parsed.chapters.length, greaterThan(1700));
    expect(parsed.chapters.first.start, 0);
    expect(parsed.chapters.first.title, startsWith('001 '));
    expect(parsed.chapters.last.title, startsWith('1737 '));
    expect(parsed.content, startsWith('　　月色清净'));
    expect(parsed.content, isNot(contains('001 一切都那么美好')));

    for (var i = 0; i < parsed.chapters.length - 1; i++) {
      expect(parsed.chapters[i].end, parsed.chapters[i + 1].start);
      expect(parsed.chapters[i].end, greaterThan(parsed.chapters[i].start));
    }
    final last = parsed.chapters.last;
    expect(parsed.content.substring(last.start, last.end), isNotEmpty);
  });
}
