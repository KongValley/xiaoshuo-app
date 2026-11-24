import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Resolves the directory where the app keeps its own copy of imported books,
/// the library index and settings.
///
/// No plugin is used. On desktop the location is derived from the platform's
/// standard application-data environment variables; `SHIJUAN_DATA_DIR` can
/// override it, which is handy for tests and for the `tool/seed_library.dart`
/// helper.
class AppDirs {
  AppDirs._();

  static Directory? _cached;

  /// The private directory of an Android app is owned by the framework and
  /// sits under the user profile the app runs in (`/data/user/0`, `/10`,
  /// `/999`, …). Dart cannot work that path out by itself, so
  /// [androidFilesDir] carries the answer from the native side; without it the
  /// usual layouts are tried in order.
  static Future<Directory> dataDir({String? androidFilesDir}) async {
    final cached = _cached;
    if (cached != null) return cached;

    final Directory dir;
    if (Platform.isAndroid) {
      dir = _overrideDir() ??
          await firstWritable(<String>[
            if (androidFilesDir != null && androidFilesDir.trim().isNotEmpty)
              androidFilesDir,
            ...androidCandidates,
          ]);
    } else {
      dir = _overrideDir() ?? _desktopDir();
    }
    await dir.create(recursive: true);
    _cached = dir;
    return dir;
  }

  /// Synchronous desktop resolution, for the developer tools. Android has to
  /// go through [dataDir] to ask the framework first.
  static Directory get dataDirSync => _cached ?? _overrideDir() ?? _desktopDir();

  /// Private file locations Android is known to use for this package.
  static const List<String> androidCandidates = [
    '/data/user/0/com.shijuan.shijuan_reader/files',
    '/data/data/com.shijuan.shijuan_reader/files',
  ];

  /// Returns the first directory that exists or can be created. A profile the
  /// app does not belong to is not writable, so trying to create the folder is
  /// what tells the candidates apart.
  @visibleForTesting
  static Future<Directory> firstWritable(Iterable<String> candidates) async {
    for (final candidate in candidates) {
      if (candidate.trim().isEmpty) continue;
      final dir = Directory(candidate.trim());
      try {
        await dir.create(recursive: true);
        return dir;
      } catch (_) {
        // Not this profile, or not permitted: try the next one.
      }
    }
    return Directory(p.join(Directory.systemTemp.path, 'ShijuanReader'));
  }

  static Directory? _overrideDir() {
    final override = Platform.environment['SHIJUAN_DATA_DIR'] ??
        Platform.environment['MODU_DATA_DIR'];
    if (override == null || override.trim().isEmpty) return null;
    return Directory(p.normalize(override.trim()));
  }

  static Directory _desktopDir() {
    final home = Platform.environment['HOME'] ?? Directory.current.path;
    if (Platform.isWindows) {
      final base = Platform.environment['LOCALAPPDATA'] ??
          Platform.environment['APPDATA'] ??
          Directory.current.path;
      return Directory(p.join(base, 'ShijuanReader'));
    }
    if (Platform.isMacOS) {
      return Directory(p.join(home, 'Library', 'Application Support', 'ShijuanReader'));
    }
    if (Platform.isLinux) {
      final base = Platform.environment['XDG_DATA_HOME'];
      return Directory(p.join(
        (base == null || base.isEmpty) ? p.join(home, '.local', 'share') : base,
        'shijuan-reader',
      ));
    }
    return Directory(p.join(Directory.systemTemp.path, 'ShijuanReader'));
  }
}
