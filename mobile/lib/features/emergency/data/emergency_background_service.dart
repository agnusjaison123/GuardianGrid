import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

const _serviceChannelId = 'guardian_grid_emergency_service';
const _serviceNotificationId = 888;

Future<void> initializeEmergencyBackgroundService() async {
  if (kIsWeb) {
    return;
  }

  const channel = AndroidNotificationChannel(
    _serviceChannelId,
    'GuardianGrid Emergency Monitor',
    description: 'Keeps emergency monitoring active in foreground service mode.',
    importance: Importance.low,
  );
  final localNotifications = FlutterLocalNotificationsPlugin();
  await localNotifications
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(channel);

  final service = FlutterBackgroundService();
  if (await service.isRunning()) {
    service.invoke('stopService');
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: emergencyBackgroundOnStart,
      autoStart: false,
      autoStartOnBoot: false,
      isForegroundMode: true,
      notificationChannelId: _serviceChannelId,
      initialNotificationTitle: 'GuardianGrid',
      initialNotificationContent: 'Emergency monitor ready',
      foregroundServiceNotificationId: _serviceNotificationId,
      foregroundServiceTypes: const <AndroidForegroundType>[
        AndroidForegroundType.location,
      ],
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: emergencyBackgroundOnStart,
      onBackground: emergencyBackgroundOnIosBackground,
    ),
  );
}

@pragma('vm:entry-point')
Future<bool> emergencyBackgroundOnIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

@pragma('vm:entry-point')
void emergencyBackgroundOnStart(ServiceInstance service) {
  DartPluginRegistrant.ensureInitialized();

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });
    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  Timer.periodic(const Duration(minutes: 1), (_) async {
    if (service is AndroidServiceInstance) {
      await service.setForegroundNotificationInfo(
        title: 'GuardianGrid',
        content: 'Emergency monitor active',
      );
    }
  });
}
