import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'core/app_dirs.dart';
import 'core/app_errors.dart';
import 'data/library_repository.dart';
import 'data/native_paths.dart';
import 'data/settings_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // An exception thrown from a callback or a future must not take the whole
  // app down with it. Log it and carry on; in release builds a widget that
  // fails to build shows a short explanation instead of a blank rectangle.
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    debugPrint('[墨读] 未捕获的异常: $error\n$stackTrace');
    return true;
  };
  if (kReleaseMode) {
    ErrorWidget.builder = (details) =>
        ErrorPane(detail: details.exceptionAsString());
  }

  try {
    final androidFilesDir =
        Platform.isAndroid ? await NativePaths.filesDir() : null;
    final dataRoot = await AppDirs.dataDir(androidFilesDir: androidFilesDir);
    final library = LibraryRepository(root: dataRoot);
    final settings = SettingsRepository(root: dataRoot);

    await Future.wait([library.init(), settings.init()]);

    runApp(ModuApp(library: library, settings: settings));
  } catch (error, stackTrace) {
    // Without this a failed start would be a blank window and nothing else.
    debugPrint('[墨读] 启动失败: $error\n$stackTrace');
    runApp(StartupErrorApp(error: error));
  }
}
