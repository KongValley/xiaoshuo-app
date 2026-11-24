import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/theme.dart';
import 'data/library_repository.dart';
import 'data/settings_repository.dart';
import 'data/stats_repository.dart';
import 'features/bookshelf/bookshelf_page.dart';

class ShijuanApp extends StatelessWidget {
  const ShijuanApp({
    super.key,
    required this.library,
    required this.settings,
    this.stats,
  });

  final LibraryRepository library;
  final SettingsRepository settings;
  final StatsRepository? stats;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: settings,
      builder: (context, _) {
        return MaterialApp(
          title: '拾卷',
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
          themeMode: settings.settings.themePreference.themeMode,
          home: BookshelfPage(
            library: library,
            settings: settings,
            stats: stats,
          ),
        );
      },
    );
  }
}
