import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:path/path.dart' as p;
import 'package:unseal/unseal.dart' as unseal;

import '../../core/formatters.dart';
import '../models/chapter.dart';
import '../txt/parser.dart';
import 'legacy_doc_parser.dart';

/// Parses TXT, EPUB, MOBI/AZW/AZW3, Word (`.docx`/`.doc`), and PDF files
/// into a normalized [ParsedNovel] suitable for ShiJuan's reading engine.
class DocumentParser {
  DocumentParser._();

  static const int _maxChapterChars = 20000;
  static const int _pdfChunkPages = 10;

  static ParsedNovel parseFile(String path) {
    final file = File(path);
    final bytes = file.readAsBytesSync();
    return parseBytes(bytes, fileName: p.basename(path));
  }

  static ParsedNovel parseBytes(
    Uint8List bytes, {
    required String fileName,
  }) {
    if (bytes.isEmpty) {
      throw const FormatException('文件为空，没有可阅读的内容');
    }
    final ext = Fmt.lowerExtension(fileName);

    if (ext == '.txt') {
      return TxtParser.parse(bytes, fileName: fileName);
    }

    try {
      if (ext == '.doc') {
        final extracted = LegacyDocParser.extract(bytes);
        switch (extracted) {
          case LegacyDocText():
            return LegacyDocParser.parseAsNovel(bytes, fileName: fileName);
          case LegacyDocUnsealed(:final book, :final encodingLabel):
            return _convertBookToParsedNovel(
              book,
              fileName: fileName,
              sourceBytes: bytes.length,
              formatLabel: encodingLabel,
            );
        }
      }

      final unseal.Book book;
      if (ext == '.pdf') {
        book = unseal.parsePdfBook(bytes);
      } else if (ext == '.epub') {
        book = unseal.parseEpubBook(bytes);
      } else if (ext == '.docx') {
        book = unseal.parseDocxBook(bytes);
      } else if (ext == '.mobi' ||
          ext == '.azw' ||
          ext == '.azw3' ||
          ext == '.prc') {
        book = unseal.parseMobiBook(bytes);
      } else {
        book = unseal.Unseal.parse(bytes);
      }

      if (book is unseal.PdfBook && !book.hasTextLayer) {
        throw const FormatException('纯图片/扫描版 PDF 暂未包含可提取的文字层');
      }

      return _convertBookToParsedNovel(
        book,
        fileName: fileName,
        sourceBytes: bytes.length,
        formatLabel: _formatLabel(book.format, ext),
      );
    } on unseal.PdfEncryptedException {
      throw const FormatException('PDF 已设置密码保护，无法导入');
    } on unseal.DrmProtectedException {
      throw const FormatException('电子书受 DRM 加密保护，无法导入');
    } on unseal.UnsealException catch (error) {
      throw FormatException(_friendlyUnsealError(error.message));
    }
  }

  static String _formatLabel(unseal.BookFormat format, String ext) {
    switch (format) {
      case unseal.BookFormat.epub:
        return 'EPUB';
      case unseal.BookFormat.mobi:
        return 'MOBI';
      case unseal.BookFormat.azw3:
        return 'AZW3';
      case unseal.BookFormat.azw4:
        return 'AZW4';
      case unseal.BookFormat.pdf:
        return 'PDF';
      case unseal.BookFormat.docx:
        return 'DOCX';
      case unseal.BookFormat.rtf:
        return 'RTF';
      case unseal.BookFormat.palmdoc:
        return 'PalmDOC';
      default:
        return Fmt.formatTagForPath('file$ext');
    }
  }

