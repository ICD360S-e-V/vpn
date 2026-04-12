// ICD360SVPN — lib/src/api/vpn_tunnel.dart
//
// REAL connect / disconnect for the WireGuard tunnel that came in
// the M7.2 enrollment bundle. NOT the previous "save .conf to
// Documents and pray the user imports it" workaround.
//
// Why we shell out to `wg-quick` instead of using a Flutter plugin:
//
//   Every Flutter wireguard package on pub.dev (`wireguard_flutter`,
//   `wireguard_flutter_plus`, `wireguard_dart`, `flutter_wireguard_vpn`)
//   requires Apple's NetworkExtension entitlement on macOS, which in
//   turn requires an Apple Developer Program membership ($99/year).
//   The user explicitly opted out of the developer program ("connect
//   button fara apple developer program"), so none of those packages
//   are usable.
//
//   The non-NetworkExtension path that actually works is the same
//   one Tunnelblick / OpenVPN Connect / classic CLI tools use:
//   shell out to a privileged command (`wg-quick up`) and let the
//   OS handle the elevation prompt. On macOS we wrap the command
//   in `osascript -e 'do shell script "..." with administrator
//   privileges'`, which produces the standard Touch ID / password
//   prompt. The user's password is never seen by us.
//
// Requirements on the user's Mac:
//   - `wireguard-tools` installed via Homebrew: `brew install wireguard-tools`
//   - The user must have admin rights (typical for personal Macs)
//
// Linux: same idea via `pkexec wg-quick up`.
// Windows: not yet implemented — Windows uses a system service model
// that's structurally different from wg-quick.

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

/// Snapshot of whether the tunnel is currently active.
enum VpnTunnelStatus {
  unknown,
  disconnected,
  connecting,
  connected,
  disconnecting,
}

class VpnTunnel {
  /// Checks for `wg-quick` and, if missing on macOS, runs
  /// `brew install wireguard-tools` automatically (with optional
  /// confirmation from the caller). Throws [VpnTunnelException] if
  /// neither wireguard-tools nor Homebrew is installed and we can't
  /// recover.
  ///
  /// [confirm] is called BEFORE running brew install with a Romanian
  /// prompt — return true to proceed, false to abort. If null we
  /// auto-confirm.
  ///
  /// [progress] is called with status messages while brew runs so
  /// the UI can show "Se instalează wireguard-tools…" in a snackbar
  /// or progress dialog.
  static Future<void> ensureDependencies({
    Future<bool> Function(String message)? confirm,
    void Function(String message)? progress,
  }) async {
    if (await _findWgQuick() != null) return;

    if (!Platform.isMacOS) {
      // Auto-install via brew is macOS-only for now. Linux users get
      // the manual error message.
      throw VpnTunnelException(
        'Nu am găsit `wg-quick` pe sistem. Instalează wireguard-tools '
        'cu pachetul de sistem (apt / dnf / pacman / brew), apoi reîncearcă.',
      );
    }

    final brew = await _findBrew();
    if (brew == null) {
      throw VpnTunnelException(
        'Nu am găsit nici `wireguard-tools`, nici Homebrew pe sistem. '
        'Instalează Homebrew de la https://brew.sh și apoi reîncearcă, '
        'sau rulează manual `brew install wireguard-tools` într-un '
        'Terminal.',
      );
    }

    final go = (confirm == null)
        ? true
        : await confirm(
            'wireguard-tools nu este instalat pe Mac-ul tău. Vrei să '
            'îl instalez acum automat prin Homebrew? (durează ~30 '
            'de secunde, nu cere parolă de admin)',
          );
    if (!go) {
      throw VpnTunnelException(
        'Instalare anulată de utilizator.',
        userCancelled: true,
      );
    }

    progress?.call('Se instalează wireguard-tools prin brew…');
    final result = await Process.run(brew, <String>[
      'install',
      'wireguard-tools',
    ]);
    if (result.exitCode != 0) {
      throw VpnTunnelException(
        'brew install wireguard-tools a eșuat (exit ${result.exitCode}): '
        '${(result.stderr as String).trim()}',
      );
    }

    if (await _findWgQuick() == null) {
      throw VpnTunnelException(
        'brew a raportat succes dar `wg-quick` tot lipsește. '
        'Verifică `brew list wireguard-tools` într-un Terminal.',
      );
    }
    progress?.call('wireguard-tools instalat cu succes.');
  }

