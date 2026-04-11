// ICD360SVPN — lib/src/api/user_agent.dart
//
// Single source of truth for the User-Agent header sent on every
// outbound HTTP request from this app — auto-update fetches,
// CHANGELOG fetches, enrollment POST, mTLS API calls. Format:
//
//     icd360sev_client_vpn_management_versiunea_<semver>+<build>
//
// The custom format (rather than the more common
// `Product/version (Platform)`) matches the user's stated naming
// convention so server access logs are easy to grep:
//
//     grep icd360sev_client_vpn_management /var/log/nginx/access.log
//
// Implementation notes:
//   - We resolve the version once per app launch and cache the
//     resulting string. The PackageInfo.fromPlatform() call is
//     fast on every platform but we still don't want to redo it
//     on every Dio request.
//   - The helper is intentionally async because PackageInfo is
//     async; callers must `await VpnUserAgent.value` before
//     constructing their Dio. The handful of call sites all do
//     this in their `_init` / constructor path.
//   - On any failure (PackageInfo unavailable, plugin missing on
//     desktop linux, etc.) we fall back to a "_dev" suffix so the
//     header is always set to SOMETHING — never empty.

import 'dart:async';

import 'package:package_info_plus/package_info_plus.dart';

class VpnUserAgent {
  VpnUserAgent._();

  static String? _cached;
  static Future<String>? _inflight;

  /// Returns the cached User-Agent string, computing it on first
  /// call. Safe to call from many places concurrently — only the
  /// first invocation runs the underlying PackageInfo lookup.
  static Future<String> value() {
    if (_cached != null) return Future<String>.value(_cached!);
    return _inflight ??= _resolve();
  }

  static Future<String> _resolve() async {
    String version;
    String build;
    try {
      final info = await PackageInfo.fromPlatform();
      version = info.version.isEmpty ? '0.0.0' : info.version;
      build = info.buildNumber.isEmpty ? '0' : info.buildNumber;
    } catch (_) {
      version = '0.0.0';
      build = 'dev';
    }
    final ua = 'icd360sev_client_vpn_management_versiunea_$version+$build';
    _cached = ua;
    _inflight = null;
    return ua;
  }

  /// Synchronous read of the cached value, returning a fallback if
  /// it hasn't been resolved yet. Use this from places that can't
  /// await — the worst case is one missed log line on the first
  /// request after app launch.
  static String currentOrFallback() {
    return _cached ?? 'icd360sev_client_vpn_management_versiunea_pending';
  }
}