  static String _friendlyUnsealError(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('drm') || lower.contains('encrypt')) {
      return '文件包含加密保护，无法导入';
    }
    if (lower.contains('password')) {
      return '文件已设置密码保护，无法导入';
    }
    if (lower.contains('empty') || lower.contains('no pages')) {
      return '文件中没有可阅读的正文内容';
    }
    return '文件格式解析失败：${message.length > 80 ? message.substring(0, 80) : message}';
  }

  static ParsedNovel _convertBookToParsedNovel(
    unseal.Book book, {
    required String fileName,
    required int sourceBytes,
    required String formatLabel,
  }) {
    final htmlFiles = book.files.html;
    if (htmlFiles.isEmpty) {
      throw const FormatException('未能从文件中解析出可阅读文本');
    }

    final orderedSections = _orderedSections(book, htmlFiles);
    final allParagraphs = <String>[];
    final sectionStarts = <String, int>{};
    final sectionByNormalized = <String, _SectionResult>{};
    final sectionList = <_SectionResult>[];
    final globalAnchors = <String, int>{};
    final domHeadings = <({int paragraphIndex, String title})>[];

    for (final sectionFile in orderedSections) {
      final normPath = _normPath(sectionFile.path);
      final baseParagraph = allParagraphs.length;
      sectionStarts.putIfAbsent(normPath, () => baseParagraph);
      final parsedSection = _extractHtmlSection(
        sectionFile.content,
        baseParagraphIndex: baseParagraph,
      );
      allParagraphs.addAll(parsedSection.paragraphs);

      for (final entry in parsedSection.anchors.entries) {
        globalAnchors.putIfAbsent(entry.key, () => entry.value);
      }
      domHeadings.addAll(parsedSection.headings);
      sectionByNormalized[normPath] = parsedSection;
      sectionList.add(parsedSection);
    }

    if (allParagraphs.isEmpty) {
      throw const FormatException('没有找到可阅读的正文内容');
    }

    final rawTitle = book.metadata.title?.trim() ?? '';
    final title = _cleanMetadataTitle(rawTitle).isNotEmpty
        ? _cleanMetadataTitle(rawTitle)
        : TxtParser.titleFromFileName(fileName);

    final author = book.metadata.authors
        .map((a) => a.trim())
        .where((a) => a.isNotEmpty)
        .join(' · ');

    // Resolve TOC chapters from navigation or headings or heuristics.
    var groups = _resolveNavigationChapters(
      book: book,
      allParagraphs: allParagraphs,
      sectionStarts: sectionStarts,
      sectionByNormalized: sectionByNormalized,
      globalAnchors: globalAnchors,
      fallbackTitle: title,
    );

    if (groups.length < 2 && domHeadings.length >= 2) {
      groups = _groupByHeadings(
        allParagraphs,
        domHeadings,
        prefaceTitle: '正文前页',
      );
    }

    if (groups.length < 2) {
      final reParsed = _groupParagraphsWithTxtHeuristics(
        allParagraphs,
        fallbackTitle: title,
      );
      if (reParsed.length >= 2) {
        groups = reParsed;
      } else if (book is unseal.PdfBook &&
          sectionList.length > _pdfChunkPages &&
          allParagraphs.fold<int>(0, (sum, s) => sum + s.length) > 12000) {
        groups = _chunkPdfSections(sectionList);
      } else {
        groups = [_ChapterGroup('全文', allParagraphs)];
      }
    }

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
      throw const FormatException('没有找到可阅读的正文内容');
    }

    return ParsedNovel(
      title: title,
      author: author,
      encoding: formatLabel,
      content: content.toString(),
      chapters: chapters,
      sourceBytes: sourceBytes,
    );
  }

  static List<unseal.TextFile> _orderedSections(
    unseal.Book book,
    List<unseal.TextFile> htmlFiles,
  ) {
    final byPath = <String, unseal.TextFile>{};
    for (final f in htmlFiles) {
      byPath[_normPath(f.path)] = f;
    }
    final used = <unseal.TextFile>{};
    final ordered = <unseal.TextFile>[];
    for (final item in book.readingOrder) {
      final file = byPath[_normPath(item.name)];
      if (file != null && used.add(file)) {
        ordered.add(file);
      }
    }
    for (final f in htmlFiles) {
      if (used.add(f)) ordered.add(f);
    }
    return ordered;
  }

  static String _normPath(String raw) {
    var path = raw.trim().replaceAll('\\', '/');
    try {
      path = Uri.decodeFull(path);
    } catch (_) {
      // Keep original if malformed percent encoding.
    }
    while (path.startsWith('./') || path.startsWith('/')) {
      path = path.startsWith('./') ? path.substring(2) : path.substring(1);
    }
    return path.toLowerCase();
  }

  static _SectionResult _extractHtmlSection(
    String html, {
    required int baseParagraphIndex,
  }) {
    final document = html_parser.parse(html);
    final root = document.body ?? document.documentElement;
    if (root == null) {
      return _SectionResult(
        startParagraph: baseParagraphIndex,
        paragraphs: const [],
        anchors: const {},
        headings: const [],
      );
    }

    final paragraphs = <String>[];
    final anchors = <String, int>{};
    final headings = <({int paragraphIndex, String title})>[];
    final buffer = StringBuffer();

    void flushParagraph({bool isHeading = false}) {
      final cleaned = _normalizeInlineText(buffer.toString());
      buffer.clear();
      if (cleaned.isEmpty) return;
      final idx = baseParagraphIndex + paragraphs.length;
      if (isHeading && cleaned.length <= 80) {
        headings.add((paragraphIndex: idx, title: cleaned));
      }
      paragraphs.add(cleaned);
    }

    const skipTags = {'script', 'style', 'noscript', 'head', 'title', 'svg'};
    const headingTags = {'h1', 'h2', 'h3'};
    const blockTags = {
      'p',
      'div',
      'section',
      'article',
      'blockquote',
      'li',
      'tr',
      'h1',
      'h2',
      'h3',
      'h4',
      'h5',
      'h6',
      'dt',
      'dd',
      'pre',
      'header',
      'footer',
      'aside',
      'figure',
      'figcaption',
      'hr',
      'table',
    };

    void recordAnchor(dom.Element el) {
      final id = el.attributes['id'] ?? el.attributes['filepos-id'];
      if (id != null && id.isNotEmpty) {
        anchors.putIfAbsent(id, () => baseParagraphIndex + paragraphs.length);
      }
      final name = el.attributes['name'];
      if (name != null && name.isNotEmpty) {
        anchors.putIfAbsent(name, () => baseParagraphIndex + paragraphs.length);
      }
    }

    void walk(dom.Node node) {
      if (node is dom.Text) {
        buffer.write(node.text);
        return;
      }
      if (node is! dom.Element) {
        for (final child in node.nodes) {
          walk(child);
        }
        return;
      }

      final tag = node.localName?.toLowerCase() ?? '';
      if (skipTags.contains(tag)) return;

      if (tag == 'br' || tag == 'hr') {
        flushParagraph();
        return;
      }

      final isBlock = blockTags.contains(tag);
      final isHeading = headingTags.contains(tag);
      if (isBlock && buffer.isNotEmpty) {
        flushParagraph();
      }
      recordAnchor(node);

      for (final child in node.nodes) {
        walk(child);
      }

      if (tag == 'td' || tag == 'th') {
        if (buffer.isNotEmpty && !buffer.toString().endsWith(' ')) {
          buffer.write('  ');
        }
      } else if (isBlock) {
        flushParagraph(isHeading: isHeading);
      }
    }

    walk(root);
    flushParagraph();

    return _SectionResult(
      startParagraph: baseParagraphIndex,
      paragraphs: paragraphs,
      anchors: anchors,
      headings: headings,
    );
  }

  static String _normalizeInlineText(String raw) {
    final cleaned = raw
        .replaceAll('\u00A0', ' ')
        .replaceAll('\u200B', '')
        .replaceAll('\uFEFF', '');
    // PDF/HTML reflow often emits `\n` inside Chinese paragraphs. Remove
    // newlines between adjacent CJK characters without inserting spaces.
    final buf = StringBuffer();
    var lastWasSpace = true;
    int? lastCode;
    for (var i = 0; i < cleaned.length; i++) {
      final code = cleaned.codeUnitAt(i);
      if (code == 0x0A || code == 0x0D || code == 0x09 || code == 0x20 || code == 0x3000) {
        if (code == 0x0A && lastCode != null && _isCjk(lastCode)) {
          // Peek next non-whitespace char: if CJK, omit the newline space!
          var nextIdx = i + 1;
          while (nextIdx < cleaned.length &&
              (cleaned.codeUnitAt(nextIdx) == 0x20 ||
                  cleaned.codeUnitAt(nextIdx) == 0x09 ||
                  cleaned.codeUnitAt(nextIdx) == 0x0D ||
                  cleaned.codeUnitAt(nextIdx) == 0x0A)) {
            nextIdx++;
          }
          if (nextIdx < cleaned.length && _isCjk(cleaned.codeUnitAt(nextIdx))) {
            continue;
          }
        }
        if (!lastWasSpace) {
          buf.write(' ');
          lastWasSpace = true;
        }
        continue;
      }
      buf.writeCharCode(code);
      lastWasSpace = false;
      lastCode = code;
    }
    return buf.toString().trim();
  }

  static bool _isCjk(int unit) =>
      (unit >= 0x4E00 && unit <= 0x9FFF) ||
      (unit >= 0x3400 && unit <= 0x4DBF) ||
      (unit >= 0x3000 && unit <= 0x303F) ||
      (unit >= 0xFF00 && unit <= 0xFFEF);

  static List<_ChapterGroup> _resolveNavigationChapters({
    required unseal.Book book,
    required List<String> allParagraphs,
    required Map<String, int> sectionStarts,
    required Map<String, _SectionResult> sectionByNormalized,
    required Map<String, int> globalAnchors,
    required String fallbackTitle,
  }) {
    final flatNav = <({String label, String content})>[];
    void collect(List<unseal.NavPoint> points) {
      for (final point in points) {
        final label = point.label.trim();
        if (label.isNotEmpty) {
          flatNav.add((label: label, content: point.content.trim()));
        }
        if (point.subNavPoints.isNotEmpty) collect(point.subNavPoints);
      }
    }

    collect(book.navigation.navPoints);
    if (flatNav.isEmpty) return const [];

    final markers = <({int index, String title})>[];
    for (final entry in flatNav) {
      final target = entry.content;
      final hash = target.indexOf('#');
      final rawHref = hash >= 0 ? target.substring(0, hash) : target;
      final fragment = hash >= 0 ? target.substring(hash + 1) : '';
      final normHref = _normPath(rawHref);

      int? paragraphIndex;
      if (normHref.isNotEmpty) {
        final section = sectionByNormalized[normHref] ??
            _matchSectionBySuffix(sectionByNormalized, normHref);
        if (section != null) {
          if (fragment.isNotEmpty && section.anchors.containsKey(fragment)) {
            paragraphIndex = section.anchors[fragment];
          } else {
            paragraphIndex = section.startParagraph;
          }
        }
      }
      if (paragraphIndex == null && fragment.isNotEmpty) {
        paragraphIndex = globalAnchors[fragment];
      }
      if (paragraphIndex == null) continue;
      final clamped = paragraphIndex
          .clamp(0, math.max(0, allParagraphs.length - 1))
          .toInt();
      markers.add((index: clamped, title: entry.label));
    }

    if (markers.isEmpty) return const [];
    markers.sort((a, b) => a.index.compareTo(b.index));

    // Deduplicate markers pointing to the exact same starting paragraph.
    final deduped = <({int index, String title})>[];
    for (final m in markers) {
      if (deduped.isNotEmpty && deduped.last.index == m.index) continue;
      deduped.add(m);
    }

    if (deduped.length < 2) return const [];

    final groups = <_ChapterGroup>[];
    if (deduped.first.index > 0) {
      groups.add(
        _ChapterGroup(
          '序言',
          allParagraphs.sublist(0, deduped.first.index),
        ),
      );
    }
    for (var i = 0; i < deduped.length; i++) {
      final start = deduped[i].index;
      final end = i + 1 < deduped.length ? deduped[i + 1].index : allParagraphs.length;
      if (end <= start) continue;
      final slice = allParagraphs.sublist(start, end);
      // Drop redundant duplicated chapter heading at first paragraph if exact match.
      if (slice.length > 1 && slice.first.trim() == deduped[i].title.trim()) {
        groups.add(_ChapterGroup(deduped[i].title, slice.sublist(1)));
      } else {
        groups.add(_ChapterGroup(deduped[i].title, slice));
      }
    }
    return groups;
  }

  static _SectionResult? _matchSectionBySuffix(
    Map<String, _SectionResult> map,
    String suffix,
  ) {
    final base = suffix.contains('/') ? suffix.split('/').last : suffix;
    for (final entry in map.entries) {
      if (entry.key == suffix || entry.key.endsWith('/$suffix')) {
        return entry.value;
      }
    }
    for (final entry in map.entries) {
      final keyBase =
          entry.key.contains('/') ? entry.key.split('/').last : entry.key;
      if (keyBase == base) return entry.value;
    }
    return null;
  }

  static List<_ChapterGroup> _groupByHeadings(
    List<String> paragraphs,
    List<({int paragraphIndex, String title})> headings, {
    required String prefaceTitle,
  }) {
    final sorted = List.of(headings)
      ..sort((a, b) => a.paragraphIndex.compareTo(b.paragraphIndex));
    final deduped = <({int paragraphIndex, String title})>[];
    for (final h in sorted) {
      if (deduped.isNotEmpty && deduped.last.paragraphIndex == h.paragraphIndex) {
        continue;
      }
      deduped.add(h);
    }
    if (deduped.length < 2) return const [];

    final groups = <_ChapterGroup>[];
    if (deduped.first.paragraphIndex > 0) {
      groups.add(
        _ChapterGroup(
          prefaceTitle,
          paragraphs.sublist(0, deduped.first.paragraphIndex),
        ),
      );
    }
    for (var i = 0; i < deduped.length; i++) {
      final start = deduped[i].paragraphIndex;
      final end = i + 1 < deduped.length
          ? deduped[i + 1].paragraphIndex
          : paragraphs.length;
      if (end <= start) continue;
      final slice = paragraphs.sublist(start, end);
      if (slice.length > 1 && slice.first.trim() == deduped[i].title.trim()) {
        groups.add(_ChapterGroup(deduped[i].title, slice.sublist(1)));
      } else {
        groups.add(_ChapterGroup(deduped[i].title, slice));
      }
    }
    return groups;
  }

  static List<_ChapterGroup> _groupParagraphsWithTxtHeuristics(
    List<String> paragraphs, {
    required String fallbackTitle,
  }) {
    // Feed clean paragraphs through TxtParser's regex chapter recognizer without
    // losing indentation by temporarily formatting unindented lines separated by
    // blank lines.
    final rawText = paragraphs.join('\n\n');
    final parsed = TxtParser.parse(
      Uint8List.fromList(utf8.encode(rawText)),
      fileName: '$fallbackTitle.txt',
    );
    if (parsed.chapters.length < 2) return const [];
    return [
      for (final ch in parsed.chapters)
        _ChapterGroup(
          ch.title,
          parsed.content
              .substring(ch.start, ch.end)
              .split('\n')
              .map((line) => line.replaceFirst(RegExp(r'^[\u3000\s]+'), '').trim())
              .where((line) => line.isNotEmpty)
              .toList(),
        ),
    ];
  }

  static List<_ChapterGroup> _chunkPdfSections(List<_SectionResult> pages) {
    final groups = <_ChapterGroup>[];
    for (var i = 0; i < pages.length; i += _pdfChunkPages) {
      final end = math.min(pages.length, i + _pdfChunkPages);
      final body = <String>[];
      for (var pIdx = i; pIdx < end; pIdx++) {
        body.addAll(pages[pIdx].paragraphs);
      }
      if (body.isEmpty) continue;
      groups.add(_ChapterGroup('第 ${i + 1}–$end 页', body));
    }
    return groups;
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
        if (current.isNotEmpty && chars + paragraph.length > _maxChapterChars) {
          flush();
        }
        current.add(paragraph);
        chars += paragraph.length;
      }
      flush();
    }
    return result;
  }

  static String _cleanMetadataTitle(String raw) {
    var title = raw.trim();
    if (title.isEmpty) return '';
    for (final ext in Fmt.supportedExtensions) {
      if (title.toLowerCase().endsWith(ext) && title.length > ext.length) {
        title = title.substring(0, title.length - ext.length).trim();
        break;
      }
    }
    return title;
  }
}

class _SectionResult {
  const _SectionResult({
    required this.startParagraph,
    required this.paragraphs,
    required this.anchors,
    required this.headings,
  });

  final int startParagraph;
  final List<String> paragraphs;
  final Map<String, int> anchors;
  final List<({int paragraphIndex, String title})> headings;
}

class _ChapterGroup {
  const _ChapterGroup(this.title, this.body);

  final String title;
  final List<String> body;
}
