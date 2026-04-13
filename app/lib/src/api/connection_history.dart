// ICD360SVPN — lib/src/api/connection_history.dart
//
// Persists VPN connect/disconnect events to a local JSON file.
// Each entry records timestamp, event type, and duration.

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

enum ConnectionEvent { connected, disconnected }

class ConnectionRecord {
  const ConnectionRecord({
    required this.timestamp,
    required this.event,
    this.durationSeconds,
  });

  final DateTime timestamp;
  final ConnectionEvent event;
  final int? durationSeconds;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'timestamp': timestamp.toIso8601String(),
    'event': event.name,
    if (durationSeconds != null) 'duration_seconds': durationSeconds,
  };

  factory ConnectionRecord.fromJson(Map<String, dynamic> json) {
    return ConnectionRecord(
      timestamp: DateTime.parse(json['timestamp'] as String),
      event: json['event'] == 'connected'
          ? ConnectionEvent.connected
          : ConnectionEvent.disconnected,
      durationSeconds: json['duration_seconds'] as int?,
    );
  }
}

class ConnectionHistory {
  ConnectionHistory._();
  static final ConnectionHistory instance = ConnectionHistory._();

  static const int _maxEntries = 200;
  static const String _filename = 'connection_history.json';

  List<ConnectionRecord> _records = <ConnectionRecord>[];
  bool _loaded = false;
  DateTime? _lastConnected;

  List<ConnectionRecord> get records => List<ConnectionRecord>.unmodifiable(_records);

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_filename');
  }

  Future<void> _load() async {
    if (_loaded) return;
    try {
      final file = await _file();
      if (await file.exists()) {
        final body = await file.readAsString();
        final list = jsonDecode(body) as List<dynamic>;
        _records = list
            .map((e) => ConnectionRecord.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {
      _records = <ConnectionRecord>[];
    }
    _loaded = true;
  }

  Future<void> _save() async {
    final file = await _file();
    final json = _records.map((r) => r.toJson()).toList();
    await file.writeAsString(jsonEncode(json), flush: true);
  }

  Future<void> recordConnect() async {
    await _load();
    _lastConnected = DateTime.now();
    _records.insert(0, ConnectionRecord(
      timestamp: _lastConnected!,
      event: ConnectionEvent.connected,
    ));
    if (_records.length > _maxEntries) {
      _records = _records.sublist(0, _maxEntries);
    }
    await _save();
  }

  Future<void> recordDisconnect() async {
    await _load();
    int? duration;
    if (_lastConnected != null) {
      duration = DateTime.now().difference(_lastConnected!).inSeconds;
      _lastConnected = null;
    }
    _records.insert(0, ConnectionRecord(
      timestamp: DateTime.now(),
      event: ConnectionEvent.disconnected,
      durationSeconds: duration,
    ));
    if (_records.length > _maxEntries) {
      _records = _records.sublist(0, _maxEntries);
    }
    await _save();
  }

  Future<List<ConnectionRecord>> loadAll() async {
    await _load();
    return records;
  }
}
