// ICD360SVPN — lib/src/features/health/health_screen.dart
//
// Polls /v1/health every 5 seconds while the screen is mounted.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../api/app_logger.dart';
import '../../api/vpn_tunnel.dart';
import '../../common/needs_vpn_view.dart';
import '../../common/status_badge.dart';
import '../../models/api_error.dart';
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
  bool _needsVpn = false;
  bool _fetching = false;
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
    if (_fetching) return;
    // Check VPN status first — show "connect to VPN" instantly
    // instead of waiting 10s for a timeout.
    final vpnStatus = await VpnTunnel.status();
    if (vpnStatus != VpnTunnelStatus.connected) {
      if (!mounted) return;
      setState(() {
        _needsVpn = true;
        _fetching = false;
      });
      return;
    }
    setState(() => _fetching = true);
    try {
      final h = await widget.client.health();
      if (!mounted) return;
      setState(() {
        _health = h;
        _error = null;
        _needsVpn = false;
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      appLogger.warn('HEALTH', 'Eroare: ${e.message}');
      setState(() {
        _needsVpn = e.kind == ApiErrorKind.transport;
        _error = _needsVpn ? null : e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _fetching = false);
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
    if (_health == null && _needsVpn) {
      return NeedsVpnView(onRetry: _fetch, isRetrying: _fetching);
    }
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
