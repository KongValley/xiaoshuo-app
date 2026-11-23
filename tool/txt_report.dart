import 'dart:convert';
import 'dart:io';

import 'package:modu_reader/data/txt/parser.dart';
import 'package:path/path.dart' as p;

/// Developer helper: parse a TXT file and write a UTF-8 report.
///
/// Usage: `dart run tool/txt_report.dart <novel.txt> <report.txt> [sampleCount]`
void main(List<String> args) {
  if (args.length < 2) {
    stderr.writeln(
      'Usage: dart run tool/txt_report.dart <novel.txt> <report.txt> [sampleCount]',
    );
    exitCode = 64;
    return;
  }

  final path = args[0];
  final reportPath = args[1];
  final sampleCount = args.length > 2 ? int.tryParse(args[2]) ?? 6 : 6;
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('File not found: $path');
    exitCode = 66;
    return;
  }

  final stopwatch = Stopwatch()..start();
  final parsed = TxtParser.parse(
    file.readAsBytesSync(),
    fileName: p.basename(path),
  );
  stopwatch.stop();

  final out = StringBuffer();
  out.writeln('title: ${parsed.title}');
  out.writeln('author: ${parsed.author.isEmpty ? '(unknown)' : parsed.author}');
  out.writeln('encoding: ${parsed.encoding}');
  out.writeln('sourceBytes: ${parsed.sourceBytes}');
  out.writeln('contentChars: ${parsed.content.length}');
  out.writeln('chapters: ${parsed.chapters.length}');
  out.writeln('parseMillis: ${stopwatch.elapsedMilliseconds}');
  out.writeln('firstChapterChars: '
      '${parsed.chapters.isEmpty ? 0 : parsed.chapters.first.length}');
  out.writeln();
  out.writeln('--- first $sampleCount chapters ---');
  for (final chapter in parsed.chapters.take(sampleCount)) {
    out.writeln('[${chapter.start}..${chapter.end}] ${chapter.title}');
    final body = parsed.content.substring(chapter.start, chapter.end).trim();
    final preview = body.length > 120 ? body.substring(0, 120) : body;
    out.writeln(preview.replaceAll('\n', ' ⏎ '));
    out.writeln();
  }
  final tailCount = sampleCount > parsed.chapters.length
      ? parsed.chapters.length
      : sampleCount;
  out.writeln('--- last $tailCount chapters ---');
  if (tailCount > 0) {
    for (final chapter in parsed.chapters.reversed.take(tailCount)) {
      out.writeln('[${chapter.start}..${chapter.end}] ${chapter.title}');
    }
  }
  out.writeln();
  out.writeln('--- head of content ---');
  out.writeln(parsed.content.substring(
    0,
    parsed.content.length < 300 ? parsed.content.length : 300,
  ));
  out.writeln();
  out.writeln('--- tail of content ---');
  final tailStart =
      parsed.content.length > 300 ? parsed.content.length - 300 : 0;
  out.writeln(parsed.content.substring(tailStart));

  final numbers = <int>[];
  for (final chapter in parsed.chapters) {
    final match = RegExp(r'^(\d{1,4})\s').firstMatch(chapter.title);
    if (match != null) {
      numbers.add(int.parse(match.group(1)!));
    }
  }
  if (numbers.length > 2) {
    out.writeln();
    out.writeln('--- numeric chapter gaps ---');
    for (var i = 1; i < numbers.length; i++) {
      if (numbers[i] != numbers[i - 1] + 1) {
        out.writeln('${numbers[i - 1]} -> ${numbers[i]} '
            '(${numbers[i] - numbers[i - 1] - 1} missing)');
      }
    }
  }

  File(reportPath).writeAsStringSync(out.toString(), encoding: utf8);
  stdout.writeln('Wrote $reportPath');
}
