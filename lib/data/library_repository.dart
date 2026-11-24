import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/formatters.dart';
import '../data/models/book.dart';
import '../data/models/chapter.dart';
import '../data/models/reading_stats.dart';
import 'txt/parser.dart';

class BookText {
  const BookText({required this.content, required this.chapters});

  final String content;
  final List<Chapter> chapters;
}

class ImportFailure {
  const ImportFailure(this.fileName, this.message);

  final String fileName;
  final String message;
}

class ImportSummary {
  const ImportSummary({
    required this.added,
    required this.skipped,
    required this.failures,
  });

  final List<Book> added;
  final List<String> skipped;
  final List<ImportFailure> failures;

  bool get isEmpty => added.isEmpty && skipped.isEmpty && failures.isEmpty;
}

/// What [LibraryRepository.init] had to repair. The shelf mentions it once so
/// a recovered library is never a silent surprise.
class RecoveryReport {
  const RecoveryReport({
    this.usedBackupIndex = false,
    this.recoveredBooks = 0,
  });

  /// The main index could not be read and the backup copy was used instead.
  final bool usedBackupIndex;

  /// Book folders that were on disk but missing from the index.
  final int recoveredBooks;

  bool get hasRecovery => usedBackupIndex || recoveredBooks > 0;
}

/// The local book library. Books are copied into the app's own data folder so
/// they remain available even if the original TXT is moved or deleted.
///
/// The shelf is described by `library.json`, which is written through a
/// temporary file and mirrored to `library.json.bak`. Every book folder also
/// carries its own `book.json`, so a lost index can always be rebuilt from
/// what is on disk.
class LibraryRepository extends ChangeNotifier {
  LibraryRepository({
    required Directory root,
    this.parseInIsolate = true,
  })  : _root = root,
        _booksDir = Directory(p.join(root.path, 'books')),
        _libraryFile = File(p.join(root.path, 'library.json')),
        _backupFile = File(p.join(root.path, 'library.json.bak'));

  final Directory _root;
  final Directory _booksDir;
  final File _libraryFile;
  final File _backupFile;
  final bool parseInIsolate;

  final List<Book> _books = [];
  final Set<String> _dirtyBooks = {};
  Timer? _saveTimer;
  Future<void> _writeChain = Future<void>.value();
  bool _loaded = false;
  String? _lastIndexPayload;
  RecoveryReport _recovery = const RecoveryReport();

  List<Book> get books => List<Book>.unmodifiable(_books);

  Directory get booksDirectory => _booksDir;

  RecoveryReport get recovery => _recovery;

  Future<void> init() async {
    await _booksDir.create(recursive: true);

    var books = <Book>[];
    var usedBackup = false;
    try {
      books = await _readIndex(_libraryFile);
    } catch (_) {
      // Unreadable or half-written: fall back to the backup copy.
      try {
        books = await _readIndex(_backupFile);
        usedBackup = true;
      } catch (_) {
        // Both copies are unusable; the book folders are the last resort.
      }
    }

    // Drop entries whose text was removed outside the app.
    final known = <String>{};
    for (final book in books) {
      if (!await _hasBookFiles(book.id)) continue;
      known.add(book.id);
    }
    books = [for (final book in books) if (known.contains(book.id)) book];

    // Folders the index does not know about are books it lost. Every folder
    // has its own metadata file, so they can simply be taken back in.
    final orphans = <String>[];
    await for (final entity in _booksDir.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final id = p.basename(entity.path);
      if (known.contains(id) || !await _hasBookFiles(id)) continue;
      orphans.add(id);
    }
    orphans.sort();
    var recovered = 0;
    for (final id in orphans) {
      final book = await _recoverBook(id, ++recovered);
      if (book == null) {
        recovered--;
        continue;
      }
      books.add(book);
    }

    _recovery = RecoveryReport(
      usedBackupIndex: usedBackup,
      recoveredBooks: recovered,
    );
    _books
      ..clear()
      ..addAll(books);
    // Books imported before `book.json` existed get one now.
    _dirtyBooks.clear();
    for (final book in _books) {
      if (!_sidecarFile(book.id).existsSync()) _dirtyBooks.add(book.id);
    }
    _loaded = true;
    await _persistNow();
    notifyListeners();
  }

