// ICD360SVPN — lib/src/features/connection/connection_history_screen.dart
//
// Shows VPN connection history with timestamps and session durations.
// Also shows peer device info detected from peer names.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/connection_history.dart';

class ConnectionHistoryScreen extends StatefulWidget {
  const ConnectionHistoryScreen({super.key});

  @override
  State<ConnectionHistoryScreen> createState() => _ConnectionHistoryScreenState();
}

class _ConnectionHistoryScreenState extends State<ConnectionHistoryScreen> {
  List<ConnectionRecord> _records = <ConnectionRecord>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final records = await ConnectionHistory.instance.loadAll();
    if (mounted) {
      setState(() {
        _records = records;
        _loading = false;
      });
    }
  }

  String _formatDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) return '${h}h ${m}m ${s}s';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_records.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.history, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 8),
            const Text('Niciun eveniment înregistrat.'),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _records.length,
      itemBuilder: (_, i) {
        final r = _records[i];
        final t = r.timestamp.toLocal();
        final date = '${t.year}-${t.month.toString().padLeft(2, '0')}-'
            '${t.day.toString().padLeft(2, '0')}';
        final time = '${t.hour.toString().padLeft(2, '0')}:'
            '${t.minute.toString().padLeft(2, '0')}:'
            '${t.second.toString().padLeft(2, '0')}';
        final isConnect = r.event == ConnectionEvent.connected;

        return ListTile(
          dense: true,
          leading: Icon(
            isConnect ? Icons.vpn_lock : Icons.vpn_lock_outlined,
            color: isConnect ? Colors.green : Colors.red,
            size: 20,
          ),
          title: Text(
            isConnect ? 'VPN Conectat' : 'VPN Deconectat',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isConnect ? Colors.green : Colors.red,
            ),
          ),
          subtitle: Text(
            '$date $time'
            '${r.durationSeconds != null ? '  •  Sesiune: ${_formatDuration(r.durationSeconds!)}' : ''}',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
          ),
        );
      },
    );
  }
}
