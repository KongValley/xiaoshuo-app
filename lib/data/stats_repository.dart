import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'models/reading_stats.dart';

/// Persists offline reading milestones, daily streaks, and chop-seal badges
/// in `<dataDir>/reading_stats.json`.
class StatsRepository extends ChangeNotifier {
  StatsRepository({required Directory root})
      : _file = File(p.join(root.path, 'reading_stats.json'));

  final File _file;
  ReadingStats _stats = const ReadingStats();
  Timer? _saveTimer;
  bool _loaded = false;

  ReadingStats get stats => _stats;

  static String dateKey(DateTime time) {
    final local = time.toLocal();
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '${local.year}-$m-$d';
  }

  int get todayReadingSeconds => _stats.todaySecondsFor(dateKey(DateTime.now()));

  double get todayGoalProgress =>
      _stats.todayGoalProgress(dateKey(DateTime.now()));

  Future<void> init() async {
    try {
      if (await _file.exists()) {
        final raw = await _file.readAsString(encoding: utf8);
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          _stats = ReadingStats.fromJson(decoded.cast<String, dynamic>());
        }
      }
    } catch (_) {
      _stats = const ReadingStats();
    }
    _loaded = true;
  }

  List<StampId> recordBookOpened({DateTime? now}) {
    final stampTime = now ?? DateTime.now();
    _syncDateRoll(stampTime);
    final unlocked = _unlock(StampId.firstOpen, stampTime);
    _checkStreakUnlock(stampTime, unlocked);
    notifyListeners();
    _scheduleSave();
    return unlocked;
  }

  List<StampId> recordPageTurn({
    required int charsOnPage,
    required bool isNightTheme,
    int pageCount = 1,
    DateTime? now,
  }) {
    final stampTime = now ?? DateTime.now();
    _syncDateRoll(stampTime);
    _stats = _stats.copyWith(
      totalPagesTurned: _stats.totalPagesTurned + math.max(1, pageCount),
      totalCharsRead: _stats.totalCharsRead + math.max(0, charsOnPage),
    );
    final unlocked = <StampId>[];
    if (_stats.totalPagesTurned >= StampId.pages50.target) {
      unlocked.addAll(_unlock(StampId.pages50, stampTime));
    }
    if (_stats.totalCharsRead >= StampId.chars5w.target) {
      unlocked.addAll(_unlock(StampId.chars5w, stampTime));
    }
    if (isNightTheme) {
      unlocked.addAll(_unlock(StampId.nightReader, stampTime));
    }
    _checkStreakUnlock(stampTime, unlocked);
    notifyListeners();
    _scheduleSave();
    return unlocked;
  }

  List<StampId> recordChapterFinished({DateTime? now}) {
    final stampTime = now ?? DateTime.now();
    _syncDateRoll(stampTime);
    _stats = _stats.copyWith(
      totalChaptersFinished: _stats.totalChaptersFinished + 1,
    );
    final unlocked = <StampId>[];
    if (_stats.totalChaptersFinished >= StampId.chapters10.target) {
      unlocked.addAll(_unlock(StampId.chapters10, stampTime));
    }
    notifyListeners();
    _scheduleSave();
    return unlocked;
  }

  List<StampId> recordReadingSeconds(
    int seconds, {
    required int sessionSeconds,
    required bool isNightTheme,
    DateTime? now,
  }) {
    if (seconds <= 0 && sessionSeconds <= 0) return const [];
    final stampTime = now ?? DateTime.now();
    _syncDateRoll(stampTime);
    _stats = _stats.copyWith(
      totalReadingSeconds: _stats.totalReadingSeconds + math.max(0, seconds),
      todayReadingSeconds: _stats.todayReadingSeconds + math.max(0, seconds),
      maxSessionSeconds: math.max(_stats.maxSessionSeconds, sessionSeconds),
    );
    final unlocked = <StampId>[];
    if (_stats.maxSessionSeconds >= StampId.session15m.target) {
      unlocked.addAll(_unlock(StampId.session15m, stampTime));
    }
    if (isNightTheme) {
      unlocked.addAll(_unlock(StampId.nightReader, stampTime));
    }
    _checkStreakUnlock(stampTime, unlocked);
    notifyListeners();
    _scheduleSave();
    return unlocked;
  }

  List<StampId> recordBookFinished(String bookId, {DateTime? now}) {
    final stampTime = now ?? DateTime.now();
    _syncDateRoll(stampTime);
    final finished = List<String>.from(_stats.finishedBookIds);
    if (!finished.contains(bookId)) {
      finished.add(bookId);
    }
    _stats = _stats.copyWith(finishedBookIds: finished);
    final unlocked = _unlock(StampId.bookFinished, stampTime);
    notifyListeners();
    _scheduleSave();
    return unlocked;
  }

  void updateDailyGoalMinutes(int minutes) {
    _stats = _stats.copyWith(dailyGoalMinutes: minutes);
    notifyListeners();
    _scheduleSave();
  }

  void _syncDateRoll(DateTime now) {
    final today = dateKey(now);
    if (_stats.lastReadDate == today) return;
    int nextStreak = 1;
    if (_stats.lastReadDate.isNotEmpty) {
      final prev = DateTime.tryParse(_stats.lastReadDate);
      if (prev != null) {
        final todayDate = DateTime(now.year, now.month, now.day);
        final prevDate = DateTime(prev.year, prev.month, prev.day);
        final diff = todayDate.difference(prevDate).inDays;
        if (diff == 1) {
          nextStreak = _stats.streakDays + 1;
        } else if (diff == 0) {
          nextStreak = math.max(1, _stats.streakDays);
        }
      }
    }
    _stats = _stats.copyWith(
      lastReadDate: today,
      todayReadingSeconds: 0,
      streakDays: nextStreak,
      bestStreakDays: math.max(_stats.bestStreakDays, nextStreak),
    );
  }

  void _checkStreakUnlock(DateTime now, List<StampId> unlocked) {
    if (_stats.bestStreakDays >= StampId.streak3d.target) {
      unlocked.addAll(_unlock(StampId.streak3d, now));
    }
  }

  List<StampId> _unlock(StampId id, DateTime now) {
    if (_stats.isUnlocked(id)) return const [];
    final map = Map<String, String>.from(_stats.unlockedStamps);
    map[id.name] = now.toIso8601String();
    _stats = _stats.copyWith(unlockedStamps: map);
    return [id];
  }

  void _scheduleSave() {
    if (!_loaded) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 350), flush);
  }

  Future<void> flush() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    try {
      await _file.parent.create(recursive: true);
      await _file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(_stats.toJson()),
        flush: true,
      );
    } catch (_) {
      // Keep in-memory stats usable if disk fails.
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }
}
