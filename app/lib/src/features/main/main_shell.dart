// ICD360SVPN — lib/src/features/main/main_shell.dart
//
// NavigationRail-based shell for the connected state. Sidebar holds
// the page destinations (Peers / Health / Settings) plus persistent
// trailing actions: dark-mode toggle and Logout. The detail area is
// on the right, the project footer is pinned to the bottom of every
// screen, and a Connect/Disconnect-to-VPN floating action button
// hovers above the footer (custom location so it never overlaps).
//
// The Connect button performs a REAL `wg-quick up` via osascript with
// administrator privileges (M7.9). No more "save .conf to Documents
// and pray". Disconnect runs `wg-quick down` symmetrically.
//
// Also hosts the auto-update banner: when UpdateNotifier surfaces a
// new version we drop in a one-line MaterialBanner above the detail
// area inviting the user to open the install dialog.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../api/app_logger.dart';
import '../../api/app_prefs.dart';
import '../../api/update_service.dart';
import '../../api/vpn_tunnel.dart';
import '../../app.dart';
import '../../common/app_footer.dart';
import '../../common/log_console.dart';
import '../bandwidth/bandwidth_screen.dart';
import '../connection/connection_screen.dart';
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
  bool _busy = false;
  VpnTunnelStatus _tunnelStatus = VpnTunnelStatus.unknown;
  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();
    unawaited(_pollStatus());
    _statusTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _pollStatus(),
    );
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    super.dispose();
  }

  Future<void> _pollStatus() async {
    final s = await VpnTunnel.status();
    if (!mounted) return;
    if (s != _tunnelStatus) {
      appLogger.info('VPN', 'Status: ${s.name}');
      setState(() => _tunnelStatus = s);
    }
  }

  Future<void> _toggleVpn() async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (_tunnelStatus == VpnTunnelStatus.connected) {
        await VpnTunnel.disconnect();
        messenger.showSnackBar(
          const SnackBar(
            duration: Duration(seconds: 3),
            content: Text('VPN deconectat.'),
          ),
        );
      } else {
        final identity = await ref.read(secureStoreProvider).loadIdentity();
        if (identity == null || !identity.hasWireguard) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text(
                'Nu există o configurație WireGuard salvată. '
                'Re-enroll cu un cod nou ca să primești una.',
              ),
            ),
          );
          return;
        }
        // Check WireGuard App is installed (macOS) or wg-quick (Linux)
        await VpnTunnel.ensureDependencies();
        await VpnTunnel.connect(wgConfig: identity.wgConfig);
        messenger.showSnackBar(
          const SnackBar(
            duration: Duration(seconds: 3),
            content: Text('VPN conectat.'),
          ),
        );
      }
      // Re-poll immediately so the FAB icon flips without waiting
      // for the next 5s tick.
      await _pollStatus();
    } on VpnTunnelException catch (e) {
      messenger.hideCurrentSnackBar();
      if (e.userCancelled) {
        appLogger.info('VPN', 'Anulat de utilizator');
        return;
      }
      appLogger.error('VPN', e.message);
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 6),
          content: Text(e.message),
        ),
      );
    } catch (e) {
      messenger.hideCurrentSnackBar();
      appLogger.error('VPN', 'Eroare neașteptată: $e');
      messenger.showSnackBar(
        SnackBar(content: Text('Eroare neașteptată: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delogare?'),
        content: const Text(
          'Vei pierde certificatul stocat și va trebui să faci '
          'enrollment din nou cu un cod nou.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Anulează'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delogare'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(appPhaseProvider.notifier).logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      const ConnectionScreen(),
      PeersScreen(client: widget.client),
      BandwidthScreen(client: widget.client),
      const SettingsScreen(),
    ];

    final updateInfo = ref.watch(updateNotifierProvider);
    final themeMode = ref.watch(themeModeProvider);
    final isConnected = _tunnelStatus == VpnTunnelStatus.connected;

    return Scaffold(
      // Custom location pulls the FAB above the footer (which is ~36px
      // tall) so it never sits on top of the version label / check
      // updates button.
      floatingActionButtonLocation: const _AboveFooterFabLocation(
        footerOffset: 52,
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: isConnected
            ? Theme.of(context).colorScheme.errorContainer
            : Theme.of(context).colorScheme.primaryContainer,
        foregroundColor: isConnected
            ? Theme.of(context).colorScheme.onErrorContainer
            : Theme.of(context).colorScheme.onPrimaryContainer,
        onPressed: _busy ? null : _toggleVpn,
        icon: _busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(isConnected ? Icons.vpn_lock : Icons.vpn_lock_outlined),
        label: Text(
          _busy
              ? 'Se procesează…'
              : (isConnected ? 'Disconnect VPN' : 'Connect to VPN'),
        ),
      ),
      body: Column(
        children: <Widget>[
          if (updateInfo != null)
            MaterialBanner(
              leading: const Icon(Icons.system_update),
              content: Text(
                'Versiunea ${updateInfo.version} este disponibilă.',
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () =>
                      ref.read(updateNotifierProvider.notifier).dismiss(),
                  child: const Text('Mai târziu'),
                ),
                FilledButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => UpdateAvailableDialog(info: updateInfo),
                  ),
                  child: const Text('Vezi'),
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
                  onDestinationSelected: (i) =>
                      setState(() => _selected = i),
                  labelType: NavigationRailLabelType.none,
                  destinations: const <NavigationRailDestination>[
                    NavigationRailDestination(
                      icon: Icon(Icons.shield_outlined),
                      selectedIcon: Icon(Icons.shield),
                      label: Text('Status'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.people_outline),
                      selectedIcon: Icon(Icons.people),
                      label: Text('Peers'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.show_chart_outlined),
                      selectedIcon: Icon(Icons.show_chart),
                      label: Text('Trafic'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.settings_outlined),
                      selectedIcon: Icon(Icons.settings),
                      label: Text('Settings'),
                    ),
                  ],
                  trailing: Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            IconButton(
                              tooltip: _themeTooltip(themeMode),
                              icon: Icon(_themeIcon(themeMode)),
                              onPressed: () => ref
                                  .read(themeModeProvider.notifier)
                                  .toggle(),
                            ),
                            const SizedBox(height: 8),
                            IconButton(
                              tooltip: 'Delogare',
                              icon: Icon(
                                Icons.logout,
                                color:
                                    Theme.of(context).colorScheme.error,
                              ),
                              onPressed: _confirmLogout,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const VerticalDivider(thickness: 1, width: 1),
                Expanded(child: pages[_selected]),
              ],
            ),
          ),
          const LogConsole(),
          const AppFooter(),
        ],
      ),
    );
  }

  IconData _themeIcon(ThemeMode mode) {
    return switch (mode) {
      ThemeMode.system => Icons.brightness_auto,
      ThemeMode.light => Icons.light_mode,
      ThemeMode.dark => Icons.dark_mode,
    };
  }

  String _themeTooltip(ThemeMode mode) {
    return switch (mode) {
      ThemeMode.system => 'Temă: System (apasă pentru Light)',
      ThemeMode.light => 'Temă: Light (apasă pentru Dark)',
      ThemeMode.dark => 'Temă: Dark (apasă pentru System)',
    };
  }
}

/// Custom FAB location that places the FAB above the footer instead
/// of overlapping it. The default endFloat / centerFloat assumes the
/// Scaffold's body extends to the bottom of the screen — our footer
/// adds extra fixed height that the FAB has no way of knowing about.
class _AboveFooterFabLocation extends FloatingActionButtonLocation {
  const _AboveFooterFabLocation({required this.footerOffset});

  /// Pixels to lift the FAB above the bottom edge of the Scaffold.
  /// Should be `footer height + desired margin`.
  final double footerOffset;

  @override
  Offset getOffset(ScaffoldPrelayoutGeometry s) {
    final fabX = s.scaffoldSize.width -
        s.floatingActionButtonSize.width -
        16; // right margin
    final fabY = s.scaffoldSize.height -
        s.floatingActionButtonSize.height -
        footerOffset;
    return Offset(fabX, fabY);
  }
}
