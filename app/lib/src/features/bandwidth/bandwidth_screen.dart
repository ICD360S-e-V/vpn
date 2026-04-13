// ICD360SVPN — lib/src/features/bandwidth/bandwidth_screen.dart
//
// Bandwidth chart with selectable time ranges: Live, 1m, 10m, 1h,
// 1d, 7d, 14d, 30d. Uses fl_chart for RX/TX visualization.
// Refresh interval adapts to the selected range.

import 'dart:async';
import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../api/vpn_tunnel.dart';
import '../../common/needs_vpn_view.dart';
import '../../models/peer.dart';
import '../../models/traffic_series.dart';

enum _TimeRange {
  live('Live', Duration(minutes: 2), 'minute', Duration(seconds: 5)),
  min1('1 min', Duration(minutes: 1), 'minute', Duration(seconds: 10)),
  min10('10 min', Duration(minutes: 10), 'minute', Duration(seconds: 15)),
  hour1('1h', Duration(hours: 1), 'minute', Duration(seconds: 30)),
  day1('1d', Duration(hours: 24), 'hour', Duration(seconds: 60)),
  day7('7d', Duration(days: 7), 'hour', Duration(minutes: 5)),
  day14('14d', Duration(days: 14), 'day', Duration(minutes: 5)),
  day30('30d', Duration(days: 30), 'day', Duration(minutes: 5));

  const _TimeRange(this.label, this.duration, this.granularity, this.refresh);
  final String label;
  final Duration duration;
  final String granularity;
  final Duration refresh;
}

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
  _TimeRange _range = _TimeRange.day1;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPeers());
    _resetTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _resetTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(_range.refresh, (_) => _loadData());
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
        from: now.subtract(_range.duration),
        to: now,
        granularity: _range.granularity,
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

  String _axisLabel(TrafficPoint p) {
    final t = p.t.toLocal();
    if (_range.granularity == 'day') {
      return '${t.day}/${t.month}';
    }
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
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
        // Peer selector + time range
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: <Widget>[
              if (_peers.length > 1)
                Expanded(
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
              if (_peers.length > 1) const SizedBox(width: 12),
              if (_loading)
                const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
        ),

        // Time range chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: _TimeRange.values.map((r) => Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(r.label),
                selected: _range == r,
                onSelected: (_) {
                  setState(() {
                    _range = r;
                    _series = null;
                  });
                  _resetTimer();
                  unawaited(_loadData());
                },
              ),
            )).toList(),
          ),
        ),
        const SizedBox(height: 8),

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

        // Chart
        Expanded(
          child: points.isEmpty
              ? Center(
                  child: _loading
                      ? const CircularProgressIndicator()
                      : const Text('Nicio dată disponibilă.'),
                )
              : Padding(
                  padding: const EdgeInsets.all(16),
                  child: _BandwidthChart(
                    points: points,
                    formatBytes: _formatBytes,
                    axisLabel: _axisLabel,
                  ),
                ),
        ),
      ],
    );
  }
}

class _BandwidthChart extends StatelessWidget {
  const _BandwidthChart({
    required this.points,
    required this.formatBytes,
    required this.axisLabel,
  });
  final List<TrafficPoint> points;
  final String Function(double) formatBytes;
  final String Function(TrafficPoint) axisLabel;

  @override
  Widget build(BuildContext context) {
    final maxRx = points.fold<int>(0, (m, p) => max(m, p.rx));
    final maxTx = points.fold<int>(0, (m, p) => max(m, p.tx));
    final maxY = max(maxRx, maxTx).toDouble() * 1.1;

    final rxSpots = <FlSpot>[];
    final txSpots = <FlSpot>[];
    for (var i = 0; i < points.length; i++) {
      rxSpots.add(FlSpot(i.toDouble(), points[i].rx.toDouble()));
      txSpots.add(FlSpot(i.toDouble(), points[i].tx.toDouble()));
    }

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maxY == 0 ? 1 : maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxY > 0 ? maxY / 4 : 1,
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 60,
              getTitlesWidget: (value, meta) {
                return Text(
                  formatBytes(value),
                  style: const TextStyle(fontSize: 9, fontFamily: 'monospace'),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: max(1, (points.length / 6).ceilToDouble()),
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= points.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    axisLabel(points[i]),
                    style: const TextStyle(fontSize: 9, fontFamily: 'monospace'),
                  ),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) => spots.map((s) {
              final isRx = s.barIndex == 0;
              return LineTooltipItem(
                '${isRx ? "↓" : "↑"} ${formatBytes(s.y)}',
                TextStyle(
                  color: isRx ? Colors.green : Colors.blue,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              );
            }).toList(),
          ),
        ),
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
      ),
    );
  }
}
