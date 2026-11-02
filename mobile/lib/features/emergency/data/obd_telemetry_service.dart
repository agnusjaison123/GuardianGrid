import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final obdTelemetryServiceProvider = Provider<ObdTelemetryService>((ref) {
  final service = ObdTelemetryService();
  ref.onDispose(service.dispose);
  return service;
});

class ObdTelemetrySnapshot {
  const ObdTelemetrySnapshot({
    required this.connected,
    required this.status,
    this.speedKmh,
    this.rpm,
    this.updatedAt,
  });

  final bool connected;
  final String status;
  final double? speedKmh;
  final double? rpm;
  final DateTime? updatedAt;
}

class ObdTelemetryService {
  final StreamController<ObdTelemetrySnapshot> _controller =
      StreamController<ObdTelemetrySnapshot>.broadcast();

  Stream<ObdTelemetrySnapshot> get stream => _controller.stream;

  bool _connected = false;
  String _status = 'OBD-II temporarily disabled for demo build';

  Future<void> initializeAndAutoConnect({bool forceReconnect = false}) async {
    if (kIsWeb) {
      _emit(
        const ObdTelemetrySnapshot(
          connected: false,
          status: 'OBD-II unavailable on web',
        ),
      );
      return;
    }
    if (forceReconnect) {
      await disconnect(
        status: 'OBD-II temporarily disabled for demo build',
      );
    }

    _connected = false;
    _status = 'OBD-II temporarily disabled for demo build';
    _emit(
      ObdTelemetrySnapshot(
        connected: _connected,
        status: _status,
      ),
    );
  }

  Future<void> disconnect({String status = 'OBD-II disconnected'}) async {
    _connected = false;
    _status = status;
    _emit(
      ObdTelemetrySnapshot(
        connected: _connected,
        status: _status,
      ),
    );
  }

  void dispose() {
    _controller.close();
  }

  void _emit(ObdTelemetrySnapshot snapshot) {
    if (_controller.isClosed) {
      return;
    }
    _controller.add(snapshot);
  }
}
