import 'package:flutter/material.dart';

import 'app.dart';
import 'core/app_dirs.dart';
import 'data/library_repository.dart';
import 'data/settings_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final dataRoot = await AppDirs.dataDir();
  final library = LibraryRepository(root: dataRoot);
  final settings = SettingsRepository(root: dataRoot);

  await Future.wait([library.init(), settings.init()]);

  runApp(ModuApp(library: library, settings: settings));
}
