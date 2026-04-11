// ICD360SVPN — lib/src/features/main/main_shell.dart
//
// NavigationRail-based shell for the connected state. Mirrors the
// Swift M3 NavigationSplitView structure: sidebar with Peers / Health
// / Settings, detail area on the right, and the project footer
// pinned to the bottom of every screen.
//
// Also hosts the auto-update banner: when UpdateNotifier surfaces a
// new version we drop in a one-line MaterialBanner above the detail
// area inviting the user to open the install dialog.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../api/secure_store.dart';
import '../../api/update_service.dart';
import '../../api/vpn_tunnel.dart';
import '../../app.dart';
import '../../common/app_footer.dart';
import '../health/health_screen.dart';
import '../peers/peers_screen.dart';
import '../settings/settings_screen.dart';
import '../updates/update_available_dialog.dart';

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key, required this.client});

  final ApiClient client;

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  int _selected = 0;
  bool _connecting = false;

  Future<void> _connectVpn() async {
    if (_connecting) return;
    setState(() => _connecting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final store = ref.read(secureStoreProvider);
      final identity = await store.loadIdentity();
      if (identity == null || !identity.hasWireguard) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Nu există un tunnel WireGuard salvat. '
              'Re-enroll cu un cod nou ca să primești unul.',
            ),
          ),
        );
        return;
      }
      final path = await VpnTunnel.importTunnel(
        wgConfig: identity.wgConfig,
      );
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 6),
          content: Text(
            'Tunnel salvat la $path. WireGuard ar trebui să-l '
            'preia automat — confirmă importul în fereastra '
            'WireGuard, apoi activează switch-ul.',
          ),
        ),
      );
    } on VpnTunnelException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Eroare: $e')));
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      PeersScreen(client: widget.client),
      HealthScreen(client: widget.client),
      const SettingsScreen(),
    ];

    final updateInfo = ref.watch(updateNotifierProvider);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _connecting ? null : _connectVpn,
        icon: _connecting
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.vpn_lock),
        label: Text(_connecting ? 'Se importă…' : 'Connect to VPN'),
      ),
      body: Column(
        children: <Widget>[
          if (updateInfo != null)
            MaterialBanner(
              leading: const Icon(Icons.system_update),
              content: Text(
                'Version ${updateInfo.version} is available.',
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () =>
                      ref.read(updateNotifierProvider.notifier).dismiss(),
                  child: const Text('Later'),
                ),
                FilledButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => UpdateAvailableDialog(info: updateInfo),
                  ),
                  child: const Text('View'),
                ),
              ],
            ),
          Expanded(
            child: Row(
              children: <Widget>[
                NavigationRail(
                  extended: true,
                  minExtendedWidth: 180,
                  selectedIndex: _selected,
                  onDestinationSelected: (i) => setState(() => _selected = i),
                  labelType: NavigationRailLabelType.none,
                  destinations: const <NavigationRailDestination>[
                    NavigationRailDestination(
                      icon: Icon(Icons.people_outline),
                      selectedIcon: Icon(Icons.people),
                      label: Text('Peers'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.favorite_outline),
                      selectedIcon: Icon(Icons.favorite),
                      label: Text('Health'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.settings_outlined),
                      selectedIcon: Icon(Icons.settings),
                      label: Text('Settings'),
                    ),
                  ],
                ),
                const VerticalDivider(thickness: 1, width: 1),
                Expanded(child: pages[_selected]),
              ],
            ),
          ),
          const AppFooter(),
        ],
      ),
    );
  }
}
