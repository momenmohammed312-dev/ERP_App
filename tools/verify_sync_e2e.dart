// ============================================================
// verify_sync_e2e.dart — end-to-end sync proof against the real
// Supabase project. NOT a widget test: it drives the app's own
// DAO → SyncQueue → SyncService → Supabase pipeline with a real
// throwaway product row, then queries Supabase to confirm the row
// actually landed, prints VERIFICATION PASSED/FAILED and exits
// 0/1 accordingly.
//
// NOTE ON RUNNING:
//   `dart run` cannot load this script: sync_service.dart pulls in
//   supabase_flutter + flutter/foundation, and the Dart VM in this
//   SDK crashes at compile time on that graph (FFI use-site bug)
//   plus dart:ui is unavailable outside the Flutter engine. The
//   repo's own tools (e.g. run_product_tests.dart) have the same
//   constraint. So this runs with the Flutter toolchain:
//
//     flutter test tools/verify_sync_e2e.dart \
//       --dart-define=SUPABASE_URL=<supabase url> \
//       --dart-define=SUPABASE_ANON_KEY=<publishable / anon key>
//
//   flutter test exits 0 when all tests pass, non-zero otherwise.
// ============================================================
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/services/sync_service.dart';

/// Same env vars the app reads in `SyncService`.
const String _url = String.fromEnvironment('SUPABASE_URL');
const String _anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

void main() {
  test('VERIFICATION: product row created locally syncs to Supabase', () async {
    SharedPreferences.setMockInitialValues({});

    final configured = _url.isNotEmpty && _anonKey.isNotEmpty;
    expect(configured, isTrue,
        reason: 'SUPABASE_URL / SUPABASE_ANON_KEY must be passed via --dart-define');

    final testName = '__SYNC_TEST_${DateTime.now().millisecondsSinceEpoch}__';
    print('name="$_url" configured');
    print('test row name: $testName');

    // 1) Throwaway temp DB — never the real user database file.
    final tempDir = Directory.systemTemp.createTempSync('sync_e2e');
    final db = AppDatabase(NativeDatabase(File('${tempDir.path}/sync_e2e.sqlite')));
    try {
      // 2) Insert a product via the REAL ProductDao → stamps sync_id and
      //    enqueues a products/insert row exactly like the app does.
      final insertedId = await db.productDao.insertProduct(
        ProductsCompanion.insert(
          name: testName,
          quantity: 7,
          price: 12.5,
          unit: const Value('kg'),
        ),
      );
      final product = await db.productDao.getProductById(insertedId);
      final localSyncId = product!.syncId!;
      print('local product inserted (id=$insertedId) sync_id=$localSyncId');

      final pending = await db.syncQueueDao.getPendingCount();
      expect(pending, greaterThanOrEqualTo(1),
          reason: 'local write must be queued in sync_queue');

      // 3) Real Supabase client (same init path as the app).
      await Supabase.initialize(url: _url, publishableKey: _anonKey);
      final sync = SyncService(db);
      await sync.initialize();

      // 4) Push synchronously.
      final summary = await sync.syncNow();
      print('syncNow summary: synced=${summary.synced} '
          'failed=${summary.failed} skippedOffline=${summary.skippedOffline}');

      // 5) Prove the row landed in Supabase under the same sync_id.
      final remote = await Supabase.instance.client
          .from('products')
          .select()
          .eq('name', testName);
      print('remote rows found: ${remote.length}');
      if (remote.isEmpty) {
        fail('VERIFICATION FAILED — row not present in Supabase after syncNow()');
      }
      final remoteSyncId = remote.first['sync_id'] as String?;
      print('remote sync_id: $remoteSyncId');
      expect(remoteSyncId, localSyncId,
          reason: 'remote sync_id must match the local row sync_id');
      expect(summary.synced, greaterThanOrEqualTo(1),
          reason: 'syncNow must report at least one synced row');

      print('VERIFICATION PASSED — row confirmed in Supabase');
    } finally {
      // 6) Cleanup: request deletion of the test row from Supabase + close local DB.
//    NOTE: RLS deliberately grants no DELETE to anon, so this is best-effort;
//    the leftovers query below is the real check.
      try {
        await Supabase.instance.client
            .from('products')
            .delete()
            .eq('name', testName);
        final leftovers = await Supabase.instance.client
            .from('products')
            .select('sync_id')
            .eq('name', testName);
        print('cleanup: rows still present after delete = ${leftovers.length}');
        if (leftovers.isNotEmpty) {
          print('WARNING: test row could not be removed from Supabase '
              '(anon has no DELETE policy) — remove manually via SQL: '
              "DELETE FROM products WHERE name = '$testName';");
        }
      } catch (e) {
        print('WARNING: cleanup delete failed: $e');
      }
      await db.close();
      try {
        tempDir.deleteSync(recursive: true);
      } catch (e) {
        print('WARNING: temp dir cleanup failed: $e');
      }
    }
  });

  test('VERIFICATION: periodic timer fires on its own (no manual syncNow)', () async {
    SharedPreferences.setMockInitialValues({});

    final tempDir = Directory.systemTemp.createTempSync('sync_e2e_timer');
    final db = AppDatabase(NativeDatabase(File('${tempDir.path}/sync_e2e_timer.sqlite')));
    var sync = SyncService(db);
    try {
      await sync.initialize();
      // Debug-only shortened interval so this proof finishes in seconds instead
      // of minutes. The production interval stays 3 minutes (startPeriodicSync
      // default). We never call syncNow() manually here.
      final fired = Stopwatch()..start();
      sync.startPeriodicSync(interval: const Duration(seconds: 2));
      await Future<void>.delayed(const Duration(seconds: 7));
      fired.stop();
      final lastRun = sync.lastPeriodicRunAt.value;
      print('PERIODIC PROOF: after ${fired.elapsed.inSeconds}s without any '
          'manual syncNow(), lastPeriodicRunAt = $lastRun');
      expect(sync.lastPeriodicRunAt.value, isNotNull,
          reason: 'Timer.periodic must fire on its own and stamp the notifier');
    } finally {
      // Cancel the background timer so it doesn't outlive the test.
      sync.dispose();
      await db.close();
      try {
        tempDir.deleteSync(recursive: true);
      } catch (e) {
        print('WARNING: temp dir cleanup failed: $e');
      }
    }
  });
}