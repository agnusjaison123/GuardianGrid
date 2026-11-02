import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final placeSearchServiceProvider = Provider<PlaceSearchService>((ref) {
  return PlaceSearchService();
});

class PlaceSearchService {
  PlaceSearchService({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: 'https://nominatim.openstreetmap.org',
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 15),
              headers: const <String, String>{
                'User-Agent': 'GuardianGrid/1.0 (Road Safety App)',
                'Accept': 'application/json',
              },
            ),
          );

  final Dio _dio;

  Future<List<PlaceSuggestion>> searchPlaces(String query) async {
    final q = query.trim();
    if (q.length < 3) {
      return const <PlaceSuggestion>[];
    }

    try {
      final response = await _dio.get<List<dynamic>>(
        '/search',
        queryParameters: <String, dynamic>{
          'q': q,
          'format': 'jsonv2',
          'addressdetails': 1,
          'limit': 6,
        },
      );

      final data = response.data;
      if (data == null) {
        return const <PlaceSuggestion>[];
      }

      return data
          .whereType<Map>()
          .map((raw) => Map<String, dynamic>.from(raw))
          .map(PlaceSuggestion.fromJson)
          .where((place) => place.latitude != 0 || place.longitude != 0)
          .toList(growable: false);
    } on DioException {
      return const <PlaceSuggestion>[];
    } catch (_) {
      return const <PlaceSuggestion>[];
    }
  }
}

class PlaceSuggestion {
  const PlaceSuggestion({
    required this.displayName,
    required this.latitude,
    required this.longitude,
  });

  final String displayName;
  final double latitude;
  final double longitude;

  factory PlaceSuggestion.fromJson(Map<String, dynamic> json) {
    final latRaw = json['lat'];
    final lonRaw = json['lon'];

    final latitude = latRaw is num
        ? latRaw.toDouble()
        : double.tryParse(latRaw?.toString() ?? '') ?? 0;
    final longitude = lonRaw is num
        ? lonRaw.toDouble()
        : double.tryParse(lonRaw?.toString() ?? '') ?? 0;

    final displayName = (json['display_name'] as String?)?.trim();

    return PlaceSuggestion(
      displayName: (displayName == null || displayName.isEmpty)
          ? '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}'
          : displayName,
      latitude: latitude,
      longitude: longitude,
    );
  }
}
