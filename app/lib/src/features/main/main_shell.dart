// ICD360SVPN — lib/src/features/main/main_shell.dart
//
// NavigationRail-based shell for the connected state. Sidebar holds
// the page destinations (Status / Peers / Trafic / AdGuard / Settings)
// plus persistent trailing actions: dark-mode toggle and Logout. The
// detail area is on the right, the project footer is pinned to the
// bottom of every screen, and a Connect/Disconnect-to-VPN floating
// action button hovers above the footer.
//
// Notifications: when the VPN tunnel status changes (connected →
// disconnected or vice-versa), a system notification is shown via
// flutter_local_notifications so the user knows even if the app is
// in the background.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_client.dart';
import '../../api/app_logger.dart';
import '../../api/connection_history.dart';
import '../../api/app_prefs.dart';
import '../../api/notification_service.dart';
import '../../api/update_service.dart';
import '../../api/vpn_tunnel.dart';
import '../../app.dart';
import '../../common/app_footer.dart';
import '../../common/log_console.dart';
import '../adguard/adguard_screen.dart';
import '../adguard/dns_log_screen.dart';
import '../speedtest/speed_test_screen.dart';
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
  bool _userInitiatedToggle = false;

  @override
  void initState() {
    super.initState();
    unawaited(NotificationService.instance.init());
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
      final prev = _tunnelStatus;
      appLogger.info('VPN', 'Status: ${s.name}');
      setState(() => _tunnelStatus = s);

      // Send system notifications on status transitions.
      // Skip the initial unknown→X transition and user-initiated toggles
      // (those already show a SnackBar).
      if (prev != VpnTunnelStatus.unknown) {
        // Record connection history
        if (s == VpnTunnelStatus.connected) {
          unawaited(ConnectionHistory.instance.recordConnect());
        } else if (s == VpnTunnelStatus.disconnected &&
            prev == VpnTunnelStatus.connected) {
          unawaited(ConnectionHistory.instance.recordDisconnect());
        }
        // System notifications (unless user-initiated toggle)
        if (!_userInitiatedToggle) {
          final notifyVpn = ref.read(notifyVpnProvider);
          if (notifyVpn) {
            if (s == VpnTunnelStatus.connected) {
              unawaited(NotificationService.instance.vpnConnected());
            } else if (s == VpnTunnelStatus.disconnected &&
                prev == VpnTunnelStatus.connected) {
              unawaited(NotificationService.instance.vpnUnexpectedDisconnect());
            }
          }
        }
      }
      _userInitiatedToggle = false;
    }
  }

  Future<void> _toggleVpn() async {
    if (_busy) return;
    setState(() => _busy = true);
    _userInitiatedToggle = true;
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
        final ks = ref.read(killSwitchProvider);
        final ac = ref.read(autoConnectProvider);
        await VpnTunnel.connect(wgConfig: identity.wgConfig, killSwitch: ks, autoConnect: ac);
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

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      ConnectionScreen(vpnStatus: _tunnelStatus),
      PeersScreen(client: widget.client),
      BandwidthScreen(client: widget.client),
      const AdGuardScreen(),
      const DnsLogScreen(),
      const SpeedTestScreen(),
      const SettingsScreen(),
    ];

    final updateInfo = ref.watch(updateNotifierProvider);
    final isConnected = _tunnelStatus == VpnTunnelStatus.connected;

    return Scaffold(
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
                      icon: Icon(Icons.ads_click_outlined),
                      selectedIcon: Icon(Icons.ads_click),
                      label: Text('AdGuard'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.list_alt_outlined),
                      selectedIcon: Icon(Icons.list_alt),
                      label: Text('DNS Log'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.speed_outlined),
                      selectedIcon: Icon(Icons.speed),
                      label: Text('Speed Test'),
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
          const LogConsole(),
          const AppFooter(),
        ],
      ),
    );
  }


}

/// Custom FAB location that places the FAB above the footer instead
/// of overlapping it.
class _AboveFooterFabLocation extends FloatingActionButtonLocation {
  const _AboveFooterFabLocation({required this.footerOffset});

  final double footerOffset;

  @override
  Offset getOffset(ScaffoldPrelayoutGeometry s) {
    final fabX = s.scaffoldSize.width -
        s.floatingActionButtonSize.width -
        16;
    final fabY = s.scaffoldSize.height -
        s.floatingActionButtonSize.height -
        footerOffset;
    return Offset(fabX, fabY);
  }
}
