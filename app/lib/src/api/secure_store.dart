// ICD360SVPN — lib/src/api/secure_store.dart
//
// Persistent secure storage for the three PEMs (cert, key, CA) and
// the agent URL. Uses flutter_secure_storage which delegates to:
//   - Keychain on macOS / iOS
//   - libsecret on Linux
//   - DPAPI on Windows
//   - Keystore on Android
//
// We store the values as separate keys (rather than bundling as JSON)
// because the underlying KV stores are perfectly happy with PEM
// strings and we never need to load them as a unit anyway.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStore {
  // Note: AndroidOptions.encryptedSharedPreferences was removed in
  // flutter_secure_storage v10 — Jetpack Security is deprecated by
  // Google and the package now migrates to custom ciphers
  // automatically on first access. We pass plain defaults.
  SecureStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              mOptions: MacOsOptions(
                accessibility: KeychainAccessibility.unlocked_this_device,
              ),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.unlocked_this_device,
              ),
            );

  final FlutterSecureStorage _storage;

  static const String _kCertPem = 'icd360svpn.cert_pem';
  static const String _kKeyPem = 'icd360svpn.key_pem';
  static const String _kCaPem = 'icd360svpn.ca_pem';
  static const String _kAgentUrl = 'icd360svpn.agent_url';
  static const String _kIdentityName = 'icd360svpn.identity_name';

  /// Persist all four enrollment fields atomically (best-effort —
  /// flutter_secure_storage doesn't expose a transaction so we just
  /// write them in order; if the second one fails the first is left
  /// behind, which is fine because we always overwrite on next save).
  Future<void> saveIdentity({
    required String certPem,
    required String keyPem,
    required String caPem,
    required String agentUrl,
    required String identityName,
  }) async {
    await _storage.write(key: _kCertPem, value: certPem);
    await _storage.write(key: _kKeyPem, value: keyPem);
    await _storage.write(key: _kCaPem, value: caPem);
    await _storage.write(key: _kAgentUrl, value: agentUrl);
    await _storage.write(key: _kIdentityName, value: identityName);
  }

  /// Returns the saved identity, or null if any of the four required
  /// fields is missing (treated as "no enrollment yet").
  Future<StoredIdentity?> loadIdentity() async {
    final cert = await _storage.read(key: _kCertPem);
    final key = await _storage.read(key: _kKeyPem);
    final ca = await _storage.read(key: _kCaPem);
    final url = await _storage.read(key: _kAgentUrl);
    if (cert == null || key == null || ca == null || url == null) {
      return null;
    }
    final name = await _storage.read(key: _kIdentityName) ?? '';
    return StoredIdentity(
      certPem: cert,
      keyPem: key,
      caPem: ca,
      agentUrl: url,
      identityName: name,
    );
  }

  /// Wipe everything we wrote. Used by the "Logout" button.
  Future<void> clear() async {
    await _storage.delete(key: _kCertPem);
    await _storage.delete(key: _kKeyPem);
    await _storage.delete(key: _kCaPem);
    await _storage.delete(key: _kAgentUrl);
    await _storage.delete(key: _kIdentityName);
  }
}

class StoredIdentity {
  const StoredIdentity({
    required this.certPem,
    required this.keyPem,
    required this.caPem,
    required this.agentUrl,
    required this.identityName,
  });

  final String certPem;
  final String keyPem;
  final String caPem;
  final String agentUrl;
  final String identityName;
}
