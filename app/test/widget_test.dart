// ICD360SVPN — test/widget_test.dart
//
// Smoke test that the root widget at least mounts without throwing.
// The default `flutter create` template tries to instantiate a
// non-existent `MyApp` class — we ship our own minimal test so the
// CI's `flutter create --platforms=…` step doesn't regenerate the
// stub. Real widget tests will land in M5.1.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:icd360svpn/src/app.dart';

void main() {
  testWidgets('root widget mounts', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: ICD360SVPNApp()),
    );
    // The first frame is the bootstrapping spinner. Just confirming
    // the widget tree builds without exceptions.
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