  /// Brings the WireGuard tunnel UP. Writes the .conf to a stable
  /// path under the app's support dir, then runs `wg-quick up` with
  /// admin privileges via osascript (macOS) / pkexec (Linux).
  ///
  /// Caller MUST call [ensureDependencies] first if there is any
  /// chance wireguard-tools is not installed — `connect` itself only
  /// produces a "missing wg-quick" error in that case, it does not
  /// auto-install.
  ///
  /// Throws [VpnTunnelException]:
  ///   - userCancelled=true if the user dismissed the password prompt
  ///   - otherwise with a friendly Romanian message
  static Future<void> connect({required String wgConfig}) async {
    if (wgConfig.isEmpty) {
      throw VpnTunnelException(
        'Nu există o configurație WireGuard salvată. Re-enroll cu un cod nou.',
      );
    }
    if (!Platform.isMacOS && !Platform.isLinux) {
      throw VpnTunnelException(
        'Connect în-app este disponibil doar pe macOS și Linux. '
        'Pe celelalte platforme, importă manual fișierul .conf.',
      );
    }

    final confPath = await _writeConfFile(wgConfig);
    final wgQuick = await _findWgQuick();
    if (wgQuick == null) {
      throw VpnTunnelException(
        'Nu am găsit `wg-quick` pe sistem. Instalează wireguard-tools '
        'cu comanda `brew install wireguard-tools` într-un Terminal, '
        'apoi reîncearcă.',
      );
    }

    appLogger.info('VPN', 'Pornire tunel WireGuard…');
    if (Platform.isMacOS) {
      // Allow wireguard-go through macOS Application Firewall.
      // Without this, the firewall silently blocks all traffic on
      // the utun interface — handshake works but 0 data flows.
      try {
        final firewallFix = _macosFirewallAllow();
        await _runWithMacosAdmin(
          <String>['/bin/sh', '-c', firewallFix],
        );
        appLogger.info('FW', 'wireguard-go permis prin macOS Firewall');
      } catch (e) {
        appLogger.warn('FW', 'Nu am putut configura firewall: $e');
      }

      // Leak protection: disable IPv6 + force DNS through VPN.
      // All commands run in the same admin session as wg-quick up
      // for reliable system-wide DNS and IPv6 leak prevention.
      final leakFixUp = _macosLeakProtectionUp();
      await _runWithMacosAdmin(<String>[wgQuick, 'up', confPath]);
      appLogger.info('VPN', 'wg-quick up reușit');
      // Log routing diagnostics so we can see if macOS set up
      // routes correctly through the utun interface.
      await _logMacosDiagnostics();
      try {
        await _runWithMacosAdmin(
          <String>['/bin/sh', '-c', leakFixUp],
        );
        appLogger.info('DNS', 'DNS forțat la 10.8.0.1, IPv6 dezactivat');
      } catch (e) {
        appLogger.warn('DNS', 'Nu am putut aplica leak protection: $e');
      }
    } else {
      await _runWithLinuxAdmin(<String>[wgQuick, 'up', confPath]);
      appLogger.info('VPN', 'wg-quick up reușit');
    }
  }

  /// Log routing table, wg show, and interface list after connect
  /// so we can diagnose routing issues from the in-app console.
  static Future<void> _logMacosDiagnostics() async {
    try {
      // Routing table — look for utun routes
      final routeResult = await Process.run(
        '/usr/sbin/netstat', <String>['-rn', '-f', 'inet'],
      );
      if (routeResult.exitCode == 0) {
        final lines = (routeResult.stdout as String).split('\n');
        for (final line in lines) {
          if (line.contains('utun') || line.contains('default')) {
            appLogger.info('ROUTE', line.trim());
          }
        }
      }
      // WireGuard interface status
      final wg = await _findWg();
      if (wg != null) {
        final wgResult = await Process.run(wg, <String>['show']);
        if (wgResult.exitCode == 0) {
          final out = (wgResult.stdout as String).trim();
          if (out.isNotEmpty) {
            for (final line in out.split('\n')) {
              final trimmed = line.trim();
              if (trimmed.startsWith('interface:') ||
                  trimmed.startsWith('listening port:') ||
                  trimmed.startsWith('peer:') ||
                  trimmed.startsWith('endpoint:') ||
                  trimmed.startsWith('allowed ips:') ||
                  trimmed.startsWith('latest handshake:') ||
                  trimmed.startsWith('transfer:')) {
                appLogger.info('WG', trimmed);
              }
            }
          }
        } else {
          appLogger.warn('WG', 'wg show necesită sudo — nu pot citi detalii');
        }
      }
      // Network interfaces
      final ifResult = await Process.run('/sbin/ifconfig', <String>['-l']);
      if (ifResult.exitCode == 0) {
        appLogger.info('NET', 'Interfețe: ${(ifResult.stdout as String).trim()}');
      }
    } catch (e) {
      appLogger.warn('DIAG', 'Diagnostice eșuate: $e');
    }
  }

