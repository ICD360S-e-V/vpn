// ICD360SVPN — lib/src/features/settings/settings_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          const Card(
            child: Column(
              children: <Widget>[
                ListTile(
                  title: Text('About'),
                  subtitle: Text('icd360svpn 0.1.0'),
                ),
                Divider(height: 1),
                ListTile(
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
