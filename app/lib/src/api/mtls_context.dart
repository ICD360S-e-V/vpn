// ICD360SVPN — lib/src/api/mtls_context.dart
//
// Builds a dart:io SecurityContext for mTLS with the vpn-agent.
//
// On macOS/iOS, dart:io's Secure Transport backend requires PKCS12
// for client certificates — PEM cert + PEM key loaded separately
// via useCertificateChainBytes / usePrivateKeyBytes silently fails
// to present the client cert during TLS handshake (known issue:
// https://github.com/dart-lang/http/issues/1277).
//
// Fix: convert PEM cert + key to PKCS12 via `openssl pkcs12` and
// load the combined bundle with usePrivateKeyBytes on Apple platforms.

import 'dart:convert';
import 'dart:io';

import 'app_logger.dart';

/// Build a SecurityContext from PEM strings.
///
/// On macOS/iOS, converts cert+key to PKCS12 first because Secure
/// Transport ignores PEM-loaded client certificates.
Future<SecurityContext> buildMtlsContext({
  required String certPem,
  required String keyPem,
  required String caPem,
}) async {
  appLogger.info('mTLS', 'Building SecurityContext (${Platform.operatingSystem})');
  appLogger.info('mTLS', 'CA: ${caPem.length}b, Cert: ${certPem.length}b, Key: ${keyPem.length}b');

  try {
    if (Platform.isMacOS || Platform.isIOS) {
      return await _buildAppleContext(certPem, keyPem, caPem);
    }
    return _buildStandardContext(certPem, keyPem, caPem);
  } catch (e) {
    appLogger.error('mTLS', 'SecurityContext EȘUAT: $e');
    rethrow;
  }
}

/// Standard PEM-based context for Linux/Windows/Android.
SecurityContext _buildStandardContext(
    String certPem, String keyPem, String caPem) {
  final ctx = SecurityContext()
    ..setTrustedCertificatesBytes(utf8.encode(caPem))
    ..useCertificateChainBytes(utf8.encode(certPem))
    ..usePrivateKeyBytes(utf8.encode(keyPem));
  appLogger.info('mTLS', 'SecurityContext creat (PEM standard)');
  return ctx;
}

/// Apple platforms: convert PEM → PKCS12, then load the p12 bundle.
/// This is the only way to make Secure Transport present the client
/// certificate during TLS handshake.
Future<SecurityContext> _buildAppleContext(
    String certPem, String keyPem, String caPem) async {
  // Write PEM files to temp dir
  final tmpDir = await Directory.systemTemp.createTemp('mtls_');
  final certFile = File('${tmpDir.path}/cert.pem');
  final keyFile = File('${tmpDir.path}/key.pem');
  final p12File = File('${tmpDir.path}/client.p12');

  try {
    await certFile.writeAsString(certPem);
    await keyFile.writeAsString(keyPem);

    // Convert PEM → PKCS12 with empty password.
    // OpenSSL 3.x needs -legacy flag (SHA1+TripleDES) for macOS
    // Secure Transport. LibreSSL (macOS built-in) already uses
    // legacy algorithms by default and doesn't have -legacy flag.
    // Try with -legacy first, fall back without it.
    var result = await Process.run('/usr/bin/openssl', <String>[
      'pkcs12', '-export',
      '-legacy',
      '-in', certFile.path,
      '-inkey', keyFile.path,
      '-out', p12File.path,
      '-passout', 'pass:',
    ]);
    if (result.exitCode != 0) {
      appLogger.info('mTLS', 'openssl -legacy nu e suportat, încerc fără');
      result = await Process.run('/usr/bin/openssl', <String>[
        'pkcs12', '-export',
        '-in', certFile.path,
        '-inkey', keyFile.path,
        '-out', p12File.path,
        '-passout', 'pass:',
      ]);
    }
    if (result.exitCode != 0) {
      final err = (result.stderr as String).trim();
      appLogger.error('mTLS', 'openssl pkcs12 eșuat: $err');
      throw Exception('PKCS12 conversion failed: $err');
    }

    final p12Bytes = await p12File.readAsBytes();
    appLogger.info('mTLS', 'PKCS12 generat: ${p12Bytes.length} bytes');

    final ctx = SecurityContext()
      ..setTrustedCertificatesBytes(utf8.encode(caPem))
      ..useCertificateChainBytes(p12Bytes, password: '')
      ..usePrivateKeyBytes(p12Bytes, password: '');
    appLogger.info('mTLS', 'SecurityContext creat (PKCS12 Apple)');
    return ctx;
  } finally {
    // Cleanup temp files
    try { await certFile.delete(); } catch (_) {}
    try { await keyFile.delete(); } catch (_) {}
    try { await p12File.delete(); } catch (_) {}
    try { await tmpDir.delete(); } catch (_) {}
  }
}
