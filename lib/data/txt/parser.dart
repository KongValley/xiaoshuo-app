import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../models/chapter.dart';
import 'encoding.dart';

class ParsedNovel {
  const ParsedNovel({
    required this.title,
    required this.author,
    required this.encoding,
    required this.content,
    required this.chapters,
    required this.sourceBytes,
  });

  final String title;
  final String author;
  final String encoding;

  /// Normalized body text: one paragraph per line, two full-width spaces of
  /// indentation, no chapter headings, no empty lines.
  final String content;
  final List<Chapter> chapters;
  final int sourceBytes;
}

/// Turns a TXT novel into normalized text plus a chapter index.
///
/// Supported heading styles include `第12章`, `第十二回`, `001 标题`, `1. 标题`
/// (only when the numbering is clearly sequential), `Chapter 12`, markdown
/// headings and common standalone headings such as `序章`, `楔子` and `番外`.
class TxtParser {
  TxtParser._();

  static const int _maxHeadingLength = 60;
  static const int _maxChapterChars = 20000;

  static ParsedNovel parse(Uint8List bytes, {required String fileName}) {
    final decoded = decodeNovelBytes(bytes);
    final paragraphs = _extractParagraphs(decoded.text);
    final title = titleFromFileName(fileName);
    final author = _extractAuthor(fileName, paragraphs);
    final headings = _detectHeadings(paragraphs);

    final groups = _groupChapters(paragraphs, headings, title);
    final splitGroups = _splitOversizedGroups(groups);

    final content = StringBuffer();
    final chapters = <Chapter>[];
    for (final group in splitGroups) {
      if (group.body.isEmpty) continue;
      final start = content.length;
      for (final paragraph in group.body) {
        content.write('\u3000\u3000');
        content.write(paragraph);
        content.write('\n');
      }
      final end = content.length;
      if (end <= start) continue;
      chapters.add(Chapter(title: group.title, start: start, end: end));
    }

    if (chapters.isEmpty) {
      // The file is empty or only whitespace.
      return ParsedNovel(
        title: title,
        author: author,
        encoding: decoded.encoding,
        content: '',
        chapters: const [],
        sourceBytes: bytes.length,
      );
    }

    return ParsedNovel(
      title: title,
      author: author,
      encoding: decoded.encoding,
      content: content.toString(),
      chapters: chapters,
      sourceBytes: bytes.length,
    );
  }

  // ---------------------------------------------------------------------------
  // Text normalization
  // ---------------------------------------------------------------------------

  static List<String> _extractParagraphs(String raw) {
    var text = raw
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll('\u0000', '')
        .replaceAll('\uFEFF', '')
        .replaceAll('\u200B', '')
        .replaceAll('\u00A0', ' ')
        .replaceAll('\u000B', '\n')
        .replaceAll('\u000C', '\n');

    final rawLines = text.split('\n');
    if (rawLines.isEmpty) return const [];

    var blankLines = 0;
    var indentedLines = 0;
    var nonEmptyLines = 0;
    for (final line in rawLines) {
      if (_isBlank(line)) {
        blankLines++;
        continue;
      }
      nonEmptyLines++;
      if (_startsWithIndent(line)) indentedLines++;
    }
    if (nonEmptyLines == 0) return const [];

    final blankRatio = blankLines / rawLines.length;
    final indentRatio = indentedLines / nonEmptyLines;

    final List<String> paragraphs;
    if (indentRatio >= 0.18) {
      paragraphs = _paragraphsByIndent(rawLines);
    } else if (blankRatio >= 0.02) {
      paragraphs = _paragraphsByBlankLines(rawLines);
    } else {
      paragraphs = <String>[
        for (final line in rawLines)
          if (!_isBlank(line)) line.trim(),
      ];
    }

    final filtered = <String>[];
    for (final paragraph in paragraphs) {
      if (paragraph.isEmpty || _isJunkLine(paragraph)) continue;
      filtered.add(paragraph);
    }
    return filtered;
  }

