import 'dart:io';

import 'package:path/path.dart' as p;

/// Resolves the directory where the app keeps its own copy of imported books,
/// the library index and settings.
///
/// No plugin is used, so the location is derived from the platform's standard
/// application-data environment variables. `MODU_DATA_DIR` can override it,
/// which is handy for tests and for the `tool/seed.dart` helper.
class AppDirs {
  AppDirs._();

  static Directory? _cached;

  static Future<Directory> dataDir() async {
    final cached = _cached;
    if (cached != null) return cached;
    final dir = _resolve();
    await dir.create(recursive: true);
    _cached = dir;
    return dir;
  }

  static Directory get dataDirSync => _cached ?? _resolve();

  static Directory _resolve() {
    final override = Platform.environment['MODU_DATA_DIR'];
    if (override != null && override.trim().isNotEmpty) {
      return Directory(p.normalize(override.trim()));
    }

    if (Platform.isWindows) {
      final base = Platform.environment['LOCALAPPDATA'] ??
          Platform.environment['APPDATA'] ??
          Directory.current.path;
      return Directory(p.join(base, 'ModuReader'));
    }
    if (Platform.isMacOS) {
      final home = Platform.environment['HOME'] ?? Directory.current.path;
      return Directory(p.join(home, 'Library', 'Application Support', 'ModuReader'));
    }
    if (Platform.isLinux) {
      final base = Platform.environment['XDG_DATA_HOME'];
      final home = Platform.environment['HOME'] ?? Directory.current.path;
      return Directory(p.join(
        (base == null || base.isEmpty) ? p.join(home, '.local', 'share') : base,
        'modu-reader',
      ));
    }

    // Mobile/other: there is no plugin to ask for the real app directory.
    // The app's private files directory is stable for a given package id.
    for (final candidate in const [
      '/data/user/0/com.modu.modu_reader/files',
      '/data/data/com.modu.modu_reader/files',
    ]) {
      if (Directory(candidate).existsSync()) return Directory(candidate);
    }
    return Directory(p.join(Directory.systemTemp.path, 'ModuReader'));
  }
}
