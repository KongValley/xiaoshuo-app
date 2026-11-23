/// Small formatting helpers used across the UI.
class Fmt {
  Fmt._();

  /// 8,432 / 1,234,567
  static String number(int value) {
    final digits = value.abs().toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return value < 0 ? '-$buffer' : buffer.toString();
  }

  /// 8,432 字 / 487.2 万字
  static String charCount(int chars) {
    if (chars >= 10000) {
      final wan = chars / 10000;
      final text = wan >= 1000 ? wan.toStringAsFixed(0) : wan.toStringAsFixed(1);
      return '${text.replaceAll(RegExp(r'\.0$'), '')} 万字';
    }
    return '${number(chars)} 字';
  }

  /// 1.4 MB
  static String fileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
    return '${(mb / 1024).toStringAsFixed(2)} GB';
  }

  /// 2026-11-23 14:05
  static String dateTime(DateTime time) {
    final local = time.toLocal();
    return '${local.year}-${_two(local.month)}-${_two(local.day)} '
        '${_two(local.hour)}:${_two(local.minute)}';
  }

  /// 2026-11-23
  static String date(DateTime time) {
    final local = time.toLocal();
    return '${local.year}-${_two(local.month)}-${_two(local.day)}';
  }

  static String clock(DateTime time) => '${_two(time.hour)}:${_two(time.minute)}';

  static String percent(double fraction, {int digits = 1}) {
    final value = (fraction.clamp(0.0, 1.0)) * 100;
    if (value > 0 && value < 0.1) return '<0.1%';
    if (value >= 99.95) return '100%';
    final text = value.toStringAsFixed(digits);
    return '${text.replaceAll(RegExp(r'\.0$'), '')}%';
  }

  /// Rough remaining reading time, assuming ~420 Chinese chars per minute.
  static String remainingTime(int chars) {
    if (chars <= 0) return '已读完';
    final minutes = (chars / 420).round();
    if (minutes < 1) return '不到 1 分钟';
    if (minutes < 60) return '约 $minutes 分钟';
    final hours = minutes / 60;
    if (hours < 10) return '约 ${hours.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '')} 小时';
    return '约 ${hours.round()} 小时';
  }

  static String _two(int value) => value.toString().padLeft(2, '0');

  static String fileName(String path) {
    final normalized = path.replaceAll('\\', '/');
    final index = normalized.lastIndexOf('/');
    return index < 0 ? normalized : normalized.substring(index + 1);
  }

  static bool isTxtFile(String path) =>
      path.toLowerCase().endsWith('.txt');
}
