// ICD360SVPN — lib/src/features/health/health_screen.dart
//
// Polls /v1/health every 5 seconds while the screen is mounted.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../common/status_badge.dart';
import '../../models/health.dart';

class HealthScreen extends StatefulWidget {
  const HealthScreen({super.key, required this.client});

  final ApiClient client;

  @override
  State<HealthScreen> createState() => _HealthScreenState();
}

class _HealthScreenState extends State<HealthScreen> {
  Health? _health;
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    unawaited(_fetch());
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _fetch());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _fetch() async {
    try {
      final h = await widget.client.health();
      if (!mounted) return;
      setState(() {
        _health = h;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  String _formatUptime(int seconds) {
    final d = seconds ~/ 86400;
    final h = (seconds % 86400) ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (d > 0) return '${d}d ${h}h ${m}m';
    if (h > 0) return '${h}h ${m}m ${s}s';
    return '${m}m ${s}s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Health')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_health == null && _error != null) {
      return Center(child: Text(_error!));
    }
    if (_health == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final h = _health!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Card(
          child: Column(
            children: <Widget>[
              ListTile(
                title: const Text('Overall'),
                trailing: StatusBadge.forStatus(h.status),
              ),
              const Divider(height: 1),
              ListTile(
                title: const Text('WireGuard'),
                trailing: Icon(
                  h.wgUp ? Icons.check_circle : Icons.cancel,
                  color: h.wgUp ? Colors.green : Colors.red,
                ),
              ),
              const Divider(height: 1),
              ListTile(
                title: const Text('AdGuard Home'),
                trailing: Icon(
                  h.adguardUp ? Icons.check_circle : Icons.cancel,
                  color: h.adguardUp ? Colors.green : Colors.red,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Column(
            children: <Widget>[
              ListTile(
                title: const Text('Uptime'),
                trailing: Text(
                  _formatUptime(h.uptimeSeconds),
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                title: const Text('Agent version'),
                trailing: Text(
                  h.agentVersion,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                title: const Text('Server time'),
                trailing: Text(h.serverTime.toLocal().toString()),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