  /// Most Chinese TXT novels indent the first line of every paragraph with two
  /// full-width spaces and often wrap long paragraphs. A line with indentation
  /// starts a paragraph; a non-indented line continues it unless the previous
  /// line clearly ended a paragraph.
  static List<String> _paragraphsByIndent(List<String> lines) {
    final result = <String>[];
    final current = StringBuffer();
    var hasCurrent = false;
    var previousEnded = true;
    var lastUnit = 0;

    void flush() {
      if (!hasCurrent) return;
      final text = current.toString().trim();
      if (text.isNotEmpty) result.add(text);
      current.clear();
      hasCurrent = false;
      lastUnit = 0;
    }

    for (final rawLine in lines) {
      if (_isBlank(rawLine)) continue;
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final indented = _startsWithIndent(rawLine);
      final startsSpecial = line.startsWith('【') || line.startsWith('[');
      if (!hasCurrent ||
          indented ||
          previousEnded ||
          startsSpecial ||
          _looksLikeHeadingStart(line)) {
        flush();
        current.write(line);
        hasCurrent = true;
        lastUnit = line.codeUnitAt(line.length - 1);
      } else {
        if (_isAsciiWord(lastUnit) && _isAsciiWord(line.codeUnitAt(0))) {
          current.write(' ');
        }
        current.write(line);
        lastUnit = line.codeUnitAt(line.length - 1);
      }
      previousEnded = _endsParagraph(line);
    }
    flush();
    return result;
  }

  static List<String> _paragraphsByBlankLines(List<String> lines) {
    final result = <String>[];
    final block = <String>[];

    void flush() {
      if (block.isEmpty) return;
      final joined = StringBuffer(block.first);
      var lastUnit = block.first.codeUnitAt(block.first.length - 1);
      for (var i = 1; i < block.length; i++) {
        final line = block[i];
        if (_isAsciiWord(lastUnit) && _isAsciiWord(line.codeUnitAt(0))) {
          joined.write(' ');
        }
        joined.write(line);
        lastUnit = line.codeUnitAt(line.length - 1);
      }
      final text = joined.toString().trim();
      if (text.isNotEmpty) result.add(text);
      block.clear();
    }

    for (final rawLine in lines) {
      if (_isBlank(rawLine)) {
        flush();
      } else {
        final line = rawLine.trim();
        // A chapter heading must stay a paragraph of its own even when the
        // surrounding text uses blank lines as paragraph separators.
        if (_looksLikeHeadingStart(line)) {
          flush();
          block.add(line);
          flush();
        } else {
          block.add(line);
        }
      }
    }
    flush();
    return result;
  }

  static bool _isAsciiWord(int unit) =>
      (unit >= 0x30 && unit <= 0x39) ||
      (unit >= 0x41 && unit <= 0x5A) ||
      (unit >= 0x61 && unit <= 0x7A);

  static bool _isBlank(String line) {
    for (var i = 0; i < line.length; i++) {
      final unit = line.codeUnitAt(i);
      if (unit != 0x20 && unit != 0x09 && unit != 0x3000) return false;
    }
    return true;
  }

  static bool _startsWithIndent(String line) {
    if (line.isEmpty) return false;
    final unit = line.codeUnitAt(0);
    return unit == 0x3000 || unit == 0x20 || unit == 0x09;
  }

  static bool _endsParagraph(String line) {
    if (line.isEmpty) return true;
    const enders = {
      '。',
      '！',
      '？',
      '…',
      '”',
      '』',
      '」',
      '）',
      '】',
      '》',
      '.',
      '!',
      '?',
      '"',
      "'",
    };
    return enders.contains(line[line.length - 1]);
  }

  static bool _looksLikeHeadingStart(String line) {
    if (line.length > _maxHeadingLength) return false;
    if (_cnHeading.hasMatch(line)) return true;
    if (_specialHeading.hasMatch(line) && line.length <= 20) return true;
    if (_englishHeading.hasMatch(line)) return true;
    if (_markdownHeading.hasMatch(line)) return true;
    return RegExp(r'^\d{1,4}[\s、.．]\S').hasMatch(line);
  }

  /// Drops obvious site watermarks/advert lines that would otherwise show up
  /// as paragraphs in the middle of a novel.
  static bool _isJunkLine(String line) {
    if (line.length > 80) return false;
    final lower = line.toLowerCase();
    if (RegExp(r'^(https?://|www\.)').hasMatch(lower)) return true;
    if (RegExp(r'^(?:[a-z0-9-]+\.)+(?:com|org|net|cc|cn|me|info|xyz)(?:/.*)?$')
        .hasMatch(lower)) {
      return true;
    }
    if (lower.contains('www.') && lower.length < 50) return true;
    if (RegExp(r'(请记住本站|本站域名|手机版阅读网址|最新网址|无弹窗阅读|一秒记住|'
            r'爬取失败|加载失败|章节错误|内容加载失败)')
        .hasMatch(line)) {
      return true;
    }
    return false;
  }

