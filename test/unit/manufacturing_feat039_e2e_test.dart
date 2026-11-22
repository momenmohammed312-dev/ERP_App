import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/dao/customer_material_receipt_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/manufacturing_delivery_dao.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_inspections_table.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_orders_table.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_stages_table.dart';
import 'package:pos_offline_desktop/core/database/tables/routing_tables.dart';

import '../helpers/license_grant.dart';

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

  group('FEAT-039 End-to-End & Edge Cases (Phases 1 → 4)', () {
    test(
      'full Phases 1->2->3->4 mixed+separate lifecycle: routing, external vendor gate, auto yield, rework, D-07 inspection, excess return, D-08 extra approval, invoice & frozen snapshot',
      () async {
        // 1. Seed customer & materials
        await db.into(db.customers).insert(
              CustomersCompanion.insert(
                id: 'cust-e2e',
                name: 'عميل التشغيل المتكامل',
              ),
            );
        final custFabric = await db.into(db.products).insert(
              ProductsCompanion.insert(
                name: 'قماش كتان العميل',
                price: 100.0,
                costPrice: const Value(80.0),
                quantity: 0,
              ),
            );
        final facThread = await db.into(db.products).insert(
              ProductsCompanion.insert(
                name: 'خيط وحشو المصنع',
                price: 30.0,
                costPrice: const Value(20.0),
                quantity: 100,
              ),
            );
        final extraZipper = await db.into(db.products).insert(
              ProductsCompanion.insert(
                name: 'سحاب إضافي خاص',
                price: 18.0,
                costPrice: const Value(10.0),
                quantity: 50,
              ),
            );
        final finJacket = await db.into(db.products).insert(
              ProductsCompanion.insert(
                name: 'جاكيت نهائي E2E',
                price: 300.0,
                quantity: 0,
              ),
            );

        // Receive 100 units of customer fabric into custody
        await db.customerMaterialReceiptDao.receiveCustomerMaterial(
          customerId: 'cust-e2e',
          items: [
            ReceiptItemInput(productId: custFabric, quantityReceived: 100.0),
          ],
        );

        // 2. BOM: 2.0 customer fabric + 1.0 factory thread per jacket
        final bomId = await db.bomDao.insertBomWithItems(
          bom: BillOfMaterialsCompanion(
            finishedProductId: Value(finJacket),
            name: const Value('BOM الجاكيت المتكامل'),
          ),
          items: [
            BomItemsCompanion(
              rawMaterialProductId: Value(custFabric),
              quantityRequired: const Value(2.0),
            ),
            BomItemsCompanion(
              rawMaterialProductId: Value(facThread),
              quantityRequired: const Value(1.0),
            ),
          ],
        );

        // 3. Universal Routing template with parallel branches & terminal node
        final tplId = await db.routingDao.createTemplate(
          code: 'RT-E2E-01',
          name: 'مسار الجاكيت المتكامل',
          productId: finJacket,
        );
        final cutNode = await db.routingDao.addTemplateNode(
          templateId: tplId,
          stageOrder: 1,
          name: 'القص',
          operationType: RoutingOperationType.machining,
          defaultLaborRate: 20.0,
          defaultMachineRate: 10.0,
          isTerminal: false,
        );
        await db.routingDao.addTemplateNode(
          templateId: tplId,
          parentNodeId: cutNode,
          stageOrder: 2,
          name: 'التطريز',
          operationType: RoutingOperationType.decoration,
          defaultLaborRate: 30.0,
          isTerminal: false,
        );
        await db.routingDao.addTemplateNode(
          templateId: tplId,
          parentNodeId: cutNode,
          stageOrder: 2,
          name: 'تشطيب وتغليف',
          operationType: RoutingOperationType.finishing,
          defaultLaborRate: 25.0,
          isTerminal: true,
        );

        // 4. Create mixed order (separate pricing) & freeze routing onto it
        final orderId = await db.manufacturingOrderDao.createOrder(
          ManufacturingOrdersCompanion(
            orderNumber: const Value('MO-E2E-001'),
            bomId: Value(bomId),
            finishedProductId: Value(finJacket),
            plannedQuantity: const Value(20.0),
            orderType: const Value('mixed'),
            customerId: const Value('cust-e2e'),
            pricingMode: const Value('separate'),
            serviceUnitPrice: const Value(50.0),
          ),
        );
        final stageIds = await db.routingDao.applyTemplateToOrder(
          templateId: tplId,
          orderId: orderId,
        );
        expect(stageIds.length, 3);
        final s1 = stageIds[0];
        final s2 = stageIds[1];
        final s3 = stageIds[2];

        // 5. Dispatch 10 units to external workshop (not yet returned)
        final extOpId = await db.externalOperationDao.insertExternalOperationRecord(
          manufacturingOrderId: orderId,
          operationId: s2,
          vendor: 'ورشة النور',
          sentQty: 10.0,
          receivedQty: 0.0,
          cost: 120.0,
        );
        expect(
          await db.externalOperationDao.atVendorQuantityForOrder(orderId),
          10.0,
        );

        // 6. Complete all 3 stages -> auto StageYieldRecords written
        await db.manufacturingStageDao.updateStageStatus(
          stageId: s1,
          status: ManufacturingStageStatus.completed,
          outputQuantity: 20.0,
          scrapQuantity: 0.0,
          laborHours: 2.0,
          machineHours: 1.0,
        );
        await db.manufacturingStageDao.updateStageStatus(
          stageId: s2,
          status: ManufacturingStageStatus.completed,
          outputQuantity: 20.0,
          scrapQuantity: 0.0,
          laborHours: 1.0,
        );
        await db.manufacturingStageDao.updateStageStatus(
          stageId: s3,
          status: ManufacturingStageStatus.completed,
          outputQuantity: 20.0,
          scrapQuantity: 0.0,
          laborHours: 2.0,
        );
        expect((await db.stageYieldDao.getForOrder(orderId)).length, 3);

        // Record terminal primary output (default disposition = 'produced', 20 units)
        final outId = await db.manufacturingStageDao.upsertStageOutput(
          stageId: s3,
          orderId: orderId,
          productId: finJacket,
          variantName: 'L',
          outputType: StageOutputType.primary,
          plannedQuantity: 20.0,
          producedQuantity: 20.0,
        );

        // 7. D-07 inspections & non-terminal rework stage (no double count §2.4)
        await db.manufacturingInspectionDao.recordInspection(
          orderId: orderId,
          stageId: s3,
          productId: finJacket,
          inspectedBy: 'المشرف كريم',
          result: InspectionResult.accepted,
          quantity: 18.0,
        );
        await db.manufacturingInspectionDao.recordInspection(
          orderId: orderId,
          stageId: s3,
          productId: finJacket,
          inspectedBy: 'المشرف كريم',
          result: InspectionResult.rejectedForRework,
          quantity: 2.0,
        );
        expect((await db.manufacturingInspectionDao.getForOrder(orderId)).length, 2);

        final rework = await db.routingDao.recordRework(
          orderId: orderId,
          originalStageId: s3,
          quantity: 2.0,
          reason: 'إعادة كي الحواف',
          reworkedBy: 'أحمد',
        );
        final reworkStage =
            await db.manufacturingStageDao.getStageById(rework.reworkStageId!);
        expect(reworkStage!.isTerminal, isFalse);
        expect(await db.routingDao.computeTerminalProducedQuantity(orderId), 20.0);

        // 8. Complete mixed order (emits linked ConsumptionRecords + productionCompletedAt)
        await db.manufacturingOrderDao.completeForOthersOrder(
          orderId: orderId,
          customerOwnedProductIds: {custFabric},
        );
        final moCompleted = await db.manufacturingOrderDao.getById(orderId);
        expect(moCompleted!.status, ManufacturingOrderStatus.completed);
        expect(moCompleted.productionCompletedAt, isNotNull);

        // Closure gate (b) must fail while AtExternalVendor = 10 > 0
        final gateViolationsPendingVendor =
            await db.reconciliationDao.checkCompletionGate(moCompleted);
        expect(gateViolationsPendingVendor, isNotEmpty);
        expect(gateViolationsPendingVendor.first, contains('AtExternalVendor'));

        // Vendor returns all 10 units -> closure gate (b) now passes
        await (db.update(db.externalOperationRecords)
              ..where((e) => e.id.equals(extOpId)))
            .write(
          ExternalOperationRecordsCompanion(
            receivedQty: const Value(10.0),
            receivedAt: Value(DateTime.now()),
          ),
        );
        expect(
          await db.externalOperationDao.atVendorQuantityForOrder(orderId),
          0.0,
        );
        expect(await db.reconciliationDao.checkCompletionGate(moCompleted), isEmpty);

        // 9. Return 5m excess customer fabric (D-02 + D-03 trim)
        await db.customerMaterialReceiptDao.returnExcessFromOrder(
          orderId: orderId,
          productId: custFabric,
          quantity: 5.0,
          notes: 'متبقي قص القماش',
        );
        final recon = await db.reconciliationDao.reconcile(orderId);
        final custLine = recon.custody[custFabric]!;
        expect(custLine.issued, 40.0);
        expect(custLine.consumed, 35.0);
        expect(custLine.returnedExcess, 5.0);
        expect(custLine.remaining, 0.0);
        expect(await db.reconciliationDao.checkCustodyEquations(orderId), isEmpty);
        expect(await db.reconciliationDao.checkSingleDisposition(orderId), isEmpty);

        // 10. Request & approve extra zipper with 20% margin (D-04/D-08)
        final req = await db.manufacturingCostingDao.requestExtraMaterial(
          orderId: orderId,
          productId: extraZipper,
          quantity: 5.0,
          requestedBy: 'المشرف طارق',
          marginPercent: 20.0,
        );
        expect(req.unitCostSnapshot, 10.0);
        expect(req.approvedAmount, 60.0); // 5 * 10 * 1.20
        await db.manufacturingCostingDao.approveExtraMaterial(
          approvalId: req.id,
          approvedBy: 'العميل',
          authorizationRef: 'WA-E2E-99',
        );

        // 11. Deliver 20 units & mark output returned_to_customer, then invoice:
        // Service = 20*50 (1000) + Separate BOM thread = 20*30 (600) + Extra = 60 => 1660
        await db.manufacturingDeliveryDao.createDelivery(
          orderId: orderId,
          items: [DeliveryItemInput(productId: finJacket, quantity: 20)],
        );
        await (db.update(db.manufacturingStageOutputs)
              ..where((o) => o.id.equals(outId)))
            .write(
          const ManufacturingStageOutputsCompanion(
            disposition: Value('returned_to_customer'),
          ),
        );
        expect(await db.reconciliationDao.checkSingleDisposition(orderId), isEmpty);
        final inv = await db.manufacturingDeliveryDao.generateServiceInvoice(orderId);
        expect(inv.totalAmount, 1660.0);

        // Frozen cost snapshot (§5, D-11):
        // Material (factory only) = 20*20 = 400; Labor = 2*20 + 1*30 + 2*25 = 120;
        // Machine = 1*10 = 10; External = 120 => Total = 650.0
        final snap = await db.manufacturingCostingDao.getLatestSnapshot(orderId);
        expect(snap, isNotNull);
        expect(snap!.isFrozen, isTrue);
        expect(snap.materialCost, 400.0);
        expect(snap.laborCost, 120.0);
        expect(snap.machineCost, 10.0);
        expect(snap.externalCost, 120.0);
        expect(snap.totalActualCost, 650.0);
        expect(snap.deliveredRevenue, 1000.0);
        expect(snap.extraMaterialsRevenue, 60.0);
      },
    );

    test(
      'ExtraMaterialApproval enforces validation & non-pending state transition guards',
      () async {
        final finId = await db.into(db.products).insert(
              ProductsCompanion.insert(name: 'Finished X', price: 200, quantity: 0),
            );
        final rawId = await db.into(db.products).insert(
              ProductsCompanion.insert(
                name: 'Raw X',
                price: 20,
                costPrice: const Value(10),
                quantity: 100,
              ),
            );
        final bomId = await db.bomDao.insertBomWithItems(
          bom: BillOfMaterialsCompanion(
            finishedProductId: Value(finId),
            name: const Value('BOM X'),
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
            orderNumber: const Value('MO-GUARD-01'),
            bomId: Value(bomId),
            finishedProductId: Value(finId),
            plannedQuantity: const Value(5.0),
          ),
        );

        await expectLater(
          () => db.manufacturingCostingDao.requestExtraMaterial(
            orderId: orderId,
            productId: rawId,
            quantity: 0.0,
            requestedBy: 'Omar',
          ),
          throwsArgumentError,
        );
        await expectLater(
          () => db.manufacturingCostingDao.requestExtraMaterial(
            orderId: orderId,
            productId: rawId,
            quantity: 2.0,
            requestedBy: 'Omar',
            marginPercent: -5.0,
          ),
          throwsArgumentError,
        );
        await expectLater(
          () => db.manufacturingCostingDao.requestExtraMaterial(
            orderId: orderId,
            productId: rawId,
            quantity: 2.0,
            requestedBy: '   ',
          ),
          throwsArgumentError,
        );
        await expectLater(
          () => db.manufacturingCostingDao.requestExtraMaterial(
            orderId: 99999,
            productId: rawId,
            quantity: 2.0,
            requestedBy: 'Omar',
          ),
          throwsArgumentError,
        );
        await expectLater(
          () => db.manufacturingCostingDao.requestExtraMaterial(
            orderId: orderId,
            productId: 99999,
            quantity: 2.0,
            requestedBy: 'Omar',
          ),
          throwsArgumentError,
        );

        final req = await db.manufacturingCostingDao.requestExtraMaterial(
          orderId: orderId,
          productId: rawId,
          quantity: 3.0,
          requestedBy: 'Omar',
        );

        await expectLater(
          () => db.manufacturingCostingDao.approveExtraMaterial(
            approvalId: req.id,
            approvedBy: '  ',
          ),
          throwsArgumentError,
        );
        await expectLater(
          () => db.manufacturingCostingDao.approveExtraMaterial(
            approvalId: req.id,
            approvedBy: 'Client',
            overrideAmount: -1.0,
          ),
          throwsArgumentError,
        );

        await db.manufacturingCostingDao.approveExtraMaterial(
          approvalId: req.id,
          approvedBy: 'Client',
        );

        // Cannot re-approve or reject an already-approved request
        await expectLater(
          () => db.manufacturingCostingDao.approveExtraMaterial(
            approvalId: req.id,
            approvedBy: 'Client',
          ),
          throwsStateError,
        );
        await expectLater(
          () => db.manufacturingCostingDao.rejectExtraMaterial(
            approvalId: req.id,
          ),
          throwsStateError,
        );

        // Cannot approve an already-rejected request
        final req2 = await db.manufacturingCostingDao.requestExtraMaterial(
          orderId: orderId,
          productId: rawId,
          quantity: 1.0,
          requestedBy: 'Omar',
        );
        await db.manufacturingCostingDao.rejectExtraMaterial(approvalId: req2.id);
        await expectLater(
          () => db.manufacturingCostingDao.approveExtraMaterial(
            approvalId: req2.id,
            approvedBy: 'Client',
          ),
          throwsStateError,
        );
      },
    );

    test(
      'updateStageStatus auto-records exact StageYieldRecord (90%) and applyTemplateToOrder rejects empty template',
      () async {
        final finId = await db.into(db.products).insert(
              ProductsCompanion.insert(name: 'Finished Y', price: 120, quantity: 0),
            );
        final rawId = await db.into(db.products).insert(
              ProductsCompanion.insert(name: 'Raw Y', price: 30, quantity: 100),
            );
        final bomId = await db.bomDao.insertBomWithItems(
          bom: BillOfMaterialsCompanion(
            finishedProductId: Value(finId),
            name: const Value('BOM Y'),
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
            orderNumber: const Value('MO-YIELD-01'),
            bomId: Value(bomId),
            finishedProductId: Value(finId),
            plannedQuantity: const Value(40.0),
          ),
        );

        // Empty routing template guard
        final emptyTplId = await db.routingDao.createTemplate(
          code: 'RT-EMPTY',
          name: 'قالب فارغ',
        );
        await expectLater(
          () => db.routingDao.applyTemplateToOrder(
            templateId: emptyTplId,
            orderId: orderId,
          ),
          throwsStateError,
        );

        // Auto StageYieldRecord: input = 40, accepted = 36 => 90.0%
        final stageId = await db.manufacturingStageDao.addStage(
          orderId: orderId,
          stageName: 'مرحلة الفحص الآلي',
          inputQuantity: 40.0,
        );
        await db.manufacturingStageDao.updateStageStatus(
          stageId: stageId,
          status: ManufacturingStageStatus.completed,
          outputQuantity: 36.0,
          scrapQuantity: 4.0,
        );
        final yieldRow = await db.stageYieldDao.getByStage(orderId, stageId);
        expect(yieldRow, isNotNull);
        expect(yieldRow!.inputQuantity, 40.0);
        expect(yieldRow.acceptedOutput, 36.0);
        expect(yieldRow.yieldPercent, closeTo(90.0, 0.001));
      },
    );
  });
}
