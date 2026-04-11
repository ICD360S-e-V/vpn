// ICD360SVPN — lib/src/models/enrollment_bundle.dart
//
// Decodes the single base64 string produced by
// `vpn-agent issue-bundle <name>` into the cert + key + CA + URL the
// app needs to enroll. The encoding chain is:
//
//     base64 -> gzip -> json -> EnrollmentBundle
//
// All whitespace is stripped from the input before decoding so the
// blob can be pasted from terminals, emails, or wrapped runbooks
// without surprising the parser.

import 'dart:convert';
import 'dart:io' show gzip;

import 'package:flutter/foundation.dart';

class EnrollmentBundleException implements Exception {
  EnrollmentBundleException(this.message);
  final String message;
  @override
  String toString() => 'EnrollmentBundleException: $message';
}

@immutable
class EnrollmentBundle {
  const EnrollmentBundle({
    required this.version,
    required this.name,
    required this.issuedAt,
    required this.agentUrl,
    required this.certPem,
    required this.keyPem,
    required this.caPem,
  });

  final int version;
  final String name;
  final DateTime issuedAt;
  final String agentUrl;
  final String certPem;
  final String keyPem;
  final String caPem;

  /// Highest bundle wire version this build understands. Bumping
  /// this on the agent side without bumping the app gives a clean
  /// "please update the app" error rather than a silent crash.
  static const int supportedVersion = 1;

  /// Decode a pasted enrollment string. Throws
  /// [EnrollmentBundleException] on any failure (bad base64, bad gzip,
  /// bad JSON, missing field, unsupported version).
  factory EnrollmentBundle.parse(String input) {
    final cleaned = input.replaceAll(RegExp(r'\s+'), '');
    if (cleaned.isEmpty) {
      throw EnrollmentBundleException('empty input');
    }

    final List<int> gzBytes;
    try {
      gzBytes = base64.decode(cleaned);
    } catch (e) {
      throw EnrollmentBundleException('not valid base64: $e');
    }

    final List<int> jsonBytes;
    try {
      jsonBytes = gzip.decode(gzBytes);
    } catch (e) {
      throw EnrollmentBundleException('gzip decode failed: $e');
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(jsonBytes));
    } catch (e) {
      throw EnrollmentBundleException('json decode failed: $e');
    }
    if (decoded is! Map<String, dynamic>) {
      throw EnrollmentBundleException('json root is not an object');
    }

    final version = decoded['version'];
    if (version is! int) {
      throw EnrollmentBundleException('missing or non-int version');
    }
    if (version > supportedVersion) {
      throw EnrollmentBundleException(
        'bundle version $version is newer than this app supports '
        '($supportedVersion). Please update the app.',
      );
    }

    return EnrollmentBundle(
      version: version,
      name: decoded['name'] as String? ?? '',
      issuedAt: decoded['issued_at'] != null
          ? DateTime.parse(decoded['issued_at'] as String)
          : DateTime.now(),
      agentUrl: decoded['agent_url'] as String? ?? '',
      certPem: decoded['cert_pem'] as String? ?? '',
      keyPem: decoded['key_pem'] as String? ?? '',
      caPem: decoded['ca_pem'] as String? ?? '',
    );
  }
}
