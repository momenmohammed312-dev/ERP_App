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

  Future<({int orderId, int stageId})> seedOrderAndStage() async {
    final finishedId = await db.into(db.products).insert(
          ProductsCompanion.insert(name: 'Printed Hoodies', price: 250, quantity: 0),
        );
    final rawId = await db.into(db.products).insert(
          ProductsCompanion.insert(name: 'Blank Hoodies', price: 100, quantity: 100),
        );
    final bomId = await db.bomDao.insertBomWithItems(
      bom: BillOfMaterialsCompanion(
        finishedProductId: Value(finishedId),
        name: const Value('Hoodie BOM'),
      ),
      items: [
        BomItemsCompanion(
          rawMaterialProductId: Value(rawId),
          quantityRequired: const Value(1.0),
        ),
      ],
    );
    final orderId = await db.manufacturingOrderDao.createOrder(
      ManufacturingOrdersCompanion(
        orderNumber: const Value('MO-EXT-001'),
        bomId: Value(bomId),
        finishedProductId: Value(finishedId),
        plannedQuantity: const Value(100.0),
      ),
    );
    final stageId = await db.manufacturingStageDao.addStage(
      orderId: orderId,
      stageName: 'Screen Printing (Vendor)',
      stageOrder: 1,
      inputQuantity: 100.0,
    );
    return (orderId: orderId, stageId: stageId);
  }

  group('ExternalOperationDao', () {
    test('validation throws ArgumentError for empty vendor, non-positive sentQty, or negative numbers', () async {
      final seeded = await seedOrderAndStage();

      await expectLater(
        () => db.externalOperationDao.insertExternalOperationRecord(
          manufacturingOrderId: seeded.orderId,
          vendor: '   ',
          sentQty: 10.0,
        ),
        throwsArgumentError,
      );

      await expectLater(
        () => db.externalOperationDao.insertExternalOperationRecord(
          manufacturingOrderId: seeded.orderId,
          vendor: 'Al-Noor Dyeing',
          sentQty: 0.0,
        ),
        throwsArgumentError,
      );

      await expectLater(
        () => db.externalOperationDao.insertExternalOperationRecord(
          manufacturingOrderId: seeded.orderId,
          vendor: 'Al-Noor Dyeing',
          sentQty: -5.0,
        ),
        throwsArgumentError,
      );

      await expectLater(
        () => db.externalOperationDao.insertExternalOperationRecord(
          manufacturingOrderId: seeded.orderId,
          vendor: 'Al-Noor Dyeing',
          sentQty: 10.0,
          receivedQty: -1.0,
        ),
        throwsArgumentError,
      );

      await expectLater(
        () => db.externalOperationDao.insertExternalOperationRecord(
          manufacturingOrderId: seeded.orderId,
          vendor: 'Al-Noor Dyeing',
          sentQty: 10.0,
          scrapQty: -1.0,
        ),
        throwsArgumentError,
      );

      await expectLater(
        () => db.externalOperationDao.insertExternalOperationRecord(
          manufacturingOrderId: seeded.orderId,
          vendor: 'Al-Noor Dyeing',
          sentQty: 10.0,
          cost: -10.0,
        ),
        throwsArgumentError,
      );
    });

    test('throws StateError when receivedQty + scrapQty exceeds sentQty', () async {
      final seeded = await seedOrderAndStage();

      await expectLater(
        () => db.externalOperationDao.insertExternalOperationRecord(
          manufacturingOrderId: seeded.orderId,
          vendor: 'Al-Noor Dyeing',
          sentQty: 50.0,
          receivedQty: 45.0,
          scrapQty: 6.0,
        ),
        throwsStateError,
      );
    });

    test('computes totals and atVendorQuantityForOrder across multiple vendor records', () async {
      final seeded = await seedOrderAndStage();

      final id1 = await db.externalOperationDao.insertExternalOperationRecord(
        manufacturingOrderId: seeded.orderId,
        operationId: seeded.stageId,
        vendor: '  Vendor Alpha  ',
        sentQty: 60.0,
        receivedQty: 50.0,
        scrapQty: 2.0,
        cost: 300.0,
      );
      final id2 = await db.externalOperationDao.insertExternalOperationRecord(
        manufacturingOrderId: seeded.orderId,
        operationId: seeded.stageId,
        vendor: 'Vendor Beta',
        sentQty: 40.0,
        receivedQty: 25.0,
        scrapQty: 3.0,
        cost: 200.0,
      );

      final rows = await db.externalOperationDao.getForOrder(seeded.orderId);
      expect(rows.length, 2);
      expect(rows[0].id, id1);
      expect(rows[0].vendor, 'Vendor Alpha');
      expect(rows[1].id, id2);

      expect(await db.externalOperationDao.totalSentForOrder(seeded.orderId), 100.0);
      expect(await db.externalOperationDao.totalReceivedForOrder(seeded.orderId), 75.0);
      expect(await db.externalOperationDao.totalScrapForOrder(seeded.orderId), 5.0);
      // (60 - 50 - 2) + (40 - 25 - 3) = 8 + 12 = 20
      expect(
        await db.externalOperationDao.atVendorQuantityForOrder(seeded.orderId),
        20.0,
      );
    });
  });
}
