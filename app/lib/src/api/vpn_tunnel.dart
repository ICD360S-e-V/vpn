// ICD360SVPN — lib/src/api/vpn_tunnel.dart
//
// VPN tunnel management using macOS Configuration Profiles
// (.mobileconfig) + WireGuard App from App Store.
//
// Instead of wg-quick (unreliable userspace wireguard-go), we
// generate a .mobileconfig file that macOS installs as a system
// VPN managed by WireGuard App (kernel-level NetworkExtension).
//
// Benefits vs wg-quick:
//   - Kernel-level tunnel (stable, no wireguard-go process)
//   - Managed by macOS System Settings → VPN
//   - No admin password on every connect/disconnect
//   - No firewall hacks (socketfilterfw, pfctl)
//   - Works reliably on all macOS versions including Sequoia
//
// Requirements:
//   - WireGuard App from Mac App Store (free)
//   - User confirms profile install once (System Settings)

import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'app_logger.dart';

class VpnTunnelException implements Exception {
  VpnTunnelException(this.message, {this.userCancelled = false});
  final String message;
  final bool userCancelled;
  @override
  String toString() => 'VpnTunnelException: $message';
}

enum VpnTunnelStatus {
  unknown,
  disconnected,
  connecting,
  connected,
  disconnecting,
}

