// ICD360SVPN — lib/src/features/settings/settings_screen.dart
//
// VPN settings: kill switch, auto-connect, notification preferences,
// and profile reinstall. Changing kill switch or auto-connect
// regenerates the .mobileconfig profile (macOS).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/app_logger.dart';
import '../../api/app_prefs.dart';
import '../../api/vpn_tunnel.dart';
import '../../app.dart';
import '../connection/connection_history_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _reinstalling = false;

  Future<void> _reinstallProfile() async {
    if (_reinstalling) return;
    setState(() => _reinstalling = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final phase = ref.read(appPhaseProvider);
      if (phase is! Connected) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Nu ești conectat la server.')),
        );
        return;
      }
      final identity = await ref.read(secureStoreProvider).loadIdentity();
      if (identity == null || !identity.hasWireguard) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Nu există configurație WireGuard.')),
        );
        return;
      }

      final killSwitch = ref.read(killSwitchProvider);
      final autoConnect = ref.read(autoConnectProvider);

      await VpnTunnel.installProfile(
        wgConfig: identity.wgConfig,
        killSwitch: killSwitch,
        autoConnect: autoConnect,
      );
      messenger.showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 5),
          content: Text(
            'Profil generat. Instalează-l din System Settings → '
            'Privacy & Security → Profiles.',
          ),
        ),
      );
    } catch (e) {
      appLogger.error('SETTINGS', 'Reinstalare profil eșuată: $e');
      messenger.showSnackBar(
        SnackBar(content: Text('Eroare: $e')),
      );
    } finally {
      if (mounted) setState(() => _reinstalling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final killSwitch = ref.watch(killSwitchProvider);
    final autoConnect = ref.watch(autoConnectProvider);
    final notifyVpn = ref.watch(notifyVpnProvider);
    final notifyPeers = ref.watch(notifyPeersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          // ----- VPN Settings -----
          Text('VPN', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: <Widget>[
                SwitchListTile(
                  secondary: const Icon(Icons.shield),
                  title: const Text('Kill Switch'),
                  subtitle: const Text(
                    'Blochează traficul de internet dacă VPN-ul '
                    'se deconectează neașteptat.',
                  ),
                  value: killSwitch,
                  onChanged: (v) {
                    ref.read(killSwitchProvider.notifier).set(v);
                    _showProfileReinstallHint();
                  },
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.autorenew),
                  title: const Text('Auto-Connect'),
                  subtitle: const Text(
                    'Conectează-te automat la VPN când rețeaua '
                    'devine disponibilă (WiFi, Ethernet, Cellular).',
                  ),
                  value: autoConnect,
                  onChanged: (v) {
                    ref.read(autoConnectProvider.notifier).set(v);
                    _showProfileReinstallHint();
                  },
                ),
                if (Platform.isMacOS) ...<Widget>[
                  const Divider(height: 1),
                  ListTile(
                    leading: _reinstalling
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                    title: const Text('Reinstalează profil VPN'),
                    subtitle: const Text(
                      'Regenerează .mobileconfig cu setările curente '
                      'și deschide promptul de instalare.',
                    ),
                    onTap: _reinstalling ? null : _reinstallProfile,
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ----- Notification Settings -----
          Text('Notificări', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: <Widget>[
                SwitchListTile(
                  secondary: const Icon(Icons.vpn_lock),
                  title: const Text('Status VPN'),
                  subtitle: const Text(
                    'Notificare când VPN-ul se conectează sau '
                    'deconectează neașteptat.',
                  ),
                  value: notifyVpn,
                  onChanged: (v) =>
                      ref.read(notifyVpnProvider.notifier).set(v),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  secondary: const Icon(Icons.people),
                  title: const Text('Status Peers'),
                  subtitle: const Text(
                    'Notificare când un peer se conectează sau '
                    'deconectează de la VPN.',
                  ),
                  value: notifyPeers,
                  onChanged: (v) =>
                      ref.read(notifyPeersProvider.notifier).set(v),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ----- Connection History -----
          Text('Istoric', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Istoric conexiuni'),
              subtitle: const Text('Evenimentele de conectare/deconectare VPN.'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    appBar: AppBar(title: const Text('Istoric conexiuni')),
                    body: const ConnectionHistoryScreen(),
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // ----- About -----
          Text('Despre', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          const Card(
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
        ],
      ),
    );
  }

  void _showProfileReinstallHint() {
    if (!Platform.isMacOS) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 5),
        content: const Text(
          'Reinstalează profilul VPN pentru a aplica schimbările.',
        ),
        action: SnackBarAction(
          label: 'Reinstalează',
          onPressed: _reinstallProfile,
        ),
      ),
    );
  }
}
