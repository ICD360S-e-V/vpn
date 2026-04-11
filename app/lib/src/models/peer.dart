// ICD360SVPN — lib/src/models/peer.dart
//
// Mirrors the JSON shape of `GET /v1/peers` (and the `peer` field of
// `POST /v1/peers`). Field names are snake_case in JSON, camelCase
// here. JSON parsing is hand-rolled — keeps build_runner out of the
// dependency graph.

import 'package:flutter/foundation.dart';

@immutable
class Peer {
  const Peer({
    required this.name,
    required this.publicKey,
    required this.allowedIPs,
    required this.enabled,
    required this.createdAt,
    required this.rxBytesTotal,
    required this.txBytesTotal,
    this.createdBy,
    this.endpoint,
    this.lastHandshakeAt,
  });

  final String name;
  final String publicKey;
  final List<String> allowedIPs;
  final bool enabled;
  final DateTime createdAt;
  final String? createdBy;
  final String? endpoint;
  final DateTime? lastHandshakeAt;
  final int rxBytesTotal;
  final int txBytesTotal;

  factory Peer.fromJson(Map<String, dynamic> json) {
    return Peer(
      name: json['name'] as String? ?? '',
      publicKey: json['public_key'] as String,
      allowedIPs:
          (json['allowed_ips'] as List<dynamic>?)?.cast<String>() ?? const <String>[],
      enabled: json['enabled'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
      createdBy: json['created_by'] as String?,
      endpoint: json['endpoint'] as String?,
      lastHandshakeAt: json['last_handshake_at'] != null
          ? DateTime.parse(json['last_handshake_at'] as String)
          : null,
      rxBytesTotal: (json['rx_bytes_total'] as num?)?.toInt() ?? 0,
      txBytesTotal: (json['tx_bytes_total'] as num?)?.toInt() ?? 0,
    );
  }
}
