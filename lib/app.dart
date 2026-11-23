import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/theme.dart';
import 'data/library_repository.dart';
import 'data/settings_repository.dart';
import 'features/bookshelf/bookshelf_page.dart';

class ModuApp extends StatelessWidget {
  const ModuApp({
    super.key,
    required this.library,
    required this.settings,
  });

  final LibraryRepository library;
  final SettingsRepository settings;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '墨读',
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: BookshelfPage(library: library, settings: settings),
    );
  }
}
