// ICD360SVPN — lib/src/models/peer_create_response.dart

import 'package:flutter/foundation.dart';

import 'peer.dart';

@immutable
class PeerCreateResponse {
  const PeerCreateResponse({required this.peer, required this.clientConfig});

  final Peer peer;
  final String clientConfig;

  factory PeerCreateResponse.fromJson(Map<String, dynamic> json) {
    return PeerCreateResponse(
      peer: Peer.fromJson(json['peer'] as Map<String, dynamic>),
      clientConfig: json['client_config'] as String,
    );
  }
}
