import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final openMeteoWeatherServiceProvider = Provider<OpenMeteoWeatherService>((ref) {
  return OpenMeteoWeatherService();
});

final currentMapWeatherProvider =
    FutureProvider.family<MapWeatherSnapshot, ({double lat, double lng})>((
      ref,
      coords,
    ) async {
      final service = ref.watch(openMeteoWeatherServiceProvider);
      return service.fetchCurrentWeather(
        latitude: coords.lat,
        longitude: coords.lng,
      );
    });

class OpenMeteoWeatherService {
  OpenMeteoWeatherService({Dio? dio})
      : _dio =
            dio ??
            Dio(
              BaseOptions(
                baseUrl: 'https://api.open-meteo.com',
                connectTimeout: const Duration(seconds: 12),
                receiveTimeout: const Duration(seconds: 20),
              ),
            );

  final Dio _dio;

  Future<MapWeatherSnapshot> fetchCurrentWeather({
    required double latitude,
    required double longitude,
  }) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/v1/forecast',
        queryParameters: <String, dynamic>{
          'latitude': latitude,
          'longitude': longitude,
          'current':
              'temperature_2m,weather_code,precipitation,rain,showers,snowfall,wind_speed_10m',
          'timezone': 'auto',
          'forecast_days': 1,
        },
      );

      final data = response.data ?? const <String, dynamic>{};
      final currentRaw = data['current'];
      if (currentRaw is! Map) {
        throw const OpenMeteoWeatherException('Weather data missing "current".');
      }
      final current = Map<String, dynamic>.from(currentRaw);

      final temperatureC = _readDouble(current['temperature_2m']) ?? 0;
      final weatherCode = _readInt(current['weather_code']) ?? 0;
      final precipitationMm = _readDouble(current['precipitation']) ?? 0;
      final rainMm = _readDouble(current['rain']) ?? 0;
      final showersMm = _readDouble(current['showers']) ?? 0;
      final snowfallMm = _readDouble(current['snowfall']) ?? 0;
      final windKmh = _readDouble(current['wind_speed_10m']) ?? 0;

      final rainLikeMm = rainMm + showersMm + snowfallMm;
      final totalPrecipMm = precipitationMm > rainLikeMm
          ? precipitationMm
          : rainLikeMm;
      final condition = _weatherCodeLabel(weatherCode);

      return MapWeatherSnapshot(
        temperatureC: temperatureC,
        weatherCode: weatherCode,
        precipitationMm: totalPrecipMm,
        windKmh: windKmh,
        condition: condition,
        caution: _roadCautionLabel(
          weatherCode: weatherCode,
          precipitationMm: totalPrecipMm,
          windKmh: windKmh,
        ),
      );
    } on DioException catch (error) {
      throw OpenMeteoWeatherException(
        _extractMessage(error) ??
            'Could not fetch weather conditions from Open-Meteo.',
      );
    } on OpenMeteoWeatherException {
      rethrow;
    } catch (_) {
      throw const OpenMeteoWeatherException(
        'Could not parse weather conditions.',
      );
    }
  }

  double? _readDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value.trim());
    }
    return null;
  }

  int? _readInt(Object? value) {
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value.trim());
    }
    return null;
  }

  String? _extractMessage(DioException error) {
    final data = error.response?.data;
    if (data is Map) {
      for (final key in const <String>['reason', 'detail', 'error', 'message']) {
        final value = data[key];
        if (value is String && value.trim().isNotEmpty) {
          return value.trim();
        }
      }
    }
    return null;
  }

  String _roadCautionLabel({
    required int weatherCode,
    required double precipitationMm,
    required double windKmh,
  }) {
    final severeCode =
        weatherCode >= 95 ||
        weatherCode == 82 ||
        weatherCode == 86 ||
        weatherCode == 75;
    if (severeCode || precipitationMm >= 5 || windKmh >= 55) {
      return 'High Risk';
    }
    if (precipitationMm > 0 || weatherCode >= 51 || windKmh >= 30) {
      return 'Caution';
    }
    return 'Normal';
  }

  String _weatherCodeLabel(int code) {
    switch (code) {
      case 0:
        return 'Clear sky';
      case 1:
      case 2:
      case 3:
        return 'Cloudy';
      case 45:
      case 48:
        return 'Fog';
      case 51:
      case 53:
      case 55:
      case 56:
      case 57:
        return 'Drizzle';
      case 61:
      case 63:
      case 65:
      case 66:
      case 67:
        return 'Rain';
      case 71:
      case 73:
      case 75:
      case 77:
        return 'Snow';
      case 80:
      case 81:
      case 82:
        return 'Rain showers';
      case 85:
      case 86:
        return 'Snow showers';
      case 95:
      case 96:
      case 99:
        return 'Thunderstorm';
      default:
        return 'Unknown';
    }
  }
}

class MapWeatherSnapshot {
  const MapWeatherSnapshot({
    required this.temperatureC,
    required this.weatherCode,
    required this.precipitationMm,
    required this.windKmh,
    required this.condition,
    required this.caution,
  });

  final double temperatureC;
  final int weatherCode;
  final double precipitationMm;
  final double windKmh;
  final String condition;
  final String caution;
}

class OpenMeteoWeatherException implements Exception {
  const OpenMeteoWeatherException(this.message);

  final String message;

  @override
  String toString() => message;
}
