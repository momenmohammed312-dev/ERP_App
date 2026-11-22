import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_orders_table.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_scrap_table.dart';

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

  Future<({
    String customerId,
    int rawA,
    int rawB,
    int finishedId,
    int bomId,
  })> seedBase() async {
    const customerId = 'cust-recon-1';
    await db.into(db.customers).insert(
          CustomersCompanion.insert(id: customerId, name: 'Test Recon Customer'),
        );
    final rawA = await db.into(db.products).insert(
          ProductsCompanion.insert(name: 'Fabric A', price: 40, quantity: 0),
        );
    final rawB = await db.into(db.products).insert(
          ProductsCompanion.insert(name: 'Thread B', price: 10, quantity: 0),
        );
    final finishedId = await db.into(db.products).insert(
          ProductsCompanion.insert(name: 'Finished Suit', price: 300, quantity: 0),
        );
    final bomId = await db.bomDao.insertBomWithItems(
      bom: BillOfMaterialsCompanion(
        finishedProductId: Value(finishedId),
        name: const Value('Suit BOM'),
      ),
      items: [
        BomItemsCompanion(
          rawMaterialProductId: Value(rawA),
          quantityRequired: const Value(2.0),
        ),
        BomItemsCompanion(
          rawMaterialProductId: Value(rawB),
          quantityRequired: const Value(1.0),
        ),
      ],
    );
    return (
      customerId: customerId,
      rawA: rawA,
      rawB: rawB,
      finishedId: finishedId,
      bomId: bomId,
    );
  }

  Future<int> createOrder({
    required int bomId,
    required int finishedId,
    required String customerId,
    required String orderNumber,
    double plannedQty = 50.0,
    String orderType = 'for_others',
    String status = ManufacturingOrderStatus.inProgress,
    double producedQty = 0.0,
  }) {
    return db.into(db.manufacturingOrders).insert(
          ManufacturingOrdersCompanion.insert(
            orderNumber: orderNumber,
            bomId: bomId,
            finishedProductId: finishedId,
            plannedQuantity: plannedQty,
            producedQuantity: Value(producedQty),
            status: Value(status),
            orderType: Value(orderType),
            customerId: Value(customerId),
          ),
        );
  }

  group('ReconciliationDao — Custody Equation (D-02)', () {
    test('tracks per-product custody via orderNumber and id.toString() and ignores factory_owned', () async {
      final s = await seedBase();
      final orderId = await createOrder(
        bomId: s.bomId,
        finishedId: s.finishedId,
        customerId: s.customerId,
        orderNumber: 'MO-REC-001',
      );

      // Main flow movement uses orderNumber ('issued_to_order')
      await db.into(db.customerStockMovements).insert(
            CustomerStockMovementsCompanion.insert(
              customerId: s.customerId,
              productId: s.rawA,
              movementType: 'issued_to_order',
              quantity: -100.0,
              referenceType: 'manufacturing_order',
              referenceId: 'MO-REC-001',
            ),
          );
      // JW branch movement uses order.id.toString() ('manufacturing_consumption')
      await db.into(db.customerStockMovements).insert(
            CustomerStockMovementsCompanion.insert(
              customerId: s.customerId,
              productId: s.rawB,
              movementType: 'manufacturing_consumption',
              quantity: -50.0,
              referenceType: 'manufacturing_order',
              referenceId: orderId.toString(),
            ),
          );
      // Optional future D-02 excess return on rawA
      await db.into(db.customerStockMovements).insert(
            CustomerStockMovementsCompanion.insert(
              customerId: s.customerId,
              productId: s.rawA,
              movementType: 'return_excess',
              quantity: 10.0,
              referenceType: 'manufacturing_order',
              referenceId: 'MO-REC-001',
            ),
          );

      // Analytical consumption logs
      await db.consumptionRecordDao.insertConsumptionRecord(
        manufacturingOrderId: orderId,
        materialProductId: s.rawA,
        ownershipType: 'customer_owned',
        actualQty: 85.0,
      );
      // Factory-owned consumption on rawA must NOT enter customer custody consumed
      await db.consumptionRecordDao.insertConsumptionRecord(
        manufacturingOrderId: orderId,
        materialProductId: s.rawA,
        ownershipType: 'factory_owned',
        actualQty: 999.0,
      );
      await db.consumptionRecordDao.insertConsumptionRecord(
        manufacturingOrderId: orderId,
        materialProductId: s.rawB,
        ownershipType: 'customer_owned',
        actualQty: 50.0,
      );

      final summary = await db.reconciliationDao.reconcile(orderId);
      expect(summary.custody.keys, containsAll([s.rawA, s.rawB]));

      final lineA = summary.custody[s.rawA]!;
      expect(lineA.issued, 100.0);
      expect(lineA.consumed, 85.0);
      expect(lineA.returnedExcess, 10.0);
      expect(lineA.remaining, 5.0);

      final lineB = summary.custody[s.rawB]!;
      expect(lineB.issued, 50.0);
      expect(lineB.consumed, 50.0);
      expect(lineB.returnedExcess, 0.0);
      expect(lineB.remaining, 0.0);

      expect(await db.reconciliationDao.checkCustodyEquations(orderId), isEmpty);
      await db.reconciliationDao.assertCustodyEquation(orderId);
    });

    test('two products do not cross-subsidize: overconsuming rawB fails even if rawA has excess', () async {
      final s = await seedBase();
      final orderId = await createOrder(
        bomId: s.bomId,
        finishedId: s.finishedId,
        customerId: s.customerId,
        orderNumber: 'MO-REC-002',
      );

      // rawA: issued 100, consumed 10 -> +90 remaining
      await db.into(db.customerStockMovements).insert(
            CustomerStockMovementsCompanion.insert(
              customerId: s.customerId,
              productId: s.rawA,
              movementType: 'issued_to_order',
              quantity: -100.0,
              referenceType: 'manufacturing_order',
              referenceId: 'MO-REC-002',
            ),
          );
      await db.consumptionRecordDao.insertConsumptionRecord(
        manufacturingOrderId: orderId,
        materialProductId: s.rawA,
        ownershipType: 'customer_owned',
        actualQty: 10.0,
      );

      // rawB: issued 20, consumed 25 -> -5 remaining (violation!)
      await db.into(db.customerStockMovements).insert(
            CustomerStockMovementsCompanion.insert(
              customerId: s.customerId,
              productId: s.rawB,
              movementType: 'issued_to_order',
              quantity: -20.0,
              referenceType: 'manufacturing_order',
              referenceId: 'MO-REC-002',
            ),
          );
      await db.consumptionRecordDao.insertConsumptionRecord(
        manufacturingOrderId: orderId,
        materialProductId: s.rawB,
        ownershipType: 'customer_owned',
        actualQty: 25.0,
      );

      final violations = await db.reconciliationDao.checkCustodyEquations(orderId);
      expect(violations.length, 1);
      expect(violations.first, contains('product #${s.rawB}'));
      await expectLater(
        () => db.reconciliationDao.assertCustodyEquation(orderId),
        throwsStateError,
      );
    });
  });

  group('ReconciliationDao — Single Disposition & Completion Gates', () {
    test('checkSingleDisposition passes when returnedOutputs + finished customer scrap <= produced', () async {
      final s = await seedBase();
      final orderId = await createOrder(
        bomId: s.bomId,
        finishedId: s.finishedId,
        customerId: s.customerId,
        orderNumber: 'MO-REC-003',
        producedQty: 50.0,
      );
      final stageId = await db.manufacturingStageDao.addStage(
        orderId: orderId,
        stageName: 'Finishing',
        stageOrder: 1,
        inputQuantity: 50.0,
      );

      await db.into(db.manufacturingStageOutputs).insert(
            ManufacturingStageOutputsCompanion.insert(
              stageId: stageId,
              manufacturingOrderId: orderId,
              productId: s.finishedId,
              disposition: const Value('returned_to_customer'),
              producedQuantity: const Value(45.0),
            ),
          );

      // 5 customer-fault scrap on finished good -> 45 + 5 == 50 (valid)
      await db.manufacturingScrapDao.recordOrderScrapWithPolicy(
        orderId: orderId,
        productId: s.finishedId,
        quantity: 5.0,
        reason: ManufacturingScrapReason.defective,
        responsibleParty: 'Customer defect',
        faultParty: 'customer',
      );

      // Customer-fault scrap on raw material does not count as finished good disposition
      await db.manufacturingScrapDao.recordOrderScrapWithPolicy(
        orderId: orderId,
        productId: s.rawA,
        quantity: 10.0,
        reason: ManufacturingScrapReason.defective,
        responsibleParty: 'Customer raw defect',
        faultParty: 'customer',
      );

      expect(await db.reconciliationDao.checkSingleDisposition(orderId), isEmpty);
      await db.reconciliationDao.assertSingleDisposition(orderId);

      // Pushing returned outputs over produced triggers double-disposition error
      await db.into(db.manufacturingStageOutputs).insert(
            ManufacturingStageOutputsCompanion.insert(
              stageId: stageId,
              manufacturingOrderId: orderId,
              productId: s.finishedId,
              disposition: const Value('returned_to_customer'),
              producedQuantity: const Value(1.0),
            ),
          );
      await expectLater(
        () => db.reconciliationDao.assertSingleDisposition(orderId),
        throwsStateError,
      );
    });

    test('gate (a): for_others order with producedQuantity > plannedQuantity fails with order id', () async {
      final s = await seedBase();
      final orderId = await createOrder(
        bomId: s.bomId,
        finishedId: s.finishedId,
        customerId: s.customerId,
        orderNumber: 'MO-REC-004',
        plannedQty: 50.0,
        producedQty: 55.0,
        status: ManufacturingOrderStatus.inProgress,
      );
      final mo = (await db.reconciliationDao.getOrder(orderId))!;

      final violations = await db.reconciliationDao.checkCompletionGate(mo);
      expect(violations.length, 1);
      expect(violations.first, contains('MO #$orderId'));
      await expectLater(
        () => db.reconciliationDao.assertCompletionGate(mo),
        throwsStateError,
      );
    });

    test('gate (b): ignores Lost (customer scrap) on closure and fails when atVendor > 0 or remainingWip > 0', () async {
      final s = await seedBase();
      final orderId = await createOrder(
        bomId: s.bomId,
        finishedId: s.finishedId,
        customerId: s.customerId,
        orderNumber: 'MO-REC-005',
        plannedQty: 50.0,
        producedQty: 50.0,
        status: ManufacturingOrderStatus.completed,
      );
      final stageId = await db.manufacturingStageDao.addStage(
        orderId: orderId,
        stageName: 'Embroidery',
        stageOrder: 1,
        inputQuantity: 50.0,
      );

      // All 50 produced units are dispositioned in stage outputs -> remainingWip == 0
      await db.into(db.manufacturingStageOutputs).insert(
            ManufacturingStageOutputsCompanion.insert(
              stageId: stageId,
              manufacturingOrderId: orderId,
              productId: s.finishedId,
              disposition: const Value('produced'),
              producedQuantity: const Value(50.0),
            ),
          );
      // Customer-fault scrap recorded -> Lost == 3 (accepted final disposition!)
      await db.manufacturingScrapDao.recordOrderScrapWithPolicy(
        orderId: orderId,
        productId: s.finishedId,
        quantity: 3.0,
        reason: ManufacturingScrapReason.defective,
        responsibleParty: 'Customer fabric tear',
        faultParty: 'customer',
      );

      var mo = (await db.reconciliationDao.getOrder(orderId))!;
      expect(await db.reconciliationDao.checkCompletionGate(mo), isEmpty);
      await db.reconciliationDao.assertCompletionGate(mo);

      // Adding unresolved external vendor work -> gate (b) rejects
      await db.externalOperationDao.insertExternalOperationRecord(
        manufacturingOrderId: orderId,
        operationId: stageId,
        vendor: 'Dye House',
        sentQty: 20.0,
        receivedQty: 15.0,
      );

      final violations = await db.reconciliationDao.checkCompletionGate(mo);
      expect(violations.length, 1);
      expect(violations.first, contains('AtExternalVendor'));
      await expectLater(
        () => db.reconciliationDao.assertCompletionGate(mo),
        throwsStateError,
      );
    });
  });
}
