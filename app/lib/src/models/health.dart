// ICD360SVPN — lib/src/models/health.dart

import 'package:flutter/foundation.dart';

@immutable
class Health {
  const Health({
    required this.status,
    required this.wgUp,
    required this.adguardUp,
    required this.uptimeSeconds,
    required this.agentVersion,
    required this.serverTime,
  });

  final String status;
  final bool wgUp;
  final bool adguardUp;
  final int uptimeSeconds;
  final String agentVersion;
  final DateTime serverTime;

  bool get isOk => status == 'ok';

  factory Health.fromJson(Map<String, dynamic> json) {
    return Health(
      status: json['status'] as String,
      wgUp: json['wg_up'] as bool,
      adguardUp: json['adguard_up'] as bool,
      uptimeSeconds: (json['uptime_seconds'] as num).toInt(),
      agentVersion: json['agent_version'] as String,
      serverTime: DateTime.parse(json['server_time'] as String),
    );
  }
}
