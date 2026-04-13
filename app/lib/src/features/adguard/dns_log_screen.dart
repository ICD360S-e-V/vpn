// ICD360SVPN — lib/src/features/adguard/dns_log_screen.dart
//
// Full DNS query log with search, filtering (blocked/allowed/all),
// pagination (load more), and detail view. Uses AdGuard Home API
// GET /control/querylog with older_than for paging.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../api/app_logger.dart';
import '../../api/vpn_tunnel.dart';

enum DnsFilter { all, blocked, allowed }

class DnsLogScreen extends StatefulWidget {
  const DnsLogScreen({super.key});

  @override
  State<DnsLogScreen> createState() => _DnsLogScreenState();
}

class _DnsLogScreenState extends State<DnsLogScreen> {
  final List<Map<String, dynamic>> _entries = <Map<String, dynamic>>[];
  bool _loading = false;
  bool _hasMore = true;
  String? _oldest;
  DnsFilter _filter = DnsFilter.all;
  final TextEditingController _searchCtrl = TextEditingController();
  String _search = '';
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    unawaited(_loadMore());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadMore() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final vpn = await VpnTunnel.status();
      if (vpn != VpnTunnelStatus.connected) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('VPN nu este conectat.')),
          );
        }
        return;
      }

      var url = 'http://10.8.0.1:3000/control/querylog?limit=50';
      if (_oldest != null) {
        url += '&older_than=${Uri.encodeComponent(_oldest!)}';
      }
      if (_search.isNotEmpty) {
        url += '&search=${Uri.encodeComponent(_search)}';
      }
      final responseStatus = switch (_filter) {
        DnsFilter.blocked => '&response_status=blocked',
        DnsFilter.allowed => '&response_status=whitelisted',
        DnsFilter.all => '',
      };
      url += responseStatus;

      final result = await Process.run('/usr/bin/curl', <String>[
        '-s', '--connect-timeout', '5', '--max-time', '10',
        '-u', 'admin:admin',
        url,
      ]).timeout(const Duration(seconds: 12));

      if (result.exitCode != 0 || !mounted) return;
      final body = (result.stdout as String).trim();
      if (body.isEmpty) return;

      final json = jsonDecode(body) as Map<String, dynamic>;
      final data = json['data'] as List<dynamic>? ?? <dynamic>[];
      final oldest = json['oldest'] as String?;

      if (!mounted) return;
      setState(() {
        for (final d in data) {
          _entries.add(d as Map<String, dynamic>);
        }
        _oldest = oldest;
        _hasMore = data.length >= 50;
      });
    } catch (e) {
      appLogger.warn('DNS', 'Query log load eșuat: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _refresh() {
    setState(() {
      _entries.clear();
      _oldest = null;
      _hasMore = true;
    });
    unawaited(_loadMore());
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _search = value.trim();
      _refresh();
    });
  }

  void _onFilterChanged(DnsFilter f) {
    _filter = f;
    _refresh();
  }

  void _showDetail(Map<String, dynamic> entry) {
    final question = entry['question'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final name = (question['name'] as String?) ?? '?';
    final qType = (question['type'] as String?) ?? '?';
    final client = (entry['client'] as String?) ?? '?';
    final reason = (entry['reason'] as String?) ?? '';
    final upstream = (entry['upstream'] as String?) ?? '';
    final cached = entry['cached'] == true;
    final time = (entry['time'] as String?) ?? '';
    final elapsedMs = (entry['elapsedMs'] as num?)?.toStringAsFixed(1) ?? '?';
    final answers = entry['answer'] as List<dynamic>? ?? <dynamic>[];

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(name, style: const TextStyle(fontFamily: 'monospace', fontSize: 14)),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _DetailRow('Tip', qType),
                _DetailRow('Client', client),
                _DetailRow('Status', reason.isEmpty ? 'Allowed' : reason),
                _DetailRow('Upstream', upstream.isEmpty ? '-' : upstream),
                _DetailRow('Cached', cached ? 'Da' : 'Nu'),
                _DetailRow('Timp răspuns', '${elapsedMs}ms'),
                _DetailRow('Timestamp', time),
                if (answers.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 8),
                  const Text('Răspunsuri:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                  const SizedBox(height: 4),
                  ...answers.map((a) {
                    final ans = a as Map<String, dynamic>;
                    final type = (ans['type'] as String?) ?? '?';
                    final value = (ans['value'] as String?) ?? '?';
                    final ttl = ans['ttl'] as num? ?? 0;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        '$type → $value (TTL: $ttl)',
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: <Widget>[
        // Search + filter bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.search, size: 18),
                    hintText: 'Caută domeniu sau IP client…',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  style: const TextStyle(fontSize: 13),
                  onChanged: _onSearchChanged,
                ),
              ),
              const SizedBox(width: 8),
              SegmentedButton<DnsFilter>(
                segments: const <ButtonSegment<DnsFilter>>[
                  ButtonSegment<DnsFilter>(value: DnsFilter.all, label: Text('Toate')),
                  ButtonSegment<DnsFilter>(value: DnsFilter.blocked, label: Text('Blocate')),
                  ButtonSegment<DnsFilter>(value: DnsFilter.allowed, label: Text('Permise')),
                ],
                selected: <DnsFilter>{_filter},
                onSelectionChanged: (s) => _onFilterChanged(s.first),
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  textStyle: WidgetStatePropertyAll<TextStyle>(
                    theme.textTheme.labelSmall!,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Reîncarcă',
                icon: const Icon(Icons.refresh),
                onPressed: _loading ? null : _refresh,
              ),
            ],
          ),
        ),
        // Entries list
        Expanded(
          child: _entries.isEmpty && _loading
              ? const Center(child: CircularProgressIndicator())
              : _entries.isEmpty
                  ? Center(
                      child: Text(
                        'Nicio interogare DNS găsită.',
                        style: theme.textTheme.bodyMedium,
                      ),
                    )
                  : ListView.builder(
                      itemCount: _entries.length + (_hasMore ? 1 : 0),
                      itemBuilder: (_, i) {
                        if (i == _entries.length) {
                          // Load more button
                          return Padding(
                            padding: const EdgeInsets.all(16),
                            child: Center(
                              child: _loading
                                  ? const CircularProgressIndicator()
                                  : OutlinedButton(
                                      onPressed: _loadMore,
                                      child: const Text('Încarcă mai multe'),
                                    ),
                            ),
                          );
                        }
                        final entry = _entries[i];
                        return _QueryTile(
                          entry: entry,
                          onTap: () => _showDetail(entry),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

class _QueryTile extends StatelessWidget {
  const _QueryTile({required this.entry, required this.onTap});
  final Map<String, dynamic> entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final question = entry['question'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final name = ((question['name'] as String?) ?? '?');
    final qType = (question['type'] as String?) ?? '';
    final client = (entry['client'] as String?) ?? '?';
    final reason = (entry['reason'] as String?) ?? '';
    final blocked = reason.contains('Filtered');
    final cached = entry['cached'] == true;
    final time = (entry['time'] as String?) ?? '';
    final timeShort = time.length >= 19 ? time.substring(11, 19) : time;
    final upstream = (entry['upstream'] as String?) ?? '';

    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      onTap: onTap,
      leading: Icon(
        blocked ? Icons.block : (cached ? Icons.cached : Icons.check_circle_outline),
        size: 18,
        color: blocked ? Colors.red : (cached ? Colors.orange : Colors.green),
      ),
      title: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              name,
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: blocked ? Colors.red : null,
                decoration: blocked ? TextDecoration.lineThrough : null,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (qType.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(left: 4),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(qType, style: const TextStyle(fontSize: 9, fontFamily: 'monospace')),
            ),
        ],
      ),
      subtitle: Row(
        children: <Widget>[
          Text(client, style: const TextStyle(fontSize: 10, fontFamily: 'monospace')),
          const SizedBox(width: 6),
          Text(timeShort, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
          if (upstream.isNotEmpty) ...<Widget>[
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                upstream,
                style: TextStyle(fontSize: 9, color: Colors.grey.shade500),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
      trailing: Icon(
        Icons.chevron_right,
        size: 16,
        color: Theme.of(context).colorScheme.outline,
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 110,
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
