import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shijuan_reader/app.dart';
import 'package:shijuan_reader/core/responsive.dart';
import 'package:shijuan_reader/core/theme.dart';
import 'package:shijuan_reader/data/library_repository.dart';
import 'package:shijuan_reader/data/models/book.dart';
import 'package:shijuan_reader/data/models/chapter.dart';
import 'package:shijuan_reader/data/models/reader_settings.dart';
import 'package:shijuan_reader/data/settings_repository.dart';
import 'package:shijuan_reader/data/stats_repository.dart';
import 'package:shijuan_reader/features/bookshelf/journey_sheet.dart';
import 'package:shijuan_reader/features/reader/reader_controller.dart';
import 'package:shijuan_reader/features/reader/reader_page.dart';
import 'package:shijuan_reader/features/reader/reader_sheets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('AppAdaptive and ReaderSettings.pageLayout handle all screen sizes cleanly', () {
    final phone = AppAdaptive.fromSize(const Size(360, 780));
    expect(phone.sizeClass, AppSizeClass.compact);
    expect(phone.shelfGridColumns(328), 2);
    expect(phone.showSplitShelfHero, isFalse);
    expect(phone.useTwoColumnShelfList, isFalse);

    final portraitTablet = AppAdaptive.fromSize(const Size(800, 1280));
    expect(portraitTablet.sizeClass, AppSizeClass.medium);
    expect(portraitTablet.shelfGridColumns(748), 4);
    expect(portraitTablet.useTwoColumnShelfList, isTrue);
    expect(portraitTablet.showSplitShelfHero, isFalse);

    final landscapeTablet = AppAdaptive.fromSize(const Size(1280, 800));
    expect(landscapeTablet.sizeClass, AppSizeClass.expanded);
    expect(landscapeTablet.showSplitShelfHero, isTrue);
    expect(landscapeTablet.useTwoColumnShelfList, isTrue);
    expect(landscapeTablet.shelfGridColumns(1180), 6);

    const custom = ReaderSettings(pageLayout: ReaderPageLayout.doublePage);
    final decoded = ReaderSettings.fromJson(custom.toJson());
    expect(decoded.pageLayout, ReaderPageLayout.doublePage);

    final fallback = ReaderSettings.fromJson(const {'fontSize': 20});
    expect(fallback.pageLayout, ReaderPageLayout.auto);
  });

  testWidgets('ReaderController spread navigation handles even and odd chapters',
      (tester) async {
    final p1 = List.filled(24, '　　春水初生，春林初盛，微风轻拂纸页之间。').join('\n');
    final p2 = '\n${List.filled(6, '　　第二章尾声静谧落幕。').join('\n')}';
    final content = '$p1$p2';
    final chapters = [
      Chapter(title: '第一章 长歌', start: 0, end: p1.length),
      Chapter(title: '第二章 尾声', start: p1.length, end: content.length),
    ];
    final book = Book(
      id: 'spread_book',
      title: '双页测试',
      author: '作者',
      fileName: 'spread.txt',
      encoding: 'UTF-8',
      charCount: content.length,
      chapterCount: 2,
      fileSize: 1024,
      importedAt: DateTime(2026, 1, 1),
      lastOpenedAt: DateTime(2026, 1, 1),
      lastChapterTitle: '第一章 长歌',
      progress: const ReadingProgress(),
    );
    final controller = ReaderController(
      book: book,
      content: content,
      chapters: chapters,
      settings: const ReaderSettings(),
      onProgress: (_) {},
    );
    controller.ensureLayout(const Size(360, 460));
    final totalCh1Pages = controller.pages.length;
    expect(totalCh1Pages, greaterThanOrEqualTo(3));

    final initial = controller.spreadSnapshot(spread: true)!;
    expect(initial.left.pageIndex, 0);
    expect(initial.right?.pageIndex, 1);
    expect(controller.pageIndicatorFor(spread: true), '1-2 / $totalCh1Pages');

    expect(controller.turnPage(1, spread: true), isTrue);
    expect(controller.pageIndex, 2);

    final peekPrev = controller.peekSpread(-1, spread: true)!;
    expect(peekPrev.left.pageIndex, 0);
    expect(peekPrev.right?.pageIndex, 1);

    controller.dispose();
  });

  testWidgets(
      'Bookshelf adapts smoothly across narrow phone and landscape tablet hero/dialog',
      (tester) async {
    late final Directory root;
    late final Directory srcDir;
    late final LibraryRepository library;
    late final SettingsRepository settings;
    late final StatsRepository stats;
    await tester.runAsync(() async {
      root = Directory.systemTemp.createTempSync('shijuan_adapt_shelf_');
      srcDir = Directory.systemTemp.createTempSync('shijuan_adapt_src_');
      library = LibraryRepository(root: root, parseInIsolate: false);
      settings = SettingsRepository(root: root);
      stats = StatsRepository(root: root);
      await library.init();
      await settings.init();
      await stats.init();

      final b1 = File(p.join(srcDir.path, '青山集.txt'))
        ..writeAsStringSync('第一章 初见\n　　青山隐隐，长风万里。\n');
      final b2 = File(p.join(srcDir.path, '沧海录.txt'))
        ..writeAsStringSync('第一章 渡海\n　　沧海横流，星汉灿烂。\n');
      final sum = await library.importPaths([b1.path, b2.path]);
      library.saveProgress(
        sum.added.first.id,
        chapterIndex: 0,
        charOffset: 6,
        percent: 0.35,
        chapterTitle: '第一章 初见',
      );
      stats.recordBookOpened();
      stats.recordReadingSeconds(240, sessionSeconds: 240, isNightTheme: false);
      await library.flush();
    });
    addTearDown(() {
      library.dispose();
      settings.dispose();
      stats.dispose();
      if (root.existsSync()) root.deleteSync(recursive: true);
      if (srcDir.existsSync()) srcDir.deleteSync(recursive: true);
    });

    // 1. Tight phone viewport (360x780): bottom sheet presentation.
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ShijuanApp(library: library, settings: settings, stats: stats),
    );
    await tester.pumpAndSettle();

    expect(find.text('案头续读'), findsOneWidget);
    expect(find.text('印章 1/8'), findsOneWidget);

    await tester.tap(find.text('印章 1/8'));
    await tester.pumpAndSettle();
    final phoneSheet =
        tester.widget<ReadingJourneySheet>(find.byType(ReadingJourneySheet));
    expect(phoneSheet.asDialog, isFalse);
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();

    // 2. Landscape tablet viewport (1280x800): split hero, 2-col list & centered two-pane dialog.
    tester.view.physicalSize = const Size(1280, 800);
    await tester.pumpAndSettle();

    expect(find.text('拾卷印记'), findsOneWidget);
    await tester.tap(find.byTooltip('切换为书目列表'));
    await tester.pumpAndSettle();
    expect(find.text('青山集'), findsWidgets);
    expect(find.text('沧海录'), findsWidgets);

    await tester.tap(find.text('拾卷印记'));
    await tester.pumpAndSettle();
    final tabletDialog =
        tester.widget<ReadingJourneySheet>(find.byType(ReadingJourneySheet));
    expect(tabletDialog.asDialog, isTrue);
    expect(find.text('朱砂印章墙'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'Reader adapts between phone single-page + bottom sheet and tablet two-page spread + side drawer',
      (tester) async {
    late final Directory root;
    late final Directory srcDir;
    late final LibraryRepository library;
    late final SettingsRepository settings;
    late final Book book;
    await tester.runAsync(() async {
      root = Directory.systemTemp.createTempSync('shijuan_adapt_reader_');
      srcDir = Directory.systemTemp.createTempSync('shijuan_adapt_rsrc_');
      library = LibraryRepository(root: root, parseInIsolate: false);
      settings = SettingsRepository(root: root);
      await library.init();
      await settings.init();

      final paragraphs = List.generate(
        44,
        (i) => '　　第${i + 1}段：松风吹解带，山月照弹琴。静心读罢这一行文字，书页间的墨香与灯光渐渐融在一起。',
      ).join('\n');
      final file = File(p.join(srcDir.path, '松风集.txt'))
        ..writeAsStringSync('第一章 听松\n$paragraphs\n\n第二章 观月\n　　月涌大江流。\n');
      final sum = await library.importPaths([file.path]);
      book = sum.added.single;
    });
    addTearDown(() {
      library.dispose();
      settings.dispose();
      if (root.existsSync()) root.deleteSync(recursive: true);
      if (srcDir.existsSync()) srcDir.deleteSync(recursive: true);
    });

    // Start in phone portrait (390x844): single column + bottom TOC sheet.
    tester.view.physicalSize = const Size(390, 844);
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
        ),
      ),
    );
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 30));
      if (find.text('第一章 听松').evaluate().isNotEmpty &&
          find.byType(CircularProgressIndicator).evaluate().isEmpty) {
        break;
      }
    }

    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Text &&
            w.data != null &&
            RegExp(r'^1 / [2-9]\d*$').hasMatch(w.data!),
      ),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await tester.pumpAndSettle();
    expect(
      tester.widget<ReaderTocSheet>(find.byType(ReaderTocSheet)).asSideDrawer,
      isFalse,
    );
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();

    // Rotate / expand to tablet landscape (1280x800): automatic two-page spread + side drawer TOC + centered dialog settings!
    tester.view.physicalSize = const Size(1280, 800);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    expect(find.textContaining('1-2 / '), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.textContaining('3-'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await tester.pumpAndSettle();
    expect(
      tester.widget<ReaderTocSheet>(find.byType(ReaderTocSheet)).asSideDrawer,
      isTrue,
    );
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ReaderSettingsSheet>(find.byType(ReaderSettingsSheet))
          .asDialog,
      isTrue,
    );
    // Switch explicitly from auto to single page mode on tablet.
    await tester.tap(find.text('单页'));
    await tester.pumpAndSettle();
    expect(settings.settings.reader.pageLayout, ReaderPageLayout.single);
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 60));

    // Now renders a single page indicator instead of paired spread.
    expect(find.textContaining('1-2 / '), findsNothing);

    // Portrait tablet (800x1280): single reading page in auto mode, side-drawer TOC.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.pumpAndSettle();
    await tester.tap(find.text('自动'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    tester.view.physicalSize = const Size(800, 1280);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.textContaining('1-2 / '), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await tester.pumpAndSettle();
    expect(
      tester.widget<ReaderTocSheet>(find.byType(ReaderTocSheet)).asSideDrawer,
      isTrue,
    );
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();

    // Short landscape phone (800x390): no RenderFlex overflows in chrome or sheets.
    tester.view.physicalSize = const Size(800, 390);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.pumpAndSettle();
    expect(find.text('排版工坊'), findsOneWidget);
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
