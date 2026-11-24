import 'dart:convert';
import 'dart:typed_data';

import 'package:unseal/unseal.dart' as unseal;

import '../txt/parser.dart';

/// Result of extracting plain text from a legacy `.doc` file.
sealed class LegacyDocExtract {
  const LegacyDocExtract();
}

/// Extracted readable text to pass through chapter & paragraph parsing.
class LegacyDocText extends LegacyDocExtract {
  const LegacyDocText({required this.text, required this.encodingLabel});

  final String text;
  final String encodingLabel;
}

/// The `.doc` file turned out to actually be a DOCX ZIP or RTF stream.
class LegacyDocUnsealed extends LegacyDocExtract {
  const LegacyDocUnsealed({required this.book, required this.encodingLabel});

  final unseal.Book book;
  final String encodingLabel;
}

/// Pure-Dart text extractor for Word `.doc` files.
///
/// Handles real-world `.doc` payloads: RTF-wrapped `.doc`, renamed `.docx` ZIP
/// packages, HTML-as-`.doc`, and genuine Word 97–2003 OLE2 binary documents
/// via their FIB and Piece Table (`Clx` / `PlcPcd`).
class LegacyDocParser {
  LegacyDocParser._();

  static const List<int> _ole2Magic = [
    0xD0,
    0xCF,
    0x11,
    0xE0,
    0xA1,
    0xB1,
    0x1A,
    0xE1,
  ];

  static LegacyDocExtract extract(Uint8List bytes) {
    if (bytes.length < 8) {
      throw const FormatException('Word 文档内容过短或已损坏');
    }

    // 1. RTF-disguised `.doc` (`{\rtf...`).
    if (_startsWithAscii(bytes, r'{\rtf')) {
      final book = unseal.parseRtfBook(bytes);
      return LegacyDocUnsealed(book: book, encodingLabel: 'DOC/RTF');
    }

    // 2. Zip-disguised `.docx` named `.doc`.
    if (bytes[0] == 0x50 &&
        bytes[1] == 0x4B &&
        bytes[2] == 0x03 &&
        bytes[3] == 0x04) {
      final book = unseal.parseDocxBook(bytes);
      return LegacyDocUnsealed(book: book, encodingLabel: 'DOCX');
    }

    // 3. HTML saved with `.doc` extension.
    final probe = utf8
        .decode(bytes.sublist(0, bytes.length < 512 ? bytes.length : 512),
            allowMalformed: true)
        .trimLeft()
        .toLowerCase();
    if (probe.startsWith('<html') ||
        probe.startsWith('<!doctype') ||
        probe.startsWith('<?xml') && probe.contains('<html')) {
      final book = unseal.parseHtmlBook(bytes);
      return LegacyDocUnsealed(book: book, encodingLabel: 'DOC/HTML');
    }

    // 4. Genuine Word 97–2003 OLE2 Compound Document Binary.
    if (_matchesMagic(bytes, _ole2Magic)) {
      final text = _extractOle2DocText(bytes);
      if (text.trim().isEmpty) {
        throw const FormatException('未能从 Word (.doc) 文档中提取出正文');
      }
      return LegacyDocText(text: text, encodingLabel: 'DOC');
    }

    throw const FormatException('无法识别的 .doc 文件格式，建议在 Word 中另存为 .docx');
  }

  static ParsedNovel parseAsNovel(
    Uint8List bytes, {
    required String fileName,
  }) {
    final extracted = extract(bytes);
    if (extracted is LegacyDocText) {
      final parsed = TxtParser.parse(
        Uint8List.fromList(utf8.encode(extracted.text)),
        fileName: fileName,
      );
      return ParsedNovel(
        title: parsed.title,
        author: parsed.author,
        encoding: extracted.encodingLabel,
        content: parsed.content,
        chapters: parsed.chapters,
        sourceBytes: bytes.length,
      );
    }
    throw StateError('Unexpected LegacyDocUnsealed');
  }

  static bool _matchesMagic(Uint8List bytes, List<int> magic) {
    if (bytes.length < magic.length) return false;
    for (var i = 0; i < magic.length; i++) {
      if (bytes[i] != magic[i]) return false;
    }
    return true;
  }

  static bool _startsWithAscii(Uint8List bytes, String prefix) {
    var offset = 0;
    while (offset < bytes.length &&
        (bytes[offset] == 0x20 ||
            bytes[offset] == 0x09 ||
            bytes[offset] == 0x0D ||
            bytes[offset] == 0x0A)) {
      offset++;
    }
    if (bytes.length - offset < prefix.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (bytes[offset + i] != prefix.codeUnitAt(i)) return false;
    }
    return true;
  }

