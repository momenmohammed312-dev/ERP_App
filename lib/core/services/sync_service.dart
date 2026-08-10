import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/app_database.dart';
import '../database/dao/sync_queue_dao.dart';
import 'settings_service.dart';

/// Result of a single `syncNow()` pass.
class SyncSummary {
  final int synced;
  final int failed;
  final bool skippedOffline;

  const SyncSummary({
    this.synced = 0,
    this.failed = 0,
    this.skippedOffline = false,
  });
}

/// Result of a single `pullNow()` pass.
class PullSummary {
  final int pulled;
  final int skipped;
  final int failed;

  const PullSummary({
    this.pulled = 0,
    this.skipped = 0,
    this.failed = 0,
  });
}

/// Local-first outbox synchronizer: reads pending rows from `sync_queue`
/// (written by the DAOs) and pushes them to Supabase.
///
///  â€¢ products / customers / invoices / invoice_items â†’ `upsert` on `sync_id`
///  â€¢ stock_movements (operation `stock_delta`) â†’ `apply_stock_delta` RPC
///
/// Pull (`pullNow`) reads the same Supabase tables back and writes rows into
/// the local DB through the quiet `upsertFromRemote` DAO paths (which never
/// re-enqueue), so a pulled row is never immediately pushed back up.
///
/// Local writes are never blocked here; a failing row is just retried later
/// (up to `retryCount`). Requires `--dart-define=SUPABASE_URL=â€¦` and
/// `--dart-define=SUPABASE_ANON_KEY=â€¦` to be active.
class SyncService {
  SyncService(AppDatabase db, {SyncQueueDao? queueDao})
      : _db = db,
        _queueDao = queueDao ?? db.syncQueueDao;

  final AppDatabase _db;
  final SyncQueueDao _queueDao;

  Timer? _timer;
  bool _started = false;

  /// Latest time the periodic timer fired and started a sync pass. Set inside
  /// the `Timer.periodic` callback, so the settings UI can react live to
  /// background syncs without a manual refresh.
  final ValueNotifier<DateTime?> lastPeriodicRunAt = ValueNotifier<DateTime?>(null);

  static const String _supabaseUrl =
      String.fromEnvironment('SUPABASE_URL');
  static const String _supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Placeholder used when no real credentials were passed â€” sync stays off.
  static const String _placeholderUrl = 'https://YOUR_PROJECT.supabase.co';
  static const String _placeholderAnonKey = 'YOUR_ANON_KEY';

  /// Maps local outbox table refs to Supabase table names. Tables we only push
  /// via RPC (stock_movements) are intentionally absent here.
  static const Map<String, String> _tableNameMap = {
    'products': 'products',
    'customers': 'customers',
    'invoices': 'invoices',
    'invoice_items': 'invoice_items',
  };

  bool get _configured =>
      _supabaseUrl.isNotEmpty &&
      _supabaseUrl != _placeholderUrl &&
      _supabaseAnonKey.isNotEmpty &&
      _supabaseAnonKey != _placeholderAnonKey;

  /// Initializes the Supabase client. Safe to call when unconfigured â€” the
  /// placeholder keeps the app from crashing, but nothing will ever sync.
  Future<void> initialize() async {
    debugPrint('[SyncService] initialized, supabaseUrl configured: $_configured');
    await Supabase.initialize(
      url: _configured ? _supabaseUrl : _placeholderUrl,
      publishableKey: _configured ? _supabaseAnonKey : _placeholderAnonKey,
    );
  }

  /// One sync pass. Returns a summary; never throws.
  Future<SyncSummary> syncNow() async {
    if (!_configured) {
      return const SyncSummary();
    }
    if (!await _isOnline()) {
      return const SyncSummary(skippedOffline: true);
    }

    final pending = await _queueDao.getPending(limit: 50);
    debugPrint('[SyncService] syncNow started, pending items: ${pending.length}');
    if (pending.isEmpty) {
      debugPrint('[SyncService] syncNow finished â€” synced: 0, failed: 0, skipped(offline): false');
      return const SyncSummary();
    }

    final locationId = await SettingsService.getDeviceLocationId();
    var synced = 0;
    var failed = 0;

    for (final row in pending) {
      Map<String, dynamic> payload;
      try {
        payload = jsonDecode(row.payloadJson) as Map<String, dynamic>;
      } catch (e) {
        debugPrint('[SyncService] item failed â€” table: ${row.tableRef}, recordSyncId: ${row.recordSyncId}, error: $e');
        await _queueDao.markFailed(row.id, 'invalid json: $e');
        failed++;
        continue;
      }

      payload['location_id'] = locationId;
      // The current Supabase schema/RPC doesn't accept a synced-at column, so
      // keep it out of the sent payload.
      payload.remove('device_synced_at');

      try {
        if (row.operation == 'stock_delta') {
          // The remote apply_stock_delta RPC renamed its params with a `p_`
          // prefix (to avoid a 42702 collision against the stock_levels
          // columns); PostgREST matches RPC args by name, so translate the
          // outbox keys here â€” centrally, same as location_id. Don't move this
          // back into the DAO payload maps.
          final rpcParams = {
            'p_product_sync_id': payload['product_sync_id'],
            'p_location_id': payload['location_id'],
            'p_quantity_delta': payload['quantity_delta'],
            'p_movement_type': payload['movement_type'],
            'p_reference': payload['reference'],
            'p_movement_date': payload['movement_date'],
          };
          await Supabase.instance.client.rpc('apply_stock_delta', params: rpcParams);
        } else {
          final table = _tableNameMap[row.tableRef];
          if (table == null) {
            await _queueDao.markFailed(row.id, 'Unknown table: ${row.tableRef}');
            failed++;
            continue;
          }
          await Supabase.instance.client.from(table).upsert(
                payload,
                onConflict: 'sync_id',
              );
        }
        await _queueDao.markSynced(row.id);
        synced++;
      } catch (e) {
        debugPrint('[SyncService] item failed â€” table: ${row.tableRef}, recordSyncId: ${row.recordSyncId}, error: $e');
        await _queueDao.markFailed(row.id, e.toString());
        failed++;
      }
    }

    if (synced > 0) {
      await SettingsService.setLastSyncedAt(DateTime.now());
    }
    debugPrint('[SyncService] syncNow finished â€” synced: $synced, failed: $failed, skipped(offline): false');
    return SyncSummary(synced: synced, failed: failed);
  }

