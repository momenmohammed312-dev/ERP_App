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

  Future<({int orderId, int stage1Id, int stage2Id})> seedOrderAndStages() async {
    final finishedId = await db.into(db.products).insert(
          ProductsCompanion.insert(name: 'Dress Shirt', price: 120, quantity: 0),
        );
    final rawId = await db.into(db.products).insert(
          ProductsCompanion.insert(name: 'Cotton', price: 30, quantity: 100),
        );
    final bomId = await db.bomDao.insertBomWithItems(
      bom: BillOfMaterialsCompanion(
        finishedProductId: Value(finishedId),
        name: const Value('Shirt BOM'),
      ),
      items: [
        BomItemsCompanion(
          rawMaterialProductId: Value(rawId),
          quantityRequired: const Value(1.5),
        ),
      ],
    );
    final orderId = await db.manufacturingOrderDao.createOrder(
      ManufacturingOrdersCompanion(
        orderNumber: const Value('MO-SY-001'),
        bomId: Value(bomId),
        finishedProductId: Value(finishedId),
        plannedQuantity: const Value(100.0),
      ),
    );
    final stage1Id = await db.manufacturingStageDao.addStage(
      orderId: orderId,
      stageName: 'Cutting',
      stageOrder: 1,
      inputQuantity: 100.0,
    );
    final stage2Id = await db.manufacturingStageDao.addStage(
      orderId: orderId,
      stageName: 'Sewing',
      stageOrder: 2,
      inputQuantity: 80.0,
    );
    return (orderId: orderId, stage1Id: stage1Id, stage2Id: stage2Id);
  }

  group('StageYieldDao', () {
    test('recordStageYield computes yieldPercent = 80.0 for (100, 80)', () async {
      final seeded = await seedOrderAndStages();

      final row = await db.stageYieldDao.recordStageYield(
        manufacturingOrderId: seeded.orderId,
        stageId: seeded.stage1Id,
        inputQuantity: 100.0,
        acceptedOutput: 80.0,
      );

      expect(row.manufacturingOrderId, seeded.orderId);
      expect(row.stageId, seeded.stage1Id);
      expect(row.inputQuantity, 100.0);
      expect(row.acceptedOutput, 80.0);
      expect(row.yieldPercent, 80.0);
    });

    test('recordStageYield stores 0.0 yieldPercent when inputQuantity is 0', () async {
      final seeded = await seedOrderAndStages();

      final row = await db.stageYieldDao.recordStageYield(
        manufacturingOrderId: seeded.orderId,
        stageId: seeded.stage1Id,
        inputQuantity: 0.0,
        acceptedOutput: 0.0,
      );

      expect(row.yieldPercent, 0.0);
    });

    test('recordStageYield rejects negative inputQuantity or acceptedOutput with ArgumentError', () async {
      final seeded = await seedOrderAndStages();

      await expectLater(
        () => db.stageYieldDao.recordStageYield(
          manufacturingOrderId: seeded.orderId,
          stageId: seeded.stage1Id,
          inputQuantity: -1.0,
          acceptedOutput: 10.0,
        ),
        throwsArgumentError,
      );

      await expectLater(
        () => db.stageYieldDao.recordStageYield(
          manufacturingOrderId: seeded.orderId,
          stageId: seeded.stage1Id,
          inputQuantity: 10.0,
          acceptedOutput: -0.5,
        ),
        throwsArgumentError,
      );
    });

    test('getByStage returns latest record when duplicate rows exist for same stage', () async {
      final seeded = await seedOrderAndStages();

      expect(
        await db.stageYieldDao.getByStage(seeded.orderId, seeded.stage1Id),
        isNull,
      );

      await db.stageYieldDao.recordStageYield(
        manufacturingOrderId: seeded.orderId,
        stageId: seeded.stage1Id,
        inputQuantity: 100.0,
        acceptedOutput: 70.0,
      );
      final latest = await db.stageYieldDao.recordStageYield(
        manufacturingOrderId: seeded.orderId,
        stageId: seeded.stage1Id,
        inputQuantity: 100.0,
        acceptedOutput: 92.0,
      );

      final fetched =
          await db.stageYieldDao.getByStage(seeded.orderId, seeded.stage1Id);
      expect(fetched, isNotNull);
      expect(fetched!.id, latest.id);
      expect(fetched.acceptedOutput, 92.0);
      expect(fetched.yieldPercent, 92.0);
    });

    test('getForOrder returns all records ordered oldest first', () async {
      final seeded = await seedOrderAndStages();

      final first = await db.stageYieldDao.recordStageYield(
        manufacturingOrderId: seeded.orderId,
        stageId: seeded.stage1Id,
        inputQuantity: 100.0,
        acceptedOutput: 80.0,
      );
      final second = await db.stageYieldDao.recordStageYield(
        manufacturingOrderId: seeded.orderId,
        stageId: seeded.stage2Id,
        inputQuantity: 80.0,
        acceptedOutput: 76.0,
      );

      final list = await db.stageYieldDao.getForOrder(seeded.orderId);
      expect(list.map((r) => r.id).toList(), [first.id, second.id]);
      expect(list[1].yieldPercent, 95.0);
    });
  });
}