  static String _extractOle2DocText(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    if (bytes.length < 512) {
      throw const FormatException('损坏的 Word (.doc) 容器头');
    }

    final sectorShift = data.getUint16(30, Endian.little);
    if (sectorShift < 7 || sectorShift > 16) {
      throw const FormatException('不支持的 OLE2 扇区尺寸');
    }
    final sectorSize = 1 << sectorShift;
    final miniShift = data.getUint16(32, Endian.little);
    final miniSectorSize = 1 << (miniShift == 0 ? 6 : miniShift);

    final numFatSectors = data.getUint32(44, Endian.little);
    final firstDirSector = data.getUint32(48, Endian.little);
    final miniStreamCutoff = data.getUint32(56, Endian.little);
    final firstMiniFatSector = data.getUint32(60, Endian.little);
    final numMiniFatSectors = data.getUint32(64, Endian.little);
    final firstDifatSector = data.getUint32(68, Endian.little);
    final numDifatSectors = data.getUint32(72, Endian.little);

    const endOfChain = 0xFFFFFFFE;
    const freeSect = 0xFFFFFFFF;

    int sectorOffset(int sectorId) => (sectorId + 1) * sectorSize;

    // 1. Collect FAT sector indices from header DIFAT (109 entries) + DIFAT chain.
    final fatSectorIds = <int>[];
    for (var i = 0; i < 109 && fatSectorIds.length < numFatSectors; i++) {
      final sid = data.getUint32(76 + i * 4, Endian.little);
      if (sid != freeSect && sid != endOfChain) {
        fatSectorIds.add(sid);
      }
    }
    var difatSid = firstDifatSector;
    var difatGuard = 0;
    while (difatSid != endOfChain &&
        difatSid != freeSect &&
        fatSectorIds.length < numFatSectors &&
        difatGuard < numDifatSectors + 4) {
      difatGuard++;
      final off = sectorOffset(difatSid);
      if (off + sectorSize > bytes.length) break;
      final perSector = (sectorSize ~/ 4) - 1;
      for (var i = 0; i < perSector && fatSectorIds.length < numFatSectors; i++) {
        final sid = data.getUint32(off + i * 4, Endian.little);
        if (sid != freeSect && sid != endOfChain) fatSectorIds.add(sid);
      }
      difatSid = data.getUint32(off + perSector * 4, Endian.little);
    }

    // 2. Build FAT table.
    final fat = <int>[];
    final entriesPerSector = sectorSize ~/ 4;
    for (final sid in fatSectorIds) {
      final off = sectorOffset(sid);
      if (off + sectorSize > bytes.length) continue;
      for (var i = 0; i < entriesPerSector; i++) {
        fat.add(data.getUint32(off + i * 4, Endian.little));
      }
    }

    Uint8List readFatChain(int startSector, int expectedLength) {
      if (startSector >= 0xFFFFFFFA) return Uint8List(0);
      final out = BytesBuilder(copy: false);
      final seen = <int>{};
      var sid = startSector;
      while (sid < fat.length && sid < 0xFFFFFFFA && seen.add(sid)) {
        final off = sectorOffset(sid);
        if (off < 0 || off + sectorSize > bytes.length) break;
        out.add(Uint8List.sublistView(bytes, off, off + sectorSize));
        sid = fat[sid];
      }
      final raw = out.toBytes();
      if (expectedLength >= 0 && expectedLength < raw.length) {
        return Uint8List.sublistView(raw, 0, expectedLength);
      }
      return raw;
    }

    // 3. Parse directory stream.
    final dirBytes = readFatChain(firstDirSector, -1);
    final dirData = ByteData.sublistView(dirBytes);
    _OleDirEntry? rootEntry;
    _OleDirEntry? wordDocEntry;
    _OleDirEntry? table0Entry;
    _OleDirEntry? table1Entry;

    for (var off = 0; off + 128 <= dirBytes.length; off += 128) {
      final nameByteLen = dirData.getUint16(off + 64, Endian.little);
      final objType = dirBytes[off + 66];
      if (objType == 0 || nameByteLen < 2 || nameByteLen > 64) continue;
      final charLen = (nameByteLen ~/ 2) - 1;
      final nameUnits = <int>[];
      for (var j = 0; j < charLen; j++) {
        nameUnits.add(dirData.getUint16(off + j * 2, Endian.little));
      }
      final name = String.fromCharCodes(nameUnits);
      final startSec = dirData.getUint32(off + 116, Endian.little);
      final size = dirData.getUint32(off + 120, Endian.little);
      final entry = _OleDirEntry(name, objType, startSec, size);
      if (objType == 5) {
        rootEntry ??= entry;
      } else if (objType == 2) {
        if (name == 'WordDocument') wordDocEntry = entry;
        if (name == '0Table') table0Entry = entry;
        if (name == '1Table') table1Entry = entry;
      }
    }

    if (wordDocEntry == null) {
      throw const FormatException('Word (.doc) 中缺少 WordDocument 正文流');
    }

    Uint8List? miniStream;
    List<int>? miniFat;

    Uint8List readEntryStream(_OleDirEntry entry) {
      if (entry.objType == 2 && entry.size < miniStreamCutoff && rootEntry != null) {
        miniStream ??= readFatChain(rootEntry.startSector, rootEntry.size);
        if (miniFat == null) {
          final mfBytes = readFatChain(
            firstMiniFatSector,
            numMiniFatSectors * sectorSize,
          );
          final mfData = ByteData.sublistView(mfBytes);
          miniFat = [
            for (var i = 0; i + 4 <= mfBytes.length; i += 4)
              mfData.getUint32(i, Endian.little),
          ];
        }
        final out = BytesBuilder(copy: false);
        final seen = <int>{};
        var sid = entry.startSector;
        while (sid < miniFat!.length && sid < 0xFFFFFFFA && seen.add(sid)) {
          final off = sid * miniSectorSize;
          if (off + miniSectorSize > miniStream!.length) break;
          out.add(Uint8List.sublistView(miniStream!, off, off + miniSectorSize));
          sid = miniFat![sid];
        }
        final raw = out.toBytes();
        return entry.size < raw.length
            ? Uint8List.sublistView(raw, 0, entry.size)
            : raw;
      }
      return readFatChain(entry.startSector, entry.size);
    }

    // 4. Read FIB & Piece Table.
    final wordBytes = readEntryStream(wordDocEntry);
    if (wordBytes.length < 0x4C) {
      throw const FormatException('Word (.doc) 文件头不完整');
    }
    final wordData = ByteData.sublistView(wordBytes);
    final wIdent = wordData.getUint16(0, Endian.little);
    if (wIdent != 0xA5EC && wIdent != 0xA5DC) {
      throw const FormatException('不是有效的 Word (.doc) 二进制格式');
    }

    final flags = wordData.getUint16(10, Endian.little);
    final fEncrypted = (flags & 0x0100) != 0;
    if (fEncrypted) {
      throw const FormatException('Word 文档已设置密码保护，无法导入');
    }
    final useTable1 = (flags & 0x0200) != 0;

    final csw = wordData.getUint16(0x20, Endian.little);
    final cslwOff = 0x22 + csw * 2;
    if (cslwOff + 2 > wordBytes.length) {
      throw const FormatException('Word (.doc) FIB 结构损坏');
    }
    final cslw = wordData.getUint16(cslwOff, Endian.little);
    final rgLwOff = cslwOff + 2;
    final ccpText = (cslw > 3 && rgLwOff + 16 <= wordBytes.length)
        ? wordData.getUint32(rgLwOff + 12, Endian.little)
        : 0;

    final cbRgFcLcbOff = rgLwOff + cslw * 4;
    if (cbRgFcLcbOff + 2 <= wordBytes.length) {
      final cbRgFcLcb = wordData.getUint16(cbRgFcLcbOff, Endian.little);
      final rgFcLcbOff = cbRgFcLcbOff + 2;
      if (cbRgFcLcb > 33 && rgFcLcbOff + 34 * 8 <= wordBytes.length) {
        final fcClx = wordData.getUint32(rgFcLcbOff + 33 * 8, Endian.little);
        final lcbClx = wordData.getUint32(rgFcLcbOff + 33 * 8 + 4, Endian.little);
        final tableEntry = useTable1 ? (table1Entry ?? table0Entry) : (table0Entry ?? table1Entry);
        if (lcbClx > 0 && tableEntry != null) {
          final tableBytes = readEntryStream(tableEntry);
          if (fcClx + lcbClx <= tableBytes.length) {
            final clxBytes = Uint8List.sublistView(tableBytes, fcClx, fcClx + lcbClx);
            final extracted = _decodePieceTable(wordBytes, clxBytes, ccpText);
            if (extracted.isNotEmpty) return _normalizeWordControlChars(extracted);
          }
        }
      }
    }

    // Legacy fallback if no Clx piece table is present.
    final fcMin = wordData.getUint32(0x18, Endian.little);
    final fcMac = wordData.getUint32(0x1C, Endian.little);
    if (fcMac > fcMin && fcMac <= wordBytes.length) {
      final slice = Uint8List.sublistView(wordBytes, fcMin, fcMac);
      return _normalizeWordControlChars(latin1.decode(slice, allowInvalid: true));
    }
    return '';
  }

