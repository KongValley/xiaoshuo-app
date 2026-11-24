import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../data/models/book.dart';
import '../data/models/reader_settings.dart';

enum AppThemePreference {
  system('跟随系统', ThemeMode.system),
  light('昼间宣纸', ThemeMode.light),
  dark('夜间松烟', ThemeMode.dark);

  const AppThemePreference(this.label, this.themeMode);

  final String label;
  final ThemeMode themeMode;

  AppThemePreference next() =>
      AppThemePreference.values[(index + 1) % AppThemePreference.values.length];

  static AppThemePreference fromName(String? name) =>
      AppThemePreference.values.firstWhere(
        (value) => value.name == name,
        orElse: () => AppThemePreference.system,
      );
}

enum ShelfViewMode {
  grid('封面陈列'),
  list('雅致书目');

  const ShelfViewMode(this.label);
  final String label;

  static ShelfViewMode fromName(String? name) =>
      ShelfViewMode.values.firstWhere(
        (value) => value.name == name,
        orElse: () => ShelfViewMode.grid,
      );
}

class AppSettings {
  const AppSettings({
    this.reader = const ReaderSettings(),
    this.bookSort = BookSort.recent,
    this.themePreference = AppThemePreference.system,
    this.shelfView = ShelfViewMode.grid,
    this.lastImportDir,
  });

  final ReaderSettings reader;
  final BookSort bookSort;
  final AppThemePreference themePreference;
  final ShelfViewMode shelfView;
  final String? lastImportDir;

  AppSettings copyWith({
    ReaderSettings? reader,
    BookSort? bookSort,
    AppThemePreference? themePreference,
    ShelfViewMode? shelfView,
    String? lastImportDir,
    bool clearImportDir = false,
  }) =>
      AppSettings(
        reader: reader ?? this.reader,
        bookSort: bookSort ?? this.bookSort,
        themePreference: themePreference ?? this.themePreference,
        shelfView: shelfView ?? this.shelfView,
        lastImportDir:
            clearImportDir ? null : (lastImportDir ?? this.lastImportDir),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'version': 1,
        'reader': reader.toJson(),
        'bookSort': bookSort.name,
        'themePreference': themePreference.name,
        'shelfView': shelfView.name,
        'lastImportDir': lastImportDir,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        reader: ReaderSettings.fromJson(
          (json['reader'] as Map?)?.cast<String, dynamic>(),
        ),
        bookSort: BookSort.fromName(json['bookSort'] as String?),
        themePreference:
            AppThemePreference.fromName(json['themePreference'] as String?),
        shelfView: ShelfViewMode.fromName(json['shelfView'] as String?),
        lastImportDir: json['lastImportDir'] as String?,
      );
}

class SettingsRepository extends ChangeNotifier {
  SettingsRepository({required Directory root})
      : _file = File(p.join(root.path, 'settings.json'));

  final File _file;
  AppSettings _settings = const AppSettings();
  Timer? _saveTimer;
  bool _loaded = false;

  AppSettings get settings => _settings;

  Future<void> init() async {
    try {
      if (await _file.exists()) {
        final raw = await _file.readAsString(encoding: utf8);
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          _settings = AppSettings.fromJson(decoded.cast<String, dynamic>());
        }
      }
    } catch (_) {
      // A broken settings file is not worth blocking the app for.
      _settings = const AppSettings();
    }
    _loaded = true;
  }

  void updateReader(ReaderSettings reader) {
    _settings = _settings.copyWith(reader: reader);
    notifyListeners();
    _scheduleSave();
  }

  void updateSort(BookSort sort) {
    _settings = _settings.copyWith(bookSort: sort);
    notifyListeners();
    _scheduleSave();
  }

  void updateThemePreference(AppThemePreference preference) {
    _settings = _settings.copyWith(themePreference: preference);
    notifyListeners();
    _scheduleSave();
  }

  void updateShelfView(ShelfViewMode view) {
    _settings = _settings.copyWith(shelfView: view);
    notifyListeners();
    _scheduleSave();
  }

  void updateImportDir(String? directory) {
    _settings = directory == null
        ? _settings.copyWith(clearImportDir: true)
        : _settings.copyWith(lastImportDir: directory);
    notifyListeners();
    _scheduleSave();
  }

  void _scheduleSave() {
    if (!_loaded) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), flush);
  }

  Future<void> flush() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    try {
      await _file.parent.create(recursive: true);
      await _file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(_settings.toJson()),
        flush: true,
      );
    } catch (_) {
      // Ignore disk errors; the in-memory settings still work.
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }
}
