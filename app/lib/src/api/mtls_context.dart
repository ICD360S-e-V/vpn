// ICD360SVPN — lib/src/api/mtls_context.dart
//
// Builds a dart:io SecurityContext that:
//   1. Trusts ONLY the agent's private CA (not the system trust store).
//   2. Presents a client cert + key for the mTLS challenge.

import 'dart:convert';
import 'dart:io';

import 'app_logger.dart';

/// Build a SecurityContext from PEM strings.
///
/// Throws if any of the PEMs are malformed or if dart:io rejects them.
SecurityContext buildMtlsContext({
  required String certPem,
  required String keyPem,
  required String caPem,
}) {
  try {
    final ctx = SecurityContext()
      ..setTrustedCertificatesBytes(utf8.encode(caPem))
      ..useCertificateChainBytes(utf8.encode(certPem))
      ..usePrivateKeyBytes(utf8.encode(keyPem));
    appLogger.info('mTLS', 'SecurityContext creat cu succes');
    appLogger.info('mTLS', 'CA: ${caPem.length} bytes, Cert: ${certPem.length} bytes, Key: ${keyPem.length} bytes');
    return ctx;
  } catch (e) {
    appLogger.error('mTLS', 'SecurityContext EȘUAT: $e');
    appLogger.error('mTLS', 'CA starts: ${caPem.substring(0, 30.clamp(0, caPem.length))}...');
    appLogger.error('mTLS', 'Cert starts: ${certPem.substring(0, 30.clamp(0, certPem.length))}...');
    rethrow;
  }
}
