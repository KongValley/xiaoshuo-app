import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shijuan_reader/core/app_dirs.dart';
import 'package:shijuan_reader/core/app_errors.dart';
import 'package:path/path.dart' as p;

void main() {
  test('uses the first directory it is allowed to create', () async {
    final root = Directory.systemTemp.createTempSync('shijuan_dirs_');
    addTearDown(() => root.deleteSync(recursive: true));

    // A file cannot be used as a parent folder, so this candidate always
    // fails, like the data folder of another Android user profile.
    final blocker = File(p.join(root.path, 'blocker'))..writeAsStringSync('');
    final own = p.join(root.path, 'profile-10', 'files');

    final dir = await AppDirs.firstWritable(['  ', '${blocker.path}${p.separator}files', own]);

    expect(dir.path, own);
    expect(dir.existsSync(), isTrue);
  });

  test('falls back to the temporary folder when nothing can be created', () async {
    final dir = await AppDirs.firstWritable(const []);
    expect(dir.path, p.join(Directory.systemTemp.path, 'ShijuanReader'));
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  testWidgets('explains a failed start instead of showing an empty window', (
    tester,
  ) async {
    await tester.pumpWidget(
      StartupErrorApp(error: StateError('磁盘已满')),
    );
    await tester.pump();

    expect(find.text('书库无法打开'), findsOneWidget);
    expect(find.textContaining('磁盘已满'), findsOneWidget);
    expect(find.text('错误信息'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('error pane names the exception', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ErrorPane(detail: 'Bad state: 坏了')),
      ),
    );
    await tester.pump();

    expect(find.text('这里出了点问题'), findsOneWidget);
    expect(find.text('Bad state: 坏了'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
