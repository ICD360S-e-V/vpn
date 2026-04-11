// ICD360SVPN — lib/src/api/vpn_tunnel.dart
//
// Per-platform helper for importing the WireGuard tunnel that came in
// the M7.2 enrollment bundle. The strategy is intentionally minimal:
// we DON'T ship a userspace WireGuard implementation inside the app,
// because:
//
//   - On iOS / macOS, the official WireGuard app handles the
//     NetworkExtension dance natively. Apps without an Apple
//     Developer Program membership can't install NE providers
//     anyway, and the user explicitly opted out of the developer
//     program ("connect button fara apple developer program").
//   - On Linux / Windows, the user typically has wireguard-tools
//     installed via the OS package manager and `wg-quick` works.
//   - On Android, the WireGuard Android app accepts an intent for
//     tunnel import.
//
// What this helper does:
//   - Writes the .conf body from the enrollment bundle to a
//     well-known path on disk (Documents directory on desktop, the
//     downloads dir on Android).
//   - Asks the OS to open the file with its default handler. On
//     macOS / iOS this hands the .conf to the WireGuard.app which
//     prompts the user to import; on Linux this triggers xdg-open
//     which usually pops up the file manager (the user can then
//     `wg-quick up` manually); on Windows it launches WireGuard.exe
//     if installed.
//
// The result is "one-tap import" on the priority platform (macOS) and
// "the file is in your Documents folder, do the OS-native thing"
// everywhere else. No NetworkExtension entitlements, no developer
// account, no kernel module to ship.

import 'dart:io';

import 'package:path_provider/path_provider.dart';

class VpnTunnelException implements Exception {
  VpnTunnelException(this.message);
  final String message;
  @override
  String toString() => 'VpnTunnelException: $message';
}

class VpnTunnel {
  /// Writes the tunnel config to disk and asks the OS to open it
  /// with the default handler. Returns the absolute file path so
  /// the caller can show "Saved to ~/Documents/icd360svpn.conf"
  /// in a snackbar.
  static Future<String> importTunnel({
    required String wgConfig,
    String filename = 'icd360svpn.conf',
  }) async {
    if (wgConfig.isEmpty) {
      throw VpnTunnelException(
        'no WireGuard config available — re-enroll to get a fresh bundle',
      );
    }

    final dir = await _writeTargetDirectory();
    if (dir == null) {
      throw VpnTunnelException('cannot locate a writable directory');
    }
    final path = '${dir.path}/$filename';
    final file = File(path);
    await file.writeAsString(wgConfig, flush: true);

    await _openWithDefaultHandler(path);
    return path;
  }

  static Future<Directory?> _writeTargetDirectory() async {
    if (Platform.isMacOS || Platform.isLinux || Platform.isWindows) {
      // ~/Documents on desktop. Falls back to the app support dir
      // if Documents is unavailable (sandboxed builds, etc).
      try {
        final docs = await getApplicationDocumentsDirectory();
        return docs;
      } catch (_) {
        return getApplicationSupportDirectory();
      }
    }
    if (Platform.isAndroid) {
      // The downloads dir is the only one Android's import flow
      // can reach without extra storage permissions.
      return getDownloadsDirectory();
    }
    if (Platform.isIOS) {
      // App Documents are exposed to the Files app, from which the
      // user can pass the .conf to WireGuard via Share.
      return getApplicationDocumentsDirectory();
    }
    return null;
  }

  static Future<void> _openWithDefaultHandler(String path) async {
    try {
      if (Platform.isMacOS) {
        await Process.start('open', <String>[path]);
      } else if (Platform.isLinux) {
        await Process.start('xdg-open', <String>[path]);
      } else if (Platform.isWindows) {
        // `start` is a cmd builtin, hence the cmd /c wrapper. The
        // empty quoted "" is the title arg `start` requires when
        // the first real arg looks like a quoted path.
        await Process.start('cmd', <String>['/c', 'start', '', path]);
      }
      // On iOS / Android we leave the file in the visible directory
      // and let the user import it via the Share sheet — there is
      // no Process.start equivalent without an app intent.
    } catch (_) {
      // Best-effort. The file is on disk; the caller can still
      // surface the path so the user knows where to find it.
    }
  }
}
