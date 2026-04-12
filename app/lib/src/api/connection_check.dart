// ICD360SVPN — lib/src/api/connection_check.dart
//
// Lightweight connection diagnostics — public IP detection, DNS
// server discovery, ISP/hostname lookup, and leak checks.
//
// Uses Process.run with curl/scutil instead of dart:io HttpClient
// because macOS blocks direct network access from unsigned apps.

import 'dart:convert';
import 'dart:io';

import 'app_logger.dart';

/// Information about a public IP address.
class IpInfo {
  const IpInfo({
    required this.ip,
    this.isp = '',
    this.hostname = '',
    this.country = '',
  });
  final String ip;
  final String isp;
  final String hostname;
  final String country;

  bool get isEmpty => ip == 'nu' || ip == 'eroare' || ip.isEmpty;
}

class ConnectionInfo {
  const ConnectionInfo({
    required this.ipv4,
    required this.ipv6,
    required this.dnsServersV4,
    required this.dnsServersV6,
    required this.isVpnActive,
  });

  final IpInfo ipv4;
  final IpInfo ipv6;
  final List<String> dnsServersV4;
  final List<String> dnsServersV6;
  final bool isVpnActive;

  List<String> get allDnsServers => [...dnsServersV4, ...dnsServersV6];

  bool get isDnsSafe =>
      allDnsServers.isNotEmpty &&
      allDnsServers.every((s) => s == '10.8.0.1');

  bool get hasIpv6 => !ipv6.isEmpty;

  bool get isIpv6Leaking => isVpnActive && hasIpv6;

  bool get isFullyProtected => isVpnActive && isDnsSafe && !isIpv6Leaking;
}

class ConnectionCheck {
  /// Run all checks and return a snapshot.
  static Future<ConnectionInfo> run({required bool vpnActive}) async {
    appLogger.info('CHECK', 'Pornire verificare conexiune…');

    // Phase 1: detect IPs and DNS in parallel
    final results = await Future.wait(<Future<dynamic>>[
      _detectIpWithInfo(ipv6: false),
      _detectIpWithInfo(ipv6: true),
      _detectDnsServers(),
    ]);
    final ipv4 = results[0] as IpInfo;
    final ipv6 = results[1] as IpInfo;
    final dns = results[2] as (List<String>, List<String>);

    final info = ConnectionInfo(
      ipv4: ipv4,
      ipv6: ipv6,
      dnsServersV4: dns.$1,
      dnsServersV6: dns.$2,
      isVpnActive: vpnActive,
    );

    appLogger.info('CHECK', 'IPv4: ${ipv4.ip} (${ipv4.isp})');
    if (!ipv6.isEmpty) {
      appLogger.info('CHECK', 'IPv6: ${ipv6.ip} (${ipv6.isp})');
    } else {
      appLogger.info('CHECK', 'IPv6: nedisponibil');
    }
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
      appLogger.warn('CHECK', 'IPv6 LEAK — ${ipv6.ip}');
    }

    return info;
  }

  /// Detect public IP with fallback across multiple APIs, then
  /// look up ISP/hostname. Multiple endpoints ensure detection
  /// works even if one service is down or rate-limited.
  static Future<IpInfo> _detectIpWithInfo({required bool ipv6}) async {
    final endpoints = ipv6
        ? <String>['https://api6.ipify.org', 'https://v6.ident.me']
        : <String>[
            'https://api64.ipify.org',
            'https://ifconfig.me/ip',
            'https://icanhazip.com',
            'https://ident.me',
          ];
    final timeout = ipv6 ? '4' : '6';

    String? ip;
    for (final endpoint in endpoints) {
      try {
        final result = await Process.run('/usr/bin/curl', <String>[
          '-s', '--connect-timeout', timeout, '--max-time', '8',
          '-H', 'User-Agent: curl', // some APIs require a user-agent
          endpoint,
        ]).timeout(const Duration(seconds: 10));
        if (result.exitCode == 0) {
          final out = (result.stdout as String).trim();
          if (out.isNotEmpty && !out.contains('<')) {
            ip = out;
            break;
          }
        }
      } catch (_) {
        continue;
      }
    }

    if (ip == null || ip.isEmpty) {
      if (ipv6) return const IpInfo(ip: 'nu');
      appLogger.error('CHECK', 'Niciun API de IP nu a răspuns');
      return const IpInfo(ip: 'eroare');
    }
    if (ipv6 && !ip.contains(':')) return const IpInfo(ip: 'nu');

    // Look up ISP + hostname
    final info = await _lookupIpInfo(ip);
    return info;
  }

  /// Query ipinfo.io for ISP, hostname, and country.
  static Future<IpInfo> _lookupIpInfo(String ip) async {
    try {
      final result = await Process.run('/usr/bin/curl', <String>[
        '-s', '--connect-timeout', '4', '--max-time', '6',
        'https://ipinfo.io/$ip/json',
      ]).timeout(const Duration(seconds: 8));
      if (result.exitCode != 0) return IpInfo(ip: ip);

      final body = (result.stdout as String).trim();
      if (body.isEmpty) return IpInfo(ip: ip);

      final json = jsonDecode(body) as Map<String, dynamic>;
      return IpInfo(
        ip: ip,
        isp: (json['org'] as String?) ?? '',
        hostname: (json['hostname'] as String?) ?? '',
        country: (json['country'] as String?) ?? '',
      );
    } catch (_) {
      return IpInfo(ip: ip);
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

  /// Use both `scutil --dns` and `cat /etc/resolv.conf` to reliably
  /// detect DNS servers on macOS. scutil sometimes misses IPv4 servers
  /// that are visible in resolv.conf.
  static Future<(List<String>, List<String>)> _detectDnsMacOS() async {
    final v4 = <String>{};
    final v6 = <String>{};

    // Source 1: /etc/resolv.conf — always has the active DNS servers
    try {
      final resolvResult = await Process.run(
        '/bin/cat', <String>['/etc/resolv.conf'],
      );
      if (resolvResult.exitCode == 0) {
        for (final line in (resolvResult.stdout as String).split('\n')) {
          final trimmed = line.trim();
          if (!trimmed.startsWith('nameserver ')) continue;
          final ip = trimmed.substring(11).trim();
          if (ip.isEmpty) continue;
          if (ip.contains('%')) continue;
          if (ip.toLowerCase().startsWith('fe80:')) continue;
          if (ip.contains(':')) {
            v6.add(ip);
          } else {
            v4.add(ip);
          }
        }
      }
    } catch (_) {}

    // Source 2: scutil --dns — more detailed, catches additional resolvers
    try {
      final scutilResult = await Process.run(
        '/usr/sbin/scutil', <String>['--dns'],
      );
      if (scutilResult.exitCode == 0) {
        for (final line in (scutilResult.stdout as String).split('\n')) {
          final trimmed = line.trim();
          if (!trimmed.startsWith('nameserver[')) continue;

          // Handle both "nameserver[0] : IP" and "nameserver[0]: IP"
          final idx = trimmed.indexOf(':');
          if (idx < 0) continue;
          final ip = trimmed.substring(idx + 1).trim();
          if (ip.isEmpty) continue;
          if (ip.contains('%')) continue;
          if (ip.toLowerCase().startsWith('fe80:')) continue;

          if (ip.contains(':')) {
            v6.add(ip);
          } else {
            v4.add(ip);
          }
        }
      }
    } catch (_) {}

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
