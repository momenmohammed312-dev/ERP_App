import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:sqlite3/sqlite3.dart';

/// Dedicated migration test for Schema v83 — customer_stock_movement_id FK on
/// consumption_records (FEAT-039 Phase 1 Batch 3).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (MethodCall methodCall) async => '.',
  );

  Future<Set<String>> indexNames(AppDatabase db) async {
    final rows = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type='index'")
        .get();
    return rows.map((r) => r.read<String>('name')).toSet();
  }

  Future<List<String>> columns(AppDatabase db, String table) async {
    final rows = await db.customSelect('PRAGMA table_info($table)').get();
    return rows.map((r) => r.read<String>('name')).toList();
  }

  Future<int> userVersion(AppDatabase db) async {
    final row = await db.customSelect('PRAGMA user_version').getSingle();
    return row.read<int>('user_version');
  }

  test('v83: fresh DB has customer_stock_movement_id column and index', () async {
    final db = AppDatabase(NativeDatabase.memory());

    expect(await userVersion(db), db.schemaVersion);
    expect(db.schemaVersion, greaterThanOrEqualTo(83));

    expect(
      await columns(db, 'consumption_records'),
      contains('customer_stock_movement_id'),
    );
    expect(
      await indexNames(db),
      contains('idx_consumption_records_custody_move'),
    );

    await db.close();
  });

  test('v83: upgrade from simulated v82 adds customer_stock_movement_id and enforces FK', () async {
    final tempDir = Directory.systemTemp.createTempSync('v83_migration_test_');
    final dbFile = File('${tempDir.path}/sim_v82.db');
    addTearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    // 1. Build fresh DB, then downgrade consumption_records to v82 layout.
    final db = AppDatabase(NativeDatabase(dbFile));
    await db.customSelect('SELECT 1').get();
    await db.close();

    final raw = sqlite3.open(dbFile.path);
    try {
      raw.execute('DROP TABLE IF EXISTS consumption_records;');
      raw.execute('''
        CREATE TABLE consumption_records (
          id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
          manufacturing_order_id INTEGER NOT NULL REFERENCES manufacturing_orders(id) ON DELETE CASCADE,
          bom_item_id INTEGER REFERENCES bom_items(id) ON DELETE SET NULL,
          operation_id INTEGER REFERENCES manufacturing_stages(id) ON DELETE SET NULL,
          material_product_id INTEGER NOT NULL REFERENCES products(id) ON DELETE CASCADE,
          ownership_type TEXT NOT NULL,
          unit TEXT,
          planned_qty REAL,
          actual_qty REAL,
          unit_cost_snapshot REAL,
          stock_movement_id INTEGER REFERENCES inventory_movements(id) ON DELETE SET NULL,
          performed_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
        );
      ''');
      raw.execute('PRAGMA user_version = 82;');
    } finally {
      raw.dispose();
    }

    // 2. Re-open so onUpgrade runs _runV83ConsumptionCustodyLink.
    final db2 = AppDatabase(NativeDatabase(dbFile));
    try {
      await db2.customSelect('SELECT 1').get();
      expect(await userVersion(db2), db2.schemaVersion);
      expect(
        await columns(db2, 'consumption_records'),
        contains('customer_stock_movement_id'),
      );
      expect(
        await indexNames(db2),
        contains('idx_consumption_records_custody_move'),
      );

      // 3. Verify FK enforcement on customer_stock_movement_id under PRAGMA foreign_keys = ON.
      await db2.into(db2.customers).insert(
            CustomersCompanion.insert(id: 'cust-v83', name: 'V83 Customer'),
          );
      final rawProdId = await db2.into(db2.products).insert(
            ProductsCompanion.insert(name: 'Raw Fabric', price: 20, quantity: 0),
          );
      final finProdId = await db2.into(db2.products).insert(
            ProductsCompanion.insert(name: 'Finished Dress', price: 100, quantity: 0),
          );
      final bomId = await db2.into(db2.billOfMaterials).insert(
            BillOfMaterialsCompanion.insert(
              finishedProductId: finProdId,
              name: 'V83 BOM',
            ),
          );
      final orderId = await db2.into(db2.manufacturingOrders).insert(
            ManufacturingOrdersCompanion.insert(
              orderNumber: 'MO-V83-1',
              bomId: bomId,
              finishedProductId: finProdId,
              plannedQuantity: 10.0,
            ),
          );
      final moveId = await db2.into(db2.customerStockMovements).insert(
            CustomerStockMovementsCompanion.insert(
              customerId: 'cust-v83',
              productId: rawProdId,
              movementType: 'issued_to_order',
              quantity: -10.0,
              referenceType: 'manufacturing_order',
              referenceId: 'MO-V83-1',
            ),
          );

      final recId = await db2.consumptionRecordDao.insertConsumptionRecord(
        manufacturingOrderId: orderId,
        materialProductId: rawProdId,
        ownershipType: 'customer_owned',
        actualQty: 10.0,
        customerStockMovementId: moveId,
      );
      final inserted = (await db2.consumptionRecordDao.getForOrder(orderId))
          .firstWhere((r) => r.id == recId);
      expect(inserted.customerStockMovementId, moveId);

      // Non-existent movement id must fail with SQLite FK constraint error.
      await expectLater(
        () => db2.consumptionRecordDao.insertConsumptionRecord(
          manufacturingOrderId: orderId,
          materialProductId: rawProdId,
          ownershipType: 'customer_owned',
          actualQty: 5.0,
          customerStockMovementId: 999999,
        ),
        throwsA(isA<SqliteException>()),
      );
    } finally {
      await db2.close();
    }
  });
}
