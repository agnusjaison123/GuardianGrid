import 'package:cloud_firestore/cloud_firestore.dart';

class HazardReport {
  const HazardReport({
    required this.id,
    required this.uid,
    required this.location,
    required this.hazardType,
    required this.severity,
    required this.confidence,
    required this.imageUrl,
    required this.status,
    this.photoUrl,
    this.videoUrl,
    this.locationText,
    this.deepfakeVerdict,
    this.deepfakeConfidence,
    this.expiresAt,
    this.createdAt,
  });

  final String id;
  final String uid;
  final GeoPoint location;
  final String hazardType;
  final String severity;
  final double confidence;
  final String imageUrl;
  final String status;
  final String? photoUrl;
  final String? videoUrl;
  final String? locationText;
  final String? deepfakeVerdict;
  final double? deepfakeConfidence;
  final DateTime? expiresAt;
  final DateTime? createdAt;

  factory HazardReport.fromJson(Map<String, dynamic> json) {
    final rawLocation = json['location'];
    final location = rawLocation is GeoPoint
        ? rawLocation
        : GeoPoint(
            (rawLocation is Map ? (rawLocation['latitude'] as num?) : null)
                    ?.toDouble() ??
                0,
            (rawLocation is Map ? (rawLocation['longitude'] as num?) : null)
                    ?.toDouble() ??
                0,
          );

    return HazardReport(
      id: (json['id'] as String?) ?? '',
      uid: (json['uid'] as String?) ?? '',
      location: location,
      hazardType: (json['hazard_type'] as String?) ?? 'unknown',
      severity: (json['severity'] as String?) ?? 'low',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      imageUrl:
          (json['image_url'] as String?) ?? (json['photo_url'] as String?) ?? '',
      status: (json['status'] as String?) ?? 'pending',
      photoUrl: (json['photo_url'] as String?),
      videoUrl: (json['video_url'] as String?),
      locationText: (json['location_text'] as String?),
      deepfakeVerdict: (json['deepfake_verdict'] as String?),
      deepfakeConfidence: (json['deepfake_confidence'] as num?)?.toDouble(),
      expiresAt: _parseTimestamp(json['expires_at']),
      createdAt: _parseTimestamp(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'uid': uid,
      'location': <String, dynamic>{
        'latitude': location.latitude,
        'longitude': location.longitude,
      },
      'hazard_type': hazardType,
      'severity': severity,
      'confidence': confidence,
      'image_url': imageUrl,
      'status': status,
      'photo_url': photoUrl,
      'video_url': videoUrl,
      'location_text': locationText,
      'deepfake_verdict': deepfakeVerdict,
      'deepfake_confidence': deepfakeConfidence,
      'expires_at': expiresAt?.toIso8601String(),
      'created_at': createdAt?.toIso8601String(),
    };
  }

  static DateTime? _parseTimestamp(Object? value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is String) {
      return DateTime.tryParse(value);
    }
    return null;
  }
}
