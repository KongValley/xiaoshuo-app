import 'dart:convert';
import 'dart:typed_data';

import 'package:enough_convert/enough_convert.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modu_reader/data/txt/encoding.dart';

Uint8List _utf16(String text, {bool littleEndian = true, bool bom = true}) {
  final bytes = <int>[];
  if (bom) {
    bytes.addAll(littleEndian ? [0xFF, 0xFE] : [0xFE, 0xFF]);
  }
  for (final unit in text.codeUnits) {
    if (littleEndian) {
      bytes.add(unit & 0xFF);
      bytes.add((unit >> 8) & 0xFF);
    } else {
      bytes.add((unit >> 8) & 0xFF);
      bytes.add(unit & 0xFF);
    }
  }
  return Uint8List.fromList(bytes);
}

void main() {
  test('decodes UTF-8 with and without BOM', () {
    const text = '第一章 起点\n　　这是正文。';
    final plain = decodeNovelBytes(Uint8List.fromList(utf8.encode(text)));
    expect(plain.encoding, 'UTF-8');
    expect(plain.text, text);

    final withBom = decodeNovelBytes(
      Uint8List.fromList(<int>[0xEF, 0xBB, 0xBF, ...utf8.encode(text)]),
    );
    expect(withBom.encoding, 'UTF-8');
    expect(withBom.text, text);
  });

  test('decodes GBK', () {
    const text = '第一章 起点\n这是正文，包含中文标点。';
    final bytes = Uint8List.fromList(const GbkCodec().encode(text));
    final decoded = decodeNovelBytes(bytes);
    expect(decoded.encoding, 'GBK');
    expect(decoded.text, text);
  });

  test('decodes UTF-16 LE and BE with BOM', () {
    const text = 'Chapter 1 起点\n正文。';
    final le = decodeNovelBytes(_utf16(text));
    expect(le.encoding, 'UTF-16 LE');
    expect(le.text, text);

    final be = decodeNovelBytes(_utf16(text, littleEndian: false));
    expect(be.encoding, 'UTF-16 BE');
    expect(be.text, text);
  });

  test('detects UTF-16 without BOM from NUL bytes', () {
    const text = 'Hello 世界, this is a test.';
    final bytes = _utf16(text, bom: false);
    final decoded = decodeNovelBytes(bytes);
    expect(decoded.encoding, 'UTF-16 LE');
    expect(decoded.text, text);
  });

  test('keeps damaged UTF-8 instead of misdetecting it as GBK', () {
    const text = '第一章 起点，这是正文。';
    final bytes = Uint8List.fromList(<int>[
      ...utf8.encode(text),
      0xFF, // trailing invalid byte, as found in slightly damaged files
    ]);
    final decoded = decodeNovelBytes(bytes);
    expect(decoded.encoding, 'UTF-8');
    expect(decoded.text, contains('第一章 起点'));
  });

  test('empty input decodes safely', () {
    final decoded = decodeNovelBytes(Uint8List(0));
    expect(decoded.text, isEmpty);
    expect(decoded.encoding, 'UTF-8');
  });
}
