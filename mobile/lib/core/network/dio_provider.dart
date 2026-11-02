import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_interceptor.dart';
import 'base_url_failover_interceptor.dart';

final apiDioProvider = Provider<Dio>((ref) {
  const configuredBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );
  final baseUrl = const String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: kIsWeb ? 'http://localhost:8000' : 'http://127.0.0.1:8000',
  );

  final fallbackUrls = <String>[
    if (!kIsWeb) 'http://10.0.2.2:8000',
    if (!kIsWeb) 'http://localhost:8000',
  ];

  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 30),
    ),
  );

  if (configuredBaseUrl.trim().isEmpty) {
    dio.interceptors.add(BaseUrlFailoverInterceptor(dio, fallbackUrls));
  }
  dio.interceptors.add(AuthInterceptor(dio));
  return dio;
});
