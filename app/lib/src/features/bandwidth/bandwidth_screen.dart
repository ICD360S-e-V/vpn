// ICD360SVPN — lib/src/features/bandwidth/bandwidth_screen.dart
//
// Real-time bandwidth chart using fl_chart. Shows RX/TX traffic
// for the selected peer over time. Auto-refreshes every 30s.

import 'dart:async';
import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../api/vpn_tunnel.dart';
import '../../common/needs_vpn_view.dart';
import '../../models/peer.dart';
import '../../models/traffic_series.dart';

class BandwidthScreen extends StatefulWidget {
  const BandwidthScreen({super.key, required this.client});
  final ApiClient client;

  @override
  State<BandwidthScreen> createState() => _BandwidthScreenState();
}

class _BandwidthScreenState extends State<BandwidthScreen> {
  List<Peer> _peers = const <Peer>[];
  Peer? _selectedPeer;
  TrafficSeries? _series;
  bool _loading = false;
  bool _needsVpn = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPeers());
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _loadData());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadPeers() async {
    final vpn = await VpnTunnel.status();
    if (vpn != VpnTunnelStatus.connected) {
      if (mounted) setState(() => _needsVpn = true);
      return;
    }
    try {
      final peers = await widget.client.listPeers();
      if (!mounted) return;
      setState(() {
        _peers = peers;
        _needsVpn = false;
        if (_selectedPeer == null && peers.isNotEmpty) {
          _selectedPeer = peers.first;
        }
      });
      await _loadData();
    } catch (_) {
      if (mounted) setState(() => _needsVpn = true);
    }
  }

  Future<void> _loadData() async {
    if (_selectedPeer == null || _loading) return;
    setState(() => _loading = true);
    try {
      final now = DateTime.now().toUtc();
      final series = await widget.client.peerBandwidth(
        publicKey: _selectedPeer!.publicKey,
        from: now.subtract(const Duration(hours: 24)),
        to: now,
        granularity: 'hour',
      );
      if (!mounted) return;
      setState(() => _series = series);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  String _formatBytes(double bytes) {
    if (bytes < 1024) return '${bytes.toInt()} B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  Widget build(BuildContext context) {
    if (_needsVpn) {
      return NeedsVpnView(onRetry: _loadPeers, isRetrying: _loading);
    }

    final theme = Theme.of(context);
    final points = _series?.points ?? <TrafficPoint>[];
    final totalRx = points.fold<int>(0, (sum, p) => sum + p.rx);
    final totalTx = points.fold<int>(0, (sum, p) => sum + p.tx);

    return Column(
      children: <Widget>[
        // Peer selector
        if (_peers.length > 1)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: DropdownButton<String>(
              isExpanded: true,
              value: _selectedPeer?.publicKey,
              items: _peers.map((p) => DropdownMenuItem<String>(
                value: p.publicKey,
                child: Text(p.name.isEmpty ? p.allowedIPs.join(', ') : p.name),
              )).toList(),
              onChanged: (pk) {
                setState(() {
                  _selectedPeer = _peers.firstWhere((p) => p.publicKey == pk);
                  _series = null;
                });
                _loadData();
              },
            ),
          ),

        // Summary cards
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: <Widget>[
                        const Icon(Icons.arrow_downward, color: Colors.green, size: 20),
                        const SizedBox(height: 4),
                        Text('Download', style: theme.textTheme.labelSmall),
                        Text(_formatBytes(totalRx.toDouble()),
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: Colors.green, fontFamily: 'monospace',
                          )),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: <Widget>[
                        const Icon(Icons.arrow_upward, color: Colors.blue, size: 20),
                        const SizedBox(height: 4),
                        Text('Upload', style: theme.textTheme.labelSmall),
                        Text(_formatBytes(totalTx.toDouble()),
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: Colors.blue, fontFamily: 'monospace',
                          )),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Chart
        Expanded(
          child: points.isEmpty
              ? Center(
                  child: _loading
                      ? const CircularProgressIndicator()
                      : Text('Nicio dată de trafic disponibilă.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                )
              : Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 16, 8),
                  child: _BandwidthChart(points: points, formatBytes: _formatBytes),
                ),
        ),
      ],
    );
  }
}

class _BandwidthChart extends StatelessWidget {
  const _BandwidthChart({required this.points, required this.formatBytes});
  final List<TrafficPoint> points;
  final String Function(double) formatBytes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxY = points.fold<int>(0, (m, p) => max(m, max(p.rx, p.tx))).toDouble();

    final rxSpots = <FlSpot>[];
    final txSpots = <FlSpot>[];
    for (var i = 0; i < points.length; i++) {
      rxSpots.add(FlSpot(i.toDouble(), points[i].rx.toDouble()));
      txSpots.add(FlSpot(i.toDouble(), points[i].tx.toDouble()));
    }

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxY > 0 ? maxY / 4 : 1,
          getDrawingHorizontalLine: (_) => FlLine(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: max(1, points.length / 6).toDouble(),
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= points.length) return const SizedBox.shrink();
                final t = points[i].t.toLocal();
                return Text(
                  '${t.hour.toString().padLeft(2, '0')}:00',
                  style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 52,
              getTitlesWidget: (value, meta) {
                return Text(
                  formatBytes(value),
                  style: TextStyle(fontSize: 9, color: theme.colorScheme.onSurfaceVariant),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: <LineChartBarData>[
          LineChartBarData(
            spots: rxSpots,
            isCurved: true,
            color: Colors.green,
            barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: Colors.green.withValues(alpha: 0.1),
            ),
          ),
          LineChartBarData(
            spots: txSpots,
            isCurved: true,
            color: Colors.blue,
            barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: Colors.blue.withValues(alpha: 0.1),
            ),
          ),
        ],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) {
              return spots.map((spot) {
                final color = spot.barIndex == 0 ? Colors.green : Colors.blue;
                final label = spot.barIndex == 0 ? 'RX' : 'TX';
                return LineTooltipItem(
                  '$label: ${formatBytes(spot.y)}',
                  TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
                );
              }).toList();
            },
          ),
        ),
      ),
    );
  }
}