  // ---------------------------------------------------------------------------
  // Headings
  // ---------------------------------------------------------------------------

  static final RegExp _cnHeading = RegExp(
    r'^第\s*([0-9零一二三四五六七八九十百千万两〇]{1,12})\s*([章节回卷部集话篇幕])'
    r'\s*[、.．:：·\-—]?\s*(.*)$',
  );
  static final RegExp _numericHeading =
      RegExp(r'^(\d{1,4})\s+(\S.*)$');
  static final RegExp _numericDotHeading =
      RegExp(r'^(\d{1,4})[、.．]\s*(\S.*)$');
  static final RegExp _englishHeading =
      RegExp(r'^(?:Chapter|CHAPTER|chapter)\s+(\d{1,4})\b[\s.．:：\-—]*(.*)$');
  static final RegExp _markdownHeading = RegExp(r'^#{1,4}\s+(\S.*)$');
  static final RegExp _specialHeading = RegExp(
    r'^(序章|序言|楔子|前言|引子|尾声|终章|后记|番外(?:篇)?(?:[0-9一二三四五六七八九十]+)?|'
    r'大结局|结局|外传|终篇|卷[一二三四五六七八九十百]+)'
    r'(?:[\s：:·\-—].*)?$',
  );

  static List<_Heading> _detectHeadings(List<String> paragraphs) {
    final cn = <_Heading>[];
    final numericSpace = <_Heading>[];
    final numericSpaceNumbers = <int>[];
    final numericDot = <_Heading>[];
    final numericDotNumbers = <int>[];
    final english = <_Heading>[];
    final markdown = <_Heading>[];
    final specials = <_Heading>[];

    for (var index = 0; index < paragraphs.length; index++) {
      final raw = paragraphs[index];
      final text = _normalizeHeadingText(raw);
      if (text == null) continue;

      final cnMatch = _cnHeading.firstMatch(text);
      if (cnMatch != null) {
        cn.add(_Heading(index, text));
        continue;
      }

      final specialMatch = _specialHeading.firstMatch(text);
      if (specialMatch != null && text.length <= 20) {
        specials.add(_Heading(index, text));
        continue;
      }

      final numericSpaceMatch = _numericHeading.firstMatch(text);
      if (numericSpaceMatch != null) {
        final number = int.tryParse(numericSpaceMatch.group(1) ?? '');
        if (number != null) {
          numericSpace.add(_Heading(index, text));
          numericSpaceNumbers.add(number);
          continue;
        }
      }

      final numericDotMatch = _numericDotHeading.firstMatch(text);
      if (numericDotMatch != null) {
        final number = int.tryParse(numericDotMatch.group(1) ?? '');
        if (number != null) {
          numericDot.add(_Heading(index, text));
          numericDotNumbers.add(number);
          continue;
        }
      }

      final englishMatch = _englishHeading.firstMatch(text);
      if (englishMatch != null) {
        english.add(_Heading(index, text));
        continue;
      }

      final markdownMatch = _markdownHeading.firstMatch(text);
      if (markdownMatch != null) {
        final title = _cleanTitle(markdownMatch.group(1) ?? text);
        if (title.isNotEmpty) markdown.add(_Heading(index, title));
      }
    }

    List<_Heading>? chosen;
    if (cn.isNotEmpty) {
      chosen = cn;
    } else if (numericSpace.length >= 3 &&
        _looksSequential(numericSpaceNumbers)) {
      chosen = numericSpace;
    } else if (numericDot.length >= 3 &&
        _looksSequential(numericDotNumbers)) {
      chosen = numericDot;
    } else if (english.isNotEmpty) {
      chosen = english;
    } else if (specials.length >= 2) {
      chosen = specials;
    } else if (markdown.length >= 2) {
      chosen = markdown;
    }

    if (chosen == null || chosen.isEmpty) return const [];

    final merged = <int, _Heading>{};
    for (final heading in chosen) {
      merged.putIfAbsent(heading.paragraphIndex, () => heading);
    }
    for (final heading in specials) {
      merged.putIfAbsent(heading.paragraphIndex, () => heading);
    }
    if (identical(chosen, markdown)) {
      for (final heading in markdown) {
        merged.putIfAbsent(heading.paragraphIndex, () => heading);
      }
    }
    final result = merged.values.toList()
      ..sort((a, b) => a.paragraphIndex.compareTo(b.paragraphIndex));
    final unique = <_Heading>[];
    var lastIndex = -1;
    for (final heading in result) {
      if (heading.paragraphIndex == lastIndex) continue;
      unique.add(heading);
      lastIndex = heading.paragraphIndex;
    }
    return unique;
  }

