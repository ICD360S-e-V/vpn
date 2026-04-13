// ICD360SVPN — lib/src/features/speedtest/speed_test_screen.dart
//
// VPN speed test — measures download speed through the WireGuard
// tunnel by fetching test files from vpn.icd360s.de via curl.
// Shows result in Mbps with a progress indicator during the test.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../api/app_logger.dart';
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
  double? _downloadMbps;
  double? _uploadMbps;
  double? _pingMs;
  String _status = '';
  final List<_SpeedResult> _history = <_SpeedResult>[];

  Future<void> _runTest() async {
    final vpn = await VpnTunnel.status();
    if (vpn != VpnTunnelStatus.connected) {
      setState(() => _needsVpn = true);
      return;
    }

    setState(() {
      _testing = true;
      _needsVpn = false;
      _downloadMbps = null;
      _uploadMbps = null;
      _pingMs = null;
      _status = 'Ping…';
    });

    try {
      // Phase 1: Ping (latency)
      final ping = await _measurePing();
      if (!mounted) return;
      setState(() {
        _pingMs = ping;
        _status = 'Download (1 MB)…';
      });

      // Phase 2: Download 1MB warmup
      await _measureDownload('https://vpn.icd360s.de/download/speedtest-1mb.bin', 1.0);
      if (!mounted) return;
      setState(() => _status = 'Download (10 MB)…');

      // Phase 3: Download 10MB main test
      final dlSpeed = await _measureDownload(
        'https://vpn.icd360s.de/download/speedtest-10mb.bin',
        10.0,
      );
      if (!mounted) return;
      setState(() {
        _downloadMbps = dlSpeed;
        _status = 'Upload…';
      });

      // Phase 4: Upload test (POST 1MB of data)
      final ulSpeed = await _measureUpload();
      if (!mounted) return;

      final result = _SpeedResult(
        timestamp: DateTime.now(),
        downloadMbps: dlSpeed ?? 0,
        uploadMbps: ulSpeed ?? 0,
        pingMs: ping ?? 0,
      );

      setState(() {
        _uploadMbps = ulSpeed;
        _status = 'Gata';
        _history.insert(0, result);
      });

      appLogger.info('SPEED',
        'Ping: ${ping?.toStringAsFixed(0)}ms  '
        'DL: ${dlSpeed?.toStringAsFixed(1)} Mbps  '
        'UL: ${ulSpeed?.toStringAsFixed(1)} Mbps',
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
      final sw = Stopwatch()..start();
      final result = await Process.run('/usr/bin/curl', <String>[
        '-s', '-o', '/dev/null', '--connect-timeout', '5',
        '-w', '%{time_connect}',
        'https://vpn.icd360s.de/',
      ]).timeout(const Duration(seconds: 8));
      sw.stop();

      if (result.exitCode == 0) {
        final connectTime = double.tryParse((result.stdout as String).trim());
        if (connectTime != null) return connectTime * 1000; // seconds → ms
      }
      return sw.elapsedMilliseconds.toDouble();
    } catch (_) {
      return null;
    }
  }

  Future<double?> _measureDownload(String url, double sizeMb) async {
    try {
      final result = await Process.run('/usr/bin/curl', <String>[
        '-s', '-o', '/dev/null', '--connect-timeout', '10', '--max-time', '30',
        '-w', '%{speed_download}',
        url,
      ]).timeout(const Duration(seconds: 35));

      if (result.exitCode != 0) return null;
      final bytesPerSec = double.tryParse((result.stdout as String).trim());
      if (bytesPerSec == null) return null;
      return (bytesPerSec * 8) / 1000000; // bytes/s → Mbps
    } catch (_) {
      return null;
    }
  }

  Future<double?> _measureUpload() async {
    try {
      // Generate a 1MB temp file for upload measurement
      const tmpFile = '/tmp/icd360s_speedtest_upload.bin';
      await Process.run('dd', <String>[
        'if=/dev/urandom', 'of=$tmpFile', 'bs=1048576', 'count=1',
      ]);

      // Upload the bounded file and measure speed
      final result = await Process.run('/usr/bin/curl', <String>[
        '-s', '-o', '/dev/null', '--connect-timeout', '10', '--max-time', '30',
        '-X', 'POST',
        '-H', 'Content-Type: application/octet-stream',
        '--data-binary', '@$tmpFile',
        '-w', '%{speed_upload}',
        'https://vpn.icd360s.de/',
      ]).timeout(const Duration(seconds: 35));

      // Clean up
      try { await File(tmpFile).delete(); } catch (_) {}

      if (result.exitCode != 0) return null;
      final bytesPerSec = double.tryParse((result.stdout as String).trim());
      if (bytesPerSec == null || bytesPerSec == 0) return null;
      return (bytesPerSec * 8) / 1000000;
    } catch (_) {
      return null;
    }
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
                        width: 80,
                        height: 80,
                        child: CircularProgressIndicator(strokeWidth: 6),
                      ),
                      const SizedBox(height: 16),
                      Text(_status, style: theme.textTheme.bodyMedium),
                    ],
                  )
                else if (_downloadMbps != null) ...<Widget>[
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
                  ),
                ] else
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
          Text('Istoric', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          ..._history.map((r) {
            final t = r.timestamp.toLocal();
            final time =
                '${t.hour.toString().padLeft(2, '0')}:'
                '${t.minute.toString().padLeft(2, '0')}';
            return ListTile(
              dense: true,
              leading: const Icon(Icons.history, size: 18),
              title: Text(
                '↓ ${r.downloadMbps.toStringAsFixed(1)} Mbps  '
                '↑ ${r.uploadMbps.toStringAsFixed(1)} Mbps  '
                '⏱ ${r.pingMs.toStringAsFixed(0)}ms',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
              trailing: Text(time, style: const TextStyle(fontSize: 11)),
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

class _SpeedResult {
  const _SpeedResult({
    required this.timestamp,
    required this.downloadMbps,
    required this.uploadMbps,
    required this.pingMs,
  });
  final DateTime timestamp;
  final double downloadMbps;
  final double uploadMbps;
  final double pingMs;
}
