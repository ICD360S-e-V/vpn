// ICD360SVPN — lib/src/models/enrollment_bundle.dart
//
// Wire format of the JSON body returned by `POST /v1/enroll` (and
// reverse-proxied as `https://vpn.icd360s.de/enroll`). The server
// produces this in `agent/cmd/vpn-agent/main.go::cmdIssueCode` —
// version 2 of the bundle includes the WireGuard peer config alongside
// the mTLS PEMs so the app can bring up its own tunnel without the
// user importing peer1.conf into a separate WireGuard.app first.
//
// Until M7.1 the bundle was base64-gzip-json packed into a single
// 1500-char paste. M7.1 replaced that with a 16-char short code that
// the app exchanges for THIS structure over plain HTTPS — so we now
// just decode raw JSON.

import 'dart:convert';

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
    required this.wireguardConfig,
    required this.wireguardPublicKey,
    required this.wireguardAddress,
  });

  final int version;
  final String name;
  final DateTime issuedAt;
  final String agentUrl;
  final String certPem;
  final String keyPem;
  final String caPem;

  /// Rendered .conf body for the WireGuard tunnel — direct
  /// `wg-quick`/WireGuard.app input. Contains the client private key,
  /// PSK, allocated /32 address, and the public endpoint.
  final String wireguardConfig;

  /// Public key of THIS device's WireGuard peer (used for revoke
  /// later from the admin app).
  final String wireguardPublicKey;

  /// CIDR allocated to this device, e.g. `10.8.0.7/32`.
  final String wireguardAddress;

  /// Highest bundle wire version this build understands. Bumping
  /// this on the agent side without bumping the app gives a clean
  /// "please update the app" error rather than a silent crash.
  static const int supportedVersion = 2;

  /// Decode the JSON body returned by POST /v1/enroll. Throws
  /// [EnrollmentBundleException] on any failure.
  factory EnrollmentBundle.fromBytes(List<int> bytes) {
    if (bytes.isEmpty) {
      throw EnrollmentBundleException('empty response body');
    }
    final String text;
    try {
      text = utf8.decode(bytes, allowMalformed: false);
    } catch (e) {
      throw EnrollmentBundleException('not valid utf-8: $e');
    }
    return EnrollmentBundle.fromJsonString(text);
  }

  factory EnrollmentBundle.fromJsonString(String text) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(text);
    } catch (e) {
      throw EnrollmentBundleException('json decode failed: $e');
    }
    if (decoded is! Map<String, dynamic>) {
      throw EnrollmentBundleException('json root is not an object');
    }
    return EnrollmentBundle.fromJson(decoded);
  }

  factory EnrollmentBundle.fromJson(Map<String, dynamic> decoded) {
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
      wireguardConfig: decoded['wireguard_config'] as String? ?? '',
      wireguardPublicKey: decoded['wireguard_public_key'] as String? ?? '',
      wireguardAddress: decoded['wireguard_address'] as String? ?? '',
    );
  }
}