  static bool _looksSequential(List<int> numbers) {
    if (numbers.length < 3) return false;
    var consecutive = 0;
    for (var i = 1; i < numbers.length; i++) {
      if (numbers[i] == numbers[i - 1] + 1) consecutive++;
    }
    final ratio = consecutive / (numbers.length - 1);
    final span = numbers.last - numbers.first;
    return ratio >= 0.6 && span >= 2;
  }

  static String? _normalizeHeadingText(String raw) {
    var text = raw.trim();
    if (text.isEmpty || text.length > _maxHeadingLength) return null;
    text = text.replaceFirst(RegExp(r'^#{1,6}\s*'), '');
    text = text.replaceFirst(RegExp(r'^正文\s*[:：]?\s*'), '');
    text = text.replaceAll(RegExp(r'[ \t\u3000]+'), ' ');
    text = text.replaceAll(RegExp(r'[：:·\-—\s]+$'), '').trim();
    if (text.isEmpty) return null;
    // Very long lines that merely start with a number are prose, not headings.
    if (text.length > 40 && !_cnHeading.hasMatch(text)) return null;
    return _cleanTitle(text);
  }

  static String _cleanTitle(String input) {
    var text = input.trim();
    text = text.replaceFirst(RegExp(r'^#{1,6}\s*'), '');
    text = text.replaceAll(RegExp(r'[ \t\u3000]+'), ' ');
    text = text.replaceAll(RegExp(r'^\s*[：:·\-—]+\s*|\s*[：:·\-—]+\s*$'), '');
    return text.trim();
  }

  // ---------------------------------------------------------------------------
  // Chapter assembly
  // ---------------------------------------------------------------------------

  static List<_ChapterGroup> _groupChapters(
    List<String> paragraphs,
    List<_Heading> headings,
    String bookTitle,
  ) {
    if (paragraphs.isEmpty) return const [];

    if (headings.isEmpty) return _pseudoGroups(paragraphs, bookTitle);

    final groups = <_ChapterGroup>[];
    final firstHeadingIndex = headings.first.paragraphIndex;
    List<String> preface = const [];
    if (firstHeadingIndex > 0) {
      final candidate = paragraphs.sublist(0, firstHeadingIndex);
      final chars = candidate.fold<int>(0, (sum, item) => sum + item.length);
      if (chars >= 120) {
        groups.add(_ChapterGroup('开篇', candidate));
      } else {
        preface = candidate;
      }
    }

    for (var i = 0; i < headings.length; i++) {
      final bodyStart = headings[i].paragraphIndex + 1;
      final bodyEnd =
          i + 1 < headings.length ? headings[i + 1].paragraphIndex : paragraphs.length;
      if (bodyStart > bodyEnd) continue;
      final body = paragraphs.sublist(bodyStart, bodyEnd);
      if (i == 0 && preface.isNotEmpty) {
        body.insertAll(0, preface);
      }
      if (body.isEmpty) continue;
      groups.add(_ChapterGroup(headings[i].title, body));
    }

    if (groups.isEmpty) return _pseudoGroups(paragraphs, bookTitle);
    return groups;
  }

  static List<_ChapterGroup> _pseudoGroups(
    List<String> paragraphs,
    String bookTitle,
  ) {
    const target = 8000;
    final chunks = <List<String>>[];
    var current = <String>[];
    var chars = 0;
    for (final paragraph in paragraphs) {
      final pieces = paragraph.length > target * 2
          ? _splitLongParagraph(paragraph, target)
          : <String>[paragraph];
      for (final piece in pieces) {
        if (current.isNotEmpty && chars + piece.length > target) {
          chunks.add(current);
          current = <String>[];
          chars = 0;
        }
        current.add(piece);
        chars += piece.length;
      }
    }
    if (current.isNotEmpty) chunks.add(current);

    if (chunks.length <= 1) {
      return [_ChapterGroup('全文', paragraphs)];
    }
    return [
      for (var i = 0; i < chunks.length; i++)
        _ChapterGroup('第 ${i + 1} 节', chunks[i]),
    ];
  }

  static List<String> _splitLongParagraph(String text, int target) {
    final result = <String>[];
    var start = 0;
    while (start < text.length) {
      var end = (start + target).clamp(0, text.length);
      if (end < text.length) {
        final window = text.substring(start, end);
        final breakAt = _lastSentenceEnd(window);
        if (breakAt > target ~/ 2) end = start + breakAt;
      }
      result.add(text.substring(start, end));
      start = end;
    }
    return result;
  }

