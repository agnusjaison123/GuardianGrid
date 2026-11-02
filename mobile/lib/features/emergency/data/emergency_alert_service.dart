import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'emergency_alert_api.dart';
import 'emergency_alert_queue.dart';
import 'emergency_contact.dart';
import 'emergency_contacts_repository.dart';

final emergencyAlertServiceProvider = Provider<EmergencyAlertService>((ref) {
  final service = EmergencyAlertService(
    contactsRepository: ref.read(emergencyContactsRepositoryProvider),
    emergencyAlertApi: ref.read(emergencyAlertApiProvider),
    alertQueue: ref.read(emergencyAlertQueueProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

class EmergencyAlertService {
  EmergencyAlertService({
    required EmergencyContactsRepository contactsRepository,
    required EmergencyAlertApi emergencyAlertApi,
    required EmergencyAlertQueue alertQueue,
  }) : _contactsRepository = contactsRepository,
       _emergencyAlertApi = emergencyAlertApi,
       _alertQueue = alertQueue;

  final EmergencyContactsRepository _contactsRepository;
  final EmergencyAlertApi _emergencyAlertApi;
  final EmergencyAlertQueue _alertQueue;

  final StreamController<int> _queueCountController =
      StreamController<int>.broadcast();

  Timer? _queueRetryTimer;
  bool _isFlushing = false;

  Stream<int> watchQueueCount() => _queueCountController.stream;

  Future<void> initialize() async {
    await _emitQueueCount();
  }

  void startQueueRetryLoop() {
    _queueRetryTimer ??= Timer.periodic(const Duration(seconds: 30), (_) async {
      await flushQueuedAlerts();
    });
    unawaited(flushQueuedAlerts());
  }

  void stopQueueRetryLoop() {
    _queueRetryTimer?.cancel();
    _queueRetryTimer = null;
  }

  Future<EmergencyWorkflowResult> dispatchEmergency({
    required double latitude,
    required double longitude,
    List<EmergencyContact> manualContacts = const <EmergencyContact>[],
  }) async {
    List<EmergencyContact> firestoreContacts = const <EmergencyContact>[];
    EmergencyContactsException? contactsError;
    try {
      firestoreContacts = await _contactsRepository.fetchContacts();
    } on EmergencyContactsException catch (error) {
      contactsError = error;
    } catch (_) {
      contactsError = const EmergencyContactsException(
        'Could not load emergency contacts.',
      );
    }

    final contacts = _mergeContacts(firestoreContacts, manualContacts);
    if (contacts.isEmpty) {
      if (manualContacts.isEmpty && contactsError != null) {
        throw EmergencyWorkflowException(contactsError.message);
      }
      throw const EmergencyWorkflowException(
        'No emergency contacts found. Add Firestore contacts or a manual contact.',
      );
    }

    final phoneContacts = contacts
        .where((contact) => _normalizePhone(contact.phone).isNotEmpty)
        .toList(growable: false);
    if (phoneContacts.isEmpty) {
      throw const EmergencyWorkflowException(
        'No emergency contact number found. Add at least one valid phone number.',
      );
    }

    try {
      final response = await _emergencyAlertApi.sendAlert(
        latitude: latitude,
        longitude: longitude,
        contacts: phoneContacts,
      );
      await _emitQueueCount();
      return EmergencyWorkflowResult(
        sent: response.sent,
        failed: response.failed,
        queued: false,
        dryRun: response.dryRun,
        message: response.message,
      );
    } on EmergencyAlertApiException catch (error) {
      if (!error.isOffline) {
        throw EmergencyWorkflowException(error.message);
      }

      await _alertQueue.enqueue(
        latitude: latitude,
        longitude: longitude,
        contacts: phoneContacts,
      );
      await _emitQueueCount();
      return const EmergencyWorkflowResult(
        sent: 0,
        failed: 0,
        queued: true,
        dryRun: false,
        message: 'Offline. Alert queued and will retry automatically.',
      );
    }
  }

  Future<int> flushQueuedAlerts() async {
    if (_isFlushing) {
      return 0;
    }
    _isFlushing = true;

    var processed = 0;
    try {
      final pending = await _alertQueue.fetchPending(limit: 25);
      for (final queued in pending) {
        await _alertQueue.markAttempt(queued.id);
        try {
          await _emergencyAlertApi.sendAlert(
            latitude: queued.latitude,
            longitude: queued.longitude,
            contacts: queued.contacts,
          );
          await _alertQueue.remove(queued.id);
          processed += 1;
        } on EmergencyAlertApiException catch (error) {
          if (!error.isOffline) {
            // Permanent server/auth errors should not stay forever in queue.
            await _alertQueue.remove(queued.id);
          } else {
            break;
          }
        } catch (_) {
          break;
        }
      }
      await _emitQueueCount();
      return processed;
    } finally {
      _isFlushing = false;
    }
  }

  Future<int> queuedCount() => _alertQueue.pendingCount();

  Future<void> _emitQueueCount() async {
    final count = await _alertQueue.pendingCount();
    if (!_queueCountController.isClosed) {
      _queueCountController.add(count);
    }
  }

  List<EmergencyContact> _mergeContacts(
    List<EmergencyContact> firestoreContacts,
    List<EmergencyContact> manualContacts,
  ) {
    final merged = <EmergencyContact>[];
    final seenPhones = <String>{};
    final seenEmails = <String>{};

    void appendContact(EmergencyContact contact) {
      final name = contact.name.trim();
      final phone = _normalizePhone(contact.phone);
      final email = (contact.email ?? '').trim().toLowerCase();

      if (name.isEmpty || (phone.isEmpty && email.isEmpty)) {
        return;
      }

      if ((phone.isNotEmpty && seenPhones.contains(phone)) ||
          (email.isNotEmpty && seenEmails.contains(email))) {
        return;
      }

      if (phone.isNotEmpty) {
        seenPhones.add(phone);
      }
      if (email.isNotEmpty) {
        seenEmails.add(email);
      }

      merged.add(
        EmergencyContact(
          name: name,
          phone: phone.isEmpty ? null : phone,
          email: email.isEmpty ? null : email,
          relationship: contact.relationship,
        ),
      );
    }

    for (final contact in firestoreContacts) {
      appendContact(contact);
    }
    for (final contact in manualContacts) {
      appendContact(contact);
    }
    return merged;
  }

  String _normalizePhone(String? phone) {
    if (phone == null) {
      return '';
    }
    return phone.replaceAll(RegExp(r'[^0-9+]'), '');
  }

  void dispose() {
    stopQueueRetryLoop();
    _queueCountController.close();
  }
}

class EmergencyWorkflowResult {
  const EmergencyWorkflowResult({
    required this.sent,
    required this.failed,
    required this.queued,
    required this.dryRun,
    this.message,
  });

  final int sent;
  final int failed;
  final bool queued;
  final bool dryRun;
  final String? message;
}

class EmergencyWorkflowException implements Exception {
  const EmergencyWorkflowException(this.message);

  final String message;

  @override
  String toString() => message;
}
