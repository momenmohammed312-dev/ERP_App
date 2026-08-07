import 'dart:convert';

import 'package:drift/drift.dart';

import '../tables/sync_queue_table.dart';
import '../app_database.dart';
import '../../services/settings_service.dart';

part 'sync_queue_dao.g.dart';

@DriftAccessor(tables: [SyncQueue])
class SyncQueueDao extends DatabaseAccessor<AppDatabase>
    with _$SyncQueueDaoMixin {
  SyncQueueDao(super.db);

  // Resolved lazily on first enqueue and cached afterwards, so we don't hit
  // SharedPreferences on every write.
  static Future<String>? _deviceNameFuture;

  /// Queue a record change for later sync. Payload is JSON-encoded here.
  Future<void> enqueue({
    required String tableName,
    required String recordSyncId,
    required String operation,
    required Map<String, dynamic> payload,
  }) async {
    final deviceName = await _resolveDeviceName();
    await into(syncQueue).insert(
      SyncQueueCompanion.insert(
        tableRef: tableName,
        recordSyncId: recordSyncId,
        operation: operation,
        payloadJson: jsonEncode(payload),
        deviceName: Value(deviceName.isEmpty ? null : deviceName),
      ),
    );
  }

  static Future<String> _resolveDeviceName() async {
    try {
      final existing = _deviceNameFuture;
      if (existing != null) return await existing;
      final future = SettingsService.getDeviceLocationId();
      _deviceNameFuture = future;
      return await future;
    } catch (_) {
      // Never let settings access break enqueueing — reset so we can retry.
      _deviceNameFuture = null;
      return '';
    }
  }

  /// Rows still waiting to be synced, oldest first, that have not exceeded the
  /// retry budget.
  Future<List<SyncQueueData>> getPending({int limit = 50}) =>
      (select(syncQueue)
            ..where(
              (tbl) => tbl.syncedAt.isNull() & tbl.retryCount.isSmallerThanValue(8),
            )
            ..orderBy([
              (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.asc),
            ])
            ..limit(limit))
          .get();

  /// Mark a queue row as successfully synced.
  Future<void> markSynced(int queueId) =>
      (update(syncQueue)..where((tbl) => tbl.id.equals(queueId))).write(
        SyncQueueCompanion(
          syncedAt: Value(DateTime.now()),
        ),
      );

  /// Mark a queue row as failed: bump retry count and record the error.
  Future<void> markFailed(int queueId, String error) async {
    final row = await (select(syncQueue)..where((tbl) => tbl.id.equals(queueId)))
        .getSingleOrNull();
    if (row == null) return;
    await (update(syncQueue)..where((tbl) => tbl.id.equals(queueId))).write(
      SyncQueueCompanion(
        retryCount: Value(row.retryCount + 1),
        lastError: Value(error),
      ),
    );
  }

  /// Count of rows still waiting to be synced.
  Future<int> getPendingCount() async {
    final query = selectOnly(syncQueue)
      ..addColumns([syncQueue.id.count()])
      ..where(syncQueue.syncedAt.isNull() & syncQueue.retryCount.isSmallerThanValue(8));
    final row = await query.getSingle();
    return row.read(syncQueue.id.count()) ?? 0;
  }
}
