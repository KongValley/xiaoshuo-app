import 'package:flutter/material.dart';

/// Literary chop-seal achievements unlocked through genuine offline reading.
enum StampId {
  firstOpen(
    title: '初展素卷',
    subtitle: '万卷之旅，始于今朝展卷',
    requirement: '首次打开任意一本书开始阅读',
    target: 1,
    glyph: '展',
    accent: Color(0xFFC1442D),
  ),
  pages50(
    title: '渐入佳境',
    subtitle: '书页沙沙，心随文字远行',
    requirement: '累计翻阅 50 页正文',
    target: 50,
    glyph: '境',
    accent: Color(0xFF8B5A2B),
  ),
  session15m(
    title: '手不释卷',
    subtitle: '一刻钟沉心静读，尘嚣渐远',
    requirement: '单次连续专注阅读满 15 分钟',
    target: 15 * 60,
    glyph: '静',
    accent: Color(0xFF42634B),
  ),
  streak3d(
    title: '连日拾卷',
    subtitle: '三日不缀，案头灯火常暖',
    requirement: '连续 3 天每天都有阅读记录',
    target: 3,
    glyph: '恒',
    accent: Color(0xFFA84C32),
  ),
  chapters10(
    title: '百转千回',
    subtitle: '一章一印，见证故事起承转合',
    requirement: '完整翻阅并读完 10 个章节',
    target: 10,
    glyph: '章',
    accent: Color(0xFF4A4E74),
  ),
  chars5w(
    title: '五万墨行',
    subtitle: '行过五万字山川，胸中自有丘壑',
    requirement: '累计阅历超过 5 万字',
    target: 50000,
    glyph: '行',
    accent: Color(0xFF2E5C6E),
  ),
  nightReader(
    title: '秉烛夜读',
    subtitle: '万籁俱寂时，一盏夜灯陪书行',
    requirement: '在夜间或墨黑护眼主题下阅读',
    target: 1,
    glyph: '夜',
    accent: Color(0xFF5D466E),
  ),
  bookFinished(
    title: '圆满合卷',
    subtitle: '从开篇至终章，圆满一卷山河',
    requirement: '完整读完任意一本书',
    target: 1,
    glyph: '圆',
    accent: Color(0xFFB83B28),
  );

  const StampId({
    required this.title,
    required this.subtitle,
    required this.requirement,
    required this.target,
    required this.glyph,
    required this.accent,
  });

  final String title;
  final String subtitle;
  final String requirement;
  final int target;
  final String glyph;
  final Color accent;
}

class ReadingStats {
  const ReadingStats({
    this.totalReadingSeconds = 0,
    this.todayReadingSeconds = 0,
    this.lastReadDate = '',
    this.streakDays = 0,
    this.bestStreakDays = 0,
    this.dailyGoalMinutes = 20,
    this.totalPagesTurned = 0,
    this.totalChaptersFinished = 0,
    this.totalCharsRead = 0,
    this.maxSessionSeconds = 0,
    this.finishedBookIds = const [],
    this.unlockedStamps = const {},
  });

  final int totalReadingSeconds;
  final int todayReadingSeconds;
  final String lastReadDate;
  final int streakDays;
  final int bestStreakDays;
  final int dailyGoalMinutes;
  final int totalPagesTurned;
  final int totalChaptersFinished;
  final int totalCharsRead;
  final int maxSessionSeconds;
  final List<String> finishedBookIds;

  /// StampId.name -> ISO-8601 unlock timestamp.
  final Map<String, String> unlockedStamps;

  int todaySecondsFor(String todayKey) =>
      lastReadDate == todayKey ? todayReadingSeconds : 0;

  double todayGoalProgress(String todayKey) {
    final target = (dailyGoalMinutes * 60).clamp(60, 24 * 3600);
    return (todaySecondsFor(todayKey) / target).clamp(0.0, 1.0);
  }

  bool isUnlocked(StampId id) => unlockedStamps.containsKey(id.name);

  int progressValueFor(StampId id) {
    switch (id) {
      case StampId.firstOpen:
        return isUnlocked(id) ? 1 : 0;
      case StampId.pages50:
        return totalPagesTurned;
      case StampId.session15m:
        return maxSessionSeconds;
      case StampId.streak3d:
        return bestStreakDays;
      case StampId.chapters10:
        return totalChaptersFinished;
      case StampId.chars5w:
        return totalCharsRead;
      case StampId.nightReader:
        return isUnlocked(id) ? 1 : 0;
      case StampId.bookFinished:
        return finishedBookIds.length;
    }
  }

