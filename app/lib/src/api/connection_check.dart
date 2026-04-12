// ICD360SVPN — lib/src/api/connection_check.dart
//
// Lightweight connection diagnostics — public IP detection, DNS
// server discovery, and leak checks. Follows industry best
// practices for VPN leak detection and connection
// diagnostics.
//
// Uses plain dart:io HttpClient (not the mTLS Dio instance) so
// it works regardless of whether the agent is reachable.

import 'dart:convert';
import 'dart:io';

import 'app_logger.dart';

class ConnectionInfo {
  const ConnectionInfo({
    required this.publicIp,
    required this.dnsServers,
    required this.isVpnActive,
    required this.ipv6Detected,
    this.ipv6Address,
  });

  /// Current public-facing IP address.
  final String publicIp;

  /// DNS servers the OS is configured to use right now.
  final List<String> dnsServers;

  /// Whether the VPN tunnel appears to be active.
  final bool isVpnActive;

  /// True if an IPv6 address was detected (potential leak).
  final bool ipv6Detected;

  /// The detected IPv6 address, if any.
  final String? ipv6Address;

  /// DNS is safe when ALL resolvers point to the VPN DNS (10.8.0.1).
  bool get isDnsSafe =>
      dnsServers.isNotEmpty &&
      dnsServers.every((s) => s == '10.8.0.1');

  /// IPv6 is leaking if we detect a public IPv6 while the VPN is up.
  bool get isIpv6Leaking => isVpnActive && ipv6Detected;

  /// Overall protection score.
  bool get isFullyProtected => isVpnActive && isDnsSafe && !isIpv6Leaking;
}

class ConnectionCheck {
  static const _timeout = Duration(seconds: 8);

  /// Run all checks and return a snapshot.
  static Future<ConnectionInfo> run({required bool vpnActive}) async {
    appLogger.info('CHECK', 'Pornire verificare conexiune…');
    final results = await Future.wait(<Future<dynamic>>[
      _detectPublicIp(),
      _detectDnsServers(),
      _detectIpv6(),
    ]);
    final ip = results[0] as String;
    final dns = results[1] as List<String>;
    final ipv6 = results[2] as (bool, String?);

    final info = ConnectionInfo(
      publicIp: ip,
      dnsServers: dns,
      isVpnActive: vpnActive,
      ipv6Detected: ipv6.$1,
      ipv6Address: ipv6.$2,
    );

    appLogger.info('CHECK', 'IP public: $ip');
    appLogger.info('CHECK', 'DNS: ${dns.join(", ")}');
    if (info.isDnsSafe) {
      appLogger.info('CHECK', 'DNS OK — toate query-urile prin AdGuard');
    } else {
      appLogger.warn('CHECK', 'DNS LEAK — servere externe detectate!');
    }
    if (info.isIpv6Leaking) {
      appLogger.warn('CHECK', 'IPv6 LEAK — ${ipv6.$2}');
    }

    return info;
  }

  /// Detect public IP via ipify (supports v4 and v6).
  static Future<String> _detectPublicIp() async {
    try {
      final client = HttpClient()
        ..connectionTimeout = _timeout;
      final req = await client.getUrl(
        Uri.parse('https://api.ipify.org?format=json'),
      );
      final resp = await req.close().timeout(_timeout);
      final body = await resp.transform(utf8.decoder).join();
      client.close(force: true);
      final json = jsonDecode(body) as Map<String, dynamic>;
      return (json['ip'] as String?) ?? 'necunoscut';
    } catch (e) {
      appLogger.error('CHECK', 'Nu am putut detecta IP-ul public: $e');
      return 'eroare';
    }
  }

  /// Read DNS servers from scutil (macOS) or resolv.conf (Linux).
  static Future<List<String>> _detectDnsServers() async {
    try {
      if (Platform.isMacOS) {
        return _detectDnsMacOS();
      } else if (Platform.isLinux) {
        return _detectDnsLinux();
      }
      return <String>['platformă nesuportată'];
    } catch (e) {
      appLogger.error('CHECK', 'Nu am putut detecta DNS: $e');
      return <String>['eroare'];
    }
  }

  static Future<List<String>> _detectDnsMacOS() async {
    final result = await Process.run('/usr/sbin/scutil', <String>['--dns']);
    if (result.exitCode != 0) return <String>['eroare scutil'];
    final lines = (result.stdout as String).split('\n');
    final servers = <String>{};
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('nameserver[')) {
        // Format: "nameserver[0] : 10.8.0.1"
        final parts = trimmed.split(':');
        if (parts.length >= 2) {
          final ip = parts.sublist(1).join(':').trim();
          if (ip.isNotEmpty) servers.add(ip);
        }
      }
    }
    return servers.toList();
  }

  static Future<List<String>> _detectDnsLinux() async {
    try {
      final file = File('/etc/resolv.conf');
      if (!await file.exists()) return <String>['resolv.conf lipsă'];
      final lines = await file.readAsLines();
      final servers = <String>[];
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.startsWith('nameserver ')) {
          servers.add(trimmed.substring(11).trim());
        }
      }
      return servers;
    } catch (e) {
      return <String>['eroare: $e'];
    }
  }

  /// Check for IPv6 connectivity by trying to reach an IPv6-only
  /// endpoint. If it responds, IPv6 is active (potential leak if
  /// VPN is up but doesn't tunnel IPv6).
  static Future<(bool, String?)> _detectIpv6() async {
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 4);
      final req = await client.getUrl(
        Uri.parse('https://api64.ipify.org?format=json'),
      );
      final resp = await req.close().timeout(const Duration(seconds: 5));
      final body = await resp.transform(utf8.decoder).join();
      client.close(force: true);
      final json = jsonDecode(body) as Map<String, dynamic>;
      final ip = (json['ip'] as String?) ?? '';
      // If the returned IP contains ":" it's an IPv6 address.
      if (ip.contains(':')) {
        return (true, ip);
      }
      return (false, null);
    } catch (_) {
      // Timeout or failure means no IPv6 connectivity — good.
      return (false, null);
    }
  }
}
