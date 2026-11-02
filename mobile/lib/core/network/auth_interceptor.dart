import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuthInterceptor extends Interceptor {
  AuthInterceptor(this._dio, {FirebaseAuth? auth})
      : _auth = auth ?? FirebaseAuth.instance;

  final Dio _dio;
  final FirebaseAuth _auth;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        final token = await user.getIdToken();
        options.headers['Authorization'] = 'Bearer $token';
      }
    } catch (_) {
      // Continue request without header; API will reject if token is required.
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final statusCode = err.response?.statusCode;
    final alreadyRetried = err.requestOptions.extra['retried'] == true;
    if (statusCode != 401 || alreadyRetried) {
      handler.next(err);
      return;
    }

    final user = _auth.currentUser;
    if (user == null) {
      handler.next(err);
      return;
    }

    try {
      final token = await user.getIdToken(true);
      final updatedHeaders = Map<String, dynamic>.from(err.requestOptions.headers)
        ..['Authorization'] = 'Bearer $token';

      final retryRequest = err.requestOptions.copyWith(
        headers: updatedHeaders,
        extra: <String, dynamic>{
          ...err.requestOptions.extra,
          'retried': true,
        },
      );

      final retryResponse = await _dio.fetch<dynamic>(retryRequest);
      handler.resolve(retryResponse);
    } catch (_) {
      handler.next(err);
    }
  }
}
