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
  // M7.2: WireGuard fields. Store the full .conf body (already
  // rendered by the agent) plus the public key + allocated CIDR so
  // the Connect button knows what to import / disconnect.
  static const String _kWgConfig = 'icd360svpn.wg_config';
  static const String _kWgPublicKey = 'icd360svpn.wg_public_key';
  static const String _kWgAddress = 'icd360svpn.wg_address';

  /// Persist all enrollment fields. Best-effort — flutter_secure_storage
  /// has no transaction so we just write in order; if a later write
  /// fails, the partial state is fine because we always overwrite on
  /// next save.
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
    await _storage.write(key: _kCertPem, value: certPem);
    await _storage.write(key: _kKeyPem, value: keyPem);
    await _storage.write(key: _kCaPem, value: caPem);
    await _storage.write(key: _kAgentUrl, value: agentUrl);
    await _storage.write(key: _kIdentityName, value: identityName);
    await _storage.write(key: _kWgConfig, value: wgConfig);
    await _storage.write(key: _kWgPublicKey, value: wgPublicKey);
    await _storage.write(key: _kWgAddress, value: wgAddress);
  }

  /// Returns the saved identity, or null if any of the four required
  /// mTLS fields is missing (treated as "no enrollment yet"). The
  /// WireGuard fields are optional — older bundles (pre-M7.1) had
  /// none and we still want those identities to load.
  Future<StoredIdentity?> loadIdentity() async {
    final cert = await _storage.read(key: _kCertPem);
    final key = await _storage.read(key: _kKeyPem);
    final ca = await _storage.read(key: _kCaPem);
    final url = await _storage.read(key: _kAgentUrl);
    if (cert == null || key == null || ca == null || url == null) {
      return null;
    }
    final name = await _storage.read(key: _kIdentityName) ?? '';
    final wgConfig = await _storage.read(key: _kWgConfig) ?? '';
    final wgPub = await _storage.read(key: _kWgPublicKey) ?? '';
    final wgAddr = await _storage.read(key: _kWgAddress) ?? '';
    return StoredIdentity(
      certPem: cert,
      keyPem: key,
      caPem: ca,
      agentUrl: url,
      identityName: name,
      wgConfig: wgConfig,
      wgPublicKey: wgPub,
      wgAddress: wgAddr,
    );
  }

  /// Wipe everything we wrote. Used by the "Logout" button.
  Future<void> clear() async {
    await _storage.delete(key: _kCertPem);
    await _storage.delete(key: _kKeyPem);
    await _storage.delete(key: _kCaPem);
    await _storage.delete(key: _kAgentUrl);
    await _storage.delete(key: _kIdentityName);
    await _storage.delete(key: _kWgConfig);
    await _storage.delete(key: _kWgPublicKey);
    await _storage.delete(key: _kWgAddress);
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

  /// Rendered WireGuard .conf body (M7.2). Empty for pre-M7.1 enrolls.
  final String wgConfig;
  final String wgPublicKey;
  final String wgAddress;

  bool get hasWireguard => wgConfig.isNotEmpty;
}
