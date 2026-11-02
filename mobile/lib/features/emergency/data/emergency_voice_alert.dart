import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_tts/flutter_tts.dart';

final emergencyVoiceAlertProvider = Provider<EmergencyVoiceAlert>((ref) {
  final service = EmergencyVoiceAlert();
  ref.onDispose(service.dispose);
  return service;
});

class EmergencyVoiceAlert {
  final FlutterTts _tts = FlutterTts();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized || kIsWeb) {
      return;
    }
    try {
      await _tts.awaitSpeakCompletion(true);
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(0.48);
      await _tts.setPitch(1.0);
      await _tts.setVolume(1.0);
      _initialized = true;
    } catch (_) {
      // Voice is optional; emergency flow must continue without TTS.
    }
  }

  Future<void> speakCrashWarning({required int seconds}) async {
    await _speak(
      'Possible crash detected. Emergency alert will be sent in $seconds '
      'seconds. Tap I am OK to cancel.',
    );
  }

  Future<void> speakCancelled() async {
    await _speak('Emergency alert cancelled.');
  }

  Future<void> speakAlertSent() async {
    await _speak('Emergency alert sent to your emergency contacts.');
  }

  Future<void> speakQueued() async {
    await _speak('You are offline. Emergency alert has been queued for retry.');
  }

  Future<void> speakFailure({String? reason}) async {
    final text = (reason == null || reason.trim().isEmpty)
        ? 'Emergency alert failed.'
        : 'Emergency alert failed. $reason';
    await _speak(text);
  }

  Future<void> stop() async {
    if (kIsWeb) {
      return;
    }
    try {
      await _tts.stop();
    } catch (_) {
      // Best effort.
    }
  }

  void dispose() {
    unawaited(stop());
  }

  Future<void> _speak(String text) async {
    if (kIsWeb) {
      return;
    }
    await initialize();
    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (_) {
      // Best effort.
    }
  }
}
