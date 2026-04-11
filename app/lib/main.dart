// ICD360SVPN — lib/main.dart
//
// Entry point of the Flutter admin app. Wraps the root widget in a
// Riverpod ProviderScope and hands off to the Material app shell.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/app.dart';

void main() {
  runApp(const ProviderScope(child: ICD360SVPNApp()));
}
