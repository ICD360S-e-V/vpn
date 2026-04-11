// ICD360SVPN — lib/src/models/update_info.dart
//
// Wire format of `https://mail.icd360s.de/downloads/vpn-admin/version.json`.
// The publish-release script writes this file (and the matching DMG)
// after every release. The auto-updater polls it once a day.
//
// {
//   "version":      "0.2.0",
//   "build":        7,
//   "released_at":  "2026-04-15T12:00:00Z",
//   "min_supported": "0.1.0",
//   "platforms": {
//     "macos": {
//       "url":    "https://mail.icd360s.de/downloads/vpn-admin/icd360svpn-0.2.0.dmg",
//       "sha256": "abcdef…"
//     },
//     "linux": { ... },
//     "windows": { ... }
//   },
//   "changelog": [
//     "Bandwidth charts now render hourly buckets",
//     "Fix flickering on the Health screen"
//   ]
// }

import 'package:flutter/foundation.dart';

@immutable
class UpdateAsset {
  const UpdateAsset({required this.url, required this.sha256});

  final String url;
  final String sha256;

  factory UpdateAsset.fromJson(Map<String, dynamic> json) {
    return UpdateAsset(
      url: json['url'] as String,
      sha256: json['sha256'] as String,
    );
  }
}

@immutable
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.build,
    required this.releasedAt,
    required this.changelog,
    required this.platforms,
    this.minSupported,
  });

  final String version;
  final int build;
  final DateTime releasedAt;
  final String? minSupported;
  final List<String> changelog;
  final Map<String, UpdateAsset> platforms;

  /// Returns the asset for the current platform, or null if this
  /// version does not ship for it.
  UpdateAsset? assetFor(String platform) => platforms[platform];

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    final platformsJson = (json['platforms'] as Map<String, dynamic>?) ??
        const <String, dynamic>{};
    final platforms = <String, UpdateAsset>{};
    platformsJson.forEach((k, v) {
      if (v is Map<String, dynamic>) {
        platforms[k] = UpdateAsset.fromJson(v);
      }
    });
    return UpdateInfo(
      version: json['version'] as String,
      build: (json['build'] as num).toInt(),
      releasedAt: DateTime.parse(json['released_at'] as String),
      minSupported: json['min_supported'] as String?,
      changelog: ((json['changelog'] as List<dynamic>?) ?? const <dynamic>[])
          .cast<String>()
          .toList(growable: false),
      platforms: platforms,
    );
  }

  /// Returns true if this update is strictly newer than the given
  /// (currentVersion, currentBuild). Build number is the primary
  /// signal because it is monotonic; semver is the fallback for
  /// pretty display only.
  bool isNewerThan({required String currentVersion, required int currentBuild}) {
    return build > currentBuild;
  }
}
