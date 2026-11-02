import 'package:dio/dio.dart';

class BaseUrlFailoverInterceptor extends Interceptor {
  BaseUrlFailoverInterceptor(this._dio, this._fallbackBaseUrls);

  final Dio _dio;
  final List<String> _fallbackBaseUrls;

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final isConnectivityError =
        err.type == DioExceptionType.connectionError ||
        err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.receiveTimeout;

    if (!isConnectivityError) {
      handler.next(err);
      return;
    }

    final alreadyRetried =
        err.requestOptions.extra['base_url_failover_done'] == true;
    if (alreadyRetried) {
      handler.next(err);
      return;
    }

    final currentBaseUrl = err.requestOptions.baseUrl.trim();
    for (final fallbackBaseUrl in _fallbackBaseUrls) {
      final normalized = fallbackBaseUrl.trim();
      if (normalized.isEmpty || normalized == currentBaseUrl) {
        continue;
      }

      try {
        final retryRequest = err.requestOptions.copyWith(
          baseUrl: normalized,
          extra: <String, dynamic>{
            ...err.requestOptions.extra,
            'base_url_failover_done': true,
          },
        );
        final retryResponse = await _dio.fetch<dynamic>(retryRequest);
        _dio.options.baseUrl = normalized;
        handler.resolve(retryResponse);
        return;
      } catch (_) {
        // Try next fallback URL.
      }
    }

    handler.next(err);
  }
}
