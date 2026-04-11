// ICD360SVPN — lib/src/common/app_footer.dart
//
// Single-line attribution footer rendered at the bottom of every
// screen. Reads the running app version via package_info_plus so it
// stays in sync with pubspec.yaml after every release bump.
//
// The version label is tappable: it pushes ChangelogScreen which
// shows the per-version release notes parsed from the auto-generated
// CHANGELOG.md (M7.5).

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../features/about/changelog_screen.dart';

class AppFooter extends StatefulWidget {
  const AppFooter({super.key});

  @override
  State<AppFooter> createState() => _AppFooterState();
}

class _AppFooterState extends State<AppFooter> {
  String _version = '';

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 2),
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
        ],
      ),
    );
  }
}
