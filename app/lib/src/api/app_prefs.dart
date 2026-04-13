// ICD360SVPN — lib/src/api/app_prefs.dart
//
// Tiny file-backed key/value store for non-secret UI preferences:
// theme mode, VPN settings (kill switch, auto-connect), notification
// preferences, etc. Lives next to identity.json under the OS
// application-support directory but is a separate file so wiping it
// does not log the user out.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

class AppPrefs {
  AppPrefs({Directory? overrideDir}) : _overrideDir = overrideDir;

  final Directory? _overrideDir;
  Map<String, dynamic> _cache = <String, dynamic>{};
  bool _loaded = false;

  static const String _filename = 'prefs.json';
  static const String _kThemeMode = 'theme_mode';
  static const String _kKillSwitch = 'vpn_kill_switch';
  static const String _kAutoConnect = 'vpn_auto_connect';
  static const String _kNotifyVpn = 'notify_vpn_status';
  static const String _kNotifyPeers = 'notify_peer_status';

  Future<File> _file() async {
    final dir = _overrideDir ?? await getApplicationSupportDirectory();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File('${dir.path}/$_filename');
  }

  Future<void> _load() async {
    if (_loaded) return;
    try {
      final file = await _file();
      if (await file.exists()) {
        final body = await file.readAsString();
        if (body.trim().isNotEmpty) {
          final decoded = jsonDecode(body);
          if (decoded is Map<String, dynamic>) {
            _cache = decoded;
          }
        }
      }
    } catch (_) {
      _cache = <String, dynamic>{};
    }
    _loaded = true;
  }

  Future<void> _save() async {
    final file = await _file();
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(_cache), flush: true);
    await tmp.rename(file.path);
  }

  // ----- Theme -----

  Future<ThemeMode> loadThemeMode() async {
    await _load();
    final raw = _cache[_kThemeMode] as String?;
    return switch (raw) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> saveThemeMode(ThemeMode mode) async {
    await _load();
    _cache[_kThemeMode] = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    await _save();
  }

  // ----- VPN settings -----

  Future<bool> loadKillSwitch() async {
    await _load();
    return (_cache[_kKillSwitch] as bool?) ?? true; // ON by default
  }

  Future<void> saveKillSwitch(bool value) async {
    await _load();
    _cache[_kKillSwitch] = value;
    await _save();
  }

  Future<bool> loadAutoConnect() async {
    await _load();
    return (_cache[_kAutoConnect] as bool?) ?? true; // ON by default
  }

  Future<void> saveAutoConnect(bool value) async {
    await _load();
    _cache[_kAutoConnect] = value;
    await _save();
  }

  // ----- Notification settings -----

  Future<bool> loadNotifyVpn() async {
    await _load();
    return (_cache[_kNotifyVpn] as bool?) ?? true;
  }

  Future<void> saveNotifyVpn(bool value) async {
    await _load();
    _cache[_kNotifyVpn] = value;
    await _save();
  }

  Future<bool> loadNotifyPeers() async {
    await _load();
    return (_cache[_kNotifyPeers] as bool?) ?? true;
  }

  Future<void> saveNotifyPeers(bool value) async {
    await _load();
    _cache[_kNotifyPeers] = value;
    await _save();
  }
}

// ---------------------------------------------------------------
// Riverpod glue
// ---------------------------------------------------------------

final Provider<AppPrefs> appPrefsProvider = Provider<AppPrefs>(
  (ref) => AppPrefs(),
);

// ----- Theme mode -----

final NotifierProvider<ThemeModeController, ThemeMode>
    themeModeProvider =
    NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);

class ThemeModeController extends Notifier<ThemeMode> {
  late AppPrefs _prefs;

  @override
  ThemeMode build() {
    _prefs = ref.read(appPrefsProvider);
    Future<void>.microtask(() async {
      final saved = await _prefs.loadThemeMode();
      if (saved != state) state = saved;
    });
    return ThemeMode.system;
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    await _prefs.saveThemeMode(mode);
  }

  Future<void> toggle() async {
    final next = switch (state) {
      ThemeMode.system => ThemeMode.light,
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
    };
    await set(next);
  }
}

// ----- Kill switch -----

final NotifierProvider<KillSwitchController, bool>
    killSwitchProvider =
    NotifierProvider<KillSwitchController, bool>(KillSwitchController.new);

class KillSwitchController extends Notifier<bool> {
  late AppPrefs _prefs;

  @override
  bool build() {
    _prefs = ref.read(appPrefsProvider);
    Future<void>.microtask(() async {
      final saved = await _prefs.loadKillSwitch();
      if (saved != state) state = saved;
    });
    return true; // default ON
  }

  Future<void> set(bool value) async {
    state = value;
    await _prefs.saveKillSwitch(value);
  }
}

// ----- Auto-connect -----

final NotifierProvider<AutoConnectController, bool>
    autoConnectProvider =
    NotifierProvider<AutoConnectController, bool>(AutoConnectController.new);

class AutoConnectController extends Notifier<bool> {
  late AppPrefs _prefs;

  @override
  bool build() {
    _prefs = ref.read(appPrefsProvider);
    Future<void>.microtask(() async {
      final saved = await _prefs.loadAutoConnect();
      if (saved != state) state = saved;
    });
    return true; // default ON
  }

  Future<void> set(bool value) async {
    state = value;
    await _prefs.saveAutoConnect(value);
  }
}

// ----- Notification: VPN status -----

final NotifierProvider<NotifyVpnController, bool>
    notifyVpnProvider =
    NotifierProvider<NotifyVpnController, bool>(NotifyVpnController.new);

class NotifyVpnController extends Notifier<bool> {
  late AppPrefs _prefs;

  @override
  bool build() {
    _prefs = ref.read(appPrefsProvider);
    Future<void>.microtask(() async {
      final saved = await _prefs.loadNotifyVpn();
      if (saved != state) state = saved;
    });
    return true;
  }

  Future<void> set(bool value) async {
    state = value;
    await _prefs.saveNotifyVpn(value);
  }
}

// ----- Notification: Peer status -----

final NotifierProvider<NotifyPeersController, bool>
    notifyPeersProvider =
    NotifierProvider<NotifyPeersController, bool>(NotifyPeersController.new);

class NotifyPeersController extends Notifier<bool> {
  late AppPrefs _prefs;

  @override
  bool build() {
    _prefs = ref.read(appPrefsProvider);
    Future<void>.microtask(() async {
      final saved = await _prefs.loadNotifyPeers();
      if (saved != state) state = saved;
    });
    return true;
  }

  Future<void> set(bool value) async {
    state = value;
    await _prefs.saveNotifyPeers(value);
  }
}
