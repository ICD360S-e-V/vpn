// ICD360SVPN — lib/src/features/settings/settings_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../api/update_service.dart';
import '../../app.dart';
import '../updates/update_available_dialog.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String _version = '…';
  String _build = '';
  bool _checkingForUpdate = false;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _version = info.version;
        _build = info.buildNumber;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _version = 'dev');
    }
  }

  Future<void> _checkForUpdate() async {
    setState(() => _checkingForUpdate = true);
    await ref.read(updateNotifierProvider.notifier).checkNow();
    if (!mounted) return;
    setState(() => _checkingForUpdate = false);
    final info = ref.read(updateNotifierProvider);
    if (!mounted) return;
    if (info != null) {
      await showDialog<void>(
        context: context,
        builder: (_) => UpdateAvailableDialog(info: info),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You are on the latest version.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Card(
            child: Column(
              children: <Widget>[
                const ListTile(
                  title: Text('Account'),
                  subtitle: Text(
                    'Logging out clears the cert from the OS keychain. '
                    'You will need to enroll again with a fresh '
                    'vpn-agent issue-bundle output.',
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.red),
                  title: const Text(
                    'Log out',
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Log out?'),
                        content: const Text(
                          'This will remove the saved client certificate '
                          'from this device.',
                        ),
                        actions: <Widget>[
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Log out'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true) {
                      await ref.read(appPhaseProvider.notifier).logout();
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: <Widget>[
                ListTile(
                  title: const Text('Version'),
                  subtitle: Text('icd360svpn $_version (build $_build)'),
                  trailing: _checkingForUpdate
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : TextButton(
                          onPressed: _checkForUpdate,
                          child: const Text('Check for updates'),
                        ),
                ),
                const Divider(height: 1),
                const ListTile(
                  leading: Icon(Icons.link),
                  title: Text('github.com/ICD360S-e-V/vpn'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
