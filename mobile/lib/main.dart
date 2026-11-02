import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'features/emergency/data/emergency_background_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await initializeEmergencyBackgroundService();
  } catch (_) {
    // Background service is optional during bootstrap; app should still launch.
  }
  runApp(const ProviderScope(child: GuardianGridApp()));
}