class VpnTunnel {
  /// Check if WireGuard App is installed on macOS.
  /// Checks common App Store and direct install paths.
  static Future<bool> isWireGuardAppInstalled() async {
    if (!Platform.isMacOS) return false;
    // Check if WireGuard.app exists in standard locations
    const paths = <String>[
      '/Applications/WireGuard.app',
      '/Applications/Utilities/WireGuard.app',
    ];
    for (final p in paths) {
      if (await Directory(p).exists()) return true;
    }
    // Also check via mdfind (Spotlight) which finds App Store apps
    try {
      final result = await Process.run(
        '/usr/bin/mdfind', <String>['kMDItemCFBundleIdentifier == "com.wireguard.macos"'],
      );
      if (result.exitCode == 0 && (result.stdout as String).trim().isNotEmpty) {
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// Generate and install a .mobileconfig profile for the WireGuard
  /// tunnel. macOS opens the profile installer — user confirms once.
  /// Subsequent connects are done via System Settings or WireGuard App.
  static Future<void> installProfile({required String wgConfig, bool killSwitch = true, bool autoConnect = true}) async {
    if (wgConfig.isEmpty) {
      throw VpnTunnelException(
        'Nu există o configurație WireGuard salvată. Re-enroll cu un cod nou.',
      );
    }

    appLogger.info('VPN', 'Generare profil .mobileconfig…');

    final mobileconfig = _buildMobileconfig(wgConfig, killSwitch: killSwitch, autoConnect: autoConnect);
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/ICD360S-VPN.mobileconfig');
    await file.writeAsString(mobileconfig, flush: true);
    appLogger.info('VPN', 'Profil salvat: ${file.path}');

    // Open the profile — macOS shows the install prompt
    final result = await Process.run('/usr/bin/open', <String>[file.path]);
    if (result.exitCode != 0) {
      throw VpnTunnelException(
        'Nu am putut deschide profilul: ${(result.stderr as String).trim()}',
      );
    }
    appLogger.info('VPN', 'Profil deschis — confirmă instalarea din System Settings');
  }

  /// Connect the VPN tunnel via scutil (macOS system VPN control).
  static Future<void> connect({required String wgConfig}) async {
    if (!Platform.isMacOS && !Platform.isLinux) {
      throw VpnTunnelException(
        'Connect în-app este disponibil doar pe macOS și Linux.',
      );
    }

    if (Platform.isLinux) {
      return _connectLinux(wgConfig);
    }

    // macOS: try to connect via scutil --nc (system VPN)
    final tunnelName = await _findWireGuardTunnel();
    if (tunnelName == null) {
      // Profile not installed yet — generate and install
      appLogger.info('VPN', 'Profil WireGuard nu e instalat — se generează');
      await installProfile(wgConfig: wgConfig);
      throw VpnTunnelException(
        'Profilul VPN a fost generat. Instalează-l din System Settings → '
        'Privacy & Security → Profiles, apoi conectează-te din '
        'System Settings → VPN sau din WireGuard App.',
        userCancelled: true,
      );
    }

    appLogger.info('VPN', 'Conectare tunel "$tunnelName"…');
    final result = await Process.run(
      '/usr/sbin/scutil', <String>['--nc', 'start', tunnelName],
    );
    if (result.exitCode != 0) {
      final err = (result.stderr as String).trim();
      appLogger.error('VPN', 'scutil --nc start eșuat: $err');
      throw VpnTunnelException('Conectare eșuată: $err');
    }
    appLogger.info('VPN', 'Tunel "$tunnelName" pornit');
  }

  /// Disconnect the VPN tunnel.
  static Future<void> disconnect() async {
    if (!Platform.isMacOS && !Platform.isLinux) {
      throw VpnTunnelException(
        'Disconnect în-app este disponibil doar pe macOS și Linux.',
      );
    }

    if (Platform.isLinux) {
      return _disconnectLinux();
    }

    final tunnelName = await _findWireGuardTunnel();
    if (tunnelName == null) {
      throw VpnTunnelException('Nu s-a găsit tunelul WireGuard.');
    }

    appLogger.info('VPN', 'Deconectare tunel "$tunnelName"…');
    final result = await Process.run(
      '/usr/sbin/scutil', <String>['--nc', 'stop', tunnelName],
    );
    if (result.exitCode != 0) {
      final err = (result.stderr as String).trim();
      appLogger.error('VPN', 'scutil --nc stop eșuat: $err');
      throw VpnTunnelException('Deconectare eșuată: $err');
    }
    appLogger.info('VPN', 'Tunel "$tunnelName" oprit');
  }

  /// Check VPN tunnel status via scutil --nc status.
  static Future<VpnTunnelStatus> status() async {
    if (Platform.isMacOS) {
      return _statusMacOS();
    }
    // Linux fallback: check wg show interfaces
    final wg = await _findWg();
    if (wg == null) return VpnTunnelStatus.unknown;
    try {
      final result = await Process.run(wg, <String>['show', 'interfaces']);
      if (result.exitCode != 0) return VpnTunnelStatus.unknown;
      final out = (result.stdout as String).trim();
      if (out.isEmpty) return VpnTunnelStatus.disconnected;
      return VpnTunnelStatus.connected;
    } catch (_) {
      return VpnTunnelStatus.unknown;
    }
  }

  /// Detect VPN status on macOS via scutil --nc status.
  static Future<VpnTunnelStatus> _statusMacOS() async {
    final tunnelName = await _findWireGuardTunnel();
    if (tunnelName == null) return VpnTunnelStatus.disconnected;

    try {
      final result = await Process.run(
        '/usr/sbin/scutil', <String>['--nc', 'status', tunnelName],
      );
      if (result.exitCode != 0) return VpnTunnelStatus.unknown;
      final out = (result.stdout as String).trim().toLowerCase();
      if (out.contains('connected')) {
        if (out.startsWith('connected')) {
          return VpnTunnelStatus.connected;
        }
        return VpnTunnelStatus.connecting;
      }
      if (out.contains('disconnecting')) return VpnTunnelStatus.disconnecting;
      return VpnTunnelStatus.disconnected;
    } catch (_) {
      return VpnTunnelStatus.unknown;
    }
  }

  /// Find the WireGuard tunnel name from scutil --nc list.
  static Future<String?> _findWireGuardTunnel() async {
    try {
      final result = await Process.run(
        '/usr/sbin/scutil', <String>['--nc', 'list'],
      );
      if (result.exitCode != 0) return null;
      // Lines look like:
      // * (Connected)     "ICD360S VPN"   [VPN:com.wireguard.macos] ...
      // * (Disconnected)  "ICD360S VPN"   [VPN:com.wireguard.macos] ...
      final lines = (result.stdout as String).split('\n');
      for (final line in lines) {
        if (line.contains('com.wireguard.macos') || line.contains('ICD360S')) {
          // Extract tunnel name between quotes
          final match = RegExp(r'"([^"]+)"').firstMatch(line);
          if (match != null) return match.group(1);
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Build a .mobileconfig XML for the WireGuard tunnel.
  static String _buildMobileconfig(String wgConfig, {bool killSwitch = true, bool autoConnect = true}) {
    // Extract endpoint from config for RemoteAddress
    final endpointMatch = RegExp(r'Endpoint\s*=\s*(\S+)').firstMatch(wgConfig);
    final endpoint = endpointMatch?.group(1) ?? 'vpn.icd360s.de:443';

    return '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>PayloadDisplayName</key>
	<string>ICD360S VPN</string>
	<key>PayloadType</key>
	<string>Configuration</string>
	<key>PayloadVersion</key>
	<integer>1</integer>
	<key>PayloadIdentifier</key>
	<string>de.icd360s.vpn.profile</string>
	<key>PayloadUUID</key>
	<string>A1B2C3D4-E5F6-7890-ABCD-EF1234567890</string>
	<key>PayloadContent</key>
	<array>
		<dict>
			<key>PayloadDisplayName</key>
			<string>VPN</string>
			<key>PayloadType</key>
			<string>com.apple.vpn.managed</string>
			<key>PayloadVersion</key>
			<integer>1</integer>
			<key>PayloadIdentifier</key>
			<string>de.icd360s.vpn.profile.tunnel</string>
			<key>PayloadUUID</key>
			<string>B2C3D4E5-F6A7-8901-BCDE-F12345678901</string>
			<key>UserDefinedName</key>
			<string>ICD360S VPN</string>
			<key>VPNType</key>
			<string>VPN</string>
			<key>VPNSubType</key>
			<string>com.wireguard.macos</string>
			<key>VendorConfig</key>
			<dict>
				<key>WgQuickConfig</key>
				<string>${_escapeXml(wgConfig)}</string>
			</dict>
			<key>VPN</key>
			<dict>
				<key>RemoteAddress</key>
				<string>$endpoint</string>
				<key>AuthenticationMethod</key>
				<string>Password</string>
			</dict>
${_buildOnDemandRules(killSwitch: killSwitch, autoConnect: autoConnect)}
		</dict>
	</array>
</dict>
</plist>''';
  }

  /// Build OnDemandRules XML fragment based on user preferences.
  ///
  /// - killSwitch + autoConnect: Always-on VPN. OnDemandRules with
  ///   Connect action on all interfaces ensures macOS reconnects
  ///   immediately when the tunnel drops. This is the closest to a
  ///   "kill switch" achievable without MDM/IncludeAllNetworks.
  ///   Note: true traffic-blocking kill switch requires supervised
  ///   mode with IncludeAllNetworks=true, which is MDM-only.
  /// - autoConnect only: same Connect rules, reconnects on any network.
  /// - killSwitch only: Connect rules (forces reconnect = best effort).
  /// - neither: OnDemandEnabled=0, manual connect/disconnect.
  static String _buildOnDemandRules({
    required bool killSwitch,
    required bool autoConnect,
  }) {
    if (!killSwitch && !autoConnect) {
      return '\t\t\t<key>OnDemandEnabled</key>\n\t\t\t<integer>0</integer>';
    }

    final buf = StringBuffer();
    buf.writeln('\t\t\t<key>OnDemandEnabled</key>');
    buf.writeln('\t\t\t<integer>1</integer>');
    buf.writeln('\t\t\t<key>OnDemandRules</key>');
    buf.writeln('\t\t\t<array>');

    // Connect on WiFi and Cellular (Apple-documented interface types)
    for (final iface in <String>['WiFi', 'Cellular']) {
      buf.writeln('\t\t\t\t<dict>');
      buf.writeln('\t\t\t\t\t<key>Action</key>');
      buf.writeln('\t\t\t\t\t<string>Connect</string>');
      buf.writeln('\t\t\t\t\t<key>InterfaceTypeMatch</key>');
      buf.writeln('\t\t\t\t\t<string>$iface</string>');
      buf.writeln('\t\t\t\t</dict>');
    }

    // Catch-all: Connect on any other interface (Ethernet, etc.)
    buf.writeln('\t\t\t\t<dict>');
    buf.writeln('\t\t\t\t\t<key>Action</key>');
    buf.writeln('\t\t\t\t\t<string>Connect</string>');
    buf.writeln('\t\t\t\t</dict>');

    buf.write('\t\t\t</array>');
    return buf.toString();
  }

    static String _escapeXml(String s) {
    return s
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
  }

  // ---------------------------------------------------------------
  // Linux fallback (wg-quick, same as before)
  // ---------------------------------------------------------------

  static Future<void> _connectLinux(String wgConfig) async {
    final dir = await getApplicationSupportDirectory();
    if (!await dir.exists()) await dir.create(recursive: true);
    final confPath = '${dir.path}/icd360svpn.conf';
    await File(confPath).writeAsString(wgConfig, flush: true);
    try {
      await Process.run('/bin/chmod', <String>['600', confPath]);
    } catch (_) {}

    final wgQuick = await _findWgQuick();
    if (wgQuick == null) {
      throw VpnTunnelException(
        'Nu am găsit wg-quick. Instalează wireguard-tools.',
      );
    }
    await _runWithLinuxAdmin(<String>[wgQuick, 'up', confPath]);
    appLogger.info('VPN', 'wg-quick up reușit');
  }

  static Future<void> _disconnectLinux() async {
    final dir = await getApplicationSupportDirectory();
    final confPath = '${dir.path}/icd360svpn.conf';
    if (!await File(confPath).exists()) {
      throw VpnTunnelException('Config nu există.');
    }
    final wgQuick = await _findWgQuick();
    if (wgQuick == null) {
      throw VpnTunnelException('wg-quick nu a fost găsit.');
    }
    await _runWithLinuxAdmin(<String>[wgQuick, 'down', confPath]);
    appLogger.info('VPN', 'wg-quick down reușit');
  }

  static Future<String?> _findWgQuick() async {
    const candidates = <String>[
      '/opt/homebrew/bin/wg-quick',
      '/usr/local/bin/wg-quick',
      '/usr/bin/wg-quick',
    ];
    for (final p in candidates) {
      if (await File(p).exists()) return p;
    }
    return null;
  }

  static Future<String?> _findWg() async {
    const candidates = <String>[
      '/opt/homebrew/bin/wg',
      '/usr/local/bin/wg',
      '/usr/bin/wg',
    ];
    for (final p in candidates) {
      if (await File(p).exists()) return p;
    }
    return null;
  }

  static Future<void> _runWithLinuxAdmin(List<String> argv) async {
    ProcessResult result;
    if (await File('/usr/bin/pkexec').exists()) {
      result = await Process.run('/usr/bin/pkexec', argv);
    } else if (await File('/usr/bin/sudo').exists()) {
      result = await Process.run('/usr/bin/sudo', argv);
    } else {
      throw VpnTunnelException('Nu am găsit pkexec sau sudo.');
    }
    if (result.exitCode == 0) return;
    final err = (result.stderr as String).trim();
    if (result.exitCode == 126 || err.contains('not authorized')) {
      throw VpnTunnelException('Anulat de utilizator.', userCancelled: true);
    }
    throw VpnTunnelException('wg-quick eșuat (exit ${result.exitCode}): $err');
  }

  /// Not needed for macOS mobileconfig approach. Kept for Linux.
  static Future<void> ensureDependencies({
    Future<bool> Function(String message)? confirm,
    void Function(String message)? progress,
  }) async {
    if (Platform.isMacOS) {
      // Check if WireGuard App is installed
      final installed = await isWireGuardAppInstalled();
      if (!installed) {
        appLogger.warn('VPN', 'WireGuard App nu e instalat');
        throw VpnTunnelException(
          'Instalează WireGuard din Mac App Store pentru a te conecta la VPN. '
          'Este gratuit și necesar pentru conexiunea VPN.',
        );
      }
      return;
    }
    // Linux: check wg-quick
    if (await _findWgQuick() != null) return;
    throw VpnTunnelException(
      'Nu am găsit wg-quick. Instalează wireguard-tools.',
    );
  }
}
