// ICD360SVPN — lib/src/features/settings/settings_screen.dart
//
// M7.9 cleanup: the Account / Logout card was moved to the sidebar
// (NavigationRail trailing actions in MainShell) and the Version /
// Check-for-updates card was removed because the same controls now
// live in the persistent app footer (every screen). What remains
// here is just project links / about information.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const <Widget>[
          Card(
            child: Column(
              children: <Widget>[
                ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('Despre aplicație'),
                  subtitle: Text(
                    'Aplicație de management pentru serverul WireGuard '
                    'al ICD360S e.V. Conectarea, enrollment-ul și '
                    'actualizările automate sunt disponibile prin '
                    'butoanele din sidebar și footer.',
                  ),
                ),
                Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.link),
                  title: Text('github.com/ICD360S-e-V/vpn'),
                  subtitle: Text('Cod sursă, issues, releases'),
                ),
              ],
            ),
          ),
          SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: Icon(Icons.help_outline),
              title: Text('Cum activez VPN-ul?'),
              subtitle: Text(
                'Apasă butonul "Connect to VPN" din colțul din '
                'dreapta-jos. macOS îți va cere parola de admin '
                'pentru a activa tunelul WireGuard. Necesită '
                'wireguard-tools instalat: `brew install wireguard-tools`.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
