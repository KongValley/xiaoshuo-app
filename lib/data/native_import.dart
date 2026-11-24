import 'package:flutter/services.dart';

/// Bridge to the small native Android helper in `MainActivity.kt`.
///
/// The app has no third-party plugins, so Android uses the system document
/// picker (Storage Access Framework) instead of the desktop file browser.
class NativeImport {
  NativeImport._();

  static const MethodChannel _channel = MethodChannel('shijuan/native');

  /// Opens the system picker and returns local copies of the selected TXT
  /// files. Returns an empty list when the user cancels.
  static Future<List<String>> pickTxtFiles() async {
    final result = await _channel.invokeMethod<List<dynamic>>('pickTxtFiles');
    if (result == null) return const [];
    return [
      for (final item in result)
        if (item is String && item.isNotEmpty) item,
    ];
  }
}
