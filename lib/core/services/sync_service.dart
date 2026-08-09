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

/// Local-first outbox synchronizer: reads pending rows from `sync_queue`
/// (written by the DAOs) and pushes them to Supabase.
///
///  • products / customers / invoices / invoice_items → `upsert` on `sync_id`
///  • stock_movements (operation `stock_delta`) → `apply_stock_delta` RPC
///
/// Local writes are never blocked here; a failing row is just retried later
/// (up to `retryCount`). Requires `--dart-define=SUPABASE_URL=…` and
/// `--dart-define=SUPABASE_ANON_KEY=…` to be active.
class SyncService {
  SyncService(AppDatabase db, {SyncQueueDao? queueDao})
      : _queueDao = queueDao ?? db.syncQueueDao;

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

  /// Placeholder used when no real credentials were passed — sync stays off.
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

  /// Initializes the Supabase client. Safe to call when unconfigured — the
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
      debugPrint('[SyncService] syncNow finished — synced: 0, failed: 0, skipped(offline): false');
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
        debugPrint('[SyncService] item failed — table: ${row.tableRef}, recordSyncId: ${row.recordSyncId}, error: $e');
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
          await Supabase.instance.client.rpc('apply_stock_delta', params: payload);
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
        debugPrint('[SyncService] item failed — table: ${row.tableRef}, recordSyncId: ${row.recordSyncId}, error: $e');
        await _queueDao.markFailed(row.id, e.toString());
        failed++;
      }
    }

    if (synced > 0) {
      await SettingsService.setLastSyncedAt(DateTime.now());
    }
    debugPrint('[SyncService] syncNow finished — synced: $synced, failed: $failed, skipped(offline): false');
    return SyncSummary(synced: synced, failed: failed);
  }

  /// Number of rows waiting to be pushed (for the settings UI badge).
  Future<int> pendingCount() => _queueDao.getPendingCount();

  /// Starts a background timer. Safe to call more than once.
  void startPeriodicSync({Duration interval = const Duration(minutes: 3)}) {
    if (_started || !_configured) return;
    _started = true;
    debugPrint('[SyncService] periodic sync timer started, interval: 3 minutes');
    _timer ??= Timer.periodic(interval, (_) async {
      debugPrint('[SyncService] periodic sync triggered at ${DateTime.now()}');
      lastPeriodicRunAt.value = DateTime.now();
      try {
        await syncNow();
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
