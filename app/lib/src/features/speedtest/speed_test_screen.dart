// ICD360SVPN — lib/src/features/speedtest/speed_test_screen.dart
//
// VPN speed test — measures download/upload speed and ping through
// the WireGuard tunnel. Results persisted to SQLite. Auto-runs
// every 5 minutes when enabled. Records connection type
// (WiFi / Ethernet / Cellular) for ISP-quality evidence.

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../api/app_logger.dart';
import '../../api/network_info.dart';
import '../../api/speed_test_db.dart';
import '../../api/vpn_tunnel.dart';
import '../../common/needs_vpn_view.dart';

class SpeedTestScreen extends StatefulWidget {
  const SpeedTestScreen({super.key});

  @override
  State<SpeedTestScreen> createState() => _SpeedTestScreenState();
}

class _SpeedTestScreenState extends State<SpeedTestScreen> {
  bool _testing = false;
  bool _needsVpn = false;
  bool _autoRun = false;
  double? _downloadMbps;
  double? _uploadMbps;
  double? _pingMs;
  String _status = '';
  String? _connectionType;
  List<SpeedTestRecord> _history = <SpeedTestRecord>[];
  Timer? _autoTimer;

  @override
  void initState() {
    super.initState();
    unawaited(_loadHistory());
    unawaited(_detectType());
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    super.dispose();
  }

  Future<void> _detectType() async {
    final type = await NetworkInfo.instance.detectType();
    if (mounted) setState(() => _connectionType = type);
  }

  Future<void> _loadHistory() async {
    try {
      final records = await SpeedTestDb.instance.loadRecent(limit: 50);
      if (mounted) setState(() => _history = records);
    } catch (e) {
      appLogger.warn('SPEED', 'Load history eșuat: $e');
    }
  }

  void _toggleAutoRun() {
    setState(() => _autoRun = !_autoRun);
    if (_autoRun) {
      _autoTimer = Timer.periodic(const Duration(minutes: 5), (_) {
        if (!_testing) unawaited(_runTest());
      });
      appLogger.info('SPEED', 'Auto-test activat (5 min)');
    } else {
      _autoTimer?.cancel();
      appLogger.info('SPEED', 'Auto-test dezactivat');
    }
  }