  ReadingStats copyWith({
    int? totalReadingSeconds,
    int? todayReadingSeconds,
    String? lastReadDate,
    int? streakDays,
    int? bestStreakDays,
    int? dailyGoalMinutes,
    int? totalPagesTurned,
    int? totalChaptersFinished,
    int? totalCharsRead,
    int? maxSessionSeconds,
    List<String>? finishedBookIds,
    Map<String, String>? unlockedStamps,
  }) =>
      ReadingStats(
        totalReadingSeconds: totalReadingSeconds ?? this.totalReadingSeconds,
        todayReadingSeconds: todayReadingSeconds ?? this.todayReadingSeconds,
        lastReadDate: lastReadDate ?? this.lastReadDate,
        streakDays: streakDays ?? this.streakDays,
        bestStreakDays: bestStreakDays ?? this.bestStreakDays,
        dailyGoalMinutes: (dailyGoalMinutes ?? this.dailyGoalMinutes).clamp(5, 180),
        totalPagesTurned: totalPagesTurned ?? this.totalPagesTurned,
        totalChaptersFinished:
            totalChaptersFinished ?? this.totalChaptersFinished,
        totalCharsRead: totalCharsRead ?? this.totalCharsRead,
        maxSessionSeconds: maxSessionSeconds ?? this.maxSessionSeconds,
        finishedBookIds: finishedBookIds ?? this.finishedBookIds,
        unlockedStamps: unlockedStamps ?? this.unlockedStamps,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'version': 1,
        'totalReadingSeconds': totalReadingSeconds,
        'todayReadingSeconds': todayReadingSeconds,
        'lastReadDate': lastReadDate,
        'streakDays': streakDays,
        'bestStreakDays': bestStreakDays,
        'dailyGoalMinutes': dailyGoalMinutes,
        'totalPagesTurned': totalPagesTurned,
        'totalChaptersFinished': totalChaptersFinished,
        'totalCharsRead': totalCharsRead,
        'maxSessionSeconds': maxSessionSeconds,
        'finishedBookIds': finishedBookIds,
        'unlockedStamps': unlockedStamps,
      };

  factory ReadingStats.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const ReadingStats();
    final stamps = <String, String>{};
    final rawStamps = json['unlockedStamps'];
    if (rawStamps is Map) {
      for (final entry in rawStamps.entries) {
        if (entry.key is String && entry.value is String) {
          stamps[entry.key as String] = entry.value as String;
        }
      }
    }
    return ReadingStats(
      totalReadingSeconds:
          (json['totalReadingSeconds'] as num?)?.toInt() ?? 0,
      todayReadingSeconds:
          (json['todayReadingSeconds'] as num?)?.toInt() ?? 0,
      lastReadDate: json['lastReadDate'] as String? ?? '',
      streakDays: (json['streakDays'] as num?)?.toInt() ?? 0,
      bestStreakDays: (json['bestStreakDays'] as num?)?.toInt() ?? 0,
      dailyGoalMinutes:
          ((json['dailyGoalMinutes'] as num?)?.toInt() ?? 20).clamp(5, 180),
      totalPagesTurned: (json['totalPagesTurned'] as num?)?.toInt() ?? 0,
      totalChaptersFinished:
          (json['totalChaptersFinished'] as num?)?.toInt() ?? 0,
      totalCharsRead: (json['totalCharsRead'] as num?)?.toInt() ?? 0,
      maxSessionSeconds: (json['maxSessionSeconds'] as num?)?.toInt() ?? 0,
      finishedBookIds: [
        for (final id in (json['finishedBookIds'] as List? ?? const []))
          if (id is String && id.isNotEmpty) id,
      ],
      unlockedStamps: stamps,
    );
  }
}

/// A page bookmark clipped inside a book with a short excerpt.
class BookBookmark {
  const BookBookmark({
    required this.id,
    required this.chapterIndex,
    required this.charOffset,
    required this.chapterTitle,
    required this.excerpt,
    required this.createdAt,
  });

  final String id;
  final int chapterIndex;
  final int charOffset;
  final String chapterTitle;
  final String excerpt;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'chapterIndex': chapterIndex,
        'charOffset': charOffset,
        'chapterTitle': chapterTitle,
        'excerpt': excerpt,
        'createdAt': createdAt.toIso8601String(),
      };

  factory BookBookmark.fromJson(Map<String, dynamic> json) => BookBookmark(
        id: json['id'] as String? ?? '',
        chapterIndex: (json['chapterIndex'] as num?)?.toInt() ?? 0,
        charOffset: (json['charOffset'] as num?)?.toInt() ?? 0,
        chapterTitle: json['chapterTitle'] as String? ?? '',
        excerpt: json['excerpt'] as String? ?? '',
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
            DateTime.now(),
      );
}