  static String _decodePieceTable(
    Uint8List wordBytes,
    Uint8List clxBytes,
    int ccpText,
  ) {
    final clxData = ByteData.sublistView(clxBytes);
    var pos = 0;
    while (pos < clxBytes.length) {
      final clxt = clxBytes[pos];
      if (clxt == 0x01) {
        if (pos + 3 > clxBytes.length) return '';
        final cbGrpprl = clxData.getUint16(pos + 1, Endian.little);
        pos += 3 + cbGrpprl;
      } else if (clxt == 0x02) {
        if (pos + 5 > clxBytes.length) return '';
        final lcb = clxData.getUint32(pos + 1, Endian.little);
        final plcStart = pos + 5;
        if (lcb < 16 || plcStart + lcb > clxBytes.length) return '';

        final pieceCount = (lcb - 4) ~/ 12;
        if (pieceCount <= 0) return '';
        final pcdBase = plcStart + (pieceCount + 1) * 4;
        final out = StringBuffer();
        var collectedChars = 0;

        for (var i = 0; i < pieceCount; i++) {
          final cpStart = clxData.getUint32(plcStart + i * 4, Endian.little);
          final cpEnd = clxData.getUint32(plcStart + (i + 1) * 4, Endian.little);
          if (cpEnd <= cpStart) continue;
          var charCount = cpEnd - cpStart;
          if (ccpText > 0 && collectedChars >= ccpText) break;
          if (ccpText > 0 && collectedChars + charCount > ccpText) {
            charCount = ccpText - collectedChars;
          }

          final fcRaw = clxData.getUint32(pcdBase + i * 8 + 2, Endian.little);
          final isCompressed = (fcRaw & 0x40000000) != 0;
          final fcOffset = fcRaw & 0x3FFFFFFF;

          if (isCompressed) {
            final byteStart = fcOffset ~/ 2;
            final available = (wordBytes.length - byteStart).clamp(0, charCount);
            if (byteStart >= 0 && available > 0) {
              out.write(_decodeCp1252Slice(wordBytes, byteStart, available));
              collectedChars += available;
            }
          } else {
            final byteStart = fcOffset;
            final availableChars =
                ((wordBytes.length - byteStart) ~/ 2).clamp(0, charCount);
            if (byteStart >= 0 && availableChars > 0) {
              final units = <int>[];
              final wordData = ByteData.sublistView(wordBytes);
              for (var c = 0; c < availableChars; c++) {
                units.add(
                  wordData.getUint16(byteStart + c * 2, Endian.little),
                );
              }
              out.write(String.fromCharCodes(units));
              collectedChars += availableChars;
            }
          }
        }
        return out.toString();
      } else {
        break;
      }
    }
    return '';
  }

