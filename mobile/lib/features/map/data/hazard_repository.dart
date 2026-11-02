import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/hazard_report.dart';

final hazardReportsProvider = StreamProvider<List<HazardReport>>((ref) {
  return FirebaseFirestore.instance
      .collection('hazard_reports')
      .limit(200)
      .snapshots()
      .map((snapshot) {
    final now = DateTime.now().toUtc();
    final reports = snapshot.docs
        .map((doc) {
          final data = Map<String, dynamic>.from(doc.data());
          final status = (data['status'] as String?)?.toLowerCase().trim() ?? '';
          final isAuthentic = data['deepfake_is_authentic'] == true;
          final expiresAtRaw = data['expires_at'];
          DateTime? expiresAt;
          if (expiresAtRaw is Timestamp) {
            expiresAt = expiresAtRaw.toDate().toUtc();
          } else if (expiresAtRaw is String) {
            expiresAt = DateTime.tryParse(expiresAtRaw)?.toUtc();
          }

          // Only show verified, deepfake-cleared, non-expired issues on live map.
          if (status != 'verified' || !isAuthentic) {
            return null;
          }
          if (expiresAt != null && expiresAt.isBefore(now)) {
            return null;
          }

          data['id'] = doc.id;
          try {
            return HazardReport.fromJson(data);
          } catch (_) {
            return null;
          }
        })
        .whereType<HazardReport>()
        .toList(growable: true);

    reports.sort((a, b) {
      final aTime = a.createdAt;
      final bTime = b.createdAt;
      if (aTime == null && bTime == null) {
        return 0;
      }
      if (aTime == null) {
        return 1;
      }
      if (bTime == null) {
        return -1;
      }
      return bTime.compareTo(aTime);
    });

    return reports;
  });
});
