// ICD360SVPN — lib/src/features/peers/peer_tile.dart

import 'package:flutter/material.dart';

import '../../models/peer.dart';

class PeerTile extends StatelessWidget {
  const PeerTile({
    super.key,
    required this.peer,
    required this.onToggle,
    required this.onDelete,
    required this.onCopyPubkey,
  });

  final Peer peer;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;
  final VoidCallback onCopyPubkey;

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KiB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MiB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GiB';
  }

  String _truncatePubkey(String s) {
    if (s.length <= 16) return s;
    return '${s.substring(0, 8)}…${s.substring(s.length - 8)}';
  }

  String _handshakeText() {
    final hs = peer.lastHandshakeAt;
    if (hs == null) return 'never connected';
    final diff = DateTime.now().toUtc().difference(hs.toUtc());
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      isThreeLine: true,
      leading: CircleAvatar(
        backgroundColor: peer.enabled
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerHighest,
        child: Icon(
          Icons.person,
          color: peer.enabled
              ? theme.colorScheme.onPrimaryContainer
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
      title: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              peer.name.isEmpty ? '(unnamed)' : peer.name,
              style: theme.textTheme.titleMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (!peer.enabled)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'SUSPENDED',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SizedBox(height: 4),
          Text(
            _truncatePubkey(peer.publicKey),
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${peer.allowedIPs.join(", ")}'
            '${peer.endpoint != null ? "  ·  ${peer.endpoint}" : ""}'
            '  ·  ↓${_formatBytes(peer.rxBytesTotal)}'
            '  ·  ↑${_formatBytes(peer.txBytesTotal)}'
            '  ·  ${_handshakeText()}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Switch(value: peer.enabled, onChanged: onToggle),
          PopupMenuButton<String>(
            onSelected: (v) {
              switch (v) {
                case 'copy':
                  onCopyPubkey();
                case 'delete':
                  onDelete();
              }
            },
            itemBuilder: (_) => const <PopupMenuEntry<String>>[
              PopupMenuItem<String>(value: 'copy', child: Text('Copy public key')),
              PopupMenuDivider(),
              PopupMenuItem<String>(
                value: 'delete',
                child: Text('Revoke…',
                    style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
