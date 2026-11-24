import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shijuan_reader/data/library_repository.dart';
import 'package:shijuan_reader/data/models/book.dart';
import 'package:path/path.dart' as p;

/// A tiny two-chapter novel.
File writeSample(Directory dir) {
  final source = File(p.join(dir.path, '测试小说.txt'));
  source.writeAsStringSync(
    '第一章 起点\n　　这是第一段。\n\n第二章 转折\n　　这是第二段。\n',
  );
  return source;
}

void main() {
  late Directory root;
  late Directory sourceDir;
  late File index;
  late File backup;

  setUp(() {
    root = Directory.systemTemp.createTempSync('modu_library_');
    sourceDir = Directory.systemTemp.createTempSync('modu_source_');
    index = File(p.join(root.path, 'library.json'));
    backup = File(p.join(root.path, 'library.json.bak'));
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
    if (sourceDir.existsSync()) sourceDir.deleteSync(recursive: true);
  });

  File sidecarOf(Book book) =>
      File(p.join(root.path, 'books', book.id, 'book.json'));

  /// Imports the sample novel and returns it together with its source path.
  Future<(Book, String)> importSample(LibraryRepository library) async {
    final source = writeSample(sourceDir);
    final summary = await library.importPaths([source.path]);
    expect(summary.failures, isEmpty);
    return (summary.added.single, source.path);
  }

  test('imports, reloads, saves progress and deletes a book', () async {
    final library = LibraryRepository(root: root, parseInIsolate: false);
    try {
      await library.init();
      expect(library.books, isEmpty);
      expect(library.recovery.hasRecovery, isFalse);

      final (book, sourcePath) = await importSample(library);
      expect(book.title, '测试小说');
      expect(book.chapterCount, 2);
      expect(book.charCount, greaterThan(0));
      expect(library.books, hasLength(1));

      final contentPath = p.join(root.path, 'books', book.id, 'content.txt.gz');
      expect(File(contentPath).existsSync(), isTrue);

      final duplicate = await library.importPaths([sourcePath]);
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
        expect(reloaded.recovery.hasRecovery, isFalse);
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
    }
  });

  test('rejects a file with no readable text', () async {
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
    }
  });

  test('writes the index atomically and keeps a fallback copy', () async {
    final library = LibraryRepository(root: root, parseInIsolate: false);
    try {
      await library.init();
      final (book, _) = await importSample(library);
      await library.flush();

      // No temporary file is left behind, and every book carries its own
      // metadata next to its text.
      expect(File('${index.path}.tmp').existsSync(), isFalse);
      expect(backup.existsSync(), isTrue);
      final sidecar = jsonDecode(sidecarOf(book).readAsStringSync()) as Map;
      expect(sidecar['title'], '测试小说');
      expect(sidecar['id'], book.id);

      // Saving without any change must not rewrite the index.
      final before = index.readAsBytesSync();
      await library.flush();
      expect(index.readAsBytesSync(), before);
    } finally {
      library.dispose();
    }
  });

  test('falls back to the backup copy when the index is damaged', () async {
    final library = LibraryRepository(root: root, parseInIsolate: false);
    try {
      await library.init();
      final (book, _) = await importSample(library);
      await library.flush();

      // A crash in the middle of a write leaves a truncated file. Remove the
      // sidecar too, so only the fallback copy still knows the title.
      index.writeAsStringSync('{"version": 1, "books": [{"id": "x"');
      sidecarOf(book).deleteSync();

      final reopened = LibraryRepository(root: root, parseInIsolate: false);
      await reopened.init();
      try {
        expect(reopened.recovery.usedBackupIndex, isTrue);
        expect(reopened.books.map((item) => item.id), [book.id]);
        expect(reopened.books.single.title, '测试小说');

        // The damaged index has been replaced by a readable one.
        final repaired = jsonDecode(index.readAsStringSync()) as Map;
        expect((repaired['books'] as List).single['id'], book.id);
      } finally {
        reopened.dispose();
      }
    } finally {
      library.dispose();
    }
  });

  test('takes back books that the index lost', () async {
    final library = LibraryRepository(root: root, parseInIsolate: false);
    try {
      await library.init();
      final (book, _) = await importSample(library);
      final text = await library.loadBookText(book);
      library.saveProgress(
        book.id,
        chapterIndex: 1,
        charOffset: text.chapters[1].start,
        percent: 0.6,
        chapterTitle: '第二章 转折',
      );
      await library.flush();

      // What an older build left behind after failing to read its index: a
      // valid but empty shelf, with the book folders still on disk.
      index.writeAsStringSync('{"version": 1, "books": []}');
      backup.deleteSync();

      final reopened = LibraryRepository(root: root, parseInIsolate: false);
      await reopened.init();
      try {
        expect(reopened.recovery.usedBackupIndex, isFalse);
        expect(reopened.recovery.recoveredBooks, 1);
        final recovered = reopened.books.single;
        expect(recovered.id, book.id);
        expect(recovered.title, '测试小说');
        expect(recovered.chapterCount, 2);
        expect(recovered.progress.chapterIndex, 1);
        expect(recovered.progress.percent, closeTo(0.6, 0.0001));

        await reopened.flush();
        final settled = LibraryRepository(root: root, parseInIsolate: false);
        await settled.init();
        try {
          expect(settled.recovery.hasRecovery, isFalse);
          expect(settled.books.single.id, book.id);
        } finally {
          settled.dispose();
        }
      } finally {
        reopened.dispose();
      }
    } finally {
      library.dispose();
    }
  });

  test('rebuilds a book folder that has no metadata of its own', () async {
    final library = LibraryRepository(root: root, parseInIsolate: false);
    try {
      await library.init();
      final (book, _) = await importSample(library);
      await library.flush();

      // Folders written before `book.json` existed have no sidecar.
      sidecarOf(book).deleteSync();
      index.writeAsStringSync('{"version": 1, "books": []}');
      backup.deleteSync();
      // An import that was interrupted halfway only wrote the text.
      final broken = Directory(p.join(root.path, 'books', 'half'));
      broken.createSync(recursive: true);
      File(p.join(broken.path, 'content.txt')).writeAsStringSync('正文');

      final reopened = LibraryRepository(root: root, parseInIsolate: false);
      await reopened.init();
      try {
        expect(reopened.recovery.recoveredBooks, 1);
        final recovered = reopened.books.single;
        expect(recovered.id, book.id);
        expect(recovered.title, '找回的书籍');
        expect(recovered.chapterCount, 2);
        expect(recovered.progress.isStarted, isFalse);
        expect(sidecarOf(recovered).existsSync(), isTrue);
        // Incomplete folders are left alone rather than deleted.
        expect(broken.existsSync(), isTrue);
      } finally {
        reopened.dispose();
      }
    } finally {
      library.dispose();
    }
  });

  test('forgets a book whose text was removed outside the app', () async {
    final library = LibraryRepository(root: root, parseInIsolate: false);
    try {
      await library.init();
      final (book, _) = await importSample(library);
      await library.flush();
      Directory(p.join(root.path, 'books', book.id)).deleteSync(recursive: true);

      final reopened = LibraryRepository(root: root, parseInIsolate: false);
      await reopened.init();
      try {
        expect(reopened.books, isEmpty);
        expect(reopened.recovery.hasRecovery, isFalse);
      } finally {
        reopened.dispose();
      }
    } finally {
      library.dispose();
    }
  });
}
