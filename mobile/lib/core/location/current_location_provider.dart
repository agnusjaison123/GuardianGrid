import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

class CurrentLocationState {
  const CurrentLocationState({
    required this.label,
    required this.available,
  });

  final String label;
  final bool available;
}

final currentLocationProvider = StreamProvider<CurrentLocationState>((
  ref,
) async* {
  final serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    yield const CurrentLocationState(label: 'GPS off', available: false);
    return;
  }

  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }

  if (permission == LocationPermission.denied ||
      permission == LocationPermission.deniedForever) {
    yield const CurrentLocationState(
      label: 'Location permission blocked',
      available: false,
    );
    return;
  }

  try {
    await for (final position in Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
      ),
    )) {
      yield CurrentLocationState(
        label:
            '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}',
        available: true,
      );
    }
  } catch (_) {
    yield const CurrentLocationState(label: 'GPS unavailable', available: false);
  }
});
