import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'emergency_contact.dart';

final emergencyContactsRepositoryProvider =
    Provider<EmergencyContactsRepository>(
      (ref) => EmergencyContactsRepository(
        firestore: FirebaseFirestore.instance,
        auth: FirebaseAuth.instance,
      ),
    );

class EmergencyContactsRepository {
  const EmergencyContactsRepository({
    required FirebaseFirestore firestore,
    required FirebaseAuth auth,
  }) : _firestore = firestore,
       _auth = auth;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  Future<List<EmergencyContact>> fetchContacts() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const EmergencyContactsException(
        'Sign in to load emergency contacts.',
      );
    }

    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('emergency_contacts')
          .get();

      final contacts = snapshot.docs
          .map((doc) => EmergencyContact.fromJson(doc.data()))
          .where((contact) {
            if (contact.name.trim().isEmpty) {
              return false;
            }
            return (contact.email ?? '').isNotEmpty ||
                (contact.phone ?? '').isNotEmpty;
          })
          .toList(growable: false);

      return contacts;
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') {
        throw const EmergencyContactsException(
          'Permission denied while reading emergency contacts.',
        );
      }
      if (error.code == 'unavailable') {
        throw const EmergencyContactsException(
          'Contacts unavailable. Check internet and retry.',
        );
      }
      throw EmergencyContactsException(
        'Could not load contacts (${error.code}).',
      );
    } catch (_) {
      throw const EmergencyContactsException(
        'Could not load emergency contacts.',
      );
    }
  }
}

class EmergencyContactsException implements Exception {
  const EmergencyContactsException(this.message);

  final String message;

  @override
  String toString() => message;
}
