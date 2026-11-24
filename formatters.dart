import 'package:intl/intl.dart';

/// Pure formatting helpers (no Flutter dependency, easy to unit test).
class Formatters {
  Formatters._();

  /// 125 -> "02:05"
  static String mmss(int seconds) {
    final s = seconds < 0 ? 0 : seconds;
    return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
  }

  /// 1536 -> "2 KB", 5242880 -> "5.0 MB"
  static String fileSize(int bytes) {
    if (bytes >= 1 << 20) return '${(bytes / (1 << 20)).toStringAsFixed(1)} MB';
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '$bytes B';
  }

  static String dateTime(DateTime? d) => d == null ? '' : DateFormat('d MMM yyyy, hh:mm a').format(d.toLocal());

  static String date(DateTime? d) => d == null ? '' : DateFormat('d MMM yyyy').format(d.toLocal());

  static const _bn = ['০', '১', '২', '৩', '৪', '৫', '৬', '৭', '৮', '৯'];

  /// "2026" -> "২০২৬"
  static String bnDigits(String s) => s.replaceAllMapped(RegExp(r'\d'), (m) => _bn[int.parse(m[0]!)]);

  /// Score like 7 -> "7", 6.5 -> "6.50"
  static String score(double v) => v.toStringAsFixed(v % 1 == 0 ? 0 : 2);
}
