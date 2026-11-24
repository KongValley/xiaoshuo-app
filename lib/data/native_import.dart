import 'package:flutter/services.dart';

/// Bridge to the small native Android helper in `MainActivity.kt`.
///
/// The app has no third-party plugins, so Android uses the system document
/// picker (Storage Access Framework) instead of the desktop file browser.
class NativeImport {
  NativeImport._();

  static const MethodChannel _channel = MethodChannel('shijuan/native');

  /// Opens the system picker and returns local copies of the selected book
  /// files (TXT / EPUB / MOBI / AZW3 / PDF / Word).
  static Future<List<String>> pickTxtFiles() async {
    final result = await _channel.invokeMethod<List<dynamic>>('pickBookFiles');
    if (result == null) return const [];
    return [
      for (final item in result)
        if (item is String && item.isNotEmpty) item,
    ];
  }

  /// Clears temporary Android SAF import caches once copied into the library.
  static Future<void> clearImportCache() async {
    try {
      await _channel.invokeMethod<void>('clearImportCache');
    } catch (_) {
      // Non-fatal cleanup.
    }
  }
}