  /// One pull pass: reads changes made on OTHER devices back from Supabase and
  /// writes them into the local DB. Full-table pull for now (not incremental) â€”
  /// the current fleet is a handful of devices, so simplicity wins over
  /// efficiency. Rows land through the quiet `upsertFromRemote` DAO paths that
  /// never re-enqueue, so a pull can never re-queue its own rows for push.
  ///
  /// Order matters: products â†’ customers â†’ invoices â†’ invoice_items, because
  /// the invoice_item FK resolution (Phase 1) needs the parent invoice and
  /// product rows to already be local. Each table is isolated in its own
  /// try/catch so one table failing never aborts the rest.
  Future<PullSummary> pullNow() async {
    if (!_configured) {
      return const PullSummary();
    }
    if (!await _isOnline()) {
      return const PullSummary();
    }

    var pulled = 0;
    var skipped = 0;
    var failed = 0;

    await _pullTable(
      'products',
      (row) async {
        await _db.productDao.upsertFromRemote(row);
        pulled++;
      },
      onError: () => failed++,
    );

    await _pullTable(
      'customers',
      (row) async {
        await _db.customerDao.upsertFromRemote(row);
        pulled++;
      },
      onError: () => failed++,
    );

    await _pullTable(
      'invoices',
      (row) async {
        await _db.invoiceDao.upsertInvoiceFromRemote(row);
        pulled++;
      },
      onError: () => failed++,
    );

    await _pullTable(
      'invoice_items',
      (row) async {
        final written = await _db.invoiceDao.upsertInvoiceItemFromRemote(row);
        if (written) {
          pulled++;
        } else {
          skipped++;
        }
      },
      onError: () => failed++,
    );

    debugPrint('[SyncService] pullNow finished â€” pulled: $pulled, skipped: $skipped, failed: $failed');
    return PullSummary(pulled: pulled, skipped: skipped, failed: failed);
  }

  Future<void> _pullTable(
    String tableRef,
    Future<void> Function(Map<String, dynamic> row) write, {
    required VoidCallback onError,
  }) async {
    try {
      final remoteTable = _tableNameMap[tableRef];
      if (remoteTable == null) {
        debugPrint('[SyncService] pull $tableRef failed: unknown table');
        onError();
        return;
      }
      final rows = await Supabase.instance.client.from(remoteTable).select();
      debugPrint('[SyncService] pull $tableRef started, remote rows: ${rows.length}');
      for (final row in rows) {
        try {
          await write(row);
        } catch (e) {
          debugPrint(
              '[SyncService] item failed â€” table: $tableRef, recordSyncId: ${row['sync_id']}, error: $e');
          onError();
        }
      }
    } catch (e) {
      debugPrint('[SyncService] pull $tableRef failed: $e');
      onError();
    }
  }

  /// Number of rows waiting to be pushed (for the settings UI badge).
  Future<int> pendingCount() => _queueDao.getPendingCount();

  /// Starts a background timer. Safe to call more than once. Each tick runs the
  /// full push-then-pull cycle (same as the manual button), so eventually sync
  /// is fully automatic without any user interaction.
  void startPeriodicSync({Duration interval = const Duration(minutes: 3)}) {
    if (_started || !_configured) return;
    _started = true;
    debugPrint('[SyncService] periodic sync timer started, interval: 3 minutes');
    _timer ??= Timer.periodic(interval, (_) async {
      debugPrint('[SyncService] periodic sync triggered at ${DateTime.now()}');
      lastPeriodicRunAt.value = DateTime.now();
      try {
        await syncNow();
        await pullNow();
      } catch (e) {
        debugPrint('Periodic sync error: $e');
      }
    });
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _started = false;
  }

  Future<bool> _isOnline() async {
    try {
      final results = await Connectivity().checkConnectivity();
      return results.any((r) => r != ConnectivityResult.none);
    } catch (_) {
      // If the connectivity check itself fails, optimistically try to sync.
      return true;
    }
  }
}
