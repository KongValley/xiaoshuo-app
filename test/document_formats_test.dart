import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shijuan_reader/app.dart';
import 'package:shijuan_reader/core/formatters.dart';
import 'package:shijuan_reader/data/formats/document_parser.dart';
import 'package:shijuan_reader/data/formats/legacy_doc_parser.dart';
import 'package:shijuan_reader/data/library_repository.dart';
import 'package:shijuan_reader/data/settings_repository.dart';
import 'package:shijuan_reader/data/stats_repository.dart';
import 'package:shijuan_reader/features/reader/reader_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Fmt extension and format tag helpers cover all supported formats', () {
    for (final ext in const [
      '.txt',
      '.epub',
      '.mobi',
      '.azw',
      '.azw3',
      '.prc',
      '.pdf',
      '.docx',
      '.doc',
    ]) {
      expect(Fmt.isSupportedBookFile('book$ext'), isTrue);
      expect(Fmt.isSupportedBookFile('BOOK${ext.toUpperCase()}'), isTrue);
    }
    expect(Fmt.isSupportedBookFile('cover.png'), isFalse);
    expect(Fmt.isSupportedBookFile('archive.zip'), isFalse);

    expect(Fmt.formatTagForPath('a.txt'), 'TXT');
    expect(Fmt.formatTagForPath('a.EPUB'), 'EPUB');
    expect(Fmt.formatTagForPath('a.mobi'), 'MOBI');
    expect(Fmt.formatTagForPath('a.azw3'), 'AZW3');
    expect(Fmt.formatTagForPath('a.pdf'), 'PDF');
    expect(Fmt.formatTagForPath('a.docx'), 'DOCX');
    expect(Fmt.formatTagForPath('a.doc'), 'WORD');
  });

  test(
      'LibraryRepository uses transparent gzip storage, migrates legacy content.txt, and supports batch reset/delete',
      () async {
    final root = Directory.systemTemp.createTempSync('shijuan_gzip_lib_');
    final srcDir = Directory.systemTemp.createTempSync('shijuan_gzip_src_');
    final library = LibraryRepository(root: root, parseInIsolate: false);
    var firstDisposed = false;
    addTearDown(() {
      if (!firstDisposed) library.dispose();
      if (root.existsSync()) root.deleteSync(recursive: true);
      if (srcDir.existsSync()) srcDir.deleteSync(recursive: true);
    });

    await library.init();

    final body = List.generate(
      120,
      (i) => '　　第${i + 1}段：江南无所有，聊赠一枝春。风起青萍之末，云卷沧海之间。',
    ).join('\n');
    final rawText = '第一章 春信\n$body\n\n第二章 秋声\n$body\n';
    final file1 = File(p.join(srcDir.path, '春信集.txt'))
      ..writeAsStringSync(rawText);
    final file2 = File(p.join(srcDir.path, '夜雨录.txt'))
      ..writeAsStringSync('第一章 夜雨\n　　君问归期未有期，巴山夜雨涨秋池。\n');

    final summary = await library.importPaths([file1.path, file2.path]);
    expect(summary.added, hasLength(2));
    expect(summary.failures, isEmpty);

    final book1 = summary.added.firstWhere((b) => b.title == '春信集');
    final book2 = summary.added.firstWhere((b) => b.title == '夜雨录');

    final gzFile = File(p.join(root.path, 'books', book1.id, 'content.txt.gz'));
    final plainFile = File(p.join(root.path, 'books', book1.id, 'content.txt'));
    expect(gzFile.existsSync(), isTrue);
    expect(plainFile.existsSync(), isFalse);
    expect(gzFile.lengthSync(), lessThan(utf8.encode(rawText).length));
    expect(library.storageBytes, greaterThan(0));
    expect(library.legacyUncompressedCount, 0);

    final loaded = await library.loadBookText(book1);
    expect(loaded.content, contains('江南无所有，聊赠一枝春'));

    // Simulate a pre-v1.2 uncompressed `content.txt` directory and reload repo.
    final decodedBytes = gzip.decode(gzFile.readAsBytesSync());
    plainFile.writeAsBytesSync(decodedBytes, flush: true);
    gzFile.deleteSync();
    await library.flush();
    library.dispose();
    firstDisposed = true;

    final reopened = LibraryRepository(root: root, parseInIsolate: false);
    addTearDown(reopened.dispose);
    await reopened.init();
    expect(reopened.legacyUncompressedCount, 1);
    final bytesBeforeMigrate = reopened.storageBytes;
    expect(
      (await reopened.loadBookText(book1)).content,
      contains('风起青萍之末'),
    );

    final migration = await reopened.compressLegacyBooks();
    expect(migration.converted, 1);
    expect(migration.savedBytes, greaterThan(0));
    expect(reopened.legacyUncompressedCount, 0);
    expect(plainFile.existsSync(), isFalse);
    expect(gzFile.existsSync(), isTrue);
    expect(reopened.storageBytes, lessThan(bytesBeforeMigrate));
    expect(
      (await reopened.loadBookText(book1)).content,
      contains('江南无所有，聊赠一枝春'),
    );

    // Batch progress reset & batch delete.
    reopened.saveProgress(
      book1.id,
      chapterIndex: 1,
      charOffset: 24,
      percent: 0.65,
      chapterTitle: '第二章 秋声',
    );
    reopened.saveProgress(
      book2.id,
      chapterIndex: 0,
      charOffset: 10,
      percent: 0.4,
      chapterTitle: '第一章 夜雨',
    );
    await reopened.resetBooksProgress([book1.id]);
    final resetB1 = reopened.books.firstWhere((b) => b.id == book1.id);
    final keptB2 = reopened.books.firstWhere((b) => b.id == book2.id);
    expect(resetB1.progress.percent, 0);
    expect(resetB1.progress.chapterIndex, 0);
    expect(keptB2.progress.percent, closeTo(0.4, 0.001));

    await reopened.deleteBooks([book1, book2]);
    expect(reopened.books, isEmpty);
    expect(Directory(p.join(root.path, 'books', book1.id)).existsSync(), isFalse);
    expect(Directory(p.join(root.path, 'books', book2.id)).existsSync(), isFalse);
  });

  test('DocumentParser parses EPUB, DOCX, DOC (OLE2 & RTF), MOBI, and PDF',
      () {
    // 1. EPUB with CJK line breaks inside paragraphs and toc.ncx navigation.
    final epubBytes = _buildSampleEpub();
    final epubNovel =
        DocumentParser.parseBytes(epubBytes, fileName: '山居杂记.epub');
    expect(epubNovel.title, '山居杂记');
    expect(epubNovel.author, '林清晏');
    expect(epubNovel.encoding, 'EPUB');
    expect(epubNovel.chapters.map((c) => c.title).toList(), ['第一章 江南春', '第二章 塞北雪']);
    // CJK line wrap inside XHTML must join cleanly without spurious spaces.
    expect(epubNovel.content, contains('江南春色满山川，'));
    expect(epubNovel.content, isNot(contains('江南 \n春')));

    // 2. Word DOCX with Heading1 chapters & core metadata.
    final docxBytes = _buildSampleDocx();
    final docxNovel =
        DocumentParser.parseBytes(docxBytes, fileName: '案头清供.docx');
    expect(docxNovel.title, '案头清供');
    expect(docxNovel.author, '苏长卿');
    expect(docxNovel.encoding, 'DOCX');
    expect(docxNovel.chapters, hasLength(2));
    expect(docxNovel.chapters[0].title, '第一章 研墨');
    expect(docxNovel.chapters[1].title, '第二章 听泉');
    expect(docxNovel.content, contains('端溪老坑砚，润墨不滞笔。'));

    // 3a. Binary Word 97-2003 OLE2 `.doc` (UTF-16LE piece table).
    final oleDocBytes = _buildSampleOle2Doc(
      '第一章 故园松风\r'
      '　　门前旧松犹在，石阶苔色未消。\r'
      '第二章 山中夜话\r'
      '　　围炉煮茶至半夜，屋外细雨微凉。\r',
    );
    final oleNovel =
        LegacyDocParser.parseAsNovel(oleDocBytes, fileName: '故园松风.doc');
    expect(oleNovel.encoding, 'DOC');
    expect(oleNovel.chapters.map((c) => c.title).toList(), ['第一章 故园松风', '第二章 山中夜话']);
    expect(oleNovel.content, contains('围炉煮茶至半夜'));

    // 3b. RTF-wrapped `.doc` often exported by Word/WPS.
    final rtfBytes = Uint8List.fromList(
      utf8.encode(
        r'{\rtf1\ansi\deff0 '
        r'Chapter 1 Morning Mist\par '
        r'White clouds drift gently across the valley.\par '
        r'Chapter 2 Lantern Light\par '
        r'Soft lantern light illuminates the courtyard.\par}',
      ),
    );
    final rtfNovel =
        DocumentParser.parseBytes(rtfBytes, fileName: 'lantern.doc');
    expect(rtfNovel.encoding, 'DOC/RTF');
    expect(rtfNovel.content, contains('White clouds drift gently'));
    expect(rtfNovel.chapters, isNotEmpty);

    // 4. MOBI (PalmDB BOOKMOBI + uncompressed UTF-8 HTML record).
    final mobiBytes = _buildSampleMobi();
    final mobiNovel =
        DocumentParser.parseBytes(mobiBytes, fileName: '云海奇谭.mobi');
    expect(mobiNovel.title, '云海奇谭');
    expect(mobiNovel.encoding, 'MOBI');
    expect(mobiNovel.chapters.map((c) => c.title).toList(), ['第一章 云开', '第二章 月明']);
    expect(mobiNovel.content, contains('星垂平野阔'));

    // 5. Text-layer PDF + rejection of scanned/empty PDF without text layer.
    final pdfBytes = _buildSamplePdf(withText: true);
    final pdfNovel = DocumentParser.parseBytes(pdfBytes, fileName: 'morning.pdf');
    expect(pdfNovel.title, 'Morning Notes');
    expect(pdfNovel.encoding, 'PDF');
    expect(
      pdfNovel.chapters.map((c) => c.title).toList(),
      ['Chapter 1 Quiet Morning', 'Chapter 2 Evening Breeze'],
    );
    expect(pdfNovel.content, contains('Morning sunlight fills the courtyard.'));
    expect(pdfNovel.content, contains('Gentle wind drifts over the bamboo grove.'));

    final scannedPdf = _buildSamplePdf(withText: false);
    expect(
      () => DocumentParser.parseBytes(scannedPdf, fileName: 'scan.pdf'),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('文字层'),
        ),
      ),
    );
  });

  test('LibraryRepository imports EPUB, DOCX, DOC, MOBI, and PDF end-to-end',
      () async {
    final root = Directory.systemTemp.createTempSync('shijuan_multi_lib_');
    final srcDir = Directory.systemTemp.createTempSync('shijuan_multi_src_');
    final library = LibraryRepository(root: root, parseInIsolate: false);
    addTearDown(() {
      library.dispose();
      if (root.existsSync()) root.deleteSync(recursive: true);
      if (srcDir.existsSync()) srcDir.deleteSync(recursive: true);
    });
    await library.init();

    final epubFile = File(p.join(srcDir.path, 'mountain.epub'))
      ..writeAsBytesSync(_buildSampleEpub());
    final docxFile = File(p.join(srcDir.path, 'ink.docx'))
      ..writeAsBytesSync(_buildSampleDocx());
    final docFile = File(p.join(srcDir.path, 'pine.doc'))
      ..writeAsBytesSync(
        _buildSampleOle2Doc('第一章 试笔\r　　新纸铺案，静待墨香。\r'),
      );
    final mobiFile = File(p.join(srcDir.path, 'cloud.mobi'))
      ..writeAsBytesSync(_buildSampleMobi());
    final pdfFile = File(p.join(srcDir.path, 'notes.pdf'))
      ..writeAsBytesSync(_buildSamplePdf(withText: true));
    final emptyPdfFile = File(p.join(srcDir.path, 'scan.pdf'))
      ..writeAsBytesSync(_buildSamplePdf(withText: false));

    final summary = await library.importPaths([
      epubFile.path,
      docxFile.path,
      docFile.path,
      mobiFile.path,
      pdfFile.path,
      emptyPdfFile.path,
    ]);

    expect(summary.added, hasLength(5));
    expect(summary.failures, hasLength(1));
    expect(summary.failures.single.fileName, 'scan.pdf');
    expect(summary.failures.single.message, contains('文字层'));

    final tags = summary.added.map((b) => b.formatTag).toSet();
    expect(tags, containsAll(['EPUB', 'DOCX', 'WORD', 'MOBI', 'PDF']));
  });

  testWidgets(
      'Bookshelf batch management works across phone/tablet and opens EPUB in reader',
      (tester) async {
    late final Directory root;
    late final Directory srcDir;
    late final LibraryRepository library;
    late final SettingsRepository settings;
    late final StatsRepository stats;
    late final String epubId;
    late final String docxId;

    await tester.runAsync(() async {
      root = Directory.systemTemp.createTempSync('shijuan_batch_ui_');
      srcDir = Directory.systemTemp.createTempSync('shijuan_batch_src_');
      library = LibraryRepository(root: root, parseInIsolate: false);
      settings = SettingsRepository(root: root);
      stats = StatsRepository(root: root);
      await library.init();
      await settings.init();
      await stats.init();

      final epubFile = File(p.join(srcDir.path, 'mountain.epub'))
        ..writeAsBytesSync(_buildSampleEpub());
      final docxFile = File(p.join(srcDir.path, 'ink.docx'))
        ..writeAsBytesSync(_buildSampleDocx());
      final sum = await library.importPaths([epubFile.path, docxFile.path]);
      final epubBook = sum.added.firstWhere((b) => b.formatTag == 'EPUB');
      final docxBook = sum.added.firstWhere((b) => b.formatTag == 'DOCX');
      epubId = epubBook.id;
      docxId = docxBook.id;
      library.saveProgress(
        epubId,
        chapterIndex: 0,
        charOffset: 10,
        percent: 0.42,
        chapterTitle: '第一章 江南春',
      );
      await library.flush();
    });
    addTearDown(() {
      library.dispose();
      settings.dispose();
      stats.dispose();
      try {
        if (root.existsSync()) root.deleteSync(recursive: true);
        if (srcDir.existsSync()) srcDir.deleteSync(recursive: true);
      } catch (_) {
        // Ignore transient Windows handle release delay on temp cleanup.
      }
    });

    // Narrow phone viewport: test batch multi-select, reset & delete without overflow.
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ShijuanApp(library: library, settings: settings, stats: stats),
    );
    await tester.pumpAndSettle();

    expect(find.text('EPUB'), findsWidgets);
    expect(find.text('DOCX'), findsWidgets);
    expect(find.byTooltip('批量管理'), findsOneWidget);

    await tester.tap(find.byTooltip('批量管理'));
    await tester.pumpAndSettle();
    expect(find.text('点击书籍卡片多选'), findsOneWidget);

    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();
    expect(find.text('已选择 2 本'), findsOneWidget);

    // Deselect DOCX, leaving EPUB (which has progress), and batch reset it.
    final docxCard = find.byKey(ValueKey(docxId));
    await tester.ensureVisible(docxCard);
    await tester.tap(docxCard);
    await tester.pumpAndSettle();
    expect(find.text('已选择 1 本'), findsOneWidget);

    await tester.tap(find.text('重置进度'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重置'));
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump(const Duration(milliseconds: 25));
      if (find.text('已重置 1 本书的阅读进度').evaluate().isNotEmpty) break;
    }
    expect(library.books.firstWhere((b) => b.id == epubId).progress.percent, 0);

    // Scroll back to header, re-enter batch mode, and remove the DOCX book.
    tester.state<ScrollableState>(find.byType(Scrollable).first).position.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('批量管理'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(docxCard);
    await tester.tap(docxCard);
    await tester.pumpAndSettle();
    await tester.tap(find.text('移出书架'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    final docxDir = Directory(p.join(root.path, 'books', docxId));
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 25)),
      );
      await tester.pump(const Duration(milliseconds: 25));
      if (!docxDir.existsSync() &&
          library.books.length == 1 &&
          find.text('移出书架').evaluate().isEmpty) {
        break;
      }
    }
    await tester.pumpAndSettle();

    expect(library.books, hasLength(1));
    expect(library.books.single.id, epubId);

    // Switch to tablet viewport and open the imported EPUB into ReaderPage.
    tester.view.physicalSize = const Size(1280, 800);
    await tester.pumpAndSettle();

    final epubCard = find.byKey(ValueKey(epubId));
    await tester.ensureVisible(epubCard);
    await tester.tap(epubCard);
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 30));
      if (find.textContaining('江南春色满山川').evaluate().isNotEmpty &&
          find.byType(CircularProgressIndicator).evaluate().isEmpty) {
        break;
      }
    }
    expect(find.byType(ReaderPage), findsOneWidget);
    expect(find.textContaining('江南春色满山川'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Uint8List _buildSampleEpub() {
  final archive = Archive();
  void addStr(String name, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  addStr('mimetype', 'application/epub+zip');
  addStr(
    'META-INF/container.xml',
    '<?xml version="1.0" encoding="UTF-8"?>'
        '<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
        '<rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>'
        '</container>',
  );
  addStr(
    'OEBPS/content.opf',
    '<?xml version="1.0" encoding="UTF-8"?>'
        '<package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="uid">'
        '<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">'
        '<dc:title>山居杂记</dc:title>'
        '<dc:creator>林清晏</dc:creator>'
        '</metadata>'
        '<manifest>'
        '<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>'
        '<item id="ch1" href="ch1.xhtml" media-type="application/xhtml+xml"/>'
        '<item id="ch2" href="ch2.xhtml" media-type="application/xhtml+xml"/>'
        '</manifest>'
        '<spine toc="ncx">'
        '<itemref idref="ch1"/>'
        '<itemref idref="ch2"/>'
        '</spine>'
        '</package>',
  );
  addStr(
    'OEBPS/toc.ncx',
    '<?xml version="1.0" encoding="UTF-8"?>'
        '<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">'
        '<navMap>'
        '<navPoint id="n1" playOrder="1"><navLabel><text>第一章 江南春</text></navLabel><content src="ch1.xhtml"/></navPoint>'
        '<navPoint id="n2" playOrder="2"><navLabel><text>第二章 塞北雪</text></navLabel><content src="ch2.xhtml"/></navPoint>'
        '</navMap>'
        '</ncx>',
  );
  addStr(
    'OEBPS/ch1.xhtml',
    '<html xmlns="http://www.w3.org/1999/xhtml"><body>'
        '<h1>第一章 江南春</h1>'
        '<p>江南\n春色满山川，画船听雨眠。</p>'
        '<p>竹外桃花三两枝，春江水暖鸭先知。</p>'
        '</body></html>',
  );
  addStr(
    'OEBPS/ch2.xhtml',
    '<html xmlns="http://www.w3.org/1999/xhtml"><body>'
        '<h1>第二章 塞北雪</h1>'
        '<p>北风卷地白草折，胡天八月即飞雪。</p>'
        '</body></html>',
  );

  return Uint8List.fromList(ZipEncoder().encode(archive));
}

Uint8List _buildSampleDocx() {
  final archive = Archive();
  void addStr(String name, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  addStr(
    '[Content_Types].xml',
    '<?xml version="1.0" encoding="UTF-8"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
        '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>'
        '</Types>',
  );
  addStr(
    '_rels/.rels',
    '<?xml version="1.0" encoding="UTF-8"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>'
        '</Relationships>',
  );
  addStr(
    'docProps/core.xml',
    '<?xml version="1.0" encoding="UTF-8"?>'
        '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
        'xmlns:dc="http://purl.org/dc/elements/1.1/">'
        '<dc:title>案头清供</dc:title>'
        '<dc:creator>苏长卿</dc:creator>'
        '</cp:coreProperties>',
  );
  addStr(
    'word/document.xml',
    '<?xml version="1.0" encoding="UTF-8"?>'
        '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
        '<w:body>'
        '<w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr><w:r><w:t>第一章 研墨</w:t></w:r></w:p>'
        '<w:p><w:r><w:t>端溪老坑砚，润墨不滞笔。</w:t></w:r></w:p>'
        '<w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr><w:r><w:t>第二章 听泉</w:t></w:r></w:p>'
        '<w:p><w:r><w:t>石涧清流响，林端月色明。</w:t></w:r></w:p>'
        '</w:body></w:document>',
  );

  return Uint8List.fromList(ZipEncoder().encode(archive));
}

Uint8List _buildSampleOle2Doc(String text) {
  const sectorSize = 512;
  const endOfChain = 0xFFFFFFFE;
  const freeSect = 0xFFFFFFFF;
  const fatSect = 0xFFFFFFFD;

  // Layout (sector indices):
  // 0: FAT
  // 1: Directory (Root Entry + WordDocument + 1Table)
  // 2..9: WordDocument stream (4096 bytes >= 4096 miniStreamCutoff so it stays in normal FAT)
  // 10..17: 1Table stream (4096 bytes)
  const totalSectors = 18;
  final file = Uint8List((1 + totalSectors) * sectorSize);
  final data = ByteData.sublistView(file);

  // OLE2 CDF Header (512 bytes)
  const magic = [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1];
  file.setRange(0, 8, magic);
  data.setUint16(24, 0x003E, Endian.little);
  data.setUint16(26, 0x0003, Endian.little);
  data.setUint16(28, 0xFFFE, Endian.little);
  data.setUint16(30, 9, Endian.little); // sectorShift = 512
  data.setUint16(32, 6, Endian.little); // miniShift = 64
  data.setUint32(44, 1, Endian.little); // numFatSectors
  data.setUint32(48, 1, Endian.little); // firstDirSector = 1
  data.setUint32(56, 4096, Endian.little); // miniStreamCutoff
  data.setUint32(60, endOfChain, Endian.little);
  data.setUint32(68, endOfChain, Endian.little);
  data.setUint32(76, 0, Endian.little); // DIFAT[0] -> FAT at sector 0
  for (var i = 1; i < 109; i++) {
    data.setUint32(76 + i * 4, freeSect, Endian.little);
  }

  // FAT (sector 0)
  final fatOff = (1 + 0) * sectorSize;
  for (var i = 0; i < 128; i++) {
    data.setUint32(fatOff + i * 4, freeSect, Endian.little);
  }
  data.setUint32(fatOff + 0 * 4, fatSect, Endian.little);
  data.setUint32(fatOff + 1 * 4, endOfChain, Endian.little); // Dir
  for (var s = 2; s < 9; s++) {
    data.setUint32(fatOff + s * 4, s + 1, Endian.little);
  }
  data.setUint32(fatOff + 9 * 4, endOfChain, Endian.little);
  for (var s = 10; s < 17; s++) {
    data.setUint32(fatOff + s * 4, s + 1, Endian.little);
  }
  data.setUint32(fatOff + 17 * 4, endOfChain, Endian.little);

  // WordDocument stream payload (starts at 0x800 inside stream)
  final wordBuf = Uint8List(4096);
  final wordData = ByteData.sublistView(wordBuf);
  const textStart = 0x800;
  final units = text.codeUnits;
  for (var i = 0; i < units.length; i++) {
    wordData.setUint16(textStart + i * 2, units[i], Endian.little);
  }

  // FIB header with FIB base (0x20), csw=0, cslw=4 (ccpText at idx 3), cbRgFcLcb=34 (fcClx/lcbClx at idx 33).
  wordData.setUint16(0, 0xA5EC, Endian.little);
  wordData.setUint16(10, 0x0200, Endian.little); // fWhichTblStm = 1 (1Table)
  wordData.setUint32(0x18, textStart, Endian.little);
  wordData.setUint32(0x1C, textStart + units.length * 2, Endian.little);
  wordData.setUint16(0x20, 0, Endian.little); // csw = 0
  const cslwOff = 0x22;
  wordData.setUint16(cslwOff, 4, Endian.little); // cslw = 4
  const rgLwOff = cslwOff + 2;
  wordData.setUint32(rgLwOff + 12, units.length, Endian.little); // ccpText
  const cbRgFcLcbOff = rgLwOff + 16;
  wordData.setUint16(cbRgFcLcbOff, 34, Endian.little); // cbRgFcLcb = 34
  const rgFcLcbOff = cbRgFcLcbOff + 2;
  const clxBytesLen = 5 + 4 + 4 + 8; // 0x02 + lcb + cp[0,len] + 1 pcd(8)
  wordData.setUint32(rgFcLcbOff + 33 * 8, 0, Endian.little); // fcClx = 0
  wordData.setUint32(rgFcLcbOff + 33 * 8 + 4, clxBytesLen, Endian.little);

  // 1Table stream payload: Clx Piece Table (clxt=0x02, lcb=16, 1 piece UTF-16LE).
  final tableBuf = Uint8List(4096);
  final tableData = ByteData.sublistView(tableBuf);
  tableBuf[0] = 0x02;
  tableData.setUint32(1, 16, Endian.little); // lcb
  tableData.setUint32(5, 0, Endian.little); // cp[0]
  tableData.setUint32(9, units.length, Endian.little); // cp[1]
  // pcd[0] starts at offset 13; fc raw sits at +2 (bit 30 cleared => UTF-16LE).
  tableData.setUint32(13 + 2, textStart, Endian.little);

  file.setRange((1 + 2) * sectorSize, (1 + 2) * sectorSize + 4096, wordBuf);
  file.setRange((1 + 10) * sectorSize, (1 + 10) * sectorSize + 4096, tableBuf);

  // Directory entries in sector 1.
  void writeDirEntry(int slot, String name, int objType, int startSec, int size) {
    final base = (1 + 1) * sectorSize + slot * 128;
    for (var i = 0; i < name.length; i++) {
      data.setUint16(base + i * 2, name.codeUnitAt(i), Endian.little);
    }
    data.setUint16(base + 64, (name.length + 1) * 2, Endian.little);
    file[base + 66] = objType;
    data.setUint32(base + 116, startSec, Endian.little);
    data.setUint32(base + 120, size, Endian.little);
  }

  writeDirEntry(0, 'Root Entry', 5, endOfChain, 0);
  writeDirEntry(1, 'WordDocument', 2, 2, wordBuf.length);
  writeDirEntry(2, '1Table', 2, 10, tableBuf.length);

  return file;
}

Uint8List _buildSampleMobi() {
  final htmlBody = utf8.encode(
    '<html><body>'
    '<h1>第一章 云开</h1><p>长风破浪会有时，直挂云帆济沧海。</p>'
    '<h1>第二章 月明</h1><p>星垂平野阔，月涌大江流。</p>'
    '</body></html>',
  );
  final titleBytes = utf8.encode('云海奇谭');

  final record0 = Uint8List(256 + titleBytes.length);
  final r0View = ByteData.sublistView(record0);
  r0View.setUint16(0, 1); // PalmDOC uncompressed
  r0View.setUint32(4, htmlBody.length);
  r0View.setUint16(8, 1); // 1 text record
  r0View.setUint16(10, 4096);
  r0View.setUint16(12, 0); // no encryption
  record0.setRange(16, 20, ascii.encode('MOBI'));
  r0View.setUint32(20, 232); // headerLength (ends at 16 + 232 = 248)
  r0View.setUint32(28, 65001); // UTF-8 codepage
  r0View.setUint32(0x54, 248); // title offset
  r0View.setUint32(0x58, titleBytes.length);
  r0View.setUint32(0x68, 6); // MOBI 6
  r0View.setUint32(0x6C, 0xFFFFFFFF); // no images
  record0.setRange(248, 248 + titleBytes.length, titleBytes);

  const recordTableEnd = 78 + 2 * 8;
  final r0Off = recordTableEnd;
  final r1Off = r0Off + record0.length;
  final out = Uint8List(r1Off + htmlBody.length);
  final outView = ByteData.sublistView(out);

  final pdbName = ascii.encode('YunHaiQiTan');
  out.setRange(0, pdbName.length, pdbName);
  out.setRange(60, 68, ascii.encode('BOOKMOBI'));
  outView.setUint16(76, 2); // 2 records
  outView.setUint32(78, r0Off);
  outView.setUint32(86, r1Off);

  out.setRange(r0Off, r1Off, record0);
  out.setRange(r1Off, out.length, htmlBody);
  return out;
}

Uint8List _buildSamplePdf({required bool withText}) {
  final objects = <int, String>{};
  objects[1] = '<< /Type /Catalog /Pages 2 0 R >>';
  objects[2] = '<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >>';
  objects[3] =
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 5 0 R >> >> /Contents 6 0 R >>';
  objects[4] =
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 5 0 R >> >> /Contents 7 0 R >>';
  objects[5] = '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>';

  final stream1 = withText
      ? 'BT /F1 12 Tf 72 640 Td (Chapter 1 Quiet Morning) Tj 0 -18 Td (Morning sunlight fills the courtyard.) Tj 0 -18 Td (Tea steam rises beside the inkstone.) Tj ET'
      : 'q Q';
  final stream2 = withText
      ? 'BT /F1 12 Tf 72 640 Td (Chapter 2 Evening Breeze) Tj 0 -18 Td (Gentle wind drifts over the bamboo grove.) Tj 0 -18 Td (Lantern light warms the stone path.) Tj ET'
      : 'q Q';
  objects[6] = '<< /Length ${stream1.length} >>\nstream\n$stream1\nendstream';
  objects[7] = '<< /Length ${stream2.length} >>\nstream\n$stream2\nendstream';
  objects[8] = '<< /Title (Morning Notes) /Author (Reader Author) >>';

  final sb = StringBuffer('%PDF-1.4\n');
  final offsets = <int, int>{};
  for (var id = 1; id <= 8; id++) {
    offsets[id] = sb.length;
    sb.write('$id 0 obj\n${objects[id]}\nendobj\n');
  }
  final xrefOffset = sb.length;
  sb.write('xref\n0 9\n0000000000 65535 f \n');
  for (var id = 1; id <= 8; id++) {
    sb.write('${offsets[id].toString().padLeft(10, '0')} 00000 n \n');
  }
  sb.write('trailer\n<< /Size 9 /Root 1 0 R /Info 8 0 R >>\nstartxref\n$xrefOffset\n%%EOF\n');
  return Uint8List.fromList(latin1.encode(sb.toString()));
}
