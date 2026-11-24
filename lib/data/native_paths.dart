import 'package:flutter/services.dart';

/// Asks the Android side for paths that only the framework knows.
///
/// The app has no third-party plugins, so this goes through the same
/// MethodChannel as the TXT picker (see `MainActivity.kt`).
class NativePaths {
  NativePaths._();

  static const MethodChannel _channel = MethodChannel('shijuan/native');

  /// The app's private files directory, as reported by
  /// `Context.getFilesDir()`. Null when the platform cannot answer.
  static Future<String?> filesDir() async {
    try {
      final result = await _channel.invokeMethod<String>('getFilesDir');
      if (result == null || result.trim().isEmpty) return null;
      return result.trim();
    } catch (_) {
      return null;
    }
  }
}
