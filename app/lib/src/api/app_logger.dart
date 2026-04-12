// ICD360SVPN — lib/src/api/app_logger.dart
//
// In-app debug console with exportable
// Singleton logger with a ValueNotifier so the footer console
// widget rebuilds on every new entry. Keeps the last 500 entries.

import 'package:flutter/foundation.dart';

enum LogLevel { info, warning, error }

class LogEntry {
  LogEntry({
    required this.timestamp,
    required this.tag,
    required this.message,
    required this.level,
  });

  final DateTime timestamp;
  final String tag;
  final String message;
  final LogLevel level;

  String get formatted {
    final t = timestamp.toLocal();
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    final ss = t.second.toString().padLeft(2, '0');
    return '$hh:$mm:$ss [$tag] $message';
  }
}

class AppLogger {
  AppLogger._();
  static final AppLogger instance = AppLogger._();

  static const int _maxEntries = 500;

  final ValueNotifier<List<LogEntry>> entries =
      ValueNotifier<List<LogEntry>>(<LogEntry>[]);

  void _add(LogLevel level, String tag, String message) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      tag: tag,
      message: message,
      level: level,
    );
    final list = List<LogEntry>.of(entries.value);
    list.add(entry);
    if (list.length > _maxEntries) {
      list.removeRange(0, list.length - _maxEntries);
    }
    entries.value = list;
    if (kDebugMode) {
      // ignore: avoid_print
      print(entry.formatted);
    }
  }

  void info(String tag, String message) => _add(LogLevel.info, tag, message);
  void warn(String tag, String message) =>
      _add(LogLevel.warning, tag, message);
  void error(String tag, String message) =>
      _add(LogLevel.error, tag, message);

  void clear() => entries.value = <LogEntry>[];

  /// Export all entries as a single string for copy/paste or filing
  /// a bug report.
  String export() => entries.value.map((e) => e.formatted).join('\n');
}

/// Convenience top-level accessor.
final appLogger = AppLogger.instance;
