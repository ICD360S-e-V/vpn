// ICD360SVPN — lib/src/features/main/main_shell.dart
//
// NavigationRail-based shell for the connected state. Mirrors the
// Swift M3 NavigationSplitView structure: sidebar with Peers / Health
// / Settings, detail area on the right.

import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../health/health_screen.dart';
import '../peers/peers_screen.dart';
import '../settings/settings_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key, required this.client});

  final ApiClient client;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      PeersScreen(client: widget.client),
      HealthScreen(client: widget.client),
      const SettingsScreen(),
    ];

    return Scaffold(
      body: Row(
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
    );
  }
}
