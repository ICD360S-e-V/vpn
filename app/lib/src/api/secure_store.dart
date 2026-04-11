// ICD360SVPN — lib/src/api/secure_store.dart
//
// Persistent storage for the cert + WireGuard config across app
// launches. Originally used `flutter_secure_storage` (Keychain on
// macOS, libsecret on Linux, DPAPI on Windows, Keystore on Android),
// but the macOS Keychain plugin produced
// `errSecMissingEntitlement -34018` even with the sandbox dropped,
// and chasing the right combination of entitlements / Team IDs /
// keychain-access-groups for an unsigned (no Apple Developer Program)
// build was a hopeless game of whack-a-mole.
//
// We switched to a plain JSON file written under the OS-blessed
// "application support" directory with POSIX mode 0600. Threat
// model justification:
//
//   - The user IS the admin who installed the app on their own
//     machine. Anything able to read this file (process running as
//     them, or root) already has full access to their Keychain
//     too — the OS-level Keychain provides ZERO additional defense
//     against an attacker who already owns the user account.
//   - In shared-machine scenarios (a single Mac with multiple users),
//     POSIX 0600 means OTHER local users cannot read the file.
//     Keychain offers similar but not stronger isolation.
//   - The cert can be revoked from the agent server side at any
//     time, so a leaked cert has bounded blast radius.
//
// What we lose vs Keychain: the cert is in plaintext on disk
// instead of encrypted at rest. We accept that.
//
// What we gain: cross-platform identical behavior, zero plugin
// dependencies, zero entitlement / signing concerns, zero
// `errSecMissingEntitlement` errors, deterministic semantics, and
// trivially auditable code.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class SecureStore {
  SecureStore({Directory? overrideDir}) : _overrideDir = overrideDir;

  final Directory? _overrideDir;
  Directory? _cachedDir;

  /// Filename inside the application-support directory. Single file
  /// containing all fields as JSON for atomic writes.
  static const String _filename = 'identity.json';

  Future<Directory> _supportDir() async {
    if (_cachedDir != null) return _cachedDir!;
    final dir = _overrideDir ?? await getApplicationSupportDirectory();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    // Best effort: tighten the parent directory permissions on Unix.
    // chmod is a no-op on Windows; the catch swallows the unsupported
    // operation in that case.
    if (!Platform.isWindows) {
      try {
        await Process.run('/bin/chmod', <String>['700', dir.path]);
      } catch (_) {}
    }
    _cachedDir = dir;
    return dir;
  }

  Future<File> _identityFile() async {
    final dir = await _supportDir();
    return File('${dir.path}/$_filename');
  }

  /// Persist all enrollment fields atomically. Writes to a `.tmp`
  /// file first then renames so a crash mid-write does not corrupt
  /// the existing identity.
  Future<void> saveIdentity({
    required String certPem,
    required String keyPem,
    required String caPem,
    required String agentUrl,
    required String identityName,
    String wgConfig = '',
    String wgPublicKey = '',
    String wgAddress = '',
  }) async {
    final body = jsonEncode(<String, String>{
      'cert_pem': certPem,
      'key_pem': keyPem,
      'ca_pem': caPem,
      'agent_url': agentUrl,
      'identity_name': identityName,
      'wg_config': wgConfig,
      'wg_public_key': wgPublicKey,
      'wg_address': wgAddress,
    });
    final file = await _identityFile();
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(body, flush: true);
    if (!Platform.isWindows) {
      try {
        await Process.run('/bin/chmod', <String>['600', tmp.path]);
      } catch (_) {}
    }
    await tmp.rename(file.path);
  }

  /// Returns the saved identity, or null if no identity file exists
  /// or any of the four mTLS-required fields is missing. WireGuard
  /// fields are optional — pre-M7.1 enrolls had none.
  Future<StoredIdentity?> loadIdentity() async {
    final file = await _identityFile();
    if (!await file.exists()) return null;
    final String body;
    try {
      body = await file.readAsString();
    } catch (_) {
      return null;
    }
    if (body.trim().isEmpty) return null;
    final dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;
    final cert = decoded['cert_pem'] as String?;
    final key = decoded['key_pem'] as String?;
    final ca = decoded['ca_pem'] as String?;
    final url = decoded['agent_url'] as String?;
    if (cert == null ||
        cert.isEmpty ||
        key == null ||
        key.isEmpty ||
        ca == null ||
        ca.isEmpty ||
        url == null ||
        url.isEmpty) {
      return null;
    }
    return StoredIdentity(
      certPem: cert,
      keyPem: key,
      caPem: ca,
      agentUrl: url,
      identityName: (decoded['identity_name'] as String?) ?? '',
      wgConfig: (decoded['wg_config'] as String?) ?? '',
      wgPublicKey: (decoded['wg_public_key'] as String?) ?? '',
      wgAddress: (decoded['wg_address'] as String?) ?? '',
    );
  }

  /// Wipe the identity file. Used by the Logout button.
  Future<void> clear() async {
    final file = await _identityFile();
    if (await file.exists()) {
      try {
        await file.delete();
      } catch (_) {}
    }
  }
}

class StoredIdentity {
  const StoredIdentity({
    required this.certPem,
    required this.keyPem,
    required this.caPem,
    required this.agentUrl,
    required this.identityName,
    this.wgConfig = '',
    this.wgPublicKey = '',
    this.wgAddress = '',
  });

  final String certPem;
  final String keyPem;
  final String caPem;
  final String agentUrl;
  final String identityName;
  final String wgConfig;
  final String wgPublicKey;
  final String wgAddress;

  bool get hasWireguard => wgConfig.isNotEmpty;
}