  static int _lastSentenceEnd(String text) {
    const enders = '。！？…”';
    for (var i = text.length - 1; i >= 0; i--) {
      if (enders.contains(text[i])) return i + 1;
    }
    return -1;
  }

  static List<_ChapterGroup> _splitOversizedGroups(List<_ChapterGroup> groups) {
    final result = <_ChapterGroup>[];
    for (final group in groups) {
      final total = group.body.fold<int>(0, (sum, item) => sum + item.length);
      if (total <= _maxChapterChars) {
        result.add(group);
        continue;
      }
      var current = <String>[];
      var chars = 0;
      var part = 1;
      void flush() {
        if (current.isEmpty) return;
        final title = part == 1 ? group.title : '${group.title}（续 $part）';
        result.add(_ChapterGroup(title, List<String>.from(current)));
        current = <String>[];
        chars = 0;
        part++;
      }

      for (final paragraph in group.body) {
        final pieces = paragraph.length > 20000
            ? _splitLongParagraph(paragraph, 8000)
            : <String>[paragraph];
        for (final piece in pieces) {
          if (current.isNotEmpty && chars + piece.length > _maxChapterChars) {
            flush();
          }
          current.add(piece);
          chars += piece.length;
        }
      }
      flush();
    }
    return result;
  }

  // ---------------------------------------------------------------------------
  // Title / author
  // ---------------------------------------------------------------------------

  static String titleFromFileName(String fileName) {
    var name = p.basenameWithoutExtension(fileName).trim();
    if (name.isEmpty) return '未命名';

    final authorCut = RegExp(r'[\s_\-（(\[【]*作\s*者\s*[:：]').firstMatch(name);
    if (authorCut != null && authorCut.start > 0) {
      name = name.substring(0, authorCut.start);
    }

    final bookMark = RegExp(r'《([^》]{1,80})》').firstMatch(name);
    if (bookMark != null) {
      final inner = _cleanBookName(bookMark.group(1) ?? '');
      if (inner.isNotEmpty) return inner;
    }

    name = name.replaceFirst(
      RegExp(r'^(?:[\s_\-]*[\[【(（][^\]】)）]{0,60}[\]】)）])+'),
      '',
    );
    name = name.replaceAll(
      RegExp(
        r'[\[【(（][^\]】)）]{0,40}(?:完本|全集|全本|校对|精校|精修|无删减|未删节|'
        r'[Tt][Xx][Tt]|下载|www\.|\.com|\.org|\.net)[^\]】)）]{0,10}[\]】)）]',
      ),
      '',
    );
    name = _cleanBookName(name);
    return name.isEmpty ? '未命名' : name;
  }

  static String _cleanBookName(String input) {
    var name = input
        .replaceAll(RegExp(r'[_\u3000]+'), ' ')
        .replaceAll(RegExp(r'^\s*[\-—·]+\s*|\s*[\-—·]+\s*$'), '')
        .trim();
    if (name.length > 60) name = name.substring(0, 60).trim();
    return name;
  }

  static String _extractAuthor(String fileName, List<String> paragraphs) {
    final fileMatch = RegExp(
      r'作\s*者\s*[:：]\s*([^\s，,。；;、_\-/\\|<>()（）\[\]【】]{1,24})',
    ).firstMatch(p.basenameWithoutExtension(fileName));
    if (fileMatch != null) {
      final author = _cleanAuthor(fileMatch.group(1) ?? '');
      if (author.isNotEmpty) return author;
    }

    if (paragraphs.isEmpty) return '';
    final sample = paragraphs.take(8).join('\n');
    final match = RegExp(
      r'作\s*者\s*[:：]\s*([^\s，,。；;、\n\r_\-/\\|<>()（）\[\]【】]{1,24})',
    ).firstMatch(sample);
    if (match == null) return '';
    return _cleanAuthor(match.group(1) ?? '');
  }

  static String _cleanAuthor(String input) {
    var author = input.trim();
    author = author.replaceAll(RegExp(r'(著|的作品)$'), '').trim();
    if (author.length > 24) author = author.substring(0, 24);
    if (author.contains('的话') || author.contains('简介')) return '';
    return author;
  }
}

class _Heading {
  const _Heading(this.paragraphIndex, this.title);

  final int paragraphIndex;
  final String title;
}

class _ChapterGroup {
  _ChapterGroup(this.title, this.body);

  final String title;
  final List<String> body;
}
