import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final userProfileRepositoryProvider = Provider<UserProfileRepository>((ref) {
  return UserProfileRepository(FirebaseFirestore.instance);
});

class UserProfileRepository {
  const UserProfileRepository(this._firestore);

  final FirebaseFirestore _firestore;

  Future<void> ensureUserProfile(User user) async {
    final userDocRef = _firestore.collection('users').doc(user.uid);
    final existingSnapshot = await userDocRef.get();
    final existingData = existingSnapshot.data() ?? <String, dynamic>{};

    final trustScore = (existingData['trust_score'] as num?)?.toDouble() ?? 0.5;
    final reportsVerified = (existingData['reports_verified'] as num?)?.toInt() ?? 0;
    final createdAt = existingData['created_at'] ?? FieldValue.serverTimestamp();

    await userDocRef.set(
      <String, dynamic>{
        'email': user.email ?? '',
        'displayName': user.displayName ?? '',
        'trust_score': trustScore,
        'reports_verified': reportsVerified,
        'created_at': createdAt,
      },
      SetOptions(merge: true),
    );
  }
}
