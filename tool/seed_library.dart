import 'dart:convert';
import 'dart:io';

import 'package:modu_reader/data/txt/parser.dart';
import 'package:path/path.dart' as p;

/// Developer helper: import a TXT file directly into the app's data directory
/// without opening the UI. Useful for screenshots and manual testing.
///
/// Usage:
///   `dart run tool/seed_library.dart <novel.txt> [dataDir]`
///
/// If dataDir is omitted, %LOCALAPPDATA%/ModuReader is used on Windows.
void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run tool/seed_library.dart <novel.txt> [dataDir]');
    exitCode = 64;
    return;
  }

  final source = File(args[0]);
  if (!source.existsSync()) {
    stderr.writeln('File not found: ${args[0]}');
    exitCode = 66;
    return;
  }

  final dataDir = Directory(
    args.length > 1
        ? args[1]
        : p.join(
            Platform.environment['LOCALAPPDATA'] ??
                Platform.environment['APPDATA'] ??
                Directory.current.path,
            'ModuReader',
          ),
  );

  final bytes = source.readAsBytesSync();
  final parsed = TxtParser.parse(bytes, fileName: p.basename(source.path));
  if (parsed.content.isEmpty || parsed.chapters.isEmpty) {
    stderr.writeln('No readable content in ${source.path}');
    exitCode = 65;
    return;
  }

  final booksDir = Directory(p.join(dataDir.path, 'books'));
  booksDir.createSync(recursive: true);

  final libraryFile = File(p.join(dataDir.path, 'library.json'));
  final existing = <Map<String, dynamic>>[];
  if (libraryFile.existsSync()) {
    try {
      final decoded = jsonDecode(libraryFile.readAsStringSync(encoding: utf8));
      if (decoded is Map && decoded['books'] is List) {
        for (final item in decoded['books'] as List) {
          if (item is Map) existing.add(item.cast<String, dynamic>());
        }
      }
    } catch (_) {
      // Start a fresh index.
    }
  }

  final fileName = p.basename(source.path);
  existing.removeWhere(
    (book) => book['fileName'] == fileName && book['fileSize'] == bytes.length,
  );

  final id = 'seed${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
  final bookDir = Directory(p.join(booksDir.path, id));
  bookDir.createSync(recursive: true);
  File(p.join(bookDir.path, 'content.txt'))
      .writeAsStringSync(parsed.content, encoding: utf8, flush: true);
  File(p.join(bookDir.path, 'chapters.json')).writeAsStringSync(
    jsonEncode({
      'version': 1,
      'totalChars': parsed.content.length,
      'chapters': [
        for (final chapter in parsed.chapters) chapter.toJson(),
      ],
    }),
    encoding: utf8,
    flush: true,
  );

  final now = DateTime.now().toIso8601String();
  existing.add({
    'id': id,
    'title': parsed.title,
    'author': parsed.author,
    'fileName': fileName,
    'encoding': parsed.encoding,
    'charCount': parsed.content.length,
    'chapterCount': parsed.chapters.length,
    'fileSize': bytes.length,
    'importedAt': now,
    'lastOpenedAt': now,
    'lastChapterTitle': parsed.chapters.first.title,
    'progress': {
      'chapterIndex': 0,
      'charOffset': 0,
      'percent': 0.0,
      'updatedAt': null,
    },
  });

  libraryFile.writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'version': 1,
      'books': existing,
    }),
    encoding: utf8,
    flush: true,
  );

  stdout.writeln('seeded id=$id');
  stdout.writeln('dataDir=${dataDir.path}');
  stdout.writeln('chapters=${parsed.chapters.length} chars=${parsed.content.length}');
  stdout.writeln('title=${parsed.title}');
}
