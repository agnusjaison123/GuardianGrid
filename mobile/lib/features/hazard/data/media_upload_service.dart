import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final mediaUploadServiceProvider = Provider<MediaUploadService>((ref) {
  return MediaUploadService();
});

class MediaUploadService {
  MediaUploadService({Dio? dio})
      : _dio =
            dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 20),
                receiveTimeout: const Duration(seconds: 60),
                sendTimeout: const Duration(seconds: 120),
              ),
            );

  static const String _cloudinaryCloudName = String.fromEnvironment(
    'CLOUDINARY_CLOUD_NAME',
    defaultValue: '',
  );
  static const String _cloudinaryUploadPreset = String.fromEnvironment(
    'CLOUDINARY_UPLOAD_PRESET',
    defaultValue: '',
  );
  static const String _cloudinaryFolder = String.fromEnvironment(
    'CLOUDINARY_UPLOAD_FOLDER',
    defaultValue: 'guardian-grid/hazards',
  );
  static const bool _allowDemoMediaFallback = bool.fromEnvironment(
    'ALLOW_DEMO_MEDIA_FALLBACK',
    defaultValue: true,
  );

  final Dio _dio;

  Future<String> uploadImage({
    required Uint8List bytes,
    required String fileName,
    required String publicId,
    void Function(double progress)? onProgress,
  }) {
    return _upload(
      resourceType: 'image',
      bytes: bytes,
      fileName: fileName,
      publicId: publicId,
      onProgress: onProgress,
    );
  }

  Future<String> uploadVideo({
    required Uint8List bytes,
    required String fileName,
    required String publicId,
    void Function(double progress)? onProgress,
  }) {
    return _upload(
      resourceType: 'video',
      bytes: bytes,
      fileName: fileName,
      publicId: publicId,
      onProgress: onProgress,
    );
  }

  Future<String> _upload({
    required String resourceType,
    required Uint8List bytes,
    required String fileName,
    required String publicId,
    void Function(double progress)? onProgress,
  }) async {
    if (_cloudinaryCloudName.isEmpty || _cloudinaryUploadPreset.isEmpty) {
      if (_allowDemoMediaFallback) {
        onProgress?.call(1);
        return _fallbackMediaUrl(
          resourceType: resourceType,
          publicId: publicId,
          fileName: fileName,
        );
      }
      throw const MediaUploadException(
        'Cloudinary is not configured. Set CLOUDINARY_CLOUD_NAME and CLOUDINARY_UPLOAD_PRESET.',
      );
    }

    final endpoint =
        'https://api.cloudinary.com/v1_1/$_cloudinaryCloudName/$resourceType/upload';
    final formData = FormData.fromMap(<String, dynamic>{
      'file': MultipartFile.fromBytes(
        bytes,
        filename: fileName.isEmpty ? '$resourceType.bin' : fileName,
      ),
      'upload_preset': _cloudinaryUploadPreset,
      'folder': _cloudinaryFolder,
      'public_id': publicId,
    });

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        endpoint,
        data: formData,
        options: Options(contentType: 'multipart/form-data'),
        onSendProgress: (sent, total) {
          if (onProgress == null) {
            return;
          }
          if (total <= 0) {
            return;
          }
          onProgress((sent / total).clamp(0, 1).toDouble());
        },
      );

      final payload = response.data ?? const <String, dynamic>{};
      final secureUrl = payload['secure_url']?.toString();
      if (secureUrl == null || secureUrl.trim().isEmpty) {
        throw const MediaUploadException(
          'Media upload succeeded but no secure URL was returned.',
        );
      }
      return secureUrl.trim();
    } on DioException catch (error) {
      if (_allowDemoMediaFallback) {
        onProgress?.call(1);
        return _fallbackMediaUrl(
          resourceType: resourceType,
          publicId: publicId,
          fileName: fileName,
        );
      }
      final message = _extractMessage(error.response?.data);
      throw MediaUploadException(
        message ?? 'Media upload failed. Check Cloudinary setup and network.',
      );
    } on MediaUploadException {
      rethrow;
    } catch (_) {
      throw const MediaUploadException('Media upload failed unexpectedly.');
    }
  }

  String _fallbackMediaUrl({
    required String resourceType,
    required String publicId,
    required String fileName,
  }) {
    final safeFileName = fileName.trim().isEmpty ? '$resourceType.bin' : fileName.trim();
    final encodedPublicId = Uri.encodeComponent(publicId.trim().isEmpty ? 'demo-media' : publicId.trim());
    final encodedFileName = Uri.encodeComponent(safeFileName);
    return 'demo-media://$resourceType/$encodedPublicId/$encodedFileName';
  }

  String? _extractMessage(Object? data) {
    if (data is String && data.trim().isNotEmpty) {
      return data.trim();
    }
    if (data is Map) {
      final nestedError = data['error'];
      if (nestedError is Map) {
        final nestedMessage = nestedError['message'];
        if (nestedMessage is String && nestedMessage.trim().isNotEmpty) {
          return nestedMessage.trim();
        }
      }

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
}

class MediaUploadException implements Exception {
  const MediaUploadException(this.message);

  final String message;

  @override
  String toString() => message;
}
