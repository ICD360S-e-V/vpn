// ICD360SVPN — lib/src/features/adguard/adguard_screen.dart
//
// AdGuard Home dashboard — blocked queries, top domains, recent
// query log. Replaces browser access to 10.8.0.1:3000.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../api/app_logger.dart';
import '../../api/vpn_tunnel.dart';
import '../../common/needs_vpn_view.dart';

class AdGuardScreen extends StatefulWidget {
  const AdGuardScreen({super.key});

  @override
  State<AdGuardScreen> createState() => _AdGuardScreenState();
}

class _AdGuardScreenState extends State<AdGuardScreen> {
  Map<String, dynamic>? _stats;
  List<dynamic>? _queries;
  bool _loading = false;
  bool _needsVpn = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final vpn = await VpnTunnel.status();
    if (vpn != VpnTunnelStatus.connected) {
      if (mounted) setState(() => _needsVpn = true);
      return;
    }
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final results = await Future.wait(<Future<dynamic>>[
        _curlJson('http://10.8.0.1:3000/control/stats'),
        _curlJson('http://10.8.0.1:3000/control/querylog?limit=20'),
      ]);
      if (!mounted) return;
      setState(() {
        _stats = results[0] as Map<String, dynamic>?;
        final ql = results[1] as Map<String, dynamic>?;
        _queries = ql?['data'] as List<dynamic>?;
        _needsVpn = false;
      });
    } catch (e) {
      appLogger.warn('AG', 'Load eșuat: $e');
      if (mounted) setState(() => _needsVpn = true);
    }
    if (mounted) setState(() => _loading = false);
  }

  static Future<Map<String, dynamic>?> _curlJson(String url) async {
    final result = await Process.run('/usr/bin/curl', <String>[
      '-s', '--connect-timeout', '5', '--max-time', '8',
      '-u', 'admin:admin',
      url,
    ]).timeout(const Duration(seconds: 10));
    if (result.exitCode != 0) return null;
    final body = (result.stdout as String).trim();
    if (body.isEmpty) return null;
    return jsonDecode(body) as Map<String, dynamic>;
  }

  @override
  Widget build(BuildContext context) {
    if (_needsVpn) {
      return NeedsVpnView(onRetry: _load, isRetrying: _loading);
    }

    final theme = Theme.of(context);
    final stats = _stats;
    final queries = _queries;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        // Stats cards
        if (stats != null) ...<Widget>[
          Row(
            children: <Widget>[
              _StatCard(
                icon: Icons.dns,
                label: 'Total queries',
                value: '${stats['num_dns_queries'] ?? 0}',
                color: Colors.blue,
              ),
              const SizedBox(width: 8),
              _StatCard(
                icon: Icons.block,
                label: 'Blocate',
                value: '${stats['num_blocked_filtering'] ?? 0}',
                subtitle: stats['num_dns_queries'] != null && (stats['num_dns_queries'] as num) > 0
                    ? '${(((stats['num_blocked_filtering'] as num?) ?? 0) / (stats['num_dns_queries'] as num) * 100).toStringAsFixed(1)}%'
                    : null,
                color: Colors.red,
              ),
              const SizedBox(width: 8),
              _StatCard(
                icon: Icons.security,
                label: 'Safe browsing',
                value: '${stats['num_replaced_safebrowsing'] ?? 0}',
                color: Colors.orange,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              _StatCard(
                icon: Icons.timer,
                label: 'Timp mediu',
                value: stats['avg_processing_time'] != null
                    ? '${((stats['avg_processing_time'] as num)).toStringAsFixed(1)}ms'
                    : '?',
                color: Colors.purple,
              ),
              const SizedBox(width: 8),
              _StatCard(
                icon: Icons.search,
                label: 'Safe search',
                value: '${stats['num_replaced_safesearch'] ?? 0}',
                color: Colors.teal,
              ),
              const SizedBox(width: 8),
              _StatCard(
                icon: Icons.family_restroom,
                label: 'Parental',
                value: '${stats['num_replaced_parental'] ?? 0}',
                color: Colors.indigo,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Top blocked domains
          if (stats['top_blocked_domains'] != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Top domenii blocate', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    ..._buildTopDomains(stats['top_blocked_domains'] as List<dynamic>),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),

          // Top queried domains
          if (stats['top_queried_domains'] != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Top domenii interogate', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    ..._buildTopList(stats['top_queried_domains'] as List<dynamic>, Colors.blue, Icons.dns),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),

          // Top clients
          if (stats['top_clients'] != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Top clienți', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    ..._buildTopList(stats['top_clients'] as List<dynamic>, Colors.green, Icons.devices),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
        ],

        // Recent queries
        if (queries != null && queries.isNotEmpty) ...<Widget>[
          Text('Interogări recente', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          ...queries.take(20).map((q) {
            final query = q as Map<String, dynamic>;
            final name = ((query['question'] as Map<String, dynamic>?)?['name'] as String?) ?? '?';
            final reason = query['reason'] as String? ?? '';
            final blocked = reason.contains('Filtered');
            final client = query['client'] as String? ?? '?';
            final time = query['time'] as String? ?? '';
            final timeShort = time.length >= 19 ? time.substring(11, 19) : time;
            return ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              leading: Icon(
                blocked ? Icons.block : Icons.check_circle_outline,
                size: 18,
                color: blocked ? Colors.red : Colors.green,
              ),
              title: Text(
                name,
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  color: blocked ? Colors.red : null,
                  decoration: blocked ? TextDecoration.lineThrough : null,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text('$client — $timeShort', style: const TextStyle(fontSize: 10)),
            );
          }),
        ],

        if (stats == null && !_loading)
          const Center(child: Text('Nu s-au putut încărca datele AdGuard.')),
        if (_loading && stats == null)
          const Center(child: Padding(
            padding: EdgeInsets.all(32),
            child: CircularProgressIndicator(),
          )),
      ],
    );
  }

  List<Widget> _buildTopDomains(List<dynamic> domains) {
    return _buildTopList(domains, Colors.red, Icons.block);
  }

  List<Widget> _buildTopList(List<dynamic> items, Color color, IconData icon) {
    final widgets = <Widget>[];
    for (final d in items.take(10)) {
      final entry = d as Map<String, dynamic>;
      final key = entry.keys.first;
      final count = entry.values.first;
      widgets.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(key, style: const TextStyle(fontFamily: 'monospace', fontSize: 11), overflow: TextOverflow.ellipsis),
            ),
            Text('$count', style: const TextStyle(fontFamily: 'monospace', fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
      ));
    }
    return widgets;
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.icon, required this.label, required this.value, required this.color, this.subtitle});
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: <Widget>[
              Icon(icon, color: color, size: 20),
              const SizedBox(height: 4),
              Text(label, style: theme.textTheme.labelSmall),
              Text(value, style: theme.textTheme.titleMedium?.copyWith(
                color: color, fontFamily: 'monospace', fontWeight: FontWeight.w700,
              )),
              if (subtitle != null)
                Text(subtitle!, style: theme.textTheme.labelSmall?.copyWith(
                  color: color, fontFamily: 'monospace',
                )),
            ],
          ),
        ),
      ),
    );
  }
}
