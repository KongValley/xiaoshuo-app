import 'dart:convert';
import 'dart:typed_data';

import 'package:enough_convert/enough_convert.dart';

class DecodedNovel {
  const DecodedNovel(this.text, this.encoding);

  final String text;
  final String encoding;
}

/// Decodes a local TXT file without any platform plugin.
///
/// Handles UTF-8 (with or without BOM), UTF-16 LE/BE with BOM, UTF-16 without
/// BOM when the byte pattern is obvious, and GBK/GB2312. A slightly damaged
/// UTF-8 file is still treated as UTF-8 instead of being misdetected as GBK.
DecodedNovel decodeNovelBytes(Uint8List bytes) {
  if (bytes.isEmpty) return const DecodedNovel('', 'UTF-8');

  // UTF-32 BOMs must be checked before UTF-16 LE (FF FE 00 00).
  if (_startsWith(bytes, const [0xFF, 0xFE, 0x00, 0x00])) {
    return DecodedNovel(_decodeUtf32(bytes.sublist(4), littleEndian: true), 'UTF-32 LE');
  }
  if (_startsWith(bytes, const [0x00, 0x00, 0xFE, 0xFF])) {
    return DecodedNovel(_decodeUtf32(bytes.sublist(4), littleEndian: false), 'UTF-32 BE');
  }
  if (_startsWith(bytes, const [0xEF, 0xBB, 0xBF])) {
    return DecodedNovel(utf8.decode(bytes.sublist(3), allowMalformed: true), 'UTF-8');
  }
  if (_startsWith(bytes, const [0xFF, 0xFE])) {
    return DecodedNovel(
      _decodeUtf16(bytes.sublist(2), littleEndian: true),
      'UTF-16 LE',
    );
  }
  if (_startsWith(bytes, const [0xFE, 0xFF])) {
    return DecodedNovel(
      _decodeUtf16(bytes.sublist(2), littleEndian: false),
      'UTF-16 BE',
    );
  }

  final utf16Guess = _guessUtf16Endianness(bytes);
  if (utf16Guess != null) {
    return DecodedNovel(
      _decodeUtf16(bytes, littleEndian: utf16Guess),
      utf16Guess ? 'UTF-16 LE' : 'UTF-16 BE',
    );
  }

  try {
    return DecodedNovel(utf8.decode(bytes), 'UTF-8');
  } on FormatException {
    // Fall through.
  }

  final utf8Lenient = utf8.decode(bytes, allowMalformed: true);
  final utf8Replacements = _replacementCount(utf8Lenient);
  // A handful of broken bytes is much more likely to be a damaged UTF-8 file
  // than a GBK file. Do not silently turn it into mojibake.
  if (utf8Replacements <= 8) {
    return DecodedNovel(utf8Lenient, 'UTF-8');
  }
  final utf8Damage = utf8Replacements / utf8Lenient.length;

  try {
    final gbkStrict = const GbkCodec().decode(bytes);
    return DecodedNovel(gbkStrict, 'GBK');
  } on FormatException {
    // Fall through to lenient comparison.
  } catch (_) {
    // Fall through.
  }

  String gbkLenient;
  try {
    gbkLenient = const GbkCodec(allowInvalid: true).decode(bytes);
  } catch (_) {
    return DecodedNovel(utf8Lenient, 'UTF-8');
  }

  final gbkDamage = _replacementRatio(gbkLenient);
  if (gbkDamage + 0.0002 < utf8Damage) {
    return DecodedNovel(gbkLenient, 'GBK');
  }
  return DecodedNovel(utf8Lenient, 'UTF-8');
}

bool _startsWith(Uint8List bytes, List<int> prefix) {
  if (bytes.length < prefix.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (bytes[i] != prefix[i]) return false;
  }
  return true;
}

/// UTF-16 text without a BOM contains NUL bytes in one of the two byte
/// positions. Only report a guess when the pattern is clear.
bool? _guessUtf16Endianness(Uint8List bytes) {
  final sampleLength = bytes.length < 8192 ? bytes.length & ~1 : 8192;
  if (sampleLength < 32) return null;
  var evenZero = 0;
  var oddZero = 0;
  final pairs = sampleLength ~/ 2;
  for (var i = 0; i < sampleLength; i += 2) {
    if (bytes[i] == 0) evenZero++;
    if (bytes[i + 1] == 0) oddZero++;
  }
  final evenRatio = evenZero / pairs;
  final oddRatio = oddZero / pairs;
  if (oddRatio > 0.18 && evenRatio < 0.03) return true; // LE
  if (evenRatio > 0.18 && oddRatio < 0.03) return false; // BE
  return null;
}

String _decodeUtf16(Uint8List bytes, {required bool littleEndian}) {
  final length = bytes.length ~/ 2;
  final units = Uint16List(length);
  for (var i = 0; i < length; i++) {
    final first = bytes[i * 2];
    final second = bytes[i * 2 + 1];
    units[i] = littleEndian ? (first | (second << 8)) : ((first << 8) | second);
  }
  var text = String.fromCharCodes(units);
  if (text.startsWith('\uFEFF')) text = text.substring(1);
  return text;
}

String _decodeUtf32(Uint8List bytes, {required bool littleEndian}) {
  final length = bytes.length ~/ 4;
  final buffer = StringBuffer();
  for (var i = 0; i < length; i++) {
    final offset = i * 4;
    final value = littleEndian
        ? bytes[offset] |
            (bytes[offset + 1] << 8) |
            (bytes[offset + 2] << 16) |
            (bytes[offset + 3] << 24)
        : (bytes[offset] << 24) |
            (bytes[offset + 1] << 16) |
            (bytes[offset + 2] << 8) |
            bytes[offset + 3];
    if (value <= 0x10FFFF && value != 0xFEFF) {
      buffer.writeCharCode(value);
    }
  }
  return buffer.toString();
}

double _replacementRatio(String text) {
  if (text.isEmpty) return 0;
  return _replacementCount(text) / text.length;
}

int _replacementCount(String text) {
  var count = 0;
  for (final unit in text.codeUnits) {
    if (unit == 0xFFFD) count++;
  }
  return count;
}
