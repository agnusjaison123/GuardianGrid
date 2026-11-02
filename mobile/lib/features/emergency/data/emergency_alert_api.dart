import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_provider.dart';
import 'emergency_contact.dart';

final emergencyAlertApiProvider = Provider<EmergencyAlertApi>(
  (ref) => EmergencyAlertApi(ref.read(apiDioProvider)),
);

class EmergencyAlertApi {
  const EmergencyAlertApi(this._dio);

  final Dio _dio;

  Future<EmergencyAlertResponse> sendAlert({
    required double latitude,
    required double longitude,
    required List<EmergencyContact> contacts,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/emergency/alert',
        data: <String, dynamic>{
          'latitude': latitude,
          'longitude': longitude,
          'contacts': contacts
              .map(
                (contact) => <String, dynamic>{
                  'name': contact.name,
                  'phone': contact.phone,
                  'email': contact.email,
                },
              )
              .toList(growable: false),
        },
      );

      final payload = response.data ?? const <String, dynamic>{};
      return EmergencyAlertResponse(
        sent: (payload['sent'] as num?)?.toInt() ?? 0,
        failed: (payload['failed'] as num?)?.toInt() ?? 0,
        dryRun: payload['dry_run'] == true,
        message: payload['message']?.toString(),
      );
    } on DioException catch (error) {
      if (error.response?.statusCode == 401) {
        throw const EmergencyAlertApiException(
          'Session expired. Sign in again.',
          isOffline: false,
        );
      }
      if (error.type == DioExceptionType.connectionError ||
          error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout) {
        throw const EmergencyAlertApiException(
          'Offline or backend unreachable.',
          isOffline: true,
        );
      }
      final detail = error.response?.data;
      if (detail is Map && detail['detail'] != null) {
        throw EmergencyAlertApiException(
          detail['detail'].toString(),
          isOffline: false,
        );
      }
      throw const EmergencyAlertApiException(
        'Failed to send emergency alert.',
        isOffline: false,
      );
    } catch (_) {
      throw const EmergencyAlertApiException(
        'Failed to send emergency alert.',
        isOffline: false,
      );
    }
  }
}

class EmergencyAlertResponse {
  const EmergencyAlertResponse({
    required this.sent,
    required this.failed,
    required this.dryRun,
    this.message,
  });

  final int sent;
  final int failed;
  final bool dryRun;
  final String? message;
}

class EmergencyAlertApiException implements Exception {
  const EmergencyAlertApiException(this.message, {required this.isOffline});

  final String message;
  final bool isOffline;

  @override
  String toString() => message;
}
