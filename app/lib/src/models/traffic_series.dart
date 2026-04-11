// ICD360SVPN — lib/src/models/traffic_series.dart
//
// Wire shape of `GET /v1/peers/{pubkey}/bandwidth`. The agent buckets
// raw samples by minute / hour / day server-side; we just render.

import 'package:flutter/foundation.dart';

@immutable
class TrafficPoint {
  const TrafficPoint({required this.t, required this.rx, required this.tx});

  final DateTime t;
  final int rx;
  final int tx;

  factory TrafficPoint.fromJson(Map<String, dynamic> json) {
    return TrafficPoint(
      t: DateTime.parse(json['t'] as String),
      rx: (json['rx'] as num).toInt(),
      tx: (json['tx'] as num).toInt(),
    );
  }
}

@immutable
class TrafficSeries {
  const TrafficSeries({
    required this.publicKey,
    required this.granularity,
    required this.points,
  });

  final String publicKey;
  final String granularity;
  final List<TrafficPoint> points;

  factory TrafficSeries.fromJson(Map<String, dynamic> json) {
    final pointsJson = json['points'] as List<dynamic>?;
    return TrafficSeries(
      publicKey: json['public_key'] as String,
      granularity: json['granularity'] as String,
      points: pointsJson == null
          ? const <TrafficPoint>[]
          : pointsJson
              .cast<Map<String, dynamic>>()
              .map(TrafficPoint.fromJson)
              .toList(growable: false),
    );
  }
}
