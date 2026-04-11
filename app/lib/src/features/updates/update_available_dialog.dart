// ICD360SVPN — lib/src/features/updates/update_available_dialog.dart
//
// Modal sheet shown when UpdateNotifier surfaces an UpdateInfo. The
// user sees the new version, the bullet-pointed changelog, and a
// "Download & Install" button. On press we download the platform-
// specific DMG / deb / msi to ~/Downloads, verify SHA256, ask the
// OS to open it, then quit so the new installer can replace the
// running app without "file in use" errors.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/update_service.dart';
import '../../models/update_info.dart';

class UpdateAvailableDialog extends ConsumerStatefulWidget {
  const UpdateAvailableDialog({super.key, required this.info});

  final UpdateInfo info;

  @override
  ConsumerState<UpdateAvailableDialog> createState() =>
      _UpdateAvailableDialogState();
}

class _UpdateAvailableDialogState extends ConsumerState<UpdateAvailableDialog> {
  bool _busy = false;
  double _progress = 0;
  String? _errorMessage;

  Future<void> _downloadAndInstall() async {
    final platform = currentPlatformKey();
    final asset = widget.info.assetFor(platform);
    if (asset == null) {
      setState(() => _errorMessage = 'No installer published for $platform');
      return;
    }

    setState(() {
      _busy = true;
      _progress = 0;
      _errorMessage = null;
    });

    final svc = ref.read(updateServiceProvider);
    final filename = _filenameFor(platform, widget.info.version);
    String? dlPath;
    try {
      dlPath = await svc.downloadUpdate(
        asset,
        filename: filename,
        onProgress: (received, total) {
          if (total > 0) {
            setState(() => _progress = received / total);
          }
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorMessage = e.toString();
      });
      return;
    }

    // Hand off to the OS-native installer flow.
    try {
      await svc.launchInstaller(dlPath);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorMessage = 'Could not open installer: $e';
      });
      return;
    }

    // Confirm with the user before quitting so they don't lose the
    // running session unexpectedly.
    if (!mounted) return;
    final shouldQuit = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Installer ready'),
        content: const Text(
          'The new version has been opened in Finder. Drag it to '
          'Applications (replacing the old copy), then click "Quit Now" '
          'so the new app can launch cleanly.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Stay open'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Quit Now'),
          ),
        ],
      ),
    );
    if (shouldQuit == true) {
      svc.quitApp();
    }
  }

  String _filenameFor(String platform, String version) {
    final ext = switch (platform) {
      'macos' => 'dmg',
      'linux' => 'deb',
      'windows' => 'msi',
      _ => 'bin',
    };
    return 'icd360svpn-$version.$ext';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      icon: const Icon(Icons.system_update),
      title: Text('Update available — v${widget.info.version}'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Released ${widget.info.releasedAt.toLocal().toString().split(".").first}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            if (widget.info.changelog.isNotEmpty) ...<Widget>[
              Text(
                "What's new",
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: widget.info.changelog
                        .map(
                          (line) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                const Text('•  '),
                                Expanded(child: Text(line)),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
            ],
            if (_busy) ...<Widget>[
              const SizedBox(height: 16),
              LinearProgressIndicator(value: _progress > 0 ? _progress : null),
              const SizedBox(height: 4),
              Text(
                _progress > 0
                    ? 'Downloading… ${(_progress * 100).toStringAsFixed(0)}%'
                    : 'Downloading…',
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (_errorMessage != null) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _busy
              ? null
              : () {
                  ref.read(updateNotifierProvider.notifier).dismiss();
                  Navigator.pop(context);
                },
          child: const Text('Later'),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.download),
          label: const Text('Download & Install'),
          onPressed: _busy ? null : _downloadAndInstall,
        ),
      ],
    );
  }
}