  /// Brings the WireGuard tunnel DOWN and restores DNS/IPv6.
  static Future<void> disconnect() async {
    if (!Platform.isMacOS && !Platform.isLinux) {
      throw VpnTunnelException(
        'Disconnect în-app este disponibil doar pe macOS și Linux.',
      );
    }
    final confPath = await _confPath();
    if (!await File(confPath).exists()) {
      throw VpnTunnelException(
        'Nu există un .conf de oprit (probabil tunelul nu a fost activat '
        'din această aplicație).',
      );
    }
    final wgQuick = await _findWgQuick();
    if (wgQuick == null) {
      throw VpnTunnelException('wg-quick nu a fost găsit pe sistem.');
    }
    appLogger.info('VPN', 'Oprire tunel WireGuard…');
    if (Platform.isMacOS) {
      await _runWithMacosAdmin(<String>[wgQuick, 'down', confPath]);
      appLogger.info('VPN', 'wg-quick down reușit');
      // Restore DNS and IPv6 after tunnel goes down.
      try {
        final leakFixDown = _macosLeakProtectionDown();
        await _runWithMacosAdmin(
          <String>['/bin/sh', '-c', leakFixDown],
        );
        appLogger.info('DNS', 'DNS restaurat la DHCP, IPv6 reactivat');
      } catch (e) {
        appLogger.warn('DNS', 'Nu am putut restaura DNS/IPv6: $e');
      }
    } else {
      await _runWithLinuxAdmin(<String>[wgQuick, 'down', confPath]);
      appLogger.info('VPN', 'wg-quick down reușit');
    }
  }

  /// Shell commands to force DNS through VPN and block IPv6 leaks.
  /// Runs as admin via osascript. Covers Wi-Fi + Ethernet + USB
  /// (the three common macOS network services).
  ///
  /// Leak prevention approach:
  /// Allow wireguard-go through macOS Application Firewall.
  /// Checks both Apple Silicon and Intel Homebrew paths.
  static String _macosFirewallAllow() {
    const sfw = '/usr/libexec/ApplicationFirewall/socketfilterfw';
    const candidates = <String>[
      '/opt/homebrew/bin/wireguard-go',
      '/usr/local/bin/wireguard-go',
      '/opt/local/bin/wireguard-go',
    ];
    final cmds = <String>[];
    for (final path in candidates) {
      // --add is idempotent (no error if already added)
      cmds.add('$sfw --add $path 2>/dev/null || true');
      cmds.add('$sfw --unblockapp $path 2>/dev/null || true');
    }
    return cmds.join(' && ');
  }

  ///   - Force DNS to VPN's AdGuard Home (10.8.0.1)
  ///   - Disable IPv6 to prevent leaking ISP's v6 address
  ///   - Flush DNS cache so stale entries don't leak
  static String _macosLeakProtectionUp() {
    const dns = '10.8.0.1';
    const services = <String>['Wi-Fi', 'Ethernet', 'USB 10/100/1000 LAN'];
    final cmds = <String>[];
    for (final svc in services) {
      cmds.add("networksetup -setdnsservers '$svc' $dns 2>/dev/null || true");
      cmds.add("networksetup -setv6off '$svc' 2>/dev/null || true");
    }
    cmds.add('dscacheutil -flushcache 2>/dev/null || true');
    cmds.add('killall -HUP mDNSResponder 2>/dev/null || true');
    return cmds.join(' && ');
  }

