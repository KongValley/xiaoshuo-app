import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shijuan_reader/app.dart';
import 'package:shijuan_reader/core/theme.dart';
import 'package:shijuan_reader/data/library_repository.dart';
import 'package:shijuan_reader/data/models/reading_stats.dart';
import 'package:shijuan_reader/data/settings_repository.dart';
import 'package:shijuan_reader/data/stats_repository.dart';
import 'package:shijuan_reader/features/reader/reader_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('StatsRepository tracks streaks, milestones, and chop-seal unlocks', () async {
    final root = Directory.systemTemp.createTempSync('shijuan_stats_');
    addTearDown(() => root.deleteSync(recursive: true));

    final repo = StatsRepository(root: root);
    await repo.init();

    final d1 = DateTime(2026, 11, 20, 9);
    final d2 = DateTime(2026, 11, 21, 9);
    final d3 = DateTime(2026, 11, 22, 9);

    expect(repo.recordBookOpened(now: d1), [StampId.firstOpen]);
    expect(repo.stats.streakDays, 1);

    // Day 2 & Day 3 roll streak to 3 and unlock streak3d.
    repo.recordPageTurn(charsOnPage: 300, isNightTheme: false, now: d2);
    expect(repo.stats.streakDays, 2);
    final d3Stamps =
        repo.recordPageTurn(charsOnPage: 300, isNightTheme: true, now: d3);
    expect(d3Stamps, containsAll([StampId.nightReader, StampId.streak3d]));
    expect(repo.stats.streakDays, 3);
    expect(repo.stats.bestStreakDays, 3);

    // Turning 48 more pages reaches 50 and unlocks pages50.
    List<StampId> last = const [];
    for (var i = 0; i < 48; i++) {
      last = repo.recordPageTurn(
        charsOnPage: 1200,
        isNightTheme: false,
        now: d3,
      );
    }
    expect(last, contains(StampId.pages50));
    expect(repo.stats.isUnlocked(StampId.chars5w), isTrue);

    // Finishing 10 chapters unlocks chapters10.
    for (var i = 0; i < 9; i++) {
      expect(repo.recordChapterFinished(now: d3), isEmpty);
    }
    expect(repo.recordChapterFinished(now: d3), [StampId.chapters10]);

    // Session >= 15m unlocks session15m.
    expect(
      repo.recordReadingSeconds(60, sessionSeconds: 15 * 60, isNightTheme: false, now: d3),
      [StampId.session15m],
    );

    // Book finished unlocks bookFinished.
    expect(repo.recordBookFinished('book_1', now: d3), [StampId.bookFinished]);

    await repo.flush();
    repo.dispose();

    final reloaded = StatsRepository(root: root);
    await reloaded.init();
    expect(reloaded.stats.unlockedStamps.length, StampId.values.length);
    expect(reloaded.stats.finishedBookIds, ['book_1']);
    reloaded.dispose();
  });

  testWidgets('Bookshelf displays Reading Journey strip and interactive chop-seal gallery',
      (tester) async {
    late final Directory root;
    late final LibraryRepository library;
    late final SettingsRepository settings;
    late final StatsRepository stats;
    await tester.runAsync(() async {
      root = Directory.systemTemp.createTempSync('shijuan_journey_ui_');
      library = LibraryRepository(root: root, parseInIsolate: false);
      settings = SettingsRepository(root: root);
      stats = StatsRepository(root: root);
      await library.init();
      await settings.init();
      await stats.init();
      stats.recordBookOpened();
      stats.recordReadingSeconds(
        300,
        sessionSeconds: 300,
        isNightTheme: false,
      );
    });
    addTearDown(() {
      library.dispose();
      settings.dispose();
      stats.dispose();
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    tester.view.physicalSize = const Size(420, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ShijuanApp(library: library, settings: settings, stats: stats),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('今日已读 5 / 20 分钟'), findsOneWidget);
    expect(find.text('印章 1/8'), findsOneWidget);

    await tester.tap(find.text('印章 1/8'));
    await tester.pumpAndSettle();
    expect(find.text('拾卷印记'), findsOneWidget);
    expect(find.text('朱砂印章墙'), findsOneWidget);

    await tester.tap(find.text('渐入佳境').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('累计翻阅 50 页正文'), findsOneWidget);

    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Reader supports silk ribbon bookmarking, bookmark TOC jump, and completion celebration',
      (tester) async {
    late final Directory root;
    late final Directory sourceDir;
    late final LibraryRepository library;
    late final SettingsRepository settings;
    late final StatsRepository stats;
    late final dynamic book;
    await tester.runAsync(() async {
      root = Directory.systemTemp.createTempSync('shijuan_reader_fun_');
      sourceDir = Directory.systemTemp.createTempSync('shijuan_fun_src_');
      library = LibraryRepository(root: root, parseInIsolate: false);
      settings = SettingsRepository(root: root);
      stats = StatsRepository(root: root);
      final source = File(p.join(sourceDir.path, '画卷记.txt'))
        ..writeAsStringSync(
          '第一章 春山\n　　春山如笑，微风拂过书页。\n\n'
          '第二章 秋水\n　　秋水长天，故事至此圆满落幕。\n',
        );
      await library.init();
      await settings.init();
      await stats.init();
      final sum = await library.importPaths([source.path]);
      book = sum.added.single;
    });
    addTearDown(() {
      library.dispose();
      settings.dispose();
      stats.dispose();
      if (root.existsSync()) root.deleteSync(recursive: true);
      if (sourceDir.existsSync()) sourceDir.deleteSync(recursive: true);
    });

    tester.view.physicalSize = const Size(1100, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: ReaderPage(
          book: book,
          library: library,
          settingsRepo: settings,
          statsRepo: stats,
        ),
      ),
    );
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 30));
      if (find.text('第一章 春山').evaluate().isNotEmpty) break;
    }

    // Clip a bookmark on chapter 1 using keyboard B (or ribbon tap).
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('取消本页书签'), findsOneWidget);

    // Turn to chapter 2.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('第二章 秋水'), findsWidgets);

    // Open TOC and switch to Bookmarks tab, then jump back to Chapter 1!
    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await tester.pumpAndSettle();
    await tester.tap(find.text('书签 (1)'));
    await tester.pumpAndSettle();
    expect(find.text('第一章 春山'), findsWidgets);
    await tester.tap(find.text('第一章 春山').last);
    await tester.pumpAndSettle();
    expect(find.text('第一章 春山'), findsWidgets);

    // Go to final chapter and turn past the last page to trigger BookCompletionDialog!
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();

    expect(find.text('合卷回书架'), findsOneWidget);
    expect(stats.stats.isUnlocked(StampId.bookFinished), isTrue);

    await tester.tap(find.text('留在末页'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
