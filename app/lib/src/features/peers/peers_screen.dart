// ICD360SVPN — lib/src/features/peers/peers_screen.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/api_client.dart';
import '../../api/app_logger.dart';
import '../../api/vpn_tunnel.dart';
import '../../common/needs_vpn_view.dart';
import '../../models/api_error.dart';
import '../../models/peer.dart';
import 'create_peer_dialog.dart';
import 'peer_tile.dart';

class PeersScreen extends StatefulWidget {
  const PeersScreen({super.key, required this.client});

  final ApiClient client;

  @override
  State<PeersScreen> createState() => _PeersScreenState();
}

class _PeersScreenState extends State<PeersScreen> {
  List<Peer> _peers = const <Peer>[];
  bool _loading = false;
  String? _error;
  bool _needsVpn = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _timer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => unawaited(_load()),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    // Check VPN status first — don't waste 10s on a timeout
    // when we already know the tunnel is down.
    final vpnStatus = await VpnTunnel.status();
    if (vpnStatus != VpnTunnelStatus.connected) {
      if (!mounted) return;
      appLogger.info('PEERS', 'VPN deconectat — se așteaptă conexiunea');
      setState(() {
        _needsVpn = true;
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final peers = await widget.client.listPeers();
      if (!mounted) return;
      setState(() {
        _peers = peers;
        _error = null;
        _needsVpn = false;
      });
    } on ApiError catch (e) {
      if (!mounted) return;
      appLogger.warn('PEERS', 'Eroare: ${e.message}');
      setState(() {
        _needsVpn = e.kind == ApiErrorKind.transport;
        _error = _needsVpn ? null : e.message;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleEnabled(Peer peer, bool value) async {
    try {
      await widget.client.setPeerEnabled(
        publicKey: peer.publicKey,
        enabled: value,
      );
      await _load();
    } on ApiError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Toggle failed: ${e.message}')),
      );
    }
  }

  Future<void> _delete(Peer peer) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revoke peer?'),
        content: Text(
          '"${peer.name.isEmpty ? "(unnamed)" : peer.name}" will be removed '
          'from the server immediately. Existing client devices will fail '
          'to reconnect.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.client.deletePeer(publicKey: peer.publicKey);
      await _load();
    } on ApiError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: ${e.message}')),
      );
    }
  }

  Future<void> _openCreate() async {
    await showDialog<void>(
      context: context,
      builder: (_) => CreatePeerDialog(client: widget.client),
    );
    await _load();
  }

  void _copyPubkey(Peer peer) {
    Clipboard.setData(ClipboardData(text: peer.publicKey));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Public key copied')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Peers'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
          ),
          IconButton(
            icon: const Icon(Icons.person_add),
            tooltip: 'New peer',
            onPressed: _openCreate,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_needsVpn && _peers.isEmpty) {
      return NeedsVpnView(onRetry: _load, isRetrying: _loading);
    }
    if (_error != null && _peers.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.wifi_off, size: 32),
            const SizedBox(height: 8),
            Text(_error!),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_loading && _peers.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_peers.isEmpty) {
      return const Center(
        child: Text('No peers yet. Tap + to add the first one.'),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _peers.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final peer = _peers[i];
          return PeerTile(
            peer: peer,
            onToggle: (v) => _toggleEnabled(peer, v),
            onDelete: () => _delete(peer),
            onCopyPubkey: () => _copyPubkey(peer),
          );
        },
      ),
    );
  }
}
