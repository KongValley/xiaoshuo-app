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

/// The local book library. Books are copied into the app's own data folder so
/// they remain available even if the original TXT is moved or deleted.
class LibraryRepository extends ChangeNotifier {
  LibraryRepository({
    required Directory root,
    this.parseInIsolate = true,
  })  : _root = root,
        _booksDir = Directory(p.join(root.path, 'books')),
        _libraryFile = File(p.join(root.path, 'library.json'));

  final Directory _root;
  final Directory _booksDir;
  final File _libraryFile;
  final bool parseInIsolate;

  final List<Book> _books = [];
  Timer? _saveTimer;
  Future<void> _writeChain = Future<void>.value();
  bool _loaded = false;

  List<Book> get books => List<Book>.unmodifiable(_books);

  Directory get booksDirectory => _booksDir;

  Future<void> init() async {
    await _booksDir.create(recursive: true);
    final books = <Book>[];
    try {
      if (await _libraryFile.exists()) {
        final raw = await _libraryFile.readAsString(encoding: utf8);
        final decoded = jsonDecode(raw);
        if (decoded is Map && decoded['books'] is List) {
          for (final item in decoded['books'] as List) {
            if (item is! Map) continue;
            final book = Book.fromJson(item.cast<String, dynamic>());
            if (book.id.isEmpty) continue;
            if (!_contentFile(book.id).existsSync()) continue;
            if (!_chaptersFile(book.id).existsSync()) continue;
            books.add(book);
          }
        }
      }
    } catch (_) {
      // Start with an empty shelf if the index cannot be read.
    }
    _books
      ..clear()
      ..addAll(books);
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

  Future<BookText> loadBookText(Book book) async {
    final contentFile = _contentFile(book.id);
    final chaptersFile = _chaptersFile(book.id);
    final content = await contentFile.readAsString(encoding: utf8);
    final chaptersRaw = await chaptersFile.readAsString(encoding: utf8);
    final decoded = jsonDecode(chaptersRaw);
    final index = decoded is Map
        ? ChapterIndex.fromJson(decoded.cast<String, dynamic>())
        : const ChapterIndex(totalChars: 0, chapters: []);
    return BookText(content: content, chapters: index.chapters);
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
    notifyListeners();
    _schedulePersist();
  }

  Future<void> deleteBook(Book book) async {
    _books.removeWhere((item) => item.id == book.id);
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
    _writeChain = _writeChain.then((_) async {
      try {
        await _root.create(recursive: true);
        await _libraryFile.writeAsString(payload, encoding: utf8, flush: true);
      } catch (_) {
        // Keep the in-memory library usable.
      }
    });
    await _writeChain;
  }

  Future<void> flush() => _persistNow();

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
