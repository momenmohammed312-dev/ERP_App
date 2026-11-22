import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_inspections_table.dart';

import '../../helpers/license_grant.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (MethodCall methodCall) async => '.',
  );

  late AppDatabase db;

  setUp(() {
    grantLicensedModules();
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    revokeLicensedModules();
    await db.close();
  });

  Future<({int orderId, int stageId, int productId})> seedOrderAndStage() async {
    final finId = await db.into(db.products).insert(
          ProductsCompanion.insert(name: 'Inspected Jacket', price: 200, quantity: 0),
        );
    final rawId = await db.into(db.products).insert(
          ProductsCompanion.insert(name: 'Linen', price: 50, quantity: 100),
        );
    final bomId = await db.bomDao.insertBomWithItems(
      bom: BillOfMaterialsCompanion(
        finishedProductId: Value(finId),
        name: const Value('Inspection BOM'),
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
        orderNumber: const Value('MO-INSP-01'),
        bomId: Value(bomId),
        finishedProductId: Value(finId),
        plannedQuantity: const Value(30.0),
      ),
    );
    final stageId = await db.manufacturingStageDao.addStage(
      orderId: orderId,
      stageName: 'فحص نهائي',
      inputQuantity: 30.0,
    );
    return (orderId: orderId, stageId: stageId, productId: finId);
  }

  group('ManufacturingInspectionDao (Phase 4 — D-07/D-10)', () {
    test('records accepted, rejected_for_rework, and second_grade inspections and queries by order & range', () async {
      final seeded = await seedOrderAndStage();

      final i1 = await db.manufacturingInspectionDao.recordInspection(
        orderId: seeded.orderId,
        stageId: seeded.stageId,
        productId: seeded.productId,
        inspectedBy: 'المشرف كريم',
        result: InspectionResult.accepted,
        quantity: 25.0,
        dispositionNote: 'مطابق لتقدير المشرف',
      );
      final i2 = await db.manufacturingInspectionDao.recordInspection(
        orderId: seeded.orderId,
        stageId: seeded.stageId,
        productId: seeded.productId,
        inspectedBy: 'العامل حسن',
        result: InspectionResult.rejectedForRework,
        quantity: 3.0,
        dispositionNote: 'خياطة تحتاج تعديل',
        photoRefs: '/internal/insp/1.jpg',
      );
      final i3 = await db.manufacturingInspectionDao.recordInspection(
        orderId: seeded.orderId,
        productId: seeded.productId,
        inspectedBy: 'المشرف كريم',
        result: InspectionResult.secondGrade,
        quantity: 2.0,
      );

      expect(i1.result, InspectionResult.accepted);
      expect(i2.photoRefs, '/internal/insp/1.jpg');
      expect(i3.stageId, isNull);

      final list = await db.manufacturingInspectionDao.getForOrder(seeded.orderId);
      expect(list.length, 3);
      expect(list.first.id, i3.id);

      final inRange = await db.manufacturingInspectionDao.getInRange(
        start: DateTime.now().subtract(const Duration(hours: 1)),
        end: DateTime.now().add(const Duration(hours: 1)),
      );
      expect(inRange.length, 3);
    });

    test('validates inspectedBy, result enum, and positive quantity', () async {
      final seeded = await seedOrderAndStage();

      await expectLater(
        () => db.manufacturingInspectionDao.recordInspection(
          orderId: seeded.orderId,
          productId: seeded.productId,
          inspectedBy: '   ',
          result: InspectionResult.accepted,
          quantity: 5.0,
        ),
        throwsArgumentError,
      );

      await expectLater(
        () => db.manufacturingInspectionDao.recordInspection(
          orderId: seeded.orderId,
          productId: seeded.productId,
          inspectedBy: 'Supervisor',
          result: 'unknown_status',
          quantity: 5.0,
        ),
        throwsArgumentError,
      );

      await expectLater(
        () => db.manufacturingInspectionDao.recordInspection(
          orderId: seeded.orderId,
          productId: seeded.productId,
          inspectedBy: 'Supervisor',
          result: InspectionResult.accepted,
          quantity: 0.0,
        ),
        throwsArgumentError,
      );
    });
  });
}