  /// Restore DNS to DHCP defaults and re-enable IPv6.
  static String _macosLeakProtectionDown() {
    const services = <String>['Wi-Fi', 'Ethernet', 'USB 10/100/1000 LAN'];
    final cmds = <String>[];
    for (final svc in services) {
      cmds.add("networksetup -setdnsservers '$svc' empty 2>/dev/null || true");
      cmds.add(
          "networksetup -setv6automatic '$svc' 2>/dev/null || true");
    }
    cmds.add('dscacheutil -flushcache 2>/dev/null || true');
    cmds.add('killall -HUP mDNSResponder 2>/dev/null || true');
    return cmds.join(' && ');
  }

  /// Probes whether a WireGuard tunnel is currently up by looking for
  /// our interface name in `wg show interfaces`. Returns
  /// [VpnTunnelStatus.connected] / [VpnTunnelStatus.disconnected].
  /// Returns [VpnTunnelStatus.unknown] if `wg` is not installed or the
  /// command fails for another reason.
  static Future<VpnTunnelStatus> status() async {
    final wg = await _findWg();
    if (wg == null) return VpnTunnelStatus.unknown;
    try {
      final result = await Process.run(wg, <String>['show', 'interfaces']);
      if (result.exitCode != 0) return VpnTunnelStatus.unknown;
      final out = (result.stdout as String).trim();
      if (out.isEmpty) return VpnTunnelStatus.disconnected;
      // Any interface name listed → at least one wg tunnel is active.
      // We don't try to match a specific name because wg-quick on macOS
      // assigns utun<N> dynamically and the .conf basename doesn't map
      // to a fixed interface name.
      appLogger.info('VPN', 'Interfețe WG active: $out');
      return VpnTunnelStatus.connected;
    } catch (_) {
      return VpnTunnelStatus.unknown;
    }
  }

  // ---------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------

  static Future<String> _confPath() async {
    final dir = await getApplicationSupportDirectory();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return '${dir.path}/icd360svpn.conf';
  }

  static Future<String> _writeConfFile(String wgConfig) async {
    final path = await _confPath();
    final file = File(path);
    await file.writeAsString(wgConfig, flush: true);
    if (!Platform.isWindows) {
      try {
        await Process.run('/bin/chmod', <String>['600', path]);
      } catch (_) {}
    }
    return path;
  }

  /// Search common install locations for wg-quick.
  static Future<String?> _findWgQuick() async {
    const candidates = <String>[
      '/opt/homebrew/bin/wg-quick', // Apple Silicon Homebrew
      '/usr/local/bin/wg-quick',    // Intel Homebrew + most Linux distros
      '/usr/bin/wg-quick',          // System packages
      '/opt/local/bin/wg-quick',    // MacPorts
    ];
    for (final p in candidates) {
      if (await File(p).exists()) return p;
    }
    // Fallback: ask the shell.
    try {
      final result = await Process.run('/bin/sh', <String>['-c', 'command -v wg-quick']);
      if (result.exitCode == 0) {
        final p = (result.stdout as String).trim();
        if (p.isNotEmpty) return p;
      }
    } catch (_) {}
    return null;
  }

  static Future<String?> _findWg() async {
    const candidates = <String>[
      '/opt/homebrew/bin/wg',
      '/usr/local/bin/wg',
      '/usr/bin/wg',
      '/opt/local/bin/wg',
    ];
    for (final p in candidates) {
      if (await File(p).exists()) return p;
    }
    return null;
  }

  /// Locate the Homebrew binary. macOS Apple Silicon installs at
  /// /opt/homebrew/bin/brew, Intel at /usr/local/bin/brew. Linux
  /// Homebrew lives under /home/linuxbrew/.linuxbrew/bin/brew.
  static Future<String?> _findBrew() async {
    const candidates = <String>[
      '/opt/homebrew/bin/brew',
      '/usr/local/bin/brew',
      '/home/linuxbrew/.linuxbrew/bin/brew',
    ];
    for (final p in candidates) {
      if (await File(p).exists()) return p;
    }
    try {
      final result = await Process.run('/bin/sh', <String>['-c', 'command -v brew']);
      if (result.exitCode == 0) {
        final p = (result.stdout as String).trim();
        if (p.isNotEmpty) return p;
      }
    } catch (_) {}
    return null;
  }

