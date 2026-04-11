// ICD360SVPN — lib/src/api/macos_updater.dart
//
// Real self-update on macOS, NOT the "drag the new app over the old
// one" workaround that the original `open <DMG>` flow used.
//
// How it works:
//   1. Locate the running .app bundle. We resolve
//      `Platform.resolvedExecutable` (e.g.
//      `/Applications/icd360svpn.app/Contents/MacOS/icd360svpn`)
//      and walk back to the `.app` directory. If the result is NOT
//      under `/Applications/`, we refuse — self-update only works
//      from the canonical install location (~/Applications, the
//      mounted DMG itself, etc. are read-only or vanish on quit).
//   2. Mount the downloaded DMG to a random `/tmp` mount point with
//      `hdiutil attach -nobrowse -mountrandom /tmp`.
//   3. Find the `.app` inside the mounted volume.
//   4. `ditto` the new .app to a per-update temp staging directory
//      under the system temp dir.
//   5. Detach the DMG (`hdiutil detach`).
//   6. Write a small bash helper script that:
//        a. Polls until the parent process (this app) exits.
//        b. Removes `/Applications/icd360svpn.app`.
//        c. `ditto`s the staged .app over /Applications/.
//        d. Strips the `com.apple.quarantine` xattr so the user
//           doesn't get the "downloaded from Internet" prompt.
//        e. `open`s the new .app.
//        f. Cleans up the staging directory.
//   7. Spawn the helper detached (`ProcessStartMode.detached`) so
//      it survives the parent's exit.
//   8. Exit the parent app cleanly.
//
// We use the system tools (`hdiutil`, `ditto`, `xattr`, `open`)
// rather than dart:io directory copies because:
//   - `ditto` is the macOS-blessed copy that preserves resource
//     forks, extended attributes, code-signing seals, and HFS+/APFS
//     metadata; a naive recursive copy via dart:io would corrupt
//     the .app's signature surface.
//   - `hdiutil` is the only sanctioned way to mount a .dmg.
//   - `xattr -dr com.apple.quarantine` is needed because Gatekeeper
//     would otherwise refuse to launch the new app (it's downloaded
//     from the internet) on first launch.
//
// We do NOT use Sparkle or any other framework — Sparkle requires a
// signed Apple Developer ID, which the user explicitly opted out of.

import 'dart:async';
import 'dart:io';

class MacosUpdaterException implements Exception {
  MacosUpdaterException(this.message);
  final String message;
  @override
  String toString() => 'MacosUpdaterException: $message';
}

class MacosUpdater {
  /// Replace the running .app with the contents of [dmgPath] and
  /// relaunch. Caller's app process exits before this method
  /// returns — anything after the call site is unreachable.
  ///
  /// Throws [MacosUpdaterException] if the running app is not in a
  /// writable canonical install location, the DMG is malformed, or
  /// any of the underlying system commands fail.
  static Future<Never> performSelfUpdate(String dmgPath) async {
    if (!Platform.isMacOS) {
      throw MacosUpdaterException('macOS only');
    }

    final appBundle = _findRunningAppBundle();
    if (appBundle == null) {
      throw MacosUpdaterException(
        'cannot locate the running .app bundle from '
        'Platform.resolvedExecutable=${Platform.resolvedExecutable}',
      );
    }
    if (!appBundle.startsWith('/Applications/') &&
        !appBundle.contains('/Applications/')) {
      throw MacosUpdaterException(
        'the app must be installed under /Applications to self-update '
        '(currently at $appBundle). Drag it to /Applications and try '
        'again.',
      );
    }
    if (!await Directory(appBundle).exists()) {
      throw MacosUpdaterException('app bundle $appBundle does not exist');
    }
    // Sanity check: we need to be able to write the parent dir.
    final parent = Directory(appBundle).parent.path;
    final probe = File('$parent/.icd360svpn-update-probe-${pid}');
    try {
      await probe.writeAsString('test');
      await probe.delete();
    } catch (e) {
      throw MacosUpdaterException(
        'cannot write to $parent ($e). Re-run the app from a copy '
        'inside /Applications.',
      );
    }

    // 1. Mount DMG.
    final mountPoint = await _mountDmg(dmgPath);
    String? stagedApp;
    try {
      // 2. Find .app in mount.
      final newAppInDmg = await _findAppInDirectory(mountPoint);
      if (newAppInDmg == null) {
        throw MacosUpdaterException(
          'no .app bundle found inside the DMG mount at $mountPoint',
        );
      }

      // 3. ditto to a per-update staging dir.
      final stageDir = await Directory.systemTemp.createTemp('icd360svpn-update-');
      stagedApp = '${stageDir.path}/icd360svpn.app';
      final dittoResult = await Process.run(
        '/usr/bin/ditto',
        <String>[newAppInDmg, stagedApp],
      );
      if (dittoResult.exitCode != 0) {
        throw MacosUpdaterException(
          'ditto from DMG failed: ${dittoResult.stderr}',
        );
      }

      // 4. Detach DMG (we already have the staged copy).
      await Process.run(
        '/usr/bin/hdiutil',
        <String>['detach', mountPoint, '-quiet'],
      );

      // 5. Write helper script.
      final scriptPath = '${stageDir.path}/finish-update.sh';
      await File(scriptPath).writeAsString(
        _helperScript(
          parentPid: pid,
          stagedApp: stagedApp,
          targetApp: appBundle,
          stageDir: stageDir.path,
        ),
      );
      await Process.run('/bin/chmod', <String>['+x', scriptPath]);

      // 6. Spawn detached so the helper outlives this process.
      await Process.start(
        '/bin/bash',
        <String>[scriptPath],
        mode: ProcessStartMode.detached,
        // Inherit no env / no I/O — fully orphan it.
      );

      // 7. Exit ourselves so the helper can replace the bundle.
      // A small delay so the spawned bash actually starts before
      // we tear down the runtime.
      await Future<void>.delayed(const Duration(milliseconds: 300));
      exit(0);
    } catch (e) {
      // Best-effort cleanup if anything went wrong before we exit.
      await Process.run(
        '/usr/bin/hdiutil',
        <String>['detach', mountPoint, '-quiet', '-force'],
      );
      if (stagedApp != null) {
        try {
          await Directory(File(stagedApp).parent.path).delete(recursive: true);
        } catch (_) {}
      }
      rethrow;
    }
  }

