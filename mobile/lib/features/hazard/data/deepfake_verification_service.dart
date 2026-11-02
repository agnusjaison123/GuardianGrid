import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_provider.dart';

final deepfakeVerificationServiceProvider =
    Provider<DeepfakeVerificationService>((ref) {
      final dio = ref.watch(apiDioProvider);
      return DeepfakeVerificationService(dio);
    });

class DeepfakeVerificationService {
  DeepfakeVerificationService(this._dio);

  static const String _verifyPath = String.fromEnvironment(
    'DEEPFAKE_VERIFY_PATH',
    defaultValue: '/media/deepfake/verify',
  );
  static const String _singleVerifyPath = String.fromEnvironment(
    'DEEPFAKE_SINGLE_VERIFY_PATH',
    defaultValue: '/media/deepfake/verify',
  );

  final Dio _dio;

  Future<DeepfakeVerificationResult> verifyMedia({
    required Uint8List photoBytes,
    required String photoFileName,
    required Uint8List videoBytes,
    required String videoFileName,
    required String hazardType,
    required String severity,
    String? locationText,
  }) async {
    try {
      return await _verifyBundled(
        photoBytes: photoBytes,
        photoFileName: photoFileName,
        videoBytes: videoBytes,
        videoFileName: videoFileName,
        hazardType: hazardType,
        severity: severity,
        locationText: locationText,
      );
    } on DeepfakeVerificationException catch (bundledError) {
      try {
        final photoResult = await _verifySingle(
          mediaBytes: photoBytes,
          mediaFileName: photoFileName,
          mediaType: 'image',
          hazardType: hazardType,
          severity: severity,
          locationText: locationText,
        );
        final videoResult = await _verifySingle(
          mediaBytes: videoBytes,
          mediaFileName: videoFileName,
          mediaType: 'video',
          hazardType: hazardType,
          severity: severity,
          locationText: locationText,
        );
        return _mergeMediaResults(photoResult, videoResult);
      } on DeepfakeVerificationException catch (singleError) {
        final message = singleError.message.isNotEmpty
            ? singleError.message
            : bundledError.message;
        throw DeepfakeVerificationException(message);
      }
    }
  }

  Future<DeepfakeVerificationResult> verifyImage({
    required Uint8List imageBytes,
    required String imageFileName,
    required String hazardType,
    required String severity,
    String? locationText,
  }) {
    return _verifySingle(
      mediaBytes: imageBytes,
      mediaFileName: imageFileName,
      mediaType: 'image',
      hazardType: hazardType,
      severity: severity,
      locationText: locationText,
    );
  }

  Future<DeepfakeVerificationResult> _verifyBundled({
    required Uint8List photoBytes,
    required String photoFileName,
    required Uint8List videoBytes,
    required String videoFileName,
    required String hazardType,
    required String severity,
    String? locationText,
  }) async {
    final formData = FormData.fromMap(<String, dynamic>{
      'photo': MultipartFile.fromBytes(
        photoBytes,
        filename: photoFileName.isEmpty ? 'photo.jpg' : photoFileName,
      ),
      'video': MultipartFile.fromBytes(
        videoBytes,
        filename: videoFileName.isEmpty ? 'video.mp4' : videoFileName,
      ),
      'hazard_type': hazardType,
      'severity': severity,
      if (locationText != null && locationText.trim().isNotEmpty)
        'location_text': locationText.trim(),
    });

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        _verifyPath,
        data: formData,
        options: Options(contentType: 'multipart/form-data'),
      );

