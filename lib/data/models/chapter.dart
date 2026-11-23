/// One chapter inside a book's normalized text.
///
/// [start] / [end] are UTF-16 code-unit offsets into the book's `content.txt`.
/// Chapter titles are excluded from the content itself, so offsets are
/// continuous and can be used directly for the overall reading percentage.
class Chapter {
  const Chapter({
    required this.title,
    required this.start,
    required this.end,
  });

  final String title;
  final int start;
  final int end;

  int get length => end - start;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'title': title,
        'start': start,
        'end': end,
      };

  factory Chapter.fromJson(Map<String, dynamic> json) => Chapter(
        title: json['title'] as String? ?? '',
        start: (json['start'] as num?)?.toInt() ?? 0,
        end: (json['end'] as num?)?.toInt() ?? 0,
      );
}

class ChapterIndex {
  const ChapterIndex({
    required this.totalChars,
    required this.chapters,
  });

  final int totalChars;
  final List<Chapter> chapters;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'version': 1,
        'totalChars': totalChars,
        'chapters': [for (final chapter in chapters) chapter.toJson()],
      };

  factory ChapterIndex.fromJson(Map<String, dynamic> json) => ChapterIndex(
        totalChars: (json['totalChars'] as num?)?.toInt() ?? 0,
        chapters: [
          for (final item in (json['chapters'] as List? ?? const []))
            Chapter.fromJson((item as Map).cast<String, dynamic>()),
        ],
      );
}