  Future<void> _runTest() async {
    final vpn = await VpnTunnel.status();
    if (vpn != VpnTunnelStatus.connected) {
      if (mounted) setState(() => _needsVpn = true);
      return;
    }

    if (!mounted) return;
    await _detectType();

    setState(() {
      _testing = true;
      _needsVpn = false;
      _downloadMbps = null;
      _uploadMbps = null;
      _pingMs = null;
      _status = 'Ping…';
    });

    try {
      final ping = await _measurePing();
      if (!mounted) return;
      setState(() {
        _pingMs = ping;
        _status = 'Warmup download (1 MB)…';
      });

      await _measureDownload('https://vpn.icd360s.de/download/speedtest-1mb.bin');
      if (!mounted) return;
      setState(() => _status = 'Download (10 MB)…');

      final dlSpeed = await _measureDownload(
        'https://vpn.icd360s.de/download/speedtest-10mb.bin',
      );
      if (!mounted) return;
      setState(() {
        _downloadMbps = dlSpeed;
        _status = 'Upload (1 MB)…';
      });

      final ulSpeed = await _measureUpload();
      if (!mounted) return;

      final record = SpeedTestRecord(
        timestamp: DateTime.now(),
        downloadMbps: dlSpeed ?? 0,
        uploadMbps: ulSpeed ?? 0,
        pingMs: ping ?? 0,
        connectionType: _connectionType ?? 'Unknown',
      );

      // Persist to SQLite
      try {
        await SpeedTestDb.instance.insert(record);
      } catch (e) {
        appLogger.warn('SPEED', 'SQLite insert eșuat: $e');
      }

      setState(() {
        _uploadMbps = ulSpeed;
        _status = 'Gata';
        _history = <SpeedTestRecord>[record, ..._history.take(49)];
      });

      appLogger.info('SPEED',
        'Ping: ${ping?.toStringAsFixed(0)}ms  '
        'DL: ${dlSpeed?.toStringAsFixed(1)} Mbps  '
        'UL: ${ulSpeed?.toStringAsFixed(1)} Mbps  '
        '[${_connectionType ?? "?"}]',
      );
    } catch (e) {
      appLogger.error('SPEED', 'Test eșuat: $e');
      if (mounted) {
        setState(() => _status = 'Eroare: $e');
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<double?> _measurePing() async {
    try {
      final result = await Process.run('/usr/bin/curl', <String>[
        '-s', '-o', '/dev/null', '--connect-timeout', '5',
        '--no-keepalive',
        '-w', '%{time_starttransfer}',
        'https://vpn.icd360s.de/',
      ]).timeout(const Duration(seconds: 8));
      if (result.exitCode == 0) {
        final t = double.tryParse((result.stdout as String).trim());
        if (t != null && t > 0) return t * 1000;
      }
    } catch (_) {}
    return null;
  }

  Future<double?> _measureDownload(String url) async {
    try {
      final result = await Process.run('/usr/bin/curl', <String>[
        '-s', '-o', '/dev/null', '--connect-timeout', '10', '--max-time', '30',
        '-w', '%{speed_download}',
        url,
      ]).timeout(const Duration(seconds: 35));
      if (result.exitCode != 0) return null;
      final bytesPerSec = double.tryParse((result.stdout as String).trim());
      if (bytesPerSec == null) return null;
      return (bytesPerSec * 8) / 1000000;
    } catch (_) {
      return null;
    }
  }

  Future<double?> _measureUpload() async {
    final tmpPath = '${Directory.systemTemp.path}/icd360s_speedtest_${DateTime.now().millisecondsSinceEpoch}.bin';
    try {
      // Generate exactly 1 MB in Dart — no shell, no /dev/urandom
      final rnd = Random();
      final bytes = List<int>.generate(1048576, (_) => rnd.nextInt(256));
      await File(tmpPath).writeAsBytes(bytes, flush: true);

      final result = await Process.run('/usr/bin/curl', <String>[
        '-s', '-o', '/dev/null', '--connect-timeout', '10', '--max-time', '30',
        '--http1.1', // force HTTP/1.1 so upload throughput is measurable
        '-X', 'POST',
        '-H', 'Content-Type: application/octet-stream',
        '--data-binary', '@$tmpPath',
        '-w', '%{speed_upload}',
        'https://vpn.icd360s.de/speedtest-upload',
      ]).timeout(const Duration(seconds: 35));

      if (result.exitCode != 0) return null;
      final bytesPerSec = double.tryParse((result.stdout as String).trim());
      if (bytesPerSec == null || bytesPerSec == 0) return null;
      return (bytesPerSec * 8) / 1000000;
    } catch (_) {
      return null;
    } finally {
      try { await File(tmpPath).delete(); } catch (_) {}
    }
  }

  IconData _iconForType(String type) {
    return switch (type) {
      'WiFi' => Icons.wifi,
      'Ethernet' => Icons.settings_ethernet,
      'Cellular' => Icons.signal_cellular_4_bar,
      'VPN' => Icons.vpn_lock,
      'Offline' => Icons.signal_wifi_off,
      _ => Icons.network_check,
    };
  }

  @override
  Widget build(BuildContext context) {
    if (_needsVpn) {
      return NeedsVpnView(onRetry: _runTest, isRetrying: _testing);
    }

    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        // Connection type chip + auto-run toggle
        Row(
          children: <Widget>[
            Chip(
              avatar: Icon(_iconForType(_connectionType ?? ''), size: 16),
              label: Text(_connectionType ?? 'Detectare…'),
              padding: const EdgeInsets.symmetric(horizontal: 4),
            ),
            const Spacer(),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Text('Auto (5 min)', style: TextStyle(fontSize: 12)),
                Switch(
                  value: _autoRun,
                  onChanged: (_) => _toggleAutoRun(),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Main speed display
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: <Widget>[
                if (_testing)
                  Column(
                    children: <Widget>[
                      const SizedBox(
                        width: 80, height: 80,
                        child: CircularProgressIndicator(strokeWidth: 6),
                      ),
                      const SizedBox(height: 16),
                      Text(_status, style: theme.textTheme.bodyMedium),
                    ],
                  )
                else if (_downloadMbps != null)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: <Widget>[
                      _SpeedGauge(
                        label: 'Download',
                        value: _downloadMbps!,
                        icon: Icons.arrow_downward,
                        color: Colors.green,
                      ),
                      _SpeedGauge(
                        label: 'Upload',
                        value: _uploadMbps ?? 0,
                        icon: Icons.arrow_upward,
                        color: Colors.blue,
                      ),
                      _SpeedGauge(
                        label: 'Ping',
                        value: _pingMs ?? 0,
                        unit: 'ms',
                        icon: Icons.speed,
                        color: Colors.orange,
                      ),
                    ],
                  )
                else
                  Column(
                    children: <Widget>[
                      Icon(Icons.speed, size: 64, color: theme.colorScheme.outline),
                      const SizedBox(height: 8),
                      Text(
                        'Apasă pentru a testa viteza VPN',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _testing ? null : _runTest,
                  icon: const Icon(Icons.play_arrow),
                  label: Text(_testing ? 'Se testează…' : 'Start Test'),
                ),
              ],
            ),
          ),
        ),

        // History
        if (_history.isNotEmpty) ...<Widget>[
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Text('Istoric (${_history.length})', style: theme.textTheme.titleSmall),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('Șterge'),
                onPressed: _history.isEmpty ? null : () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Ștergi istoricul?'),
                      content: const Text('Toate testele salvate vor fi pierdute.'),
                      actions: <Widget>[
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anulează')),
                        FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Șterge'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true) {
                    await SpeedTestDb.instance.clear();
                    await _loadHistory();
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          ..._history.map((r) {
            final t = r.timestamp.toLocal();
            final dateStr = '${t.day.toString().padLeft(2, '0')}.${t.month.toString().padLeft(2, '0')} '
                '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
            return ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              leading: Icon(_iconForType(r.connectionType), size: 18),
              title: Text(
                '↓ ${r.downloadMbps.toStringAsFixed(1)} Mbps  '
                '↑ ${r.uploadMbps.toStringAsFixed(1)} Mbps  '
                '⏱ ${r.pingMs.toStringAsFixed(0)}ms',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
              subtitle: Text('$dateStr  •  ${r.connectionType}', style: const TextStyle(fontSize: 10)),
            );
          }),
        ],
      ],
    );
  }
}

class _SpeedGauge extends StatelessWidget {
  const _SpeedGauge({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.unit = 'Mbps',
  });
  final String label;
  final double value;
  final IconData icon;
  final Color color;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: <Widget>[
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 4),
        Text(
          value < 10 ? value.toStringAsFixed(2) : value.toStringAsFixed(1),
          style: theme.textTheme.headlineMedium?.copyWith(
            color: color,
            fontFamily: 'monospace',
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(unit, style: theme.textTheme.labelSmall?.copyWith(color: color)),
        Text(label, style: theme.textTheme.labelSmall),
      ],
    );
  }
}
