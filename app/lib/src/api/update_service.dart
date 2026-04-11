// ICD360SVPN — lib/src/api/update_service.dart
//
// Polls the publish-release endpoint for a newer version, downloads
// the DMG (or .deb / .msi when those land), verifies SHA256, and
// asks Finder to open it. The replace-old-app step is left to the
// user: macOS does not support live self-replacement without a
// helper-app dance.
//
// IMPORTANT: this service makes a PLAIN HTTPS call (no mTLS) because
// it must work BEFORE the user has enrolled. The version.json
// endpoint lives on mail.icd360s.de which has a public LE cert; we
// trust the OS root store for it. mTLS is only used for talking to
// vpn-agent on the wg0 tunnel.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../models/update_info.dart';
import 'user_agent.dart';

/// URL of the version manifest. Served by nginx on vpn.icd360s.de
/// (the same server that runs vpn-agent + AdGuard Home, hosted in
/// Azure West Europe). HTTP-only — the OS root store validates the
/// Let's Encrypt cert. mTLS is NOT used here because the update
/// check must work BEFORE the user enrolls into the WireGuard tunnel.
const String kUpdateManifestUrl =
    'https://vpn.icd360s.de/updates/version.json';

/// Polled at app startup and every 24h thereafter.
const Duration kUpdateCheckInterval = Duration(hours: 24);

/// Identifies the running platform in the version.json `platforms`
/// keys.
String currentPlatformKey() {
  if (Platform.isMacOS) return 'macos';
  if (Platform.isLinux) return 'linux';
  if (Platform.isWindows) return 'windows';
  if (Platform.isAndroid) return 'android';
  if (Platform.isIOS) return 'ios';
  return 'unknown';
}

/// Encapsulates the "is there a newer version" check + the download
/// + open-in-Finder flow. Stateless except for an internal Dio.
class UpdateService {
  UpdateService({Dio? client, String manifestUrl = kUpdateManifestUrl})
      : _dio = client ?? Dio(),
        _manifestUrl = manifestUrl;

  final Dio _dio;
  final String _manifestUrl;

  /// GET the manifest. Returns null on any failure (network, parse,
  /// non-2xx) — auto-update is best-effort and must never crash the
  /// app or block startup.
  Future<UpdateInfo?> fetchManifest() async {
    try {
      // Make sure the User-Agent is resolved before the first
      // network call so server access logs see the proper
      // icd360sev_client_vpn_management_versiunea_X.Y.Z+B value
      // instead of the "_pending" placeholder.
      final ua = await VpnUserAgent.value();
      final resp = await _dio.get<String>(
        _manifestUrl,
        options: Options(
          responseType: ResponseType.plain,
          receiveTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 5),
          headers: <String, String>{'User-Agent': ua},
        ),
      );
      if (resp.statusCode == null ||
          resp.statusCode! < 200 ||
          resp.statusCode! >= 300 ||
          resp.data == null) {
        return null;
      }
      final json = jsonDecode(resp.data!) as Map<String, dynamic>;
      return UpdateInfo.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  /// Returns an [UpdateInfo] iff the manifest advertises a build
  /// number strictly greater than the running app's, AND the manifest
  /// has an asset for the current platform.
  Future<UpdateInfo?> checkForUpdate() async {
    final manifest = await fetchManifest();
    if (manifest == null) return null;

    final info = await PackageInfo.fromPlatform();
    final currentBuild = int.tryParse(info.buildNumber) ?? 0;
    if (!manifest.isNewerThan(
      currentVersion: info.version,
      currentBuild: currentBuild,
    )) {
      return null;
    }
    if (manifest.assetFor(currentPlatformKey()) == null) {
      return null;
    }
    return manifest;
  }

  /// Downloads the asset for the current platform into ~/Downloads,
  /// verifies SHA256, and returns the absolute file path. Streams
  /// progress through [onProgress] (received / total bytes).
  ///
  /// Throws on any failure (network, hash mismatch, no Downloads).
  Future<String> downloadUpdate(
    UpdateAsset asset, {
    required String filename,
    void Function(int received, int total)? onProgress,
  }) async {
    final downloads = await getDownloadsDirectory();
    if (downloads == null) {
      throw Exception('cannot locate the Downloads directory');
    }
    final dest = '${downloads.path}/$filename';

    await _dio.download(
      asset.url,
      dest,
      onReceiveProgress: onProgress,
      options: Options(
        receiveTimeout: const Duration(minutes: 10),
        sendTimeout: const Duration(seconds: 30),
      ),
    );

    final actualSha = await _sha256OfFile(dest);
    if (actualSha.toLowerCase() != asset.sha256.toLowerCase()) {
      // Don't leave the bad file behind.
      try {
        await File(dest).delete();
      } catch (_) {}
      throw Exception(
        'SHA256 mismatch for downloaded asset.\n'
        'expected: ${asset.sha256}\nactual:   $actualSha',
      );
    }
    return dest;
  }

  /// Asks the OS to open the freshly-downloaded installer in Finder /
  /// File Explorer / xdg-open. The OS-native installer experience
  /// takes over from here:
  ///
  ///   - macOS: `open` mounts the DMG and shows the .app to drag.
  ///   - Linux: opens the .deb / .AppImage with the default handler.
  ///   - Windows: launches the .msi installer.
  ///
  /// Returns the [Process] so the caller can wait for it to launch
  /// (we don't wait for the installer GUI to finish — that would
  /// block forever).
  Future<void> launchInstaller(String path) async {
    if (Platform.isMacOS) {
      await Process.start('open', <String>[path]);
    } else if (Platform.isLinux) {
      await Process.start('xdg-open', <String>[path]);
    } else if (Platform.isWindows) {
      await Process.start('cmd', <String>['/c', 'start', '', path]);
    } else {
      throw UnsupportedError(
        'launchInstaller is not implemented for this platform',
      );
    }
  }

  /// Quits the running app cleanly. Used after [launchInstaller] so
  /// the user can drag the new app over the old one without "the
  /// item is in use" errors.
  Never quitApp() {
    // Slight delay so the installer process actually starts before
    // we tear down the runtime.
    Future<void>.delayed(const Duration(milliseconds: 500), () {
      exit(0);
    });
    // Make the function type system happy.
    throw _Quitting();
  }
}

class _Quitting implements Exception {}

Future<String> _sha256OfFile(String path) async {
  final file = File(path);
  final stream = file.openRead();
  final digest = await sha256.bind(stream).first;
  return digest.toString();
}

// ---------------------------------------------------------------
// Riverpod glue
// ---------------------------------------------------------------

/// Singleton update-service instance.
final Provider<UpdateService> updateServiceProvider =
    Provider<UpdateService>((ref) => UpdateService());

/// Latest update offer (or null if up-to-date / fetch failed). The
/// notifier polls once at startup and then on a 24h interval.
final NotifierProvider<UpdateNotifier, UpdateInfo?> updateNotifierProvider =
    NotifierProvider<UpdateNotifier, UpdateInfo?>(UpdateNotifier.new);

class UpdateNotifier extends Notifier<UpdateInfo?> {
  Timer? _timer;

  @override
  UpdateInfo? build() {
    Future<void>.microtask(checkNow);
    _timer = Timer.periodic(kUpdateCheckInterval, (_) => checkNow());
    ref.onDispose(() => _timer?.cancel());
    return null;
  }

  Future<void> checkNow() async {
    final svc = ref.read(updateServiceProvider);
    final info = await svc.checkForUpdate();
    state = info;
  }

  void dismiss() {
    // Hide the banner until the next 24h tick (or app restart).
    state = null;
  }
}
