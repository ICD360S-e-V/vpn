// ICD360SVPN — lib/src/api/app_prefs.dart
//
// Tiny file-backed key/value store for non-secret UI preferences:
// theme mode, future window size memory, etc. Lives next to
// identity.json under the OS application-support directory but is a
// separate file so wiping it does not log the user out.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

class AppPrefs {
  AppPrefs({Directory? overrideDir}) : _overrideDir = overrideDir;

  final Directory? _overrideDir;
  Directory? _cachedDir;
  Map<String, dynamic> _cache = <String, dynamic>{};
  bool _loaded = false;

  static const String _filename = 'prefs.json';
  static const String _kThemeMode = 'theme_mode';

  Future<File> _file() async {
    final dir = _overrideDir ?? await getApplicationSupportDirectory();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _cachedDir = dir;
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

  /// Returns the saved ThemeMode or [ThemeMode.system] if none.
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
}

// ---------------------------------------------------------------
// Riverpod glue: theme mode notifier with disk persistence
// ---------------------------------------------------------------

final Provider<AppPrefs> appPrefsProvider = Provider<AppPrefs>(
  (ref) => AppPrefs(),
);

final NotifierProvider<ThemeModeController, ThemeMode>
    themeModeProvider =
    NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);

class ThemeModeController extends Notifier<ThemeMode> {
  late AppPrefs _prefs;

  @override
  ThemeMode build() {
    _prefs = ref.read(appPrefsProvider);
    // Best-effort hydrate from disk after first frame so the
    // saved value replaces our default `system` shortly after
    // launch. We don't `await` here because Notifier.build must
    // return synchronously.
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
    // Three-state cycle: system → light → dark → system.
    final next = switch (state) {
      ThemeMode.system => ThemeMode.light,
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
    };
    await set(next);
  }
}
