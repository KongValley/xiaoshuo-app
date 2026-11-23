import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../data/models/book.dart';
import '../data/models/reader_settings.dart';

class AppSettings {
  const AppSettings({
    this.reader = const ReaderSettings(),
    this.bookSort = BookSort.recent,
    this.lastImportDir,
  });

  final ReaderSettings reader;
  final BookSort bookSort;
  final String? lastImportDir;

  AppSettings copyWith({
    ReaderSettings? reader,
    BookSort? bookSort,
    String? lastImportDir,
    bool clearImportDir = false,
  }) =>
      AppSettings(
        reader: reader ?? this.reader,
        bookSort: bookSort ?? this.bookSort,
        lastImportDir: clearImportDir ? null : (lastImportDir ?? this.lastImportDir),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'version': 1,
        'reader': reader.toJson(),
        'bookSort': bookSort.name,
        'lastImportDir': lastImportDir,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        reader: ReaderSettings.fromJson(
          (json['reader'] as Map?)?.cast<String, dynamic>(),
        ),
        bookSort: BookSort.fromName(json['bookSort'] as String?),
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
