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
import 'package:uuid/uuid.dart';

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

  test('VERIFICATION: stock movement delta decrements Supabase stock_levels', () async {
    // Give the device a known location so the StockLevels row created by the
    // RPC uses a location we can filter on. (syncNow() injects this id into
    // every payload; the stock_delta RPC receives it as its `location_id`.
    const testLocation = 'e2e-test-location';
    SharedPreferences.setMockInitialValues({
      'device_location_id': testLocation,
    });

    final testName = '__SYNC_STOCK_${DateTime.now().millisecondsSinceEpoch}__';
    print('test row name: $testName');

    // 1) Throwaway temp DB — never the real user database file.
    final tempDir = Directory.systemTemp.createTempSync('sync_e2e_stock');
    final db = AppDatabase(NativeDatabase(File('${tempDir.path}/sync_e2e_stock.sqlite')));
    String? productSyncId; // hoisted so the finally-block cleanup can use it
    try {
      // 2) Product via the REAL ProductDao (stamps sync_id + enqueues rows).
      final productId = await db.productDao.insertProduct(
        ProductsCompanion.insert(
          name: testName,
          quantity: 10,
          price: 5.0,
          unit: const Value('kg'),
        ),
      );
      final product = await db.productDao.getProductById(productId);
      productSyncId = product!.syncId!;
      final localProductSyncId = productSyncId;
      print('local product inserted (id=$productId) sync_id=$localProductSyncId');

      // 3) Real movement #1: sale of 5 units (negative delta) via the REAL
      //    InventoryMovementDao → enqueues a stock_delta outbox row.
      final now = DateTime.now();
      await db.inventoryMovementDao.createMovementWithTimestamp(
        productId: productId,
        movementType: 'sale',
        quantity: -5,
        unitCost: 5.0,
        totalValue: 25.0,
        movementDate: now,
        reference: 'REF-A',
        referenceType: 'sale_invoice',
        previousQuantity: 10,
        newQuantity: 5,
      );
      final pendingIv = await db.syncQueueDao.getPendingCount();
      expect(pendingIv, greaterThanOrEqualTo(2),
          reason: 'product + movement must both be queued in sync_queue');

      // 4) Real Supabase client + synchronous push.
      await Supabase.initialize(url: _url, publishableKey: _anonKey);
      final sync = SyncService(db);
      await sync.initialize();
      var summary = await sync.syncNow();
      print('syncNow(1) summary: synced=${summary.synced} '
          'failed=${summary.failed} skippedOffline=${summary.skippedOffline}');

      // 5) Read the StockLevels row(s) the RPC wrote for this product/location.
      final after5 = await Supabase.instance.client
          .from('stock_levels')
          .select()
          .eq('product_sync_id', productSyncId);
      print('stock_levels rows after -5 delta: ${after5.length}');
      for (final row in after5) {
        print('  stock_level: $row');
      }
      expect(after5, isNotEmpty,
          reason: 'apply_stock_delta must upsert a stock_levels row');

      final row5 = after5.firstWhere(
        (r) => r['location_id'] == testLocation,
        orElse: () => <String, dynamic>{},
      );
      expect(row5['location_id'], testLocation,
          reason: 'the RPC must scope the row to the injected location_id');
      final qty5 = row5['quantity'] as int;
      print('stock_levels quantity after -5: $qty5');

      // 6) Movement #2: sale of 2 more units, push again, read again.
      await db.inventoryMovementDao.createMovementWithTimestamp(
        productId: productId,
        movementType: 'sale',
        quantity: -2,
        unitCost: 5.0,
        totalValue: 10.0,
        movementDate: now,
        reference: 'REF-B',
        referenceType: 'sale_invoice',
        previousQuantity: 5,
        newQuantity: 3,
      );
      summary = await sync.syncNow();
      print('syncNow(2) summary: synced=${summary.synced} '
          'failed=${summary.failed} skippedOffline=${summary.skippedOffline}');

      final after2 = await Supabase.instance.client
          .from('stock_levels')
          .select()
          .eq('product_sync_id', productSyncId);
      final row2 = after2.firstWhere(
        (r) => r['location_id'] == testLocation,
        orElse: () => <String, dynamic>{},
      );
      final qty2 = row2['quantity'] as int;
      print('stock_levels quantity after -2 more: $qty2');

      // 7) Provable: each signed delta must decrement stock by exactly its
      //    abs value. qty(-5 then -2) → drop must equal 2 for movement #2.
      expect(qty5 - qty2, 2,
          reason: 'second -2 stock delta must reduce stock_levels by exactly 2');
      expect(summary.synced, greaterThanOrEqualTo(1),
          reason: 'syncNow(2) must have pushed the second movement row');

      print('VERIFICATION PASSED — stock_levels decremented by signed deltas');
    } finally {
      // 8) Cleanup: delete the stock_levels row for this product (best-effort,
      //    anon may have no DELETE policy) + close local DB + remove temp dir.
      final cleanupSyncId = productSyncId;
      if (cleanupSyncId == null) {
        print('WARNING: no productSyncId, skipping stock_levels cleanup');
      } else {
        try {
          await Supabase.instance.client
              .from('stock_levels')
              .delete()
              .eq('product_sync_id', cleanupSyncId);
          final leftovers = await Supabase.instance.client
              .from('stock_levels')
              .select('product_sync_id')
              .eq('product_sync_id', cleanupSyncId);
          print('cleanup: stock_levels rows still present after delete = ${leftovers.length}');
          if (leftovers.isNotEmpty) {
            print('WARNING: stock_levels test row could not be removed from Supabase '
                '(anon may have no DELETE policy) — remove manually via SQL: '
                "DELETE FROM stock_levels WHERE product_sync_id = '$cleanupSyncId';");
          }
        } catch (e) {
          print('WARNING: stock_levels cleanup delete failed: $e');
        }
      }
      await db.close();
      try {
        tempDir.deleteSync(recursive: true);
      } catch (e) {
        print('WARNING: temp dir cleanup failed: $e');
      }
    }
  });

  test('VERIFICATION: pullNow downloads rows into a fresh empty DB', () async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: _url, publishableKey: _anonKey);

    // 1) Simulate "device 1 already pushed this": insert the row straight into
    //    Supabase with a recognizable name + a fresh sync_id.
    final testName = '__SYNC_PULL_${DateTime.now().millisecondsSinceEpoch}__';
    final remoteSyncId = const Uuid().v4();
    final remoteUpdated = DateTime.now().toUtc().toIso8601String();
    print('remote-authoritative row: $testName, sync_id=$remoteSyncId');
    await Supabase.instance.client.from('products').insert({
      'sync_id': remoteSyncId,
      'location_id': 'e2e-test-location',
      'name': testName,
      'quantity': 42,
      'price': 9.99,
      'unit': 'kg',
      'status': 'Active',
      'updated_at': remoteUpdated,
    });

    final tempDir = Directory.systemTemp.createTempSync('sync_e2e_pull');
    final db = AppDatabase(NativeDatabase(File('${tempDir.path}/sync_e2e_pull.sqlite')));
    try {
      // 2) Fresh EMPTY DB = "device 2, never seen this product".
      final before = await db.productDao.getAllProducts();
      expect(before, isEmpty,
          reason: 'device-2 DB must start empty to prove a genuine pull');

      // 3) pullNow() into it.
      final sync = SyncService(db);
      await sync.initialize();
      final pulled = await sync.pullNow();
      print('pullNow summary: pulled=${pulled.pulled} '
          'skipped=${pulled.skipped} failed=${pulled.failed}');

      // 4) The pulled row must now exist locally with matching values.
      final local = await (db.select(db.products)
            ..where((p) => p.syncId.equals(remoteSyncId)))
          .getSingleOrNull();
      print('local row after pull: $local');
      expect(local, isNotNull,
          reason: 'pullNow must write the remote row into the fresh DB');
      expect(local!.syncId, remoteSyncId);
      expect(local.name, testName);
      expect(local.quantity, 42);
      expect(local.price, 9.99);
      expect(local.unit, 'kg');
      expect(pulled.pulled, greaterThanOrEqualTo(1),
          reason: 'pullNow must report at least one pulled row');

      // 5) Proving it did NOT get re-enqueued for push (feedback-loop guard).
      final reQueued = await db.syncQueueDao.getPendingCount();
      print('sync_queue pending after pull: $reQueued');
      expect(reQueued, 0,
          reason: 'pulled rows must NOT be re-enqueued for push');

      print('VERIFICATION PASSED — remote row pulled into fresh DB');
    } finally {
      // 6) Cleanup: delete the test row from Supabase (best-effort).
      try {
        await Supabase.instance.client
            .from('products')
            .delete()
            .eq('sync_id', remoteSyncId);
        final leftovers = await Supabase.instance.client
            .from('products')
            .select('sync_id')
            .eq('sync_id', remoteSyncId);
        print('cleanup: pull test rows still present = ${leftovers.length}');
      } catch (e) {
        print('WARNING: pull cleanup delete failed: $e');
      }
      await db.close();
      try {
        tempDir.deleteSync(recursive: true);
      } catch (e) {
        print('WARNING: temp dir cleanup failed: $e');
      }
    }
  });

  test('VERIFICATION: pullNow applies newer remote update (last-write-wins)', () async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: _url, publishableKey: _anonKey);

    final tempDir = Directory.systemTemp.createTempSync('sync_e2e_lww');
    final db = AppDatabase(NativeDatabase(File('${tempDir.path}/sync_e2e_lww.sqlite')));
    String? remoteSyncId; // hoisted for the finally-block cleanup
    try {
      // 1) Insert a product LOCALLY (device 1 creates it) → stamps a syncId.
      final testName = '__SYNC_LWW_${DateTime.now().millisecondsSinceEpoch}__';
      final insertedId = await db.productDao.insertProduct(
        ProductsCompanion.insert(
          name: testName,
          quantity: 1,
          price: 1.0,
          unit: const Value('pcs'),
        ),
      );
      final local = await db.productDao.getProductById(insertedId);
      remoteSyncId = local!.syncId!;
      print('local product inserted (id=$insertedId) sync_id=$remoteSyncId');

      // 2) Push it up so the remote side has the row.
      final sync = SyncService(db);
      await sync.initialize();
      var summary = await sync.syncNow();
      print('initial syncNow summary: synced=${summary.synced} '
          'failed=${summary.failed}');
      expect(summary.synced, greaterThanOrEqualTo(1),
          reason: 'initial local product must reach Supabase');

      // 3) "Device 2 edits it": remote row gets a NEWER updated_at + new name.
      final newerName = '${testName}_RENAMED_ON_DEVICE2';
      final newerTime = DateTime.now().toUtc().add(const Duration(minutes: 5));
      await Supabase.instance.client
          .from('products')
          .update({
            'name': newerName,
            'updated_at': newerTime.toIso8601String(),
          })
          .eq('sync_id', remoteSyncId);
      print('remote updated_at set to (newer): $newerTime, name=$newerName');

      // 4) pullNow — the local row is OLDER → it must adopt the remote values.
      final pullSummary = await sync.pullNow();
      print('pullNow summary: pulled=${pullSummary.pulled} '
          'skipped=${pullSummary.skipped} failed=${pullSummary.failed}');
      final afterPull = await db.productDao.getProductById(insertedId);
      print('local name after pull: ${afterPull!.name}');
      expect(afterPull.name, newerName,
          reason: 'newer remote update must win over the older local copy');

      // 5) Reverse: local is now the NEWER side (pull bumped its updatedAt to
      //    the future). Set remote back to an OLD timestamp + old name, then
      //    pull again — local must win this time (last-write-wins both ways).
      final olderName = '${testName}_OLD_REMOTE';
      final olderTime = DateTime.now().toUtc().subtract(const Duration(minutes: 10));
      await Supabase.instance.client
          .from('products')
          .update({
            'name': olderName,
            'updated_at': olderTime.toIso8601String(),
          })
          .eq('sync_id', remoteSyncId);
      await sync.pullNow();
      final afterSecondPull = await db.productDao.getProductById(insertedId);
      print('local name after stale-remote pull: ${afterSecondPull!.name}');
      expect(afterSecondPull.name, newerName,
          reason: 'stale remote (older updated_at) must NOT overwrite newer local');

      print('VERIFICATION PASSED — last-write-wins honored in both directions');
    } finally {
      // 6) Cleanup remote test row (best-effort) + close local DB.
      final cleanupSyncId = remoteSyncId;
      if (cleanupSyncId != null) {
        try {
          await Supabase.instance.client
              .from('products')
              .delete()
              .eq('sync_id', cleanupSyncId);
        } catch (e) {
          print('WARNING: LWW cleanup delete failed: $e');
        }
      }
      await db.close();
      try {
        tempDir.deleteSync(recursive: true);
      } catch (e) {
        print('WARNING: temp dir cleanup failed: $e');
      }
    }
  });

  test('VERIFICATION: pulled invoice resolves customer name locally', () async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(url: _url, publishableKey: _anonKey);

    final ts = DateTime.now().millisecondsSinceEpoch;
    final custName = '__SYNC_CUST_${ts}__';
    final custId = const Uuid().v4();
    final invSyncId = const Uuid().v4();
    final invNumber = '__SYNC_INV_${ts}__';
    print('remote customer: $custName (id=$custId)');
    print('remote invoice: $invNumber (sync_id=$invSyncId)');

    // 1) 'Device 1' created the customer directly in Supabase.
    await Supabase.instance.client.from('customers').insert({
      'sync_id': custId,
      'location_id': 'e2e-test-location',
      'name': custName,
      'phone': '0100-SYNC',
      'address': 'Test Address',
      'opening_balance': 0,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    });

    // 2) 'Device 1' created an invoice referencing that customer ONLY by
    //    customer_sync_id — note there is NO customer_name field here, exactly
    //    like a real sync payload (and like the remote invoices table).
    try {
      await Supabase.instance.client.from('invoices').insert({
        'sync_id': invSyncId,
        'invoice_number': invNumber,
        'customer_sync_id': custId,
        'location_id': 'e2e-test-location',
        'total_amount': 150.0,
        'paid_amount': 50.0,
        'status': 'partial',
        'invoice_date': DateTime.now().toUtc().toIso8601String(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    } catch (e) {
      print('WARNING: invoice insert failed: $e');
      rethrow;
    }

    // 3) Fresh EMPTY DB = 'device 2'; pullNow() must bring down customer then
    //    invoice, resolving the denormalized display fields from the local
    //    Customers table (customers are always pulled before invoices).
    final tempDir = Directory.systemTemp.createTempSync('sync_e2e_inv_cust');
    final db = AppDatabase(NativeDatabase(File('${tempDir.path}/sync_e2e_inv_cust.sqlite')));
    try {
      final sync = SyncService(db);
      await sync.initialize();
      final pulled = await sync.pullNow();
      print('pullNow summary: pulled=${pulled.pulled} '
          'skipped=${pulled.skipped} failed=${pulled.failed}');

      // 4) The customer itself must be local.
      final localCustomer = await (db.select(db.customers)
            ..where((c) => c.id.equals(custId)))
          .getSingleOrNull();
      expect(localCustomer, isNotNull,
          reason: 'pulled invoice needs its customer row locally');
      print('local customer pulled: ${localCustomer!.name}');

      // 5) The invoice must carry the customer's REAL name/contact/address,
      //    resolved from the local Customers table at pull time — not blank.
      final localInvoice = await (db.select(db.invoices)
            ..where((t) => t.syncId.equals(invSyncId)))
          .getSingleOrNull();
      expect(localInvoice, isNotNull,
          reason: 'pullNow must bring the invoice into the fresh DB');
      print('local invoice: customerName=${localInvoice!.customerName} '
          'customerContact=${localInvoice.customerContact} '
          'customerAddress=${localInvoice.customerAddress}');
      expect(localInvoice.customerId, custId,
          reason: 'customer FK (customer_sync_id) must round-trip');
      expect(localInvoice.customerName, custName,
          reason: 'pulled invoice must resolve the customer NAME locally');
      expect(localInvoice.customerName!.isNotEmpty, isTrue,
          reason: 'customerName must not be blank on a pulled invoice');
      expect(localInvoice.customerContact, '0100-SYNC',
          reason: 'pulled invoice must resolve customer CONTACT locally');
      expect(localInvoice.customerAddress, 'Test Address',
          reason: 'pulled invoice must resolve customer ADDRESS locally');

      print('VERIFICATION PASSED — pulled invoice resolved customer display fields');
    } finally {
      // 6) Cleanup: delete both remote rows (best-effort; anon may have no
      //    DELETE policy) + close local DB + remove temp dir.
      for (final table in ['invoices', 'customers']) {
        try {
          await Supabase.instance.client
              .from(table)
              .delete()
              .eq('sync_id', table == 'invoices' ? invSyncId : custId);
        } catch (e) {
          print('WARNING: cleanup delete failed on $table: $e');
        }
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
