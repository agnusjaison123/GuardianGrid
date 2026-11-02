import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import 'emergency_contact.dart';

final emergencyAlertQueueProvider = Provider<EmergencyAlertQueue>(
  (ref) => EmergencyAlertQueue(),
);

class EmergencyAlertQueue {
  static const _dbName = 'guardian_grid_emergency_queue.db';
  static const _tableName = 'emergency_alert_queue';

  Database? _db;

  Future<void> enqueue({
    required double latitude,
    required double longitude,
    required List<EmergencyContact> contacts,
  }) async {
    final db = await _database();
    final payload = jsonEncode(<String, dynamic>{
      'latitude': latitude,
      'longitude': longitude,
      'contacts': contacts.map((contact) => contact.toJson()).toList(),
    });
    await db.insert(_tableName, <String, Object?>{
      'payload': payload,
      'attempts': 0,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<int> pendingCount() async {
    final db = await _database();
    final result = await db.rawQuery('SELECT COUNT(*) AS c FROM $_tableName');
    final row = result.isNotEmpty ? result.first : const <String, Object?>{};
    final count = (row['c'] as num?)?.toInt() ?? 0;
    return count;
  }

  Future<List<QueuedEmergencyAlert>> fetchPending({int limit = 20}) async {
    final db = await _database();
    final rows = await db.query(
      _tableName,
      orderBy: 'created_at ASC',
      limit: limit,
    );

    return rows
        .map((row) {
          try {
            final payloadRaw = row['payload'] as String? ?? '{}';
            final payload = jsonDecode(payloadRaw) as Map<String, dynamic>;
            final contactsRaw = payload['contacts'];
            final contacts = contactsRaw is List
                ? contactsRaw
                      .whereType<Map>()
                      .map(
                        (item) => EmergencyContact.fromJson(
                          Map<String, dynamic>.from(item),
                        ),
                      )
                      .toList(growable: false)
                : const <EmergencyContact>[];

            return QueuedEmergencyAlert(
              id: (row['id'] as num?)?.toInt() ?? 0,
              latitude: (payload['latitude'] as num?)?.toDouble() ?? 0,
              longitude: (payload['longitude'] as num?)?.toDouble() ?? 0,
              contacts: contacts,
              attempts: (row['attempts'] as num?)?.toInt() ?? 0,
              createdAt: DateTime.fromMillisecondsSinceEpoch(
                (row['created_at'] as num?)?.toInt() ?? 0,
              ),
            );
          } catch (_) {
            return null;
          }
        })
        .whereType<QueuedEmergencyAlert>()
        .toList(growable: false);
  }

  Future<void> markAttempt(int id) async {
    final db = await _database();
    await db.rawUpdate(
      'UPDATE $_tableName SET attempts = attempts + 1 WHERE id = ?',
      <Object?>[id],
    );
  }

  Future<void> remove(int id) async {
    final db = await _database();
    await db.delete(_tableName, where: 'id = ?', whereArgs: <Object?>[id]);
  }

  Future<Database> _database() async {
    if (_db != null) {
      return _db!;
    }
    final dbDir = await getDatabasesPath();
    final path = '$dbDir/$_dbName';
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE $_tableName (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            payload TEXT NOT NULL,
            attempts INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL
          )
        ''');
      },
    );
    return _db!;
  }
}

class QueuedEmergencyAlert {
  const QueuedEmergencyAlert({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.contacts,
    required this.attempts,
    required this.createdAt,
  });

  final int id;
  final double latitude;
  final double longitude;
  final List<EmergencyContact> contacts;
  final int attempts;
  final DateTime createdAt;
}
