// ICD360SVPN — lib/src/app.dart
//
// Top-level Material app + the lifecycle phase machine. The phase
// drives ContentRouter which decides whether to show the enrollment
// screen, the main shell, or an error screen.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api/api_client.dart';
import 'api/app_prefs.dart';
import 'api/enroll_client.dart';
import 'api/secure_store.dart';
import 'features/enrollment/enrollment_screen.dart';
import 'features/main/error_screen.dart';
import 'features/main/main_shell.dart';

// ---------------------------------------------------------------
// Lifecycle phases
// ---------------------------------------------------------------

sealed class AppPhase {
  const AppPhase();
}

class Bootstrapping extends AppPhase {
  const Bootstrapping();
}

class NeedsEnrollment extends AppPhase {
  const NeedsEnrollment({this.lastError});
  final String? lastError;
}

class Connecting extends AppPhase {
  const Connecting();
}

class Connected extends AppPhase {
  const Connected(this.client);
  final ApiClient client;
}

class FatalError extends AppPhase {
  const FatalError(this.message);
  final String message;
}

// ---------------------------------------------------------------
// Providers
// ---------------------------------------------------------------
//
// Riverpod 3.0 API: `StateNotifier` and `StateNotifierProvider` are
// removed in favour of `Notifier` + `NotifierProvider`. The new
// Notifier overrides `build()` to return the initial state and reads
// any dependencies via `ref` instead of constructor injection.

/// Singleton secure-storage wrapper.
final Provider<SecureStore> secureStoreProvider =
    Provider<SecureStore>((ref) => SecureStore());

/// The app's lifecycle phase. Driven by [AppPhaseController].
final NotifierProvider<AppPhaseController, AppPhase> appPhaseProvider =
    NotifierProvider<AppPhaseController, AppPhase>(AppPhaseController.new);

class AppPhaseController extends Notifier<AppPhase> {
  late SecureStore _store;

  @override
  AppPhase build() {
    _store = ref.read(secureStoreProvider);
    // Kick off the keychain probe asynchronously. The first state
    // the UI sees is Bootstrapping; once the probe finishes, the
    // controller flips to NeedsEnrollment or Connected.
    Future<void>.microtask(bootstrap);
    return const Bootstrapping();
  }

  Future<void> bootstrap() async {
    state = const Bootstrapping();
    try {
      final id = await _store.loadIdentity();
      if (id == null) {
        state = const NeedsEnrollment();
        return;
      }
      final client = ApiClient(
        baseUrl: id.agentUrl,
        certPem: id.certPem,
        keyPem: id.keyPem,
        caPem: id.caPem,
      );
      state = Connected(client);
    } catch (e) {
      state = NeedsEnrollment(lastError: e.toString());
    }
  }

  /// M7.2: exchange a 16-char short code for a v2 enrollment bundle.
  /// On success, persists the cert + WG config and flips state to
  /// Connected. On any failure, flips back to NeedsEnrollment with
  /// the friendly error message from EnrollClient.
  Future<void> enrollFromCode(String code) async {
    state = const Connecting();
    try {
      final bundle = await EnrollClient().exchange(code);
      await _store.saveIdentity(
        certPem: bundle.certPem,
        keyPem: bundle.keyPem,
        caPem: bundle.caPem,
        agentUrl: bundle.agentUrl,
        identityName: bundle.name,
        wgConfig: bundle.wireguardConfig,
        wgPublicKey: bundle.wireguardPublicKey,
        wgAddress: bundle.wireguardAddress,
      );
      final client = ApiClient(
        baseUrl: bundle.agentUrl,
        certPem: bundle.certPem,
        keyPem: bundle.keyPem,
        caPem: bundle.caPem,
      );
      state = Connected(client);
    } catch (e) {
      state = NeedsEnrollment(lastError: e.toString());
    }
  }

  Future<void> logout() async {
    await _store.clear();
    state = const NeedsEnrollment();
  }
}

// ---------------------------------------------------------------
// Root widget
// ---------------------------------------------------------------

class ICD360SVPNApp extends ConsumerWidget {
  const ICD360SVPNApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return MaterialApp(
      title: 'ICD360S VPN',
      debugShowCheckedModeBanner: false,
      themeMode: mode,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A73E8),
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A73E8),
          brightness: Brightness.dark,
        ),
      ),
      home: const ContentRouter(),
    );
  }
}

class ContentRouter extends ConsumerWidget {
  const ContentRouter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phase = ref.watch(appPhaseProvider);
    return switch (phase) {
      Bootstrapping() => const _CenteredSpinner(label: 'Loading…'),
      NeedsEnrollment() => const EnrollmentScreen(),
      Connecting() => const _CenteredSpinner(label: 'Connecting…'),
      Connected(client: final c) => MainShell(client: c),
      FatalError(message: final m) => ErrorScreen(message: m),
    };
  }
}

class _CenteredSpinner extends StatelessWidget {
  const _CenteredSpinner({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text(label),
          ],
        ),
      ),
    );
  }
}
