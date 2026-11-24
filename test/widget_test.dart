import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shijuan_reader/app.dart';
import 'package:shijuan_reader/core/theme.dart';
import 'package:shijuan_reader/data/library_repository.dart';
import 'package:shijuan_reader/data/settings_repository.dart';
import 'package:shijuan_reader/features/reader/reader_page.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(LibraryRepository, SettingsRepository, Directory)> createRepos(
    WidgetTester tester,
  ) async {
    final result = await tester.runAsync(() async {
      final root = Directory.systemTemp.createTempSync('modu_widget_');
      final library = LibraryRepository(root: root, parseInIsolate: false);
      final settings = SettingsRepository(root: root);
      await library.init();
      await settings.init();
      return (library, settings, root);
    });
    return result!;
  }

  void configureView(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('empty bookshelf offers the import action', (tester) async {
    final (library, settings, root) = await createRepos(tester);
    addTearDown(() {
      library.dispose();
      settings.dispose();
      if (root.existsSync()) root.deleteSync(recursive: true);
    });
    configureView(tester);

    await tester.pumpWidget(ShijuanApp(library: library, settings: settings));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    expect(find.text('书架'), findsOneWidget);
    expect(find.text('书架还是空的'), findsOneWidget);
    expect(find.text('选择 TXT 文件'), findsOneWidget);
    expect(find.text('导入 TXT'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('bookshelf explains a repaired library', (tester) async {
    final (library, settings, root) = await createRepos(tester);
    final sourceDir = Directory.systemTemp.createTempSync('modu_source_');
    addTearDown(() {
      library.dispose();
      settings.dispose();
      if (root.existsSync()) root.deleteSync(recursive: true);
      if (sourceDir.existsSync()) sourceDir.deleteSync(recursive: true);
    });
    configureView(tester);

    final source = File(p.join(sourceDir.path, '测试小说.txt'));
    source.writeAsStringSync('第一章 起点\n　　这是第一段。\n');
    await tester.runAsync(() => library.importPaths([source.path]));

    // What an older build left behind when it could not read its index: an
    // empty shelf, with the book itself still on disk.
    late LibraryRepository repaired;
    await tester.runAsync(() async {
      File(p.join(root.path, 'library.json'))
          .writeAsStringSync('{"version": 1, "books": []}');
      final backup = File(p.join(root.path, 'library.json.bak'));
      if (backup.existsSync()) backup.deleteSync();
      repaired = LibraryRepository(root: root, parseInIsolate: false);
      await repaired.init();
    });
    addTearDown(repaired.dispose);

    await tester.pumpWidget(ShijuanApp(library: repaired, settings: settings));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    // The book is back, and the shelf says where it came from.
    expect(find.text('测试小说'), findsWidgets);
    expect(find.text('找回了 1 本未登记的书'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('reader opens a book and turns to the next chapter', (tester) async {
    final (library, settings, root) = await createRepos(tester);
    final sourceDir = Directory.systemTemp.createTempSync('modu_source_');
    addTearDown(() {
      library.dispose();
      settings.dispose();
      if (root.existsSync()) root.deleteSync(recursive: true);
      if (sourceDir.existsSync()) sourceDir.deleteSync(recursive: true);
    });
    configureView(tester);

    final source = File(p.join(sourceDir.path, '测试小说.txt'));
    source.writeAsStringSync(
      '第一章 起点\n'
      '　　夜色清净，故事从这里开始。\n\n'
      '第二章 转折\n'
      '　　第二天清晨，风停了。\n',
    );
    final summary = await tester.runAsync(
      () => library.importPaths([source.path]),
    );
    expect(summary!.failures, isEmpty);
    final book = summary.added.single;

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

    // Let the chapter text load from disk and the first layout settle. Avoid
    // pumpAndSettle here: while loading, the spinner animates forever and the
    // settle helper would run until its timeout.
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      });
      await tester.pump(const Duration(milliseconds: 30));
      if (find.text('第一章 起点').evaluate().isNotEmpty) break;
    }

    expect(find.text('测试小说'), findsWidgets);
    expect(find.text('第一章 起点'), findsWidgets);

    // Tapping the right side turns the page; chapter one is a single page.
    await tester.tapAt(const Offset(1080, 420));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('第二章 转折'), findsWidgets);

    // Keyboard paging and the chrome shortcut.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('第一章 起点'), findsWidgets);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('目录'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
