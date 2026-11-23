import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:modu_reader/data/library_repository.dart';
import 'package:path/path.dart' as p;

void main() {
  test('imports, reloads, saves progress and deletes a book', () async {
    final root = Directory.systemTemp.createTempSync('modu_library_');
    final sourceDir = Directory.systemTemp.createTempSync('modu_source_');
    final library = LibraryRepository(root: root, parseInIsolate: false);
    try {
      await library.init();
      expect(library.books, isEmpty);

      final source = File(p.join(sourceDir.path, '测试小说.txt'));
      await source.writeAsString(
        '第一章 起点\n　　这是第一段。\n\n第二章 转折\n　　这是第二段。\n',
      );

      final first = await library.importPaths([source.path]);
      expect(first.failures, isEmpty);
      expect(first.added, hasLength(1));
      final book = first.added.single;
      expect(book.title, '测试小说');
      expect(book.chapterCount, 2);
      expect(book.charCount, greaterThan(0));
      expect(library.books, hasLength(1));

      final contentPath =
          p.join(root.path, 'books', book.id, 'content.txt');
      expect(File(contentPath).existsSync(), isTrue);

      final duplicate = await library.importPaths([source.path]);
      expect(duplicate.added, isEmpty);
      expect(duplicate.skipped, hasLength(1));

      final text = await library.loadBookText(book);
      expect(text.chapters, hasLength(2));
      expect(text.content, contains('这是第一段。'));

      library.saveProgress(
        book.id,
        chapterIndex: 1,
        charOffset: text.chapters[1].start,
        percent: 0.6,
        chapterTitle: text.chapters[1].title,
      );
      await library.flush();

      final reloaded = LibraryRepository(root: root, parseInIsolate: false);
      await reloaded.init();
      try {
        expect(reloaded.books, hasLength(1));
        final saved = reloaded.books.single;
        expect(saved.progress.chapterIndex, 1);
        expect(saved.progress.percent, closeTo(0.6, 0.0001));
        expect(saved.lastChapterTitle, '第二章 转折');

        await reloaded.deleteBook(saved);
        expect(reloaded.books, isEmpty);
        expect(
          Directory(p.join(root.path, 'books', saved.id)).existsSync(),
          isFalse,
        );
      } finally {
        reloaded.dispose();
      }
    } finally {
      library.dispose();
      if (root.existsSync()) root.deleteSync(recursive: true);
      if (sourceDir.existsSync()) sourceDir.deleteSync(recursive: true);
    }
  });

  test('rejects a file with no readable text', () async {
    final root = Directory.systemTemp.createTempSync('modu_library_');
    final sourceDir = Directory.systemTemp.createTempSync('modu_source_');
    final library = LibraryRepository(root: root, parseInIsolate: false);
    try {
      await library.init();
      final source = File(p.join(sourceDir.path, '空白.txt'));
      await source.writeAsString('\n\n   \n');
      final summary = await library.importPaths([source.path]);
      expect(summary.added, isEmpty);
      expect(summary.failures, hasLength(1));
      expect(library.books, isEmpty);
    } finally {
      library.dispose();
      if (root.existsSync()) root.deleteSync(recursive: true);
      if (sourceDir.existsSync()) sourceDir.deleteSync(recursive: true);
    }
  });
}
