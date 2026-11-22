import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_stages_table.dart';
import 'package:pos_offline_desktop/core/database/tables/routing_tables.dart';

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

  Future<({int orderId, int finishedId})> seedOrder({String orderNo = 'MO-RT-01'}) async {
    final finId = await db.into(db.products).insert(
          ProductsCompanion.insert(name: 'Printed Shirt', price: 150, quantity: 0),
        );
    final rawId = await db.into(db.products).insert(
          ProductsCompanion.insert(name: 'Cotton', price: 40, quantity: 100),
        );
    final bomId = await db.bomDao.insertBomWithItems(
      bom: BillOfMaterialsCompanion(
        finishedProductId: Value(finId),
        name: const Value('Shirt BOM'),
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
        orderNumber: Value(orderNo),
        bomId: Value(bomId),
        finishedProductId: Value(finId),
        plannedQuantity: const Value(50.0),
        orderType: const Value('for_others'),
      ),
    );
    return (orderId: orderId, finishedId: finId);
  }

  group('RoutingDao (Phase 2)', () {
    test('parallel branches, applyTemplateToOrder freeze (§3.3), and template mutation isolation', () async {
      final seeded = await seedOrder();

      final tplId = await db.routingDao.createTemplate(
        code: 'RT-TSHIRT-01',
        name: 'T-Shirt Parallel Print & Embroidery',
        productId: seeded.finishedId,
      );

      final cutNodeId = await db.routingDao.addTemplateNode(
        templateId: tplId,
        stageOrder: 1,
        name: 'القص',
        operationType: RoutingOperationType.machining,
        defaultLaborRate: 25.0,
        defaultMachineRate: 15.0,
        isTerminal: false,
      );
      // Two parallel branches sharing parentNodeId = cutNodeId
      final printNodeId = await db.routingDao.addTemplateNode(
        templateId: tplId,
        parentNodeId: cutNodeId,
        stageOrder: 2,
        name: 'طباعة سلك سكرين',
        operationType: RoutingOperationType.decoration,
        technique: 'screen_print',
        parametersJson: '{"screens":4,"ink":"waterbased"}',
        defaultLaborRate: 40.0,
        isTerminal: false,
      );
      await db.routingDao.addTemplateNode(
        templateId: tplId,
        parentNodeId: cutNodeId,
        stageOrder: 2,
        name: 'تطريز كم',
        operationType: RoutingOperationType.decoration,
        technique: 'embroidery',
        parametersJson: '{"stitches":8500}',
        defaultLaborRate: 35.0,
        isTerminal: false,
      );
      final packNodeId = await db.routingDao.addTemplateNode(
        templateId: tplId,
        parentNodeId: printNodeId,
        stageOrder: 3,
        name: 'كي وتغليف نهائي',
        operationType: RoutingOperationType.finishing,
        defaultLaborRate: 20.0,
        isTerminal: true,
      );

      final stageIds = await db.routingDao.applyTemplateToOrder(
        templateId: tplId,
        orderId: seeded.orderId,
      );
      expect(stageIds.length, 4);

      final mo = await db.manufacturingOrderDao.getById(seeded.orderId);
      expect(mo!.routingTemplateId, tplId);
      expect(mo.routingCode, 'RT-TSHIRT-01');

      final stages = await db.manufacturingStageDao.getStagesForOrder(seeded.orderId);
      expect(stages.length, 4);
      final cutStage = stages.firstWhere((s) => s.routingNodeId == cutNodeId);
      final parallelStages = stages.where((s) => s.parentStageId == cutStage.id).toList();
      expect(parallelStages.length, 2);
      final packStage = stages.firstWhere((s) => s.routingNodeId == packNodeId);
      expect(packStage.isTerminal, isTrue);

      // Edit template after freezing onto order: must NOT affect already-frozen order stages!
      await db.routingDao.addTemplateNode(
        templateId: tplId,
        stageOrder: 4,
        name: 'مرحلة إضافية بعد التجميد',
        isTerminal: true,
      );
      final stagesAfter = await db.manufacturingStageDao.getStagesForOrder(seeded.orderId);
      expect(stagesAfter.length, 4);
    });

    test('recordRework creates non-terminal rework stage & computeTerminalProducedQuantity avoids double counting (§2.4)', () async {
      final seeded = await seedOrder(orderNo: 'MO-RT-02');

      final s1 = await db.manufacturingStageDao.addStage(
        orderId: seeded.orderId,
        stageName: 'قص',
        stageOrder: 1,
        inputQuantity: 50.0,
      );
      final s2 = await db.manufacturingStageDao.addStage(
        orderId: seeded.orderId,
        stageName: 'تشطيب نهائي',
        stageOrder: 2,
        inputQuantity: 50.0,
      );
      await db.manufacturingStageDao.updateStage(
        stageId: s2,
        stageName: 'تشطيب نهائي',
        isTerminal: true,
      );

      // Intermediate stage output (50): must NOT count toward finished produced!
      await db.manufacturingStageDao.upsertStageOutput(
        stageId: s1,
        orderId: seeded.orderId,
        productId: seeded.finishedId,
        variantName: 'M',
        outputType: StageOutputType.primary,
        plannedQuantity: 50.0,
        producedQuantity: 50.0,
      );

      // Terminal stage outputs: 45 primary (scrap 2) + 5 by_product + 3 waste
      await db.manufacturingStageDao.upsertStageOutput(
        stageId: s2,
        orderId: seeded.orderId,
        productId: seeded.finishedId,
        variantName: 'M',
        outputType: StageOutputType.primary,
        plannedQuantity: 50.0,
        producedQuantity: 45.0,
        scrapQuantity: 2.0,
      );
      await db.manufacturingStageDao.upsertStageOutput(
        stageId: s2,
        orderId: seeded.orderId,
        productId: seeded.finishedId,
        variantName: 'قصاصات قماش',
        outputType: StageOutputType.byProduct,
        plannedQuantity: 5.0,
        producedQuantity: 5.0,
      );

      // Record rework on s2 (5 units) -> spawns rework stage & record
      final rw = await db.routingDao.recordRework(
        orderId: seeded.orderId,
        originalStageId: s2,
        quantity: 5.0,
        reason: 'طباعة باهتة تحتاج إعادة تثبيت',
        reworkedBy: 'Supervisor Ali',
      );
      expect(rw.reworkStageId, isNotNull);

      // Even if rework stage records output, it is non-terminal and excluded from §2.4 count!
      await db.manufacturingStageDao.upsertStageOutput(
        stageId: rw.reworkStageId!,
        orderId: seeded.orderId,
        productId: seeded.finishedId,
        variantName: 'إعادة',
        outputType: StageOutputType.primary,
        plannedQuantity: 5.0,
        producedQuantity: 5.0,
      );

      // Only terminal primary/co_product (45 - 2 = 43) counts!
      final terminalProduced =
          await db.routingDao.computeTerminalProducedQuantity(seeded.orderId);
      expect(terminalProduced, 43.0);

      // Completing s1 automatically writes a StageYieldRecord (45 / 50 = 90%)
      await db.manufacturingStageDao.updateStageStatus(
        stageId: s1,
        status: ManufacturingStageStatus.completed,
        outputQuantity: 45.0,
      );
      final y1 = await db.stageYieldDao.getByStage(seeded.orderId, s1);
      expect(y1, isNotNull);
      expect(y1!.yieldPercent, 90.0);
    });
  });
}
