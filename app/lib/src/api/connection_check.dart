// ICD360SVPN — lib/src/api/connection_check.dart
//
// Lightweight connection diagnostics — public IP detection, DNS
// server discovery, and leak checks.
//
// Uses Process.run with curl/scutil instead of dart:io HttpClient
// because macOS blocks direct network access from unsigned apps.

import 'dart:io';

import 'app_logger.dart';

class ConnectionInfo {
  const ConnectionInfo({
    required this.publicIpv4,
    required this.publicIpv6,
    required this.dnsServersV4,
    required this.dnsServersV6,
    required this.isVpnActive,
  });

  final String publicIpv4;
  final String publicIpv6;
  final List<String> dnsServersV4;
  final List<String> dnsServersV6;
  final bool isVpnActive;

  List<String> get allDnsServers => [...dnsServersV4, ...dnsServersV6];

  bool get isDnsSafe =>
      allDnsServers.isNotEmpty &&
      allDnsServers.every((s) => s == '10.8.0.1');

  bool get hasIpv6 => publicIpv6 != 'nu' && publicIpv6 != 'eroare';

  bool get isIpv6Leaking => isVpnActive && hasIpv6;

  bool get isFullyProtected => isVpnActive && isDnsSafe && !isIpv6Leaking;
}

class ConnectionCheck {
  /// Run all checks and return a snapshot.
  static Future<ConnectionInfo> run({required bool vpnActive}) async {
    appLogger.info('CHECK', 'Pornire verificare conexiune…');
    final results = await Future.wait(<Future<dynamic>>[
      _detectIpv4(),
      _detectIpv6(),
      _detectDnsServers(),
    ]);
    final ipv4 = results[0] as String;
    final ipv6 = results[1] as String;
    final dns = results[2] as (List<String>, List<String>);

    final info = ConnectionInfo(
      publicIpv4: ipv4,
      publicIpv6: ipv6,
      dnsServersV4: dns.$1,
      dnsServersV6: dns.$2,
      isVpnActive: vpnActive,
    );

    appLogger.info('CHECK', 'IPv4: $ipv4');
    appLogger.info('CHECK', 'IPv6: $ipv6');
    appLogger.info('CHECK', 'DNS v4: ${dns.$1.join(", ")}');
    if (dns.$2.isNotEmpty) {
      appLogger.info('CHECK', 'DNS v6: ${dns.$2.join(", ")}');
    }
    if (info.isDnsSafe) {
      appLogger.info('CHECK', 'DNS OK — toate query-urile prin AdGuard');
    } else if (vpnActive) {
      appLogger.warn('CHECK', 'DNS LEAK — servere externe detectate!');
    }
    if (info.isIpv6Leaking) {
      appLogger.warn('CHECK', 'IPv6 LEAK — $ipv6');
    }

    return info;
  }

  /// Detect public IPv4 via curl to ipify (IPv4-only endpoint).
  /// Uses curl because dart:io HttpClient is blocked on unsigned macOS apps.
  static Future<String> _detectIpv4() async {
    try {
      final result = await Process.run('/usr/bin/curl', <String>[
        '-s', '--connect-timeout', '8', '--max-time', '10',
        '-4', 'https://api.ipify.org',
      ]).timeout(const Duration(seconds: 12));
      if (result.exitCode != 0) {
        appLogger.error('CHECK', 'curl IPv4 exit ${result.exitCode}');
        return 'eroare';
      }
      final ip = (result.stdout as String).trim();
      return ip.isNotEmpty ? ip : 'necunoscut';
    } catch (e) {
      appLogger.error('CHECK', 'Nu am putut detecta IPv4: $e');
      return 'eroare';
    }
  }

  /// Detect public IPv6 via curl to ipify IPv6-only endpoint.
  static Future<String> _detectIpv6() async {
    try {
      final result = await Process.run('/usr/bin/curl', <String>[
        '-s', '--connect-timeout', '4', '--max-time', '6',
        '-6', 'https://api6.ipify.org',
      ]).timeout(const Duration(seconds: 8));
      if (result.exitCode != 0) return 'nu';
      final ip = (result.stdout as String).trim();
      if (ip.isNotEmpty && ip.contains(':')) return ip;
      return 'nu';
    } catch (_) {
      return 'nu';
    }
  }

  /// Detect DNS servers. Returns (ipv4_servers, ipv6_servers).
  static Future<(List<String>, List<String>)> _detectDnsServers() async {
    try {
      if (Platform.isMacOS) {
        return _detectDnsMacOS();
      } else if (Platform.isLinux) {
        final servers = await _detectDnsLinux();
        final v4 = servers.where((s) => !s.contains(':')).toList();
        final v6 = servers.where((s) => s.contains(':')).toList();
        return (v4, v6);
      }
      return (<String>['platformă nesuportată'], <String>[]);
    } catch (e) {
      appLogger.error('CHECK', 'Nu am putut detecta DNS: $e');
      return (<String>['eroare'], <String>[]);
    }
  }

  /// Parse ALL nameservers from scutil --dns. This is the reliable
  /// way to see what macOS is actually using for DNS resolution,
  /// including DHCP-assigned servers. networksetup -getdnsservers
  /// only shows manually configured ones.
  static Future<(List<String>, List<String>)> _detectDnsMacOS() async {
    final result = await Process.run('/usr/sbin/scutil', <String>['--dns']);
    if (result.exitCode != 0) return (<String>['eroare scutil'], <String>[]);

    final lines = (result.stdout as String).split('\n');
    final v4 = <String>{};
    final v6 = <String>{};

    for (final line in lines) {
      final trimmed = line.trim();
      if (!trimmed.startsWith('nameserver[')) continue;

      // Format: "nameserver[0] : 10.8.0.1" or "nameserver[0] : 2001:db8::1"
      final colonIdx = trimmed.indexOf(' : ');
      if (colonIdx < 0) continue;
      final ip = trimmed.substring(colonIdx + 3).trim();
      if (ip.isEmpty) continue;

      // Skip link-local IPv6 (fe80::) and interface-suffixed (%en0)
      if (ip.contains('%')) continue;
      if (ip.toLowerCase().startsWith('fe80:')) continue;

      if (ip.contains(':')) {
        v6.add(ip);
      } else {
        v4.add(ip);
      }
    }

    if (v4.isEmpty && v6.isEmpty) {
      return (<String>['nu s-au detectat'], <String>[]);
    }
    return (v4.toList(), v6.toList());
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
}
