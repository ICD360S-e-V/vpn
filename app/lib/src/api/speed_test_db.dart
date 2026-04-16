// ICD360SVPN — lib/src/api/speed_test_db.dart
//
// SQLite persistence for speed test history. Uses sqflite_common_ffi
// so it works on all desktop platforms (macOS, Linux, Windows).

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class SpeedTestRecord {
  const SpeedTestRecord({
    this.id,
    required this.timestamp,
    required this.downloadMbps,
    required this.uploadMbps,
    required this.pingMs,
    required this.connectionType,
  });

  final int? id;
  final DateTime timestamp;
  final double downloadMbps;
  final double uploadMbps;
  final double pingMs;
  final String connectionType;

  Map<String, Object?> toMap() => <String, Object?>{
    if (id != null) 'id': id,
    'timestamp': timestamp.millisecondsSinceEpoch,
    'download_mbps': downloadMbps,
    'upload_mbps': uploadMbps,
    'ping_ms': pingMs,
    'connection_type': connectionType,
  };

  factory SpeedTestRecord.fromMap(Map<String, Object?> m) {
    return SpeedTestRecord(
      id: m['id'] as int?,
      timestamp: DateTime.fromMillisecondsSinceEpoch(m['timestamp'] as int),
      downloadMbps: (m['download_mbps'] as num).toDouble(),
      uploadMbps: (m['upload_mbps'] as num).toDouble(),
      pingMs: (m['ping_ms'] as num).toDouble(),
      connectionType: m['connection_type'] as String? ?? 'Unknown',
    );
  }
}

class SpeedTestDb {
  SpeedTestDb._();
  static final SpeedTestDb instance = SpeedTestDb._();

  Database? _db;
  bool _initialized = false;

  Future<Database> _open() async {
    if (_db != null) return _db!;
    if (!_initialized) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      _initialized = true;
    }
    final dir = await getApplicationSupportDirectory();
    if (!await dir.exists()) await dir.create(recursive: true);
    final dbPath = p.join(dir.path, 'speedtest.db');
    _db = await databaseFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, v) async {
          await db.execute('''
            CREATE TABLE speed_results (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              timestamp INTEGER NOT NULL,
              download_mbps REAL NOT NULL,
              upload_mbps REAL NOT NULL,
              ping_ms REAL NOT NULL,
              connection_type TEXT NOT NULL
            )
          ''');
          await db.execute('CREATE INDEX idx_timestamp ON speed_results(timestamp DESC)');
        },
      ),
    );
    return _db!;
  }

  Future<int> insert(SpeedTestRecord record) async {
    final db = await _open();
    return db.insert('speed_results', record.toMap());
  }

  Future<List<SpeedTestRecord>> loadRecent({int limit = 100}) async {
    final db = await _open();
    final rows = await db.query(
      'speed_results',
      orderBy: 'timestamp DESC',
      limit: limit,
    );
    return rows.map(SpeedTestRecord.fromMap).toList();
  }

  Future<void> clear() async {
    final db = await _open();
    await db.delete('speed_results');
  }

  /// Delete records older than [days] days.
  Future<int> purgeOlderThan({int days = 90}) async {
    final db = await _open();
    final cutoff = DateTime.now().subtract(Duration(days: days));
    return db.delete(
      'speed_results',
      where: 'timestamp < ?',
      whereArgs: <Object?>[cutoff.millisecondsSinceEpoch],
    );
  }
}
