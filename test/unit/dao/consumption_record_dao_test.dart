import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';

import '../../helpers/license_grant.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (MethodCall methodCall) async => '.',
  );

  late AppDatabase db;

  setUp(() async {
    grantLicensedModules();
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    revokeLicensedModules();
    await db.close();
  });

  Future<({int orderId, int rawA, int rawB})> seedOrderAndMaterials() async {
    final finishedId = await db.into(db.products).insert(
          ProductsCompanion.insert(name: 'Finished Jacket', price: 200, quantity: 0),
        );
    final rawA = await db.into(db.products).insert(
          ProductsCompanion.insert(name: 'Wool Fabric', price: 50, quantity: 100),
        );
    final rawB = await db.into(db.products).insert(
          ProductsCompanion.insert(name: 'Metal Zipper', price: 10, quantity: 200),
        );
    final bomId = await db.bomDao.insertBomWithItems(
      bom: BillOfMaterialsCompanion(
        finishedProductId: Value(finishedId),
        name: const Value('Jacket BOM'),
      ),
      items: [
        BomItemsCompanion(
          rawMaterialProductId: Value(rawA),
          quantityRequired: const Value(2.0),
        ),
      ],
    );
    final orderId = await db.manufacturingOrderDao.createOrder(
      ManufacturingOrdersCompanion(
        orderNumber: const Value('MO-CR-001'),
        bomId: Value(bomId),
        finishedProductId: Value(finishedId),
        plannedQuantity: const Value(10.0),
      ),
    );
    return (orderId: orderId, rawA: rawA, rawB: rawB);
  }

  group('ConsumptionRecordDao', () {
    test('insertConsumptionRecord and getForOrder return rows oldest first with fields', () async {
      final seeded = await seedOrderAndMaterials();

      final id1 = await db.consumptionRecordDao.insertConsumptionRecord(
        manufacturingOrderId: seeded.orderId,
        materialProductId: seeded.rawA,
        ownershipType: 'customer_owned',
        unit: 'meter',
        plannedQty: 20.0,
        actualQty: 18.5,
        unitCostSnapshot: 0.0,
      );
      final id2 = await db.consumptionRecordDao.insertConsumptionRecord(
        manufacturingOrderId: seeded.orderId,
        materialProductId: seeded.rawB,
        ownershipType: 'factory_owned',
        unit: 'piece',
        plannedQty: 10.0,
        actualQty: 10.0,
        unitCostSnapshot: 10.0,
      );

      final rows = await db.consumptionRecordDao.getForOrder(seeded.orderId);
      expect(rows.length, 2);
      expect(rows[0].id, id1);
      expect(rows[0].ownershipType, 'customer_owned');
      expect(rows[0].unit, 'meter');
      expect(rows[0].plannedQty, 20.0);
      expect(rows[0].actualQty, 18.5);
      expect(rows[0].unitCostSnapshot, 0.0);
      expect(rows[1].id, id2);
      expect(rows[1].ownershipType, 'factory_owned');
    });

    test('consumedByProductForOrder aggregates per product with and without ownership filter', () async {
      final seeded = await seedOrderAndMaterials();

      await db.consumptionRecordDao.insertConsumptionRecord(
        manufacturingOrderId: seeded.orderId,
        materialProductId: seeded.rawA,
        ownershipType: 'customer_owned',
        actualQty: 12.0,
      );
      await db.consumptionRecordDao.insertConsumptionRecord(
        manufacturingOrderId: seeded.orderId,
        materialProductId: seeded.rawA,
        ownershipType: 'customer_owned',
        actualQty: 5.5,
      );
      await db.consumptionRecordDao.insertConsumptionRecord(
        manufacturingOrderId: seeded.orderId,
        materialProductId: seeded.rawA,
        ownershipType: 'factory_owned',
        actualQty: 2.5,
      );
      await db.consumptionRecordDao.insertConsumptionRecord(
        manufacturingOrderId: seeded.orderId,
        materialProductId: seeded.rawB,
        ownershipType: 'factory_owned',
        actualQty: 10.0,
      );

      final allByProduct =
          await db.consumptionRecordDao.consumedByProductForOrder(seeded.orderId);
      expect(allByProduct, {seeded.rawA: 20.0, seeded.rawB: 10.0});

      final customerByProduct =
          await db.consumptionRecordDao.consumedByProductForOrder(
        seeded.orderId,
        ownershipType: 'customer_owned',
      );
      expect(customerByProduct, {seeded.rawA: 17.5});

      final factoryByProduct =
          await db.consumptionRecordDao.consumedByProductForOrder(
        seeded.orderId,
        ownershipType: 'factory_owned',
      );
      expect(factoryByProduct, {seeded.rawA: 2.5, seeded.rawB: 10.0});
    });

    test('totalConsumedForOrder sums actualQty with optional ownership filter', () async {
      final seeded = await seedOrderAndMaterials();

      expect(
        await db.consumptionRecordDao.totalConsumedForOrder(seeded.orderId),
        0.0,
      );

      await db.consumptionRecordDao.insertConsumptionRecord(
        manufacturingOrderId: seeded.orderId,
        materialProductId: seeded.rawA,
        ownershipType: 'customer_owned',
        actualQty: 15.0,
      );
      await db.consumptionRecordDao.insertConsumptionRecord(
        manufacturingOrderId: seeded.orderId,
        materialProductId: seeded.rawB,
        ownershipType: 'factory_owned',
        actualQty: 7.0,
      );

      expect(
        await db.consumptionRecordDao.totalConsumedForOrder(seeded.orderId),
        22.0,
      );
      expect(
        await db.consumptionRecordDao.totalConsumedForOrder(
          seeded.orderId,
          ownershipType: 'customer_owned',
        ),
        15.0,
      );
      expect(
        await db.consumptionRecordDao.totalConsumedForOrder(
          seeded.orderId,
          ownershipType: 'factory_owned',
        ),
        7.0,
      );
    });

    test('watchForOrder emits live updates', () async {
      final seeded = await seedOrderAndMaterials();
      final stream = db.consumptionRecordDao.watchForOrder(seeded.orderId);
      final emitted = <int>[];
      final sub = stream.listen((rows) => emitted.add(rows.length));

      await pumpEventQueue();
      await db.consumptionRecordDao.insertConsumptionRecord(
        manufacturingOrderId: seeded.orderId,
        materialProductId: seeded.rawA,
        ownershipType: 'customer_owned',
        actualQty: 4.0,
      );
      await pumpEventQueue();
      await sub.cancel();

      expect(emitted.first, 0);
      expect(emitted.last, 1);
    });
  });
}