  Book? bookById(String id) {
    for (final book in _books) {
      if (book.id == id) return book;
    }
    return null;
  }

  File _contentFile(String id) => File(p.join(_booksDir.path, id, 'content.txt'));

  File _chaptersFile(String id) => File(p.join(_booksDir.path, id, 'chapters.json'));

  File _sidecarFile(String id) => File(p.join(_booksDir.path, id, 'book.json'));

  File _bookmarksFile(String id) =>
      File(p.join(_booksDir.path, id, 'bookmarks.json'));

  Future<bool> _hasBookFiles(String id) async =>
      await _contentFile(id).exists() && await _chaptersFile(id).exists();

  Future<BookText> loadBookText(Book book) async {
    final content = await _contentFile(book.id).readAsString(encoding: utf8);
    final index = await _readChapterIndex(_chaptersFile(book.id));
    return BookText(content: content, chapters: index?.chapters ?? const []);
  }

  Future<List<BookBookmark>> loadBookmarks(String bookId) async {
    try {
      final file = _bookmarksFile(bookId);
      if (!await file.exists()) return const [];
      final raw = await file.readAsString(encoding: utf8);
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded)
          if (item is Map) BookBookmark.fromJson(item.cast<String, dynamic>()),
      ]..sort((a, b) => a.charOffset.compareTo(b.charOffset));
    } catch (_) {
      return const [];
    }
  }

  Future<void> saveBookmarks(String bookId, List<BookBookmark> bookmarks) async {
    try {
      final file = _bookmarksFile(bookId);
      await file.parent.create(recursive: true);
      await file.writeAsString(
        const JsonEncoder.withIndent('  ')
            .convert([for (final item in bookmarks) item.toJson()]),
        encoding: utf8,
        flush: true,
      );
    } catch (_) {
      // Non-fatal if bookmark write fails.
    }
  }

  /// Imports the given TXT paths. Parsing happens in a background isolate so
  /// large novels do not freeze the UI.
  Future<ImportSummary> importPaths(
    List<String> paths, {
    void Function(int completed, int total, String fileName)? onProgress,
  }) async {
    final added = <Book>[];
    final skipped = <String>[];
    final failures = <ImportFailure>[];

    for (var i = 0; i < paths.length; i++) {
      final path = paths[i];
      final fileName = p.basename(path);
      onProgress?.call(i, paths.length, fileName);
      try {
        final file = File(path);
        if (!await file.exists()) {
          failures.add(ImportFailure(fileName, '文件不存在'));
          continue;
        }
        if (!Fmt.isTxtFile(path)) {
          failures.add(ImportFailure(fileName, '仅支持 TXT 文件'));
          continue;
        }
        final size = await file.length();
        final duplicate = _books.any(
          (book) => book.fileName == fileName && book.fileSize == size,
        );
        if (duplicate) {
          skipped.add(fileName);
          continue;
        }

        final parsed = parseInIsolate
            ? await Isolate.run(() => _parseNovelFile(path))
            : _parseNovelFile(path);
        if (parsed.content.trim().isEmpty || parsed.chapters.isEmpty) {
          failures.add(ImportFailure(fileName, '没有找到可阅读的正文'));
          continue;
        }

        final id = _newId();
        final bookDir = Directory(p.join(_booksDir.path, id));
        await bookDir.create(recursive: true);
        try {
          await File(p.join(bookDir.path, 'content.txt'))
              .writeAsString(parsed.content, encoding: utf8, flush: true);
          final index = ChapterIndex(
            totalChars: parsed.content.length,
            chapters: parsed.chapters,
          );
          await File(p.join(bookDir.path, 'chapters.json')).writeAsString(
            jsonEncode(index.toJson()),
            encoding: utf8,
            flush: true,
          );
        } catch (error) {
          await _deleteDirectory(bookDir);
          rethrow;
        }

        final now = DateTime.now();
        final book = Book(
          id: id,
          title: parsed.title,
          author: parsed.author,
          fileName: fileName,
          encoding: parsed.encoding,
          charCount: parsed.content.length,
          chapterCount: parsed.chapters.length,
          fileSize: parsed.sourceBytes,
          importedAt: now,
          lastOpenedAt: now,
          lastChapterTitle: parsed.chapters.first.title,
          progress: const ReadingProgress(),
        );
        _books.add(book);
        _dirtyBooks.add(id);
        added.add(book);
        _schedulePersist();
        notifyListeners();
      } catch (error) {
        failures.add(ImportFailure(fileName, _friendlyError(error)));
      }
    }

    onProgress?.call(paths.length, paths.length, '');
    await _persistNow();
    return ImportSummary(added: added, skipped: skipped, failures: failures);
  }

  static ParsedNovel _parseNovelFile(String path) {
    final bytes = File(path).readAsBytesSync();
    return TxtParser.parse(bytes, fileName: p.basename(path));
  }

  Future<void> markOpened(Book book) async {
    final index = _books.indexWhere((item) => item.id == book.id);
    if (index < 0) return;
    _books[index] = _books[index].copyWith(lastOpenedAt: DateTime.now());
    _dirtyBooks.add(book.id);
    notifyListeners();
    _schedulePersist();
  }

  void saveProgress(
    String bookId, {
    required int chapterIndex,
    required int charOffset,
    required double percent,
    required String chapterTitle,
  }) {
    final index = _books.indexWhere((item) => item.id == bookId);
    if (index < 0) return;
    final book = _books[index];
    final progress = ReadingProgress(
      chapterIndex: chapterIndex,
      charOffset: charOffset,
      percent: percent.clamp(0.0, 1.0),
      updatedAt: DateTime.now(),
    );
    _books[index] = book.copyWith(
      progress: progress,
      lastChapterTitle: chapterTitle,
      lastOpenedAt: DateTime.now(),
    );
    _dirtyBooks.add(bookId);
    notifyListeners();
    _schedulePersist();
  }

  Future<void> resetProgress(String bookId) async {
    final index = _books.indexWhere((item) => item.id == bookId);
    if (index < 0) return;
    final book = _books[index];
    final firstTitle = book.lastChapterTitle;
    _books[index] = book.copyWith(
      progress: const ReadingProgress(),
      lastChapterTitle: firstTitle,
    );
    _dirtyBooks.add(bookId);
    notifyListeners();
    await _persistNow();
  }

  Future<void> deleteBook(Book book) async {
    _books.removeWhere((item) => item.id == book.id);
    _dirtyBooks.remove(book.id);
    notifyListeners();
    await _persistNow();
    final dir = Directory(p.join(_booksDir.path, book.id));
    await _deleteDirectory(dir);
  }

  Future<void> _deleteDirectory(Directory dir) async {
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {
      // Best effort cleanup.
    }
  }

  // ---------------------------------------------------------------------------
  // Persistence
  // ---------------------------------------------------------------------------

  void _schedulePersist() {
    if (!_loaded) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 350), _persistNow);
  }

  Future<void> _persistNow() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    final payload = const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
      'version': 1,
      'books': [for (final book in _books) book.toJson()],
    });
    final indexChanged = payload != _lastIndexPayload;
    // Anything marked after this point is written by the next pass.
    final dirty = _dirtyBooks.toList();
    _dirtyBooks.clear();
    _writeChain = _writeChain.then((_) async {
      try {
        await _root.create(recursive: true);
        if (indexChanged) {
          await _writeIndex(payload);
          _lastIndexPayload = payload;
        }
        for (final id in dirty) {
          final index = _books.indexWhere((book) => book.id == id);
          if (index < 0) continue;
          try {
            await _sidecarFile(id).writeAsString(
              jsonEncode(_books[index].toJson()),
              encoding: utf8,
              flush: true,
            );
          } catch (_) {
            // The index is the primary record; a stale copy is tolerable.
          }
        }
      } catch (_) {
        // Keep the in-memory library usable.
      }
    });
    await _writeChain;
  }

  Future<void> flush() => _persistNow();

  /// Writes the index through a temporary file so a crash can never leave a
  /// half-written index behind, then refreshes the backup copy. The backup is
  /// only taken once the new index is complete, so it always matches the last
  /// successful save.
  Future<void> _writeIndex(String payload) async {
    final temp = File('${_libraryFile.path}.tmp');
    await temp.writeAsString(payload, encoding: utf8, flush: true);
    try {
      await temp.rename(_libraryFile.path);
    } on FileSystemException {
      // Windows can refuse the rename while another program holds the file
      // open. Overwriting in place still beats losing the save.
      await _libraryFile.writeAsString(payload, encoding: utf8, flush: true);
      try {
        await temp.delete();
      } catch (_) {
        // Harmless leftover.
      }
    }
    try {
      await _libraryFile.copy(_backupFile.path);
    } catch (_) {
      // A missing backup only matters if the next write is interrupted.
    }
  }

  /// Throws when the file is missing, truncated or not an index at all.
  Future<List<Book>> _readIndex(File file) async {
    final raw = await file.readAsString(encoding: utf8);
    final decoded = jsonDecode(raw);
    if (decoded is! Map || decoded['books'] is! List) {
      throw const FormatException('书库索引格式不正确');
    }
    final books = <Book>[];
    for (final item in decoded['books'] as List) {
      if (item is! Map) continue;
      final book = Book.fromJson(item.cast<String, dynamic>());
      if (book.id.isNotEmpty) books.add(book);
    }
    return books;
  }

  /// Returns null when the chapter index is missing, broken or empty.
  Future<ChapterIndex?> _readChapterIndex(File file) async {
    try {
      final raw = await file.readAsString(encoding: utf8);
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final index = ChapterIndex.fromJson(decoded.cast<String, dynamic>());
      return index.chapters.isEmpty ? null : index;
    } catch (_) {
      return null;
    }
  }

  /// Rebuilds the metadata of a book folder the index does not know about.
  /// Folders always carry their own `book.json`; only ones written before that
  /// file existed end up with a placeholder title and no reading progress.
  Future<Book?> _recoverBook(String id, int sequence) async {
    Book? book;
    try {
      final raw = await _sidecarFile(id).readAsString(encoding: utf8);
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final candidate = Book.fromJson(decoded.cast<String, dynamic>());
        if (candidate.chapterCount > 0) book = candidate;
      }
    } catch (_) {
      // No usable sidecar; rebuild from the chapter index below.
    }

    if (book == null) {
      final index = await _readChapterIndex(_chaptersFile(id));
      if (index == null) return null;
      final content = _contentFile(id);
      final size = await content.length();
      final stamp = await content.lastModified();
      book = Book(
        id: id,
        title: sequence == 1 ? '找回的书籍' : '找回的书籍 $sequence',
        author: '',
        fileName: '',
        encoding: '未知',
        charCount: index.totalChars,
        chapterCount: index.chapters.length,
        fileSize: size,
        importedAt: stamp,
        lastOpenedAt: stamp,
        lastChapterTitle: index.chapters.first.title,
        progress: const ReadingProgress(),
      );
    }
    if (book.id != id) book = book.copyWith(id: id);
    _dirtyBooks.add(id);
    return book;
  }

  String _newId() {
    final random = Random.secure().nextInt(0xFFFFFF).toRadixString(16);
    final stamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    return '$stamp$random';
  }

  String _friendlyError(Object error) {
    final text = error.toString();
    if (text.contains('FileSystemException')) return '无法读取文件';
    if (text.contains('FormatException')) return '文件编码无法识别';
    if (text.length > 120) return text.substring(0, 120);
    return text;
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }
}
