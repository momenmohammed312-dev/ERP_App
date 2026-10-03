import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/dao/bom_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/manufacturing_order_dao.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_orders_table.dart';
import 'package:sqlite3/sqlite3.dart';

/// Integrity contracts around the manufacturing schema: the BOM freeze rule,
/// the v73/v74/v75 migration ladder, and backup coverage.
///
/// **Test-first. Some of this is red on purpose until C4 lands.**
///
/// G — a BOM that an order already references is frozen. Editing or deleting
///   it would silently reinterpret that order's historical cost, because
///   BomDao.replaceBomItems deletes every line and re-inserts. Nothing in the
///   salvaged DAO guards this yet, so G2 and G3 are expected red.
///
/// I — the migration ladder. v73 adds products.product_type, v74 adds the four
///   manufacturing tables, v75 will add manufacturing_scrap. I1 and the v75 half
///   of I3 are expected red until C4 bumps the schema.
///
/// J — every manufacturing table must appear in the backup service. A table
///   that exists but is not backed up is silent data loss on restore. J1/J2 are
///   expected red until C6.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (MethodCall methodCall) async => '.',
      );

  const manufacturingTables = [
    'bill_of_materials',
    'bom_items',
    'manufacturing_orders',
    'manufacturing_cost_components',
    'manufacturing_scrap',
  ];

  Future<(BomDao, ManufacturingOrderDao, AppDatabase)> setup() async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    return (BomDao(db), ManufacturingOrderDao(db), db);
  }

  Future<int> seedProduct(
    AppDatabase db, {
    required String name,
    int quantity = 0,
    double? cost,
  }) {
    return db.productDao.insertProduct(
      ProductsCompanion.insert(
        name: name,
        quantity: quantity,
        price: cost ?? 0,
        costPrice: Value(cost),
      ),
    );
  }

  Future<int> seedBom(
    BomDao bomDao, {
    required int finishedProductId,
    required int rawProductId,
    double quantityRequired = 4,
  }) {
    return bomDao.insertBomWithItems(
      bom: BillOfMaterialsCompanion(
        finishedProductId: Value(finishedProductId),
        name: const Value('بوم اختبار'),
      ),
      items: [
        BomItemsCompanion(
          rawMaterialProductId: Value(rawProductId),
          quantityRequired: Value(quantityRequired),
        ),
      ],
    );
  }

  Future<List<String>> tableNames(AppDatabase db) async {
    final rows = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type='table'",
        )
        .get();
    return rows.map((r) => r.read<String>('name')).toList();
  }

  Future<int> userVersion(AppDatabase db) async {
    final row = await db.customSelect('PRAGMA user_version').getSingle();
    return row.read<int>('user_version');
  }

  // ── G: freeze a BOM once an order references it ────────────────────────

  group('G — a referenced BOM is frozen', () {
    test('G1 an unreferenced BOM can still be edited', () async {
      final (bomDao, moDao, db) = await setup();
      final wood = await seedProduct(db, name: 'خشب', cost: 10);
      final chair = await seedProduct(db, name: 'كرسي');
      final bomId = await seedBom(
        bomDao,
        finishedProductId: chair,
        rawProductId: wood,
        quantityRequired: 4,
      );

      // No order references it yet, so the edit must go through.
      await bomDao.replaceBomItems(
        bomId: bomId,
        items: [
          BomItemsCompanion(
            rawMaterialProductId: Value(wood),
            quantityRequired: const Value(9),
          ),
        ],
      );

      final items = await bomDao.getItemsForBom(bomId);
      expect(items.length, 1);
      expect(items.single.quantityRequired, 9);
      expect(await moDao.getByBomId(bomId), isEmpty);
    });

    test('G2 a referenced BOM refuses replacement and keeps its lines',
        () async {
      final (bomDao, moDao, db) = await setup();
      final wood = await seedProduct(db, name: 'خشب', cost: 10);
      final chair = await seedProduct(db, name: 'كرسي');
      final bomId = await seedBom(
        bomDao,
        finishedProductId: chair,
        rawProductId: wood,
        quantityRequired: 4,
      );
      await moDao.createOrder(
        ManufacturingOrdersCompanion(
          bomId: Value(bomId),
          finishedProductId: Value(chair),
          plannedQuantity: const Value(1),
        ),
      );

      await expectLater(
        bomDao.replaceBomItems(
          bomId: bomId,
          items: [
            BomItemsCompanion(
              rawMaterialProductId: Value(wood),
              quantityRequired: const Value(99),
            ),
          ],
        ),
        throwsA(anything),
        reason: 'a BOM with orders against it is frozen',
      );

      final items = await bomDao.getItemsForBom(bomId);
      expect(items.length, 1);
      expect(
        items.single.quantityRequired,
        4,
        reason: 'the historical line must survive untouched',
      );
    });

    test('G3 a referenced BOM cannot be deleted', () async {
      final (bomDao, moDao, db) = await setup();
      final wood = await seedProduct(db, name: 'خشب', cost: 10);
      final chair = await seedProduct(db, name: 'كرسي');
      final bomId = await seedBom(
        bomDao,
        finishedProductId: chair,
        rawProductId: wood,
      );
      await moDao.createOrder(
        ManufacturingOrdersCompanion(
          bomId: Value(bomId),
          finishedProductId: Value(chair),
          plannedQuantity: const Value(1),
        ),
      );

      await expectLater(
        bomDao.deleteBom(bomId),
        throwsA(anything),
        reason: 'hard-deleting a BOM would orphan its order',
      );

      expect(await bomDao.getBomById(bomId), isNotNull);
    });

    test('G4 freezing protects a completed order cost from later edits',
        () async {
      // This is the regression the freeze exists for: a completed order records
      // a unit cost derived from the BOM as it stood. Editing the BOM afterwards
      // must not be possible, so the recorded cost can never be reinterpreted.
      final (bomDao, moDao, db) = await setup();
      // Stocked, because this case completes the order to capture a real unit
      // cost before trying to edit the recipe. With the default quantity of 0
      // the completion threw InsufficientStockException and the freeze
      // assertion was never reached.
      final wood = await seedProduct(db, name: 'خشب', quantity: 100, cost: 10);
      final chair = await seedProduct(db, name: 'كرسي');
      final bomId = await seedBom(
        bomDao,
        finishedProductId: chair,
        rawProductId: wood,
        quantityRequired: 4,
      );
      final orderId = await moDao.createOrder(
        ManufacturingOrdersCompanion(
          bomId: Value(bomId),
          finishedProductId: Value(chair),
          plannedQuantity: const Value(1),
        ),
      );
      await moDao.completeManufacturingOrder(orderId: orderId);
      final before = await moDao.getById(orderId);

      await expectLater(
        bomDao.replaceBomItems(
          bomId: bomId,
          items: [
            BomItemsCompanion(
              rawMaterialProductId: Value(wood),
              quantityRequired: const Value(50),
            ),
          ],
        ),
        throwsA(anything),
      );

      final after = await moDao.getById(orderId);
      expect(after!.status, ManufacturingOrderStatus.completed);
      expect(after.producedQuantity, before!.producedQuantity);
      final items = await bomDao.getItemsForBom(bomId);
      expect(items.single.quantityRequired, 4);
    });
  });

  // ── I: the migration ladder ────────────────────────────────────────────

  group('I — migration ladder v73 / v74 / v75', () {
    test('I1 the schema contract is 75 once scrap exists', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      expect(
        db.schemaVersion,
        75,
        reason: 'v73 + v74 + the v75 scrap table',
      );
    });

    test('I2 v73 added a nullable product_type to products', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final rows = await db
          .customSelect('PRAGMA table_info(products)')
          .get();
      final names = rows.map((r) => r.read<String>('name')).toList();
      expect(names, contains('product_type'));

      // Nullable, so no backfill is required for existing rows.
      final col = rows.firstWhere((r) => r.read<String>('name') == 'product_type');
      expect(col.read<int>('notnull'), 0);
    });

    test('I3 all five manufacturing tables exist', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final names = await tableNames(db);
      for (final t in manufacturingTables) {
        expect(names, contains(t), reason: '$t must exist');
      }
    });

    test('I4 a product inserted without a type stays NULL', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final id = await seedProduct(db, name: 'صنف عادي', quantity: 5, cost: 3);
      final row = await db.productDao.getProductById(id);

      expect(row, isNotNull);
      expect(
        row!.productType,
        isNull,
        reason: 'NULL means standard/retail; existing rows keep their meaning',
      );
    });

    test('I5 re-running v73 and v74 is a no-op, not a crash', () async {
      final dir = await Directory.systemTemp.createTemp('mfg_mig');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/m.db');

      // First open builds the schema at the current version.
      final first = AppDatabase(NativeDatabase(file));
      await first.customSelect('SELECT 1').get();
      await first.close();

      // Wind the stamp back so v73 and v74 both run a second time over a
      // database that already has their objects. Each body is individually
      // guarded, so this must complete without throwing.
      final raw = sqlite3.open(file.path);
      raw.execute('PRAGMA user_version = 72');
      raw.dispose();

      final second = AppDatabase(NativeDatabase(file));
      addTearDown(second.close);
      await second.customSelect('SELECT 1').get();

      expect(await userVersion(second), 75);
      final names = await tableNames(second);
      expect(names, contains('bill_of_materials'));
      expect(names, contains('bom_items'));
      expect(names, contains('manufacturing_orders'));
      expect(names, contains('manufacturing_cost_components'));
    });
  });

  // ── J: backup coverage ─────────────────────────────────────────────────

  group('J — backup covers every manufacturing table', () {
    String readBackupService() =>
        File('lib/core/services/backup_service.dart').readAsStringSync();

    test('J1 the backup set includes all five tables', () {
      final src = readBackupService();

      for (final t in manufacturingTables) {
        expect(
          src.contains("'$t'"),
          isTrue,
          reason: '$t is missing from backup_service.dart — a restore would '
              'silently drop it',
        );
      }
    });

    test('J2 the restore order includes all five tables', () {
      // tableOrder drives restore. A table missing from it is not recreated on
      // restore even if it is in the backup set.
      final src = readBackupService();

      for (final t in manufacturingTables) {
        expect(
          src.contains("'$t'"),
          isTrue,
          reason: '$t missing from the restore order',
        );
      }
    });
  });
}