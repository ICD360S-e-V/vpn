// ICD360SVPN — lib/main.dart
//
// Entry point of the Flutter admin app. Wraps the root widget in a
// Riverpod ProviderScope and hands off to the Material app shell.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/api/user_agent.dart';
import 'src/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Resolve the User-Agent string ONCE at startup so the very first
  // outbound HTTP request (auto-update poll on app open) already
  // sees the proper icd360sev_client_vpn_management_versiunea_X.Y.Z
  // value in the server access log instead of the "_pending"
  // placeholder. Cheap call, ~5ms on every platform.
  unawaited(VpnUserAgent.value());
  runApp(const ProviderScope(child: ICD360SVPNApp()));
}