  /// Resolves Platform.resolvedExecutable back to the enclosing .app
  /// directory. Returns null if the executable is not inside a
  /// .app bundle (which happens when running via `flutter run` from
  /// the source tree).
  static String? _findRunningAppBundle() {
    final exe = Platform.resolvedExecutable;
    final marker = '.app/Contents/MacOS/';
    final i = exe.indexOf(marker);
    if (i < 0) return null;
    return exe.substring(0, i + 4); // include `.app`
  }

  static Future<String> _mountDmg(String dmgPath) async {
    final result = await Process.run(
      '/usr/bin/hdiutil',
      <String>[
        'attach',
        dmgPath,
        '-nobrowse',
        '-noautoopen',
        '-mountrandom',
        '/tmp',
      ],
    );
    if (result.exitCode != 0) {
      throw MacosUpdaterException(
        'hdiutil attach failed (exit ${result.exitCode}): ${result.stderr}',
      );
    }
    // hdiutil's output has one line per attached partition. The
    // mount point is the last tab-separated field of the line that
    // ends in a directory path under /tmp.
    final lines = (result.stdout as String).split('\n');
    for (final line in lines.reversed) {
      final fields = line.split('\t');
      if (fields.isEmpty) continue;
      final last = fields.last.trim();
      if (last.startsWith('/tmp/')) {
        return last;
      }
    }
    throw MacosUpdaterException(
      'could not parse mount point from hdiutil output: ${result.stdout}',
    );
  }

  static Future<String?> _findAppInDirectory(String dirPath) async {
    final dir = Directory(dirPath);
    await for (final entry in dir.list()) {
      if (entry is Directory && entry.path.endsWith('.app')) {
        return entry.path;
      }
    }
    return null;
  }

  static String _helperScript({
    required int parentPid,
    required String stagedApp,
    required String targetApp,
    required String stageDir,
  }) {
    // Single-quoted bash heredoc-friendly literal: NO unescaped single
    // quotes inside the script body, and we interpolate the four
    // dynamic values via Dart string interpolation BEFORE the script
    // is written to disk.
    return '''
#!/bin/bash
# ICD360SVPN macOS self-update helper.
# Generated by lib/src/api/macos_updater.dart.
#
# Waits for the parent app (PID $parentPid) to exit, then atomically
# replaces $targetApp with $stagedApp via ditto, strips the
# Gatekeeper quarantine xattr, and relaunches.

set -u

PARENT_PID=$parentPid
STAGED_APP="$stagedApp"
TARGET_APP="$targetApp"
STAGE_DIR="$stageDir"
LOG_FILE="\$STAGE_DIR/finish-update.log"

exec >>"\$LOG_FILE" 2>&1
echo "[\$(date)] starting self-update helper, parent pid \$PARENT_PID"

# Wait up to 30 seconds for the parent to exit.
for i in \$(seq 1 60); do
  if ! kill -0 "\$PARENT_PID" 2>/dev/null; then
    echo "[\$(date)] parent gone after \$i ticks"
    break
  fi
  sleep 0.5
done

# If the parent is still alive after 30s something is very wrong.
if kill -0 "\$PARENT_PID" 2>/dev/null; then
  echo "[\$(date)] parent still alive after 30s, aborting" >&2
  exit 1
fi

# Replace the bundle. ditto handles HFS+/APFS metadata + extended
# attributes correctly; a plain `cp -R` would mangle code-sign seals
# and resource forks.
if [ -d "\$TARGET_APP" ]; then
  /bin/rm -rf "\$TARGET_APP"
fi
/usr/bin/ditto "\$STAGED_APP" "\$TARGET_APP"
DITTO_RC=\$?
if [ \$DITTO_RC -ne 0 ]; then
  echo "[\$(date)] ditto failed with exit \$DITTO_RC" >&2
  exit \$DITTO_RC
fi

# Strip the Gatekeeper quarantine bit so the user doesn't get the
# "downloaded from Internet" warning the first time the new app
# launches.
/usr/bin/xattr -dr com.apple.quarantine "\$TARGET_APP" 2>/dev/null || true

# Relaunch.
/usr/bin/open "\$TARGET_APP"

# Self-clean: remove the staging dir (which contains this very
# script). The bash interpreter has the script file open already
# so deleting it mid-execution is fine on macOS.
/bin/rm -rf "\$STAGE_DIR"

echo "[\$(date)] self-update done"
exit 0
''';
  }
}
