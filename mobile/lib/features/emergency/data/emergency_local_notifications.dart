import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final emergencyLocalNotificationsProvider =
    Provider<EmergencyLocalNotifications>(
      (ref) => EmergencyLocalNotifications(),
    );

class EmergencyLocalNotifications {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized || kIsWeb) {
      return;
    }

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings();
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(settings: initSettings);
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
    _initialized = true;
  }

  Future<void> showCrashPrompt({required int seconds}) async {
    if (kIsWeb) {
      return;
    }
    await initialize();
    await _plugin.show(
      id: 1001,
      title: 'GuardianGrid - Are you okay?',
      body:
          'Crash signals detected. Alert sends in $seconds seconds unless cancelled.',
      notificationDetails: _details,
    );
  }

  Future<void> showAlertSent() async {
    if (kIsWeb) {
      return;
    }
    await initialize();
    await _plugin.show(
      id: 1002,
      title: 'GuardianGrid - Emergency Alert',
      body: 'Emergency contacts have been notified.',
      notificationDetails: _details,
    );
  }

  Future<void> showAlertQueued() async {
    if (kIsWeb) {
      return;
    }
    await initialize();
    await _plugin.show(
      id: 1003,
      title: 'GuardianGrid - Emergency Alert',
      body: 'Offline: alert queued and will retry automatically.',
      notificationDetails: _details,
    );
  }

  Future<void> showAlertFailed() async {
    if (kIsWeb) {
      return;
    }
    await initialize();
    await _plugin.show(
      id: 1004,
      title: 'GuardianGrid - Emergency Alert',
      body: 'Could not notify contacts. Check network and retry.',
      notificationDetails: _details,
    );
  }

  NotificationDetails get _details => const NotificationDetails(
    android: AndroidNotificationDetails(
      'emergency_channel',
      'Emergency Alerts',
      channelDescription: 'Crash confirmation prompts and emergency alerts',
      importance: Importance.max,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
  );
}
