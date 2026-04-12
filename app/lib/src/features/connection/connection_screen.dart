// ICD360SVPN — lib/src/features/connection/connection_screen.dart
//
// Status diagnostics dashboard. Shows public IP (v4+v6), DNS
// servers with leak indicator, IPv6 leak status, DNS encryption.

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
        title: const Text('Status'),
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
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        _ProtectionBanner(info: info),
        const SizedBox(height: 16),
        _IpCard(info: info),
        const SizedBox(height: 12),
        _DnsCard(info: info),
        const SizedBox(height: 12),
        _Ipv6Card(info: info),
        const SizedBox(height: 12),
        _DnsEncryptionCard(info: info),
        if (_checking)
          const Padding(
            padding: EdgeInsets.only(top: 24),
            child: Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }
}

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
            child: Text(text, style: theme.textTheme.titleMedium?.copyWith(color: fg)),
          ),
        ],
      ),
    );
  }
}

class _IpCard extends StatelessWidget {
  const _IpCard({required this.info});
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
                Icon(Icons.language, color: info.isVpnActive ? Colors.green : theme.colorScheme.outline, size: 28),
                const SizedBox(width: 12),
                Text('IP Public', style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
            _IpDetail(
              label: 'IPv4',
              ipInfo: info.ipv4,
              badge: info.isVpnActive ? 'VPN' : null,
            ),
            const SizedBox(height: 10),
            _IpDetail(
              label: 'IPv6',
              ipInfo: info.ipv6,
              badge: info.isIpv6Leaking ? 'LEAK!' : null,
              badgeColor: Colors.red,
            ),
          ],
        ),
      ),
    );
  }
}

class _IpDetail extends StatelessWidget {
  const _IpDetail({required this.label, required this.ipInfo, this.badge, this.badgeColor});
  final String label;
  final IpInfo ipInfo;
  final String? badge;
  final Color? badgeColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEmpty = ipInfo.isEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            SizedBox(
              width: 40,
              child: Text(label, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: theme.colorScheme.onSurfaceVariant)),
            ),
            const SizedBox(width: 8),
            Expanded(child: _CopyableText(text: isEmpty ? 'nedisponibil' : ipInfo.ip)),
            if (badge != null) ...<Widget>[
              const SizedBox(width: 8),
              Text(badge!, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: badgeColor ?? Colors.green.shade700)),
            ],
          ],
        ),
        if (!isEmpty && ipInfo.isp.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 48, top: 2),
            child: Text(
              ipInfo.isp,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
          ),
        if (!isEmpty && ipInfo.hostname.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 48, top: 1),
            child: Text(
              ipInfo.hostname,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ),
      ],
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
                Icon(Icons.dns, color: info.isDnsSafe ? Colors.green : (info.isVpnActive ? Colors.orange : theme.colorScheme.outline), size: 28),
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
                            : (info.isVpnActive ? 'ATENȚIE — DNS leak detectat!' : 'DNS de la provider (VPN oprit)'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: info.isVpnActive && !info.isDnsSafe ? Colors.orange.shade800 : theme.colorScheme.onSurfaceVariant,
                          fontWeight: info.isVpnActive && !info.isDnsSafe ? FontWeight.w600 : null,
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
            if (info.dnsServersV4.isNotEmpty) ...<Widget>[
              Text('IPv4', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 4),
              ...info.dnsServersV4.map((s) => _DnsRow(server: s)),
              const SizedBox(height: 8),
            ],
            if (info.dnsServersV6.isNotEmpty) ...<Widget>[
              Text('IPv6', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 4),
              ...info.dnsServersV6.map((s) => _DnsRow(server: s)),
            ],
          ],
        ),
      ),
    );
  }
}

class _DnsRow extends StatelessWidget {
  const _DnsRow({required this.server});
  final String server;

  @override
  Widget build(BuildContext context) {
    final isSafe = server == '10.8.0.1';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: <Widget>[
          Icon(isSafe ? Icons.check_circle : Icons.warning_amber, size: 16, color: isSafe ? Colors.green : Colors.orange),
          const SizedBox(width: 8),
          _CopyableText(text: server),
          const SizedBox(width: 8),
          Text(isSafe ? 'AdGuard (VPN)' : 'extern', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: isSafe ? Colors.green : Colors.orange.shade800)),
        ],
      ),
    );
  }
}

class _Ipv6Card extends StatelessWidget {
  const _Ipv6Card({required this.info});
  final ConnectionInfo info;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final String subtitle;
    final Color iconColor;
    final IconData icon;

    if (info.isVpnActive && !info.hasIpv6) {
      subtitle = 'Blocat — nicio adresă IPv6 vizibilă';
      iconColor = Colors.green;
      icon = Icons.check_circle_outline;
    } else if (info.isIpv6Leaking) {
      subtitle = 'LEAK — adresa IPv6 a providerului este vizibilă: ${info.ipv6.ip}';
      iconColor = Colors.red;
      icon = Icons.warning_amber;
    } else if (info.hasIpv6) {
      subtitle = 'Adresa IPv6 a providerului: ${info.ipv6.ip}';
      iconColor = theme.colorScheme.outline;
      icon = Icons.info_outline;
    } else {
      subtitle = 'Providerul nu oferă IPv6';
      iconColor = theme.colorScheme.outline;
      icon = Icons.info_outline;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: <Widget>[
            Icon(Icons.router, color: iconColor, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('IPv6', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(
                    color: info.isIpv6Leaking ? Colors.red.shade800 : theme.colorScheme.onSurfaceVariant,
                  )),
                ],
              ),
            ),
            Icon(icon, color: iconColor),
          ],
        ),
      ),
    );
  }
}

class _DnsEncryptionCard extends StatelessWidget {
  const _DnsEncryptionCard({required this.info});
  final ConnectionInfo info;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool encrypted = info.isVpnActive && info.isDnsSafe;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: <Widget>[
            Icon(encrypted ? Icons.lock_outline : Icons.lock_open, color: encrypted ? Colors.green : theme.colorScheme.outline, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('Criptare DNS', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                    encrypted
                        ? 'DoH activ — DNS queries criptate prin Quad9'
                        : (info.isVpnActive ? 'DNS nu trece complet prin VPN' : 'Necriptat — conectează-te la VPN'),
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
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
          SnackBar(duration: const Duration(seconds: 2), content: Text('Copiat: $text')),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Text(text, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w500)),
      ),
    );
  }
}
