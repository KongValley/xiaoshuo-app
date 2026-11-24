import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shijuan_reader/app.dart';
import 'package:shijuan_reader/core/brand_logo.dart';
import 'package:shijuan_reader/core/theme.dart';
import 'package:shijuan_reader/data/library_repository.dart';
import 'package:shijuan_reader/data/models/book.dart';
import 'package:shijuan_reader/data/models/chapter.dart';
import 'package:shijuan_reader/data/models/reader_settings.dart';
import 'package:shijuan_reader/data/settings_repository.dart';
import 'package:shijuan_reader/features/import/file_browser_page.dart';
import 'package:shijuan_reader/features/reader/reader_controller.dart';
import 'package:shijuan_reader/features/reader/reader_page.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(LibraryRepository, SettingsRepository, Directory)> createRepos(
    WidgetTester tester,
  ) async {
    final result = await tester.runAsync(() async {
      final root = Directory.systemTemp.createTempSync('modu_redesign_');
      final library = LibraryRepository(root: root, parseInIsolate: false);
      final settings = SettingsRepository(root: root);
      await library.init();
      await settings.init();
      return (library, settings, root);
    });
    return result!;
  }

  void configureView(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  test('ReaderSettings and AppSettings persist redesigned fields safely', () async {
    final root = Directory.systemTemp.createTempSync('modu_settings_test_');
    addTearDown(() => root.deleteSync(recursive: true));

    final repo = SettingsRepository(root: root);
    await repo.init();
    repo.updateThemePreference(AppThemePreference.dark);
    repo.updateShelfView(ShelfViewMode.list);
    repo.updateReader(
      const ReaderSettings(
        fontSize: 22,
        lineHeight: 2.0,
        font: ReaderFontId.song,
        theme: ReaderThemeId.green,
        pageTurn: PageTurnMode.slide,
        margin: ReaderMarginLevel.relaxed,
      ),
    );
    await repo.flush();
    repo.dispose();

    final reloaded = SettingsRepository(root: root);
    await reloaded.init();
    expect(reloaded.settings.themePreference, AppThemePreference.dark);
    expect(reloaded.settings.shelfView, ShelfViewMode.list);
    expect(reloaded.settings.reader.pageTurn, PageTurnMode.slide);
    expect(reloaded.settings.reader.margin, ReaderMarginLevel.relaxed);
    expect(reloaded.settings.reader.font, ReaderFontId.song);
    reloaded.dispose();

    // Legacy JSON without new keys falls back cleanly.
    final legacy = ReaderSettings.fromJson(const {
      'fontSize': 18,
      'lineHeight': 1.7,
      'font': 'hei',
      'theme': 'night',
    });
    expect(legacy.pageTurn, PageTurnMode.cover);
    expect(legacy.margin, ReaderMarginLevel.standard);
  });

  testWidgets('ReaderController.peekPage previews adjacent pages without mutating state',
      (tester) async {
    const first = '　　第一章第一页的文本内容。\n';
    const second = '　　第二章第一页的文本内容。\n';
    final content = first + second;
    final chapters = [
      Chapter(title: '第一章 起点', start: 0, end: first.length),
      Chapter(title: '第二章 远方', start: first.length, end: content.length),
    ];
    final book = Book(
      id: 'b1',
      title: '测试书',
      author: '作者',
      fileName: 'test.txt',
      encoding: 'UTF-8',
      charCount: content.length,
      chapterCount: 2,
      fileSize: 100,
      importedAt: DateTime(2026, 1, 1),
      lastOpenedAt: DateTime(2026, 1, 1),
      lastChapterTitle: '第一章 起点',
      progress: const ReadingProgress(),
    );
    final controller = ReaderController(
      book: book,
      content: content,
      chapters: chapters,
      settings: const ReaderSettings(),
      onProgress: (_) {},
    );
    controller.ensureLayout(const Size(360, 520));

    expect(controller.peekPage(-1), isNull);
    final next = controller.peekPage(1);
    expect(next, isNotNull);
    expect(next!.chapterIndex, 1);
    expect(next.chapterTitle, '第二章 远方');
    // Still on chapter 0!
    expect(controller.chapterIndex, 0);

    controller.dispose();
  });

  testWidgets('Bookshelf search, view toggle, spotlight, theme switch, and mobile responsiveness',
      (tester) async {
    final (library, settings, root) = await createRepos(tester);
    final sourceDir = Directory.systemTemp.createTempSync('modu_src_');
    addTearDown(() {
      library.dispose();
      settings.dispose();
      if (root.existsSync()) root.deleteSync(recursive: true);
      if (sourceDir.existsSync()) sourceDir.deleteSync(recursive: true);
    });

    final f1 = File(p.join(sourceDir.path, '山河志.txt'))
      ..writeAsStringSync('第一章 初入江湖\n　　风起青萍之末。\n\n第二章 风雪夜\n　　大雪封山。\n');
    final f2 = File(p.join(sourceDir.path, '星海游记.txt'))
      ..writeAsStringSync('第一章 启航\n　　群星闪耀。\n');

    await tester.runAsync(() async {
      final sum = await library.importPaths([f1.path, f2.path]);
      final first = sum.added.first;
      library.saveProgress(
        first.id,
        chapterIndex: 1,
        charOffset: 10,
        percent: 0.45,
        chapterTitle: '第二章 风雪夜',
      );
      await library.flush();
    });

    // Test on narrow mobile viewport (390x844) first for zero overflow.
    configureView(tester, const Size(390, 844));
    await tester.pumpWidget(ShijuanApp(library: library, settings: settings));
    await tester.pump(const Duration(milliseconds: 120));

    expect(find.byType(ShijuanLogo), findsWidgets);
    expect(find.text('案头续读'), findsOneWidget);
    expect(find.text('山河志'), findsWidgets);
    expect(find.text('星海游记'), findsWidgets);

    // Search bookshelf.
    await tester.tap(find.byTooltip('搜索书架'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '星海');
    await tester.pumpAndSettle();
    expect(find.text('星海游记'), findsWidgets);
    expect(find.text('山河志'), findsNothing);

    // Clear search and toggle to list view.
    await tester.tap(find.byTooltip('收起搜索'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('切换为书目列表'));
    await tester.pumpAndSettle();
    expect(settings.settings.shelfView, ShelfViewMode.list);

    // Cycle app theme preference.
    await tester.tap(find.byTooltip('外观：跟随系统（点击切换）'));
    await tester.pumpAndSettle();
    expect(settings.settings.themePreference, AppThemePreference.light);

    // Open About dialog by tapping the brand logo.
    await tester.tap(find.byTooltip('关于拾卷'));
    await tester.pumpAndSettle();
    expect(find.text('拾卷 · ShiJuan Reader'), findsOneWidget);
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Reader interactive drag paging, chrome tap-guard, undo jump, TOC reverse, and settings workshop',
      (tester) async {
    final (library, settings, root) = await createRepos(tester);
    final sourceDir = Directory.systemTemp.createTempSync('modu_reader_src_');
    addTearDown(() {
      library.dispose();
      settings.dispose();
      if (root.existsSync()) root.deleteSync(recursive: true);
      if (sourceDir.existsSync()) sourceDir.deleteSync(recursive: true);
    });
    configureView(tester, const Size(1180, 820));

    final source = File(p.join(sourceDir.path, '长夜行.txt'))
      ..writeAsStringSync(
        '第一章 启程\n　　天光微亮，行囊已备。\n\n'
        '第二章 驿站\n　　暮色四合，马蹄声碎。\n\n'
        '第三章 归途\n　　雪落无声，灯火如初。\n',
      );
    final summary =
        await tester.runAsync(() => library.importPaths([source.path]));
    final book = summary!.added.single;

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

    for (var i = 0; i < 30; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 30));
      if (find.text('第一章 启程').evaluate().isNotEmpty) break;
    }

    // Horizontal drag left advances to chapter 2.
    await tester.drag(find.byType(GestureDetector).first, const Offset(-260, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    expect(find.text('第二章 驿站'), findsWidgets);

    // Open chrome via M key; tapping left side dismisses chrome WITHOUT turning page!
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.pumpAndSettle();
    expect(find.text('排版'), findsOneWidget);

    await tester.tapAt(const Offset(120, 400));
    await tester.pumpAndSettle();
    // Still on chapter 2!
    expect(find.text('第二章 驿站'), findsWidgets);

    // Open TOC, reverse order, and jump to chapter 3.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await tester.pumpAndSettle();
    expect(find.text('共 3 章'), findsOneWidget);
    await tester.tap(find.byTooltip('切换为倒序'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('第三章 归途').last);
    await tester.pumpAndSettle();
    expect(find.text('第三章 归途'), findsWidgets);

    // Open chrome and use Undo Jump ('回到原位') back to chapter 2.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.pumpAndSettle();
    expect(find.text('回到原位'), findsOneWidget);
    await tester.tap(find.text('回到原位'));
    await tester.pumpAndSettle();
    expect(find.text('第二章 驿站'), findsWidgets);

    // Open Settings Workshop ('排版工坊') and test page-turn mode & margin switches.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.pumpAndSettle();
    expect(find.text('排版工坊'), findsOneWidget);
    await tester.tap(find.text('淡入'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('舒展'));
    await tester.pumpAndSettle();
    expect(settings.settings.reader.pageTurn, PageTurnMode.fade);
    expect(settings.settings.reader.margin, ReaderMarginLevel.relaxed);

    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('FileBrowserPage renders breadcrumbs, filters files, and supports select-all',
      (tester) async {
    final tempDir = Directory.systemTemp.createTempSync('modu_browser_');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    File(p.join(tempDir.path, 'alpha.txt')).writeAsStringSync('a');
    File(p.join(tempDir.path, 'beta.txt')).writeAsStringSync('b');

    configureView(tester, const Size(980, 700));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: FileBrowserPage(initialDirectory: tempDir.path),
      ),
    );
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 30));
      if (find.text('alpha.txt').evaluate().isNotEmpty) break;
    }

    expect(find.text('导入本地小说'), findsOneWidget);
    expect(find.text('alpha.txt'), findsOneWidget);
    expect(find.text('beta.txt'), findsOneWidget);

    await tester.tap(find.text('全选本页 (2)'));
    await tester.pumpAndSettle();
    expect(find.text('导入 2 个'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
