// ICD360SVPN — lib/src/api/connection_check.dart
//
// Lightweight connection diagnostics — public IP detection, DNS
// server discovery, and leak checks.
//
// Uses plain dart:io HttpClient (not the mTLS Dio instance) so
// it works regardless of whether the agent is reachable.

import 'dart:convert';
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

  /// Public IPv4 address (or 'nu' / 'eroare').
  final String publicIpv4;

  /// Public IPv6 address (or 'nu' if no IPv6 connectivity).
  final String publicIpv6;

  /// IPv4 DNS servers the OS is configured to use.
  final List<String> dnsServersV4;

  /// IPv6 DNS servers the OS is configured to use.
  final List<String> dnsServersV6;

  /// Whether the VPN tunnel appears to be active.
  final bool isVpnActive;

  /// All DNS servers combined.
  List<String> get allDnsServers => [...dnsServersV4, ...dnsServersV6];

  /// DNS is safe when ALL resolvers point to the VPN DNS (10.8.0.1).
  bool get isDnsSafe =>
      allDnsServers.isNotEmpty &&
      allDnsServers.every((s) => s == '10.8.0.1');

  /// True if a public IPv6 address was detected.
  bool get hasIpv6 => publicIpv6 != 'nu' && publicIpv6 != 'eroare';

  /// IPv6 is leaking if we detect a public IPv6 while the VPN is up.
  bool get isIpv6Leaking => isVpnActive && hasIpv6;

  /// Overall protection score.
  bool get isFullyProtected => isVpnActive && isDnsSafe && !isIpv6Leaking;
}

class ConnectionCheck {
  static const _timeout = Duration(seconds: 8);

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

  /// Detect public IPv4 via ipify (IPv4-only endpoint).
  static Future<String> _detectIpv4() async {
    try {
      final client = HttpClient()..connectionTimeout = _timeout;
      final req = await client.getUrl(
        Uri.parse('https://api.ipify.org?format=json'),
      );
      final resp = await req.close().timeout(_timeout);
      final body = await resp.transform(utf8.decoder).join();
      client.close(force: true);
      final json = jsonDecode(body) as Map<String, dynamic>;
      return (json['ip'] as String?) ?? 'necunoscut';
    } catch (e) {
      appLogger.error('CHECK', 'Nu am putut detecta IPv4: $e');
      return 'eroare';
    }
  }

  /// Detect public IPv6 via ipify IPv6-only endpoint.
  /// Returns the IPv6 address or 'nu' if no IPv6 connectivity.
  static Future<String> _detectIpv6() async {
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 4);
      final req = await client.getUrl(
        Uri.parse('https://api6.ipify.org?format=json'),
      );
      final resp = await req.close().timeout(const Duration(seconds: 5));
      final body = await resp.transform(utf8.decoder).join();
      client.close(force: true);
      final json = jsonDecode(body) as Map<String, dynamic>;
      final ip = (json['ip'] as String?) ?? '';
      if (ip.isNotEmpty && ip.contains(':')) return ip;
      return 'nu';
    } catch (_) {
      // Timeout or failure = no IPv6 connectivity.
      return 'nu';
    }
  }

  /// Read DNS servers from networksetup (macOS) or resolv.conf (Linux).
  /// Returns (ipv4_servers, ipv6_servers).
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

  /// Use `networksetup -getdnsservers` which returns the actual
  /// configured DNS servers per network service. Much more reliable
  /// than parsing scutil --dns which includes resolver chains,
  /// link-local addresses, and interface suffixes.
  static Future<(List<String>, List<String>)> _detectDnsMacOS() async {
    final v4 = <String>{};
    final v6 = <String>{};
    const services = <String>['Wi-Fi', 'Ethernet', 'USB 10/100/1000 LAN'];

    for (final svc in services) {
      try {
        final result = await Process.run(
          '/usr/sbin/networksetup',
          <String>['-getdnsservers', svc],
        );
        if (result.exitCode != 0) continue;
        final output = (result.stdout as String).trim();
        // networksetup returns "There aren't any DNS Servers set on ..."
        // when DHCP is managing DNS. Otherwise one IP per line.
        if (output.contains("aren't any")) continue;
        for (final line in output.split('\n')) {
          final ip = line.trim();
          if (ip.isEmpty) continue;
          if (ip.contains(':')) {
            v6.add(ip);
          } else {
            v4.add(ip);
          }
        }
      } catch (_) {
        continue;
      }
    }

    // If no explicit DNS servers are set, check what the system is
    // actually using via scutil --dns (first resolver's nameservers).
    if (v4.isEmpty && v6.isEmpty) {
      try {
        final result =
            await Process.run('/usr/sbin/scutil', <String>['--dns']);
        if (result.exitCode == 0) {
          final lines = (result.stdout as String).split('\n');
          bool inFirstResolver = false;
          for (final line in lines) {
            final trimmed = line.trim();
            if (trimmed.startsWith('resolver #1')) {
              inFirstResolver = true;
              continue;
            }
            if (inFirstResolver && trimmed.startsWith('resolver #')) break;
            if (inFirstResolver && trimmed.startsWith('nameserver[')) {
              final colonIdx = trimmed.indexOf(':');
              if (colonIdx < 0) continue;
              final ip = trimmed.substring(colonIdx + 1).trim();
              // Skip link-local IPv6 and interface-suffixed addresses.
              if (ip.contains('%')) continue;
              if (ip.startsWith('fe80:')) continue;
              if (ip.contains(':')) {
                v6.add(ip);
              } else {
                v4.add(ip);
              }
            }
          }
        }
      } catch (_) {}
    }

    if (v4.isEmpty && v6.isEmpty) {
      return (<String>['DHCP (automat)'], <String>[]);
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
