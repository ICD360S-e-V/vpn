// ICD360SVPN — lib/src/features/connection/connection_screen.dart
//
// Connection diagnostics dashboard inspired by ProtonVPN's
// connection info panel and Mullvad's leak check page. Shows:
//   - Current public IP
//   - DNS servers in use + leak indicator
//   - IPv6 leak indicator
//   - Overall protection status

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/app_logger.dart';
import '../../api/connection_check.dart';
import '../../api/vpn_tunnel.dart';

class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key});

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  ConnectionInfo? _info;
  bool _checking = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_runCheck());
  }

  Future<void> _runCheck() async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final vpnStatus = await VpnTunnel.status();
      final info = await ConnectionCheck.run(
        vpnActive: vpnStatus == VpnTunnelStatus.connected,
      );
      if (!mounted) return;
      setState(() => _info = info);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
      appLogger.error('CHECK', 'Verificare eșuată: $e');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Conexiune'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Reverifică',
            icon: _checking
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            onPressed: _checking ? null : _runCheck,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_error != null && _info == null) {
      return Center(child: Text(_error!));
    }
    if (_info == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final info = _info!;
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        // Overall status banner
        _ProtectionBanner(info: info),
        const SizedBox(height: 16),

        // Public IP card
        _InfoCard(
          icon: Icons.language,
          title: 'IP Public',
          trailing: _CopyableText(text: info.publicIp),
          status: info.isVpnActive ? _Status.ok : _Status.neutral,
          subtitle: info.isVpnActive
              ? 'Traficul trece prin VPN'
              : 'IP-ul real al providerului tău',
        ),
        const SizedBox(height: 12),

        // DNS card
        _DnsCard(info: info),
        const SizedBox(height: 12),

        // IPv6 card
        _InfoCard(
          icon: Icons.router,
          title: 'IPv6',
          status: info.isIpv6Leaking
              ? _Status.error
              : (info.ipv6Detected ? _Status.warning : _Status.ok),
          subtitle: info.isIpv6Leaking
              ? 'LEAK — IPv6 detectat: ${info.ipv6Address}'
              : (info.ipv6Detected
                  ? 'IPv6 activ (VPN oprit)'
                  : 'IPv6 blocat — fără leak'),
          trailing: Icon(
            info.isIpv6Leaking
                ? Icons.warning_amber
                : Icons.check_circle_outline,
            color: info.isIpv6Leaking ? Colors.red : Colors.green,
          ),
        ),
        const SizedBox(height: 12),

        // DNS encryption info card
        _InfoCard(
          icon: Icons.lock_outline,
          title: 'Criptare DNS',
          status: info.isDnsSafe ? _Status.ok : _Status.neutral,
          subtitle: info.isDnsSafe
              ? 'DoH activ — DNS queries criptate prin Quad9'
              : 'DNS-ul nu trece prin VPN',
          trailing: Icon(
            info.isDnsSafe ? Icons.verified_outlined : Icons.lock_open,
            color: info.isDnsSafe ? Colors.green : theme.colorScheme.outline,
          ),
        ),

        if (_checking)
          const Padding(
            padding: EdgeInsets.only(top: 24),
            child: Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }
}

// --- Helper widgets ---

enum _Status { ok, warning, error, neutral }

class _ProtectionBanner extends StatelessWidget {
  const _ProtectionBanner({required this.info});
  final ConnectionInfo info;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color bg;
    final Color fg;
    final IconData icon;
    final String text;

    if (!info.isVpnActive) {
      bg = theme.colorScheme.surfaceContainerHighest;
      fg = theme.colorScheme.onSurface;
      icon = Icons.shield_outlined;
      text = 'VPN deconectat — traficul nu este protejat';
    } else if (info.isFullyProtected) {
      bg = Colors.green.shade50;
      fg = Colors.green.shade900;
      icon = Icons.shield;
      text = 'Conexiune protejată — fără leak-uri detectate';
    } else {
      bg = Colors.orange.shade50;
      fg = Colors.orange.shade900;
      icon = Icons.shield;
      text = 'VPN activ — dar au fost detectate leak-uri!';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, color: fg, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.titleMedium?.copyWith(color: fg),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.status,
    required this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final _Status status;
  final String subtitle;
  final Widget? trailing;

  Color _statusColor(BuildContext context) {
    return switch (status) {
      _Status.ok => Colors.green,
      _Status.warning => Colors.orange,
      _Status.error => Colors.red,
      _Status.neutral => Theme.of(context).colorScheme.outline,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: <Widget>[
            Icon(icon, color: _statusColor(context), size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

class _DnsCard extends StatelessWidget {
  const _DnsCard({required this.info});
  final ConnectionInfo info;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.dns,
                  color: info.isDnsSafe ? Colors.green : Colors.orange,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('Servere DNS', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 4),
                      Text(
                        info.isDnsSafe
                            ? 'Toate query-urile trec prin AdGuard Home'
                            : 'ATENȚIE — DNS leak detectat!',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: info.isDnsSafe
                              ? theme.colorScheme.onSurfaceVariant
                              : Colors.orange.shade800,
                          fontWeight:
                              info.isDnsSafe ? null : FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
            ...info.dnsServers.map((server) {
              final isSafe = server == '10.8.0.1';
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: <Widget>[
                    Icon(
                      isSafe ? Icons.check_circle : Icons.warning_amber,
                      size: 16,
                      color: isSafe ? Colors.green : Colors.orange,
                    ),
                    const SizedBox(width: 8),
                    _CopyableText(text: server),
                    const SizedBox(width: 8),
                    Text(
                      isSafe ? 'AdGuard (VPN)' : 'extern — leak!',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isSafe
                            ? Colors.green
                            : Colors.orange.shade800,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _CopyableText extends StatelessWidget {
  const _CopyableText({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () {
        Clipboard.setData(ClipboardData(text: text));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 2),
            content: Text('Copiat: $text'),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Text(
          text,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