  static String _decodeCp1252Slice(Uint8List bytes, int start, int length) {
    final out = StringBuffer();
    for (var i = 0; i < length; i++) {
      final b = bytes[start + i];
      if (b < 0x80 || b >= 0xA0) {
        out.writeCharCode(b);
      } else {
        out.writeCharCode(_cp1252Extra[b - 0x80]);
      }
    }
    return out.toString();
  }

  static const List<int> _cp1252Extra = [
    0x20AC, 0x0081, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021,
    0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x008D, 0x017D, 0x008F,
    0x0090, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
    0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x009D, 0x017E, 0x0178,
  ];

  static String _normalizeWordControlChars(String raw) {
    final buf = StringBuffer();
    for (var i = 0; i < raw.length; i++) {
      final code = raw.codeUnitAt(i);
      if (code == 0x0D || code == 0x0B || code == 0x0C) {
        buf.write('\n');
      } else if (code == 0x07) {
        buf.write('  ');
      } else if (code == 0x01 ||
          code == 0x08 ||
          code == 0x13 ||
          code == 0x14 ||
          code == 0x15) {
        // Inline Word field markers / object anchors.
        continue;
      } else if (code == 0x00) {
        continue;
      } else {
        buf.writeCharCode(code);
      }
    }
    return buf.toString();
  }
}

class _OleDirEntry {
  const _OleDirEntry(this.name, this.objType, this.startSector, this.size);

  final String name;
  final int objType;
  final int startSector;
  final int size;
}
