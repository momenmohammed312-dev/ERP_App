import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/services/settings_service.dart';
import 'package:pos_offline_desktop/core/services/sync_service.dart';

/// System-service tests that are deterministic and require NO network or
/// Supabase instance. These cover the sync engine's safe behaviour: it must be
/// a no-op (and never throw) before it is configured with real credentials,
/// and it must report the length of the pending outbox.
void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
  });

  AppDatabase openDb() {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    return db;
  }

  test('syncNow() is a safe no-op before credentials are provided', () async {
    final db = openDb();
    final sync = SyncService(db);

    // No SUPABASE_URL / SUPABASE_ANON_KEY dart-defines are present in tests,
    // so the service is "unconfigured" and must not attempt any network I/O.
    final summary = await sync.syncNow();
    expect(summary.synced, 0);
    expect(summary.failed, 0);
    expect(summary.skippedOffline, isFalse,
        reason: 'unconfigured is not an "offline" skip — it is simply off');
  });

  test('startPeriodicSync is a safe no-op when unconfigured', () async {
    final db = openDb();
    final sync = SyncService(db);
    // Must return immediately without scheduling a timer or touching Supabase.
    sync.startPeriodicSync();
    expect(await sync.pendingCount(), 0);
  });

  test('pendingCount reflects queued, unflushed rows', () async {
    final db = openDb();
    final sync = SyncService(db);
    expect(await sync.pendingCount(), 0);

    await db.productDao.insertProduct(ProductsCompanion.insert(
      name: 'منتج',
      quantity: 5,
      price: 3.0,
    ));
    expect(await sync.pendingCount(), 1,
        reason: 'a local product write must surface as 1 pending row');
  });

  test('SettingsService persists device location + last-synced timestamps',
      () async {
    await SettingsService.setDeviceLocationId('  فرع-1  ');
    expect(await SettingsService.getDeviceLocationId(), 'فرع-1',
        reason: 'value is trimmed and saved');

    await SettingsService.setDeviceLocationId('');
    expect(await SettingsService.getDeviceLocationId(), '',
        reason: 'clearing removes the stored value');

    final now = DateTime.utc(2026, 8, 6, 12, 30);
    expect(await SettingsService.getLastSyncedAt(), isNull);
    await SettingsService.setLastSyncedAt(now);
    expect(await SettingsService.getLastSyncedAt(), now);
  });
}