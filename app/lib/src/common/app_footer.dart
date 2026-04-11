// ICD360SVPN — lib/src/common/app_footer.dart
//
// Single-line attribution footer rendered at the bottom of every
// screen. Reads the running app version via package_info_plus so it
// stays in sync with pubspec.yaml after every release bump.
//
// The version label is tappable: it pushes ChangelogScreen which
// shows the per-version release notes parsed from the auto-generated
// CHANGELOG.md (M7.5).
//
// The check-for-updates icon next to the version (M7.8) does an
// on-demand poll of version.json and either silently confirms
// "up to date" via snackbar or pops the UpdateAvailableDialog so
// the user can self-update without opening Settings.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../api/update_service.dart';
import '../features/about/changelog_screen.dart';
import '../features/updates/update_available_dialog.dart';

class AppFooter extends ConsumerStatefulWidget {
  const AppFooter({super.key});

  @override
  ConsumerState<AppFooter> createState() => _AppFooterState();
}

class _AppFooterState extends ConsumerState<AppFooter> {
  String _version = '';
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _version = '${info.version}+${info.buildNumber}');
    } catch (_) {
      if (!mounted) return;
      setState(() => _version = 'dev');
    }
  }

  void _openChangelog() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const ChangelogScreen(),
      ),
    );
  }

  Future<void> _checkForUpdates() async {
    if (_checking) return;
    setState(() => _checking = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(updateNotifierProvider.notifier).checkNow();
      if (!mounted) return;
      final info = ref.read(updateNotifierProvider);
      if (info != null) {
        await showDialog<void>(
          context: context,
          builder: (_) => UpdateAvailableDialog(info: info),
        );
      } else {
        messenger.showSnackBar(
          const SnackBar(
            duration: Duration(seconds: 3),
            content: Text('Ești pe ultima versiune.'),
          ),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 4),
          content: Text('Verificare eșuată: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant, width: 1),
        ),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              'VPN Management — ICD360S e.V.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (_version.isNotEmpty)
            InkWell(
              onTap: _openChangelog,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Text(
                  'v$_version',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontFamily: 'monospace',
                    decoration: TextDecoration.underline,
                    decorationStyle: TextDecorationStyle.dotted,
                  ),
                ),
              ),
            ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Verifică actualizări',
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(
              minWidth: 28,
              minHeight: 28,
            ),
            icon: _checking
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.system_update_alt),
            onPressed: _checking ? null : _checkForUpdates,
          ),
        ],
      ),
    );
  }
}
