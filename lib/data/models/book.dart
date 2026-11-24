import '../../core/formatters.dart';

/// Reading position of a book.
///
/// [charOffset] is an absolute UTF-16 offset into the book content and
/// [percent] is a 0..1 fraction of the whole book. Both are stored so the
/// library screen can show progress without loading chapter indexes.
class ReadingProgress {
  const ReadingProgress({
    this.chapterIndex = 0,
    this.charOffset = 0,
    this.percent = 0,
    this.updatedAt,
  });

  final int chapterIndex;
  final int charOffset;
  final double percent;
  final DateTime? updatedAt;

  bool get isStarted =>
      charOffset > 0 || percent > 0 || updatedAt != null;

  ReadingProgress copyWith({
    int? chapterIndex,
    int? charOffset,
    double? percent,
    DateTime? updatedAt,
  }) =>
      ReadingProgress(
        chapterIndex: chapterIndex ?? this.chapterIndex,
        charOffset: charOffset ?? this.charOffset,
        percent: percent ?? this.percent,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'chapterIndex': chapterIndex,
        'charOffset': charOffset,
        'percent': percent,
        'updatedAt': updatedAt?.toIso8601String(),
      };

  factory ReadingProgress.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const ReadingProgress();
    return ReadingProgress(
      chapterIndex: (json['chapterIndex'] as num?)?.toInt() ?? 0,
      charOffset: (json['charOffset'] as num?)?.toInt() ?? 0,
      percent: (json['percent'] as num?)?.toDouble() ?? 0,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
    );
  }
}

/// A book on the shelf. The text itself is stored next to the metadata in
/// `<dataDir>/books/<id>/`.
class Book {
  const Book({
    required this.id,
    required this.title,
    required this.author,
    required this.fileName,
    required this.encoding,
    required this.charCount,
    required this.chapterCount,
    required this.fileSize,
    required this.importedAt,
    required this.lastOpenedAt,
    required this.lastChapterTitle,
    required this.progress,
  });

  final String id;
  final String title;

  /// Empty when the source file does not contain author information.
  final String author;
  final String fileName;
  final String encoding;
  final int charCount;
  final int chapterCount;
  final int fileSize;
  final DateTime importedAt;
  final DateTime lastOpenedAt;
  final String lastChapterTitle;
  final ReadingProgress progress;

  String get displayAuthor => author.trim().isEmpty ? '佚名' : author.trim();

  String get formatTag => Fmt.formatTagForPath(fileName);

  Book copyWith({
    String? id,
    String? title,
    String? author,
    String? fileName,
    String? encoding,
    int? charCount,
    int? chapterCount,
    int? fileSize,
    DateTime? importedAt,
    DateTime? lastOpenedAt,
    String? lastChapterTitle,
    ReadingProgress? progress,
  }) =>
      Book(
        id: id ?? this.id,
        title: title ?? this.title,
        author: author ?? this.author,
        fileName: fileName ?? this.fileName,
        encoding: encoding ?? this.encoding,
        charCount: charCount ?? this.charCount,
        chapterCount: chapterCount ?? this.chapterCount,
        fileSize: fileSize ?? this.fileSize,
        importedAt: importedAt ?? this.importedAt,
        lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
        lastChapterTitle: lastChapterTitle ?? this.lastChapterTitle,
        progress: progress ?? this.progress,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'author': author,
        'fileName': fileName,
        'encoding': encoding,
        'charCount': charCount,
        'chapterCount': chapterCount,
        'fileSize': fileSize,
        'importedAt': importedAt.toIso8601String(),
        'lastOpenedAt': lastOpenedAt.toIso8601String(),
        'lastChapterTitle': lastChapterTitle,
        'progress': progress.toJson(),
      };

  factory Book.fromJson(Map<String, dynamic> json) => Book(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '未命名',
        author: json['author'] as String? ?? '',
        fileName: json['fileName'] as String? ?? '',
        encoding: json['encoding'] as String? ?? 'UTF-8',
        charCount: (json['charCount'] as num?)?.toInt() ?? 0,
        chapterCount: (json['chapterCount'] as num?)?.toInt() ?? 0,
        fileSize: (json['fileSize'] as num?)?.toInt() ?? 0,
        importedAt: DateTime.tryParse(json['importedAt'] as String? ?? '') ??
            DateTime.now(),
        lastOpenedAt: DateTime.tryParse(json['lastOpenedAt'] as String? ?? '') ??
            DateTime.now(),
        lastChapterTitle: json['lastChapterTitle'] as String? ?? '',
        progress: ReadingProgress.fromJson(
          (json['progress'] as Map?)?.cast<String, dynamic>(),
        ),
      );
}

enum BookSort {
  recent('最近阅读'),
  imported('导入时间'),
  title('书名');

  const BookSort(this.label);
  final String label;

  static BookSort fromName(String? name) => BookSort.values.firstWhere(
        (value) => value.name == name,
        orElse: () => BookSort.recent,
      );
}