  /// Locate a Homebrew / MacPorts bash ≥ 4. macOS ships bash 3.2 at
  /// /bin/bash which cannot run wg-quick (associative arrays, etc.).
  /// Returns null if only the system bash is available.
  static Future<String?> _findModernBash() async {
    const candidates = <String>[
      '/opt/homebrew/bin/bash', // Apple Silicon Homebrew
      '/usr/local/bin/bash',    // Intel Homebrew
      '/opt/local/bin/bash',    // MacPorts
    ];
    for (final p in candidates) {
      if (await File(p).exists()) return p;
    }
    return null;
  }

  /// Runs the given command via osascript with admin privileges. The
  /// macOS Authorization Services prompt asks the user for their
  /// password (or Touch ID if available) before the command runs.
  ///
  /// Returns normally on success. Throws VpnTunnelException with
  /// userCancelled=true if the user dismissed the prompt.
  static Future<void> _runWithMacosAdmin(List<String> argv) async {
    // wg-quick's upstream shebang is #!/bin/bash which on macOS
    // resolves to Apple's ancient bash 3.2. wg-quick requires bash 4+
    // features (associative arrays, etc.) so we must invoke it
    // explicitly with Homebrew's modern bash to bypass the shebang.
    var effective = argv;
    if (argv.isNotEmpty && argv.first.contains('wg-quick')) {
      final modernBash = await _findModernBash();
      if (modernBash != null) {
        effective = <String>[modernBash, ...argv];
      }
    }
    // We must shell-escape each arg because osascript will interpret
    // the resulting string in a sub-shell. Single-quote each arg
    // and escape any embedded single quotes by closing+reopening.
    final shellLine = effective.map(_shellEscape).join(' ');
    // Inner double quotes need to be escaped for AppleScript.
    final appleEscaped = shellLine.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
    final script =
        'do shell script "$appleEscaped" with administrator privileges';
    final result = await Process.run('/usr/bin/osascript', <String>['-e', script]);
    if (result.exitCode == 0) return;

    final stderr = (result.stderr as String).trim();
    // osascript returns errAEEventNotHandled / "User cancelled"
    // (-128) when the user dismisses the password prompt.
    if (stderr.contains('User cancelled') || stderr.contains('-128')) {
      throw VpnTunnelException(
        'Conectarea a fost anulată de utilizator.',
        userCancelled: true,
      );
    }
    throw VpnTunnelException(
      'wg-quick a eșuat (exit ${result.exitCode}): '
      '${stderr.isEmpty ? (result.stdout as String).trim() : stderr}',
    );
  }

  static Future<void> _runWithLinuxAdmin(List<String> argv) async {
    // Try pkexec (PolicyKit, GUI prompt) first; fall back to sudo.
    Future<ProcessResult> tryRun(String elevator) {
      return Process.run(elevator, argv);
    }

    ProcessResult result;
    if (await File('/usr/bin/pkexec').exists()) {
      result = await tryRun('/usr/bin/pkexec');
    } else if (await File('/usr/bin/sudo').exists()) {
      result = await tryRun('/usr/bin/sudo');
    } else {
      throw VpnTunnelException(
        'Nu am găsit pkexec sau sudo pe sistem.',
      );
    }
    if (result.exitCode == 0) return;
    final err = (result.stderr as String).trim();
    if (result.exitCode == 126 || err.contains('not authorized')) {
      throw VpnTunnelException(
        'Conectarea a fost anulată de utilizator.',
        userCancelled: true,
      );
    }
    throw VpnTunnelException(
      'wg-quick a eșuat (exit ${result.exitCode}): $err',
    );
  }

  /// Shell-escape a single argument for safe inclusion in a sh
  /// command line. Wraps in single quotes and escapes embedded
  /// single quotes via the close-quote / backslash-quote / open-quote
  /// trick.
  static String _shellEscape(String arg) {
    if (arg.isEmpty) return "''";
    if (RegExp(r'^[A-Za-z0-9_./:=@%+-]+$').hasMatch(arg)) return arg;
    return "'${arg.replaceAll("'", "'\\''")}'";
  }
}
