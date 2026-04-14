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
  // Live mode state — delta-based per-second rate tracking
  int? _prevRxTotal;
  int? _prevTxTotal;
  DateTime? _prevPollTime;
  double _liveRxRate = 0; // bytes/sec
  double _liveTxRate = 0; // bytes/sec
  final List<double> _rxHistory = <double>[];
  final List<double> _txHistory = <double>[];

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
    _prevRxTotal = null;
    _prevTxTotal = null;
    _prevPollTime = null;
    _rxHistory.clear();
    _txHistory.clear();
    _liveRxRate = 0;
    _liveTxRate = 0;
    if (_range == _TimeRange.live) {
      _timer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _loadLiveData(),
      );
    } else {
      _timer = Timer.periodic(_range.refresh, (_) => _loadData());
    }
  }

  Future<void> _loadLiveData() async {
    if (_selectedPeer == null) return;
    try {
      final peers = await widget.client.listPeers();
      if (!mounted) return;
      final peer = peers.firstWhere(
        (p) => p.publicKey == _selectedPeer!.publicKey,
        orElse: () => _selectedPeer!,
      );
      final now = DateTime.now();
      if (_prevRxTotal != null && _prevPollTime != null) {
        final elapsedSec = now.difference(_prevPollTime!).inMilliseconds / 1000.0;
        if (elapsedSec > 0) {
          final dRx = peer.rxBytesTotal - _prevRxTotal!;
          final dTx = peer.txBytesTotal - _prevTxTotal!;
          setState(() {
            _liveRxRate = dRx < 0 ? 0 : dRx / elapsedSec;
            _liveTxRate = dTx < 0 ? 0 : dTx / elapsedSec;
            if (_rxHistory.length >= 60) _rxHistory.removeAt(0);
            if (_txHistory.length >= 60) _txHistory.removeAt(0);
            _rxHistory.add(_liveRxRate);
            _txHistory.add(_liveTxRate);
          });
        }
      }
      _prevRxTotal = peer.rxBytesTotal;
      _prevTxTotal = peer.txBytesTotal;
      _prevPollTime = now;
    } catch (_) {}
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

        // Summary cards — live rate in Live mode, totals otherwise
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
                        const Icon(Icons.arrow_downward, color: Colors.green, size: 24),
                        const SizedBox(height: 4),
                        Text(
                          _range == _TimeRange.live ? 'Download acum' : 'Download total',
                          style: theme.textTheme.labelSmall,
                        ),
                        Text(
                          _range == _TimeRange.live
                              ? '${_formatBytes(_liveRxRate)}/s'
                              : _formatBytes(totalRx.toDouble()),
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: Colors.green,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (_range == _TimeRange.live && _selectedPeer != null)
                          Text(
                            'Total: ${_formatBytes(_selectedPeer!.rxBytesTotal.toDouble())}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
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
                        const Icon(Icons.arrow_upward, color: Colors.blue, size: 24),
                        const SizedBox(height: 4),
                        Text(
                          _range == _TimeRange.live ? 'Upload acum' : 'Upload total',
                          style: theme.textTheme.labelSmall,
                        ),
                        Text(
                          _range == _TimeRange.live
                              ? '${_formatBytes(_liveTxRate)}/s'
                              : _formatBytes(totalTx.toDouble()),
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: Colors.blue,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (_range == _TimeRange.live && _selectedPeer != null)
                          Text(
                            'Total: ${_formatBytes(_selectedPeer!.txBytesTotal.toDouble())}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
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
          child: _range == _TimeRange.live
              ? (_rxHistory.length < 2
                  ? const Center(child: Text('Colectare date live…'))
                  : Padding(
                      padding: const EdgeInsets.all(16),
                      child: _LiveSparkline(
                        rxHistory: _rxHistory,
                        txHistory: _txHistory,
                        formatBytes: _formatBytes,
                      ),
                    ))
              : (points.isEmpty
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
                    )),
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

class _LiveSparkline extends StatelessWidget {
  const _LiveSparkline({
    required this.rxHistory,
    required this.txHistory,
    required this.formatBytes,
  });
  final List<double> rxHistory;
  final List<double> txHistory;
  final String Function(double) formatBytes;

  @override
  Widget build(BuildContext context) {
    final maxRate = [
      ...rxHistory,
      ...txHistory,
    ].fold<double>(0, (m, v) => v > m ? v : m);
    final maxY = maxRate == 0 ? 1.0 : maxRate * 1.1;

    final rxSpots = <FlSpot>[];
    final txSpots = <FlSpot>[];
    for (var i = 0; i < rxHistory.length; i++) {
      rxSpots.add(FlSpot(i.toDouble(), rxHistory[i]));
      txSpots.add(FlSpot(i.toDouble(), txHistory[i]));
    }

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxY / 4,
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 60,
              getTitlesWidget: (v, _) => Text(
                '${formatBytes(v)}/s',
                style: const TextStyle(fontSize: 9, fontFamily: 'monospace'),
              ),
            ),
          ),
        ),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: <LineChartBarData>[
          LineChartBarData(
            spots: rxSpots,
            color: Colors.green,
            barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: Colors.green.withValues(alpha: 0.15),
            ),
          ),
          LineChartBarData(
            spots: txSpots,
            color: Colors.blue,
            barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: Colors.blue.withValues(alpha: 0.15),
            ),
          ),
        ],
      ),
    );
  }
}
