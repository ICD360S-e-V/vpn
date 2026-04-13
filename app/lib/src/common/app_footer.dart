// ICD360SVPN — lib/src/common/app_footer.dart
//
// Status bar footer with real-time server info: service status
// indicators (WireGuard, AdGuard, nginx), uptime, agent info,
// live server clock, app version + update check.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../api/app_prefs.dart';
import '../api/notification_service.dart';
import '../api/update_service.dart';
import '../api/vpn_tunnel.dart';
import '../app.dart';
import '../models/peer.dart';
import '../features/about/changelog_screen.dart';
import '../features/updates/update_available_dialog.dart';
import '../models/health.dart';

class AppFooter extends ConsumerStatefulWidget {
  const AppFooter({super.key});

  @override
  ConsumerState<AppFooter> createState() => _AppFooterState();
}

class _AppFooterState extends ConsumerState<AppFooter> {
  String _version = '';
  bool _checking = false;
  Health? _health;
  List<Peer> _peers = const <Peer>[];
  int _livePeers = 0;
  Timer? _healthTimer;
  Timer? _clockTimer;
  DateTime? _serverTime;
  Set<String> _knownPeerKeys = const <String>{};

  @override
  void initState() {
    super.initState();
    _loadVersion();
    _healthTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _fetchHealth(),
    );
    _clockTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        if (!mounted) return;
        if (_serverTime != null) {
          _serverTime = _serverTime!.add(const Duration(seconds: 1));
        }
        setState(() {});
      },
    );
    unawaited(_fetchHealth());
  }

  @override
  void dispose() {
    _healthTimer?.cancel();
    _clockTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _version = '${info.version}+${info.buildNumber}');
    } catch (_) {
      if (!mounted) return;
      setState(() => _version = 'dev');
    }
  }

  Future<void> _fetchHealth() async {
    final phase = ref.read(appPhaseProvider);
    if (phase is! Connected) return;
    final vpnStatus = await VpnTunnel.status();
    if (vpnStatus != VpnTunnelStatus.connected) {
      if (mounted && _health != null) setState(() => _health = null);
      return;
    }
    try {
      final results = await Future.wait(<Future<dynamic>>[
        phase.client.health(),
        phase.client.listPeers(),
      ]);
      if (!mounted) return;
      final h = results[0] as Health;
      final peers = results[1] as List<Peer>;
      // Peer is "live" if last handshake < 3 minutes ago
      final now = DateTime.now().toUtc();
      final live = peers.where((p) {
        if (p.lastHandshakeAt == null) return false;
        return now.difference(p.lastHandshakeAt!).inMinutes < 3;
      }).length;
      // Detect new peers connecting (handshake started)
      final currentLiveKeys = <String>{};
      for (final p in peers) {
        if (p.lastHandshakeAt != null &&
            now.difference(p.lastHandshakeAt!).inMinutes < 3) {
          currentLiveKeys.add(p.publicKey);
        }
      }
      if (_knownPeerKeys.isNotEmpty && ref.read(notifyPeersProvider)) {
        final newlyConnected = currentLiveKeys.difference(_knownPeerKeys);
        for (final key in newlyConnected) {
          final matches = peers.where((p) => p.publicKey == key);
          if (matches.isNotEmpty) {
            unawaited(NotificationService.instance.peerConnected(matches.first.name));
          }
        }
        final newlyDisconnected = _knownPeerKeys.difference(currentLiveKeys);
        for (final key in newlyDisconnected) {
          final peer = _peers.where((p) => p.publicKey == key);
          if (peer.isNotEmpty) {
            unawaited(NotificationService.instance.peerDisconnected(peer.first.name));
          }
        }
      }
      setState(() {
        _health = h;
        _peers = peers;
        _livePeers = live;
        _serverTime = h.serverTime;
        _knownPeerKeys = currentLiveKeys;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _health = null;
        _peers = const <Peer>[];
        _livePeers = 0;
      });
    }
  }

  void _openChangelog() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ChangelogScreen()),
    );
  }

  Future<void> _checkForUpdates() async {
    if (_checking) return;
    setState(() => _checking = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(updateNotifierProvider.notifier).checkNow();
      if (!mounted) return;
      final info = ref.read(updateNotifierProvider);
      if (info != null) {
        await showDialog<void>(
          context: context,
          builder: (_) => UpdateAvailableDialog(info: info),
        );
      } else {
        messenger.showSnackBar(
          const SnackBar(duration: Duration(seconds: 3), content: Text('Ești pe ultima versiune.')),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(duration: const Duration(seconds: 4), content: Text('Verificare eșuată: $e')),
      );
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  void _showServiceDetails(String title, List<String> details) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: details.map((d) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(d, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
          )).toList(),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
  }

  void _showPeersDetails() {
    final now = DateTime.now().toUtc();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Peers (${_peers.length})'),
        content: SizedBox(
          width: 400,
          child: _peers.isEmpty
              ? const Text('Niciun peer configurat.')
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: _peers.map((p) {
                    final isLive = p.lastHandshakeAt != null &&
                        now.difference(p.lastHandshakeAt!).inMinutes < 3;
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        isLive ? Icons.circle : Icons.circle_outlined,
                        size: 12,
                        color: isLive ? Colors.green : Colors.grey,
                      ),
                      title: Text(
                        p.name.isEmpty ? '(unnamed)' : p.name,
                        style: const TextStyle(fontSize: 13),
                      ),
                      subtitle: Text(
                        '${p.allowedIPs.join(", ")}${p.endpoint != null && p.endpoint!.isNotEmpty ? " — ${p.endpoint}" : ""}',
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                      ),
                      trailing: Text(
                        isLive ? 'LIVE' : 'offline',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: isLive ? Colors.green : Colors.grey,
                        ),
                      ),
                    );
                  }).toList(),
                ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
  }

  void _showAgentDetails() {
    final h = _health;
    _showServiceDetails('VPN Agent', <String>[
      'Versiune: ${h?.agentVersion ?? "necunoscut"}',
      'Status: ${h?.status ?? "offline"}',
      'Uptime: ${h != null ? _formatUptime(h.uptimeSeconds) : "N/A"}',
      'WireGuard: ${h?.wgUp == true ? "activ" : "inactiv"}',
      'AdGuard: ${h?.adguardUp == true ? "activ" : "inactiv"}',
      'Server: ${h?.serverTime.toLocal().toString() ?? "N/A"}',
    ]);
  }

  String _formatUptime(int seconds) {
    final d = seconds ~/ 86400;
    final h = (seconds % 86400) ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    if (d > 0) return '${d}d ${h}h ${m}m';
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  String _formatClock() {
    final t = _serverTime?.toLocal() ?? DateTime.now();
    return '${t.hour.toString().padLeft(2, '0')}:'
           '${t.minute.toString().padLeft(2, '0')}:'
           '${t.second.toString().padLeft(2, '0')}';
  }

  String _formatDate() {
    final t = _serverTime?.toLocal() ?? DateTime.now();
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  }

  IconData _themeIcon(ThemeMode mode) {
    return switch (mode) {
      ThemeMode.system => Icons.brightness_auto,
      ThemeMode.light => Icons.light_mode,
      ThemeMode.dark => Icons.dark_mode,
    };
  }

  String _themeTooltip(ThemeMode mode) {
    return switch (mode) {
      ThemeMode.system => 'Temă: System',
      ThemeMode.light => 'Temă: Light',
      ThemeMode.dark => 'Temă: Dark',
    };
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delogare?'),
        content: const Text(
          'Vei pierde certificatul stocat și va trebui să faci '
          'enrollment din nou cu un cod nou.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Anulează'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delogare'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(appPhaseProvider.notifier).logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final h = _health;
    final online = h != null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant, width: 1),
        ),
      ),
      child: Row(
        children: <Widget>[
          // Service status indicators
          _StatusDot(
            label: 'WG',
            active: h?.wgUp ?? false,
            online: online,
            onTap: () => _showServiceDetails('WireGuard', <String>[
              'Status: ${h?.wgUp == true ? "activ" : "inactiv"}',
              'Interfață: wg0',
              'Port: 443/UDP',
              'Subnet: 10.8.0.0/24',
            ]),
          ),
          const SizedBox(width: 6),
          _StatusDot(
            label: 'AG',
            active: h?.adguardUp ?? false,
            online: online,
            onTap: () => _showServiceDetails('AdGuard Home', <String>[
              'Status: ${h?.adguardUp == true ? "activ" : "inactiv"}',
              'DNS: 10.8.0.1:53',
              'Web UI: 10.8.0.1:3000',
              'Upstream: Cloudflare DoH',
            ]),
          ),
          const SizedBox(width: 8),

          // Agent icon
          InkWell(
            onTap: online ? _showAgentDetails : null,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    Icons.dns,
                    size: 14,
                    color: online ? Colors.green : theme.colorScheme.outline,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    'A',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: online ? Colors.green : theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Peers
          const SizedBox(width: 6),
          InkWell(
            onTap: online ? _showPeersDetails : null,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(Icons.people, size: 14, color: online ? Colors.green : theme.colorScheme.outline),
                  const SizedBox(width: 2),
                  Text(
                    online ? '$_livePeers/${_peers.length}' : '-',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: online ? (_livePeers > 0 ? Colors.green : theme.colorScheme.onSurfaceVariant) : theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Uptime
          if (online) ...<Widget>[
            const SizedBox(width: 6),
            Text(
              '↑${_formatUptime(h.uptimeSeconds)}',
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                fontSize: 10,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],

          // Server time
          const SizedBox(width: 8),
          Text(
            _serverTime != null ? '${_formatDate()} ${_formatClock()}' : '',
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              fontSize: 10,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),

          const Spacer(),

          // Dark mode toggle
          IconButton(
            tooltip: _themeTooltip(ref.watch(themeModeProvider)),
            iconSize: 14,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(2),
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            icon: Icon(_themeIcon(ref.watch(themeModeProvider))),
            onPressed: () => ref.read(themeModeProvider.notifier).toggle(),
          ),
          const SizedBox(width: 4),

          // Logout
          IconButton(
            tooltip: 'Delogare',
            iconSize: 14,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(2),
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            icon: Icon(Icons.logout, color: theme.colorScheme.error, size: 14),
            onPressed: _confirmLogout,
          ),
          const SizedBox(width: 8),

          // Version + update
          if (_version.isNotEmpty)
            InkWell(
              onTap: _openChangelog,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Text(
                  'v$_version',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontFamily: 'monospace',
                    decoration: TextDecoration.underline,
                    decorationStyle: TextDecorationStyle.dotted,
                  ),
                ),
              ),
            ),
          IconButton(
            tooltip: 'Verifică actualizări',
            iconSize: 14,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(2),
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            icon: _checking
                ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.system_update_alt),
            onPressed: _checking ? null : _checkForUpdates,
          ),
        ],
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({
    required this.label,
    required this.active,
    required this.online,
    this.onTap,
  });
  final String label;
  final bool active;
  final bool online;
  final VoidCallback? onTap;

  IconData _themeIcon(ThemeMode mode) {
    return switch (mode) {
      ThemeMode.system => Icons.brightness_auto,
      ThemeMode.light => Icons.light_mode,
      ThemeMode.dark => Icons.dark_mode,
    };
  }

  String _themeTooltip(ThemeMode mode) {
    return switch (mode) {
      ThemeMode.system => 'Temă: System',
      ThemeMode.light => 'Temă: Light',
      ThemeMode.dark => 'Temă: Dark',
    };
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delogare?'),
        content: const Text(
          'Vei pierde certificatul stocat și va trebui să faci '
          'enrollment din nou cu un cod nou.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Anulează'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delogare'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(appPhaseProvider.notifier).logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color color;
    if (!online) {
      color = theme.colorScheme.outline;
    } else if (active) {
      color = Colors.green;
    } else {
      color = Colors.red;
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
              ),
            ),
            const SizedBox(width: 3),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 10,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
