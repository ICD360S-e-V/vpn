// ICD360SVPN — lib/src/api/mtls_context.dart
//
// Builds a dart:io SecurityContext that:
//   1. Trusts ONLY the agent's private CA (not the system trust store).
//   2. Presents a client cert + key for the mTLS challenge.
//
// dart:io's SecurityContext is the right place for this on every
// supported platform (macOS, Linux, Windows, Android, iOS) — Flutter
// pipes it through to the OS TLS implementation.

import 'dart:convert';
import 'dart:io';

/// Build a SecurityContext from PEM strings stored in flutter_secure_storage.
///
/// Throws if any of the PEMs are malformed or if dart:io rejects them.
SecurityContext buildMtlsContext({
  required String certPem,
  required String keyPem,
  required String caPem,
}) {
  final ctx = SecurityContext()
    ..setTrustedCertificatesBytes(utf8.encode(caPem))
    ..useCertificateChainBytes(utf8.encode(certPem))
    ..usePrivateKeyBytes(utf8.encode(keyPem));
  return ctx;
}
