// ICD360SVPN — lib/src/api/notification_service.dart
//
// System notification service using flutter_local_notifications.
// Shows native macOS / Linux notifications for VPN status changes
// and peer connect/disconnect events.

import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'app_logger.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  int _nextId = 0;

  /// Initialize the notification plugin. Call once at app startup.
  Future<void> init() async {
    if (_initialized) return;

    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: false,
      requestSoundPermission: true,
    );

    const linuxSettings = LinuxInitializationSettings(
      defaultActionName: 'Deschide',
    );

    const settings = InitializationSettings(
      macOS: darwinSettings,
      linux: linuxSettings,
    );

    final granted = await _plugin.initialize(settings);
    _initialized = granted ?? false;
    if (_initialized) {
      appLogger.info('NOTIF', 'Notificări inițializate');
    } else {
      appLogger.warn('NOTIF', 'Utilizatorul nu a acordat permisiuni');
    }
  }

  /// Request notification permissions (macOS).
  Future<bool> requestPermissions() async {
    if (Platform.isMacOS) {
      final granted = await _plugin
          .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, sound: true);
      return granted ?? false;
    }
    return true;
  }

  Future<void> _show({
    required String title,
    required String body,
  }) async {
    if (!_initialized) return;
    try {
      await _plugin.show(
        _nextId++,
        title,
        body,
        const NotificationDetails(
          macOS: DarwinNotificationDetails(
            presentAlert: true,
            presentSound: true,
          ),
          linux: LinuxNotificationDetails(),
        ),
      );
    } catch (e) {
      appLogger.error('NOTIF', 'Eroare la trimitere notificare: $e');
    }
  }

  // ----- VPN events -----

  Future<void> vpnConnected() async {
    await _show(
      title: 'VPN Conectat',
      body: 'Tunelul WireGuard este activ. Traficul este protejat.',
    );
  }

  Future<void> vpnDisconnected() async {
    await _show(
      title: 'VPN Deconectat',
      body: 'Tunelul WireGuard s-a oprit. Traficul NU este protejat!',
    );
  }

  Future<void> vpnUnexpectedDisconnect() async {
    await _show(
      title: '⚠ VPN Deconectat Neașteptat',
      body: 'Conexiunea VPN s-a pierdut. Verifică rețeaua și reconectează-te.',
    );
  }

  // ----- Peer events -----

  Future<void> peerConnected(String name) async {
    await _show(
      title: 'Peer Conectat',
      body: '${name.isEmpty ? "(unnamed)" : name} s-a conectat la VPN.',
    );
  }

  Future<void> peerDisconnected(String name) async {
    await _show(
      title: 'Peer Deconectat',
      body: '${name.isEmpty ? "(unnamed)" : name} s-a deconectat de la VPN.',
    );
  }

  Future<void> newPeerAdded(String name) async {
    await _show(
      title: 'Peer Nou',
      body: '${name.isEmpty ? "(unnamed)" : name} a fost adăugat la server.',
    );
  }
}