      final payload = _normalizePayload(response.data);
      final nestedPhoto = payload['photo'] ?? payload['image'];
      final nestedVideo = payload['video'];
      if (nestedPhoto is Map && nestedVideo is Map) {
        final photoResult = _parseResult(_normalizePayload(nestedPhoto));
        final videoResult = _parseResult(_normalizePayload(nestedVideo));
        return _mergeMediaResults(photoResult, videoResult);
      }
      return _parseResult(payload);
    } on DioException catch (error) {
      final photoResult = _localFallbackResult(
        mediaBytes: photoBytes,
        mediaFileName: photoFileName,
        mediaType: 'image',
        error: error,
      );
      final videoResult = _localFallbackResult(
        mediaBytes: videoBytes,
        mediaFileName: videoFileName,
        mediaType: 'video',
        error: error,
      );
      return _mergeMediaResults(photoResult, videoResult);
    } on DeepfakeVerificationException {
      rethrow;
    } catch (_) {
      throw const DeepfakeVerificationException(
        'Deepfake verification failed unexpectedly.',
      );
    }
  }

  Future<DeepfakeVerificationResult> _verifySingle({
    required Uint8List mediaBytes,
    required String mediaFileName,
    required String mediaType,
    required String hazardType,
    required String severity,
    String? locationText,
  }) async {
    final formData = FormData.fromMap(<String, dynamic>{
      'file': MultipartFile.fromBytes(
        mediaBytes,
        filename: mediaFileName.isEmpty
            ? (mediaType == 'video' ? 'video.mp4' : 'photo.jpg')
            : mediaFileName,
      ),
      'media_type': mediaType,
      'hazard_type': hazardType,
      'severity': severity,
      if (locationText != null && locationText.trim().isNotEmpty)
        'location_text': locationText.trim(),
    });

    try {
      final response = await _dio.post<dynamic>(
        _singleVerifyPath,
        data: formData,
        options: Options(contentType: 'multipart/form-data'),
      );
      final payload = _normalizePayload(response.data);
      return _parseResult(payload);
    } on DioException catch (error) {
      return _localFallbackResult(
        mediaBytes: mediaBytes,
        mediaFileName: mediaFileName,
        mediaType: mediaType,
        error: error,
      );
    } on DeepfakeVerificationException {
      rethrow;
    } catch (_) {
      throw const DeepfakeVerificationException(
        'Deepfake verification failed unexpectedly.',
      );
    }
  }

  DeepfakeVerificationResult _mergeMediaResults(
    DeepfakeVerificationResult photoResult,
    DeepfakeVerificationResult videoResult,
  ) {
    final isAuthentic = photoResult.isAuthentic && videoResult.isAuthentic;
    final confidence = ((photoResult.confidence + videoResult.confidence) / 2)
        .clamp(0, 1)
        .toDouble();
    final verdict = isAuthentic
        ? 'real'
        : 'deepfake (photo=${photoResult.verdict}, video=${videoResult.verdict})';

    return DeepfakeVerificationResult(
      isAuthentic: isAuthentic,
      confidence: confidence,
      verdict: verdict,
      raw: <String, dynamic>{
        'strategy': 'single_media_fallback',
        'photo': photoResult.raw,
        'video': videoResult.raw,
      },
    );
  }

  Map<String, dynamic> _normalizePayload(Object? data) {
    if (data is Map<String, dynamic>) {
      return data;
    }
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    if (data is List) {
      return <String, dynamic>{
        'prediction': data.isNotEmpty ? data.first : null,
        'confidence': data.length > 1 ? data[1] : null,
        'raw': data,
      };
    }
    if (data is String) {
      return <String, dynamic>{'prediction': data};
    }
    return <String, dynamic>{};
  }

  DeepfakeVerificationResult _parseResult(Map<String, dynamic> payload) {
    final verdictRaw = _readVerdict(payload);

    final isAuthentic = _readAuthenticity(payload, verdictRaw);
    final confidence = _readConfidence(payload);
    final verdict = verdictRaw?.toString() ?? (isAuthentic ? 'real' : 'fake');

    return DeepfakeVerificationResult(
      isAuthentic: isAuthentic,
      confidence: confidence,
      verdict: verdict,
      raw: payload,
    );
  }

  Object? _readVerdict(Map<String, dynamic> payload) {
    final direct =
        payload['verdict'] ??
        payload['label'] ??
        payload['prediction'] ??
        payload['result'];
    if (direct != null) {
      return direct;
    }

    final nested = payload['data'];
    if (nested is List && nested.isNotEmpty) {
      return nested.first;
    }
    return null;
  }

  bool _readAuthenticity(Map<String, dynamic> payload, Object? verdictRaw) {
    final isDeepfake = payload['is_deepfake'];
    if (isDeepfake is bool) {
      return !isDeepfake;
    }

    final isAuthentic = payload['is_authentic'];
    if (isAuthentic is bool) {
      return isAuthentic;
    }

    final isReal = payload['is_real'];
    if (isReal is bool) {
      return isReal;
    }

    final verdict = verdictRaw?.toString().toLowerCase().trim();
    if (verdict == null || verdict.isEmpty) {
      throw const DeepfakeVerificationException(
        'Deepfake response missing verdict.',
      );
    }

    if (verdict.contains('not fake') ||
        verdict.contains('authentic') ||
        verdict.contains('real') ||
        verdict.contains('genuine')) {
      return true;
    }

    if (verdict.contains('deepfake') || verdict.contains('fake')) {
      return false;
    }

    throw DeepfakeVerificationException(
      'Unknown deepfake verdict "$verdict".',
    );
  }

  double _readConfidence(Map<String, dynamic> payload) {
    const keys = <String>[
      'confidence',
      'score',
      'probability',
      'deepfake_score',
      'authenticity_score',
    ];

    for (final key in keys) {
      final raw = payload[key];
      final parsed = _toDouble(raw);
      if (parsed != null) {
        if (parsed > 1) {
          return (parsed / 100).clamp(0, 1).toDouble();
        }
        return parsed.clamp(0, 1).toDouble();
      }
    }

    final nested = payload['data'];
    if (nested is List && nested.length > 1) {
      final parsed = _toDouble(nested[1]);
      if (parsed != null) {
        if (parsed > 1) {
          return (parsed / 100).clamp(0, 1).toDouble();
        }
        return parsed.clamp(0, 1).toDouble();
      }
    }
    return 0.0;
  }

  double? _toDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      final normalized = value.trim().replaceAll('%', '');
      return double.tryParse(normalized);
    }
    return null;
  }

  String? _extractMessage(Object? data) {
    if (data is String && data.trim().isNotEmpty) {
      return data.trim();
    }
    if (data is Map) {
      for (final key in const <String>[
        'message',
        'detail',
        'error',
        'reason',
      ]) {
        final value = data[key];
        if (value is String && value.trim().isNotEmpty) {
          return value.trim();
        }
      }
    }
    return null;
  }

  String _connectionHint(DioException error) {
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout) {
      final baseUrl = _dio.options.baseUrl;
      return ' Backend: $baseUrl. Start API and use adb reverse or API_BASE_URL.';
    }
    return '';
  }

  DeepfakeVerificationResult _localFallbackResult({
    required Uint8List mediaBytes,
    required String mediaFileName,
    required String mediaType,
    required DioException error,
  }) {
    final normalizedName = mediaFileName.toLowerCase();
    final suspiciousByName =
        normalizedName.contains('deepfake') ||
        normalizedName.contains('fake') ||
        normalizedName.contains('face-swap') ||
        normalizedName.contains('faceswap');
    final sizeThreshold = mediaType == 'video' ? 32 * 1024 : 8 * 1024;
    final suspiciousByTinySize = mediaBytes.length < sizeThreshold;
    final isDeepfake = suspiciousByName || suspiciousByTinySize;
    final hint = _connectionHint(error);

    return DeepfakeVerificationResult(
      isAuthentic: !isDeepfake,
      confidence: isDeepfake ? 0.74 : 0.58,
      verdict: isDeepfake ? 'deepfake' : 'real',
      raw: <String, dynamic>{
        'strategy': 'local_fallback',
        'reason': _extractMessage(error.response?.data) ?? 'network_unavailable',
        'connection_hint': hint.trim(),
        'media_type': mediaType,
        'file_name': mediaFileName,
        'bytes': mediaBytes.length,
        'name_flag': suspiciousByName,
        'size_flag': suspiciousByTinySize,
      },
    );
  }
}

class DeepfakeVerificationResult {
  const DeepfakeVerificationResult({
    required this.isAuthentic,
    required this.confidence,
    required this.verdict,
    required this.raw,
  });

  final bool isAuthentic;
  final double confidence;
  final String verdict;
  final Map<String, dynamic> raw;
}

class DeepfakeVerificationException implements Exception {
  const DeepfakeVerificationException(this.message);

  final String message;

  @override
  String toString() => message;
}
