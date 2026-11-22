import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/dao/customer_material_receipt_dao.dart';

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

  Future<int> seedProduct(String name, {int qty = 0, double price = 50}) {
    return db.into(db.products).insert(
          ProductsCompanion.insert(
            name: name,
            quantity: qty,
            price: price,
            costPrice: Value(price),
          ),
        );
  }

  group('Phase 1 Batch 3 — Consumption Linkage, return_excess & return_custody', () {
    test('completeForOthersOrder (mixed + JW) records linked ConsumptionRecords and productionCompletedAt', () async {
      await db.into(db.customers).insert(
            CustomersCompanion.insert(id: 'cust-b3', name: 'Batch 3 Customer'),
          );
      final custCloth = await seedProduct('Customer Cloth', qty: 0, price: 80);
      final factoryInk = await seedProduct('Factory Ink', qty: 100, price: 25);
      final printedShirt = await seedProduct('Printed Shirt', qty: 0, price: 150);

      await db.customerMaterialReceiptDao.receiveCustomerMaterial(
        customerId: 'cust-b3',
        items: [
          ReceiptItemInput(productId: custCloth, quantityReceived: 120.0),
        ],
      );

      final bomId = await db.bomDao.insertBomWithItems(
        bom: BillOfMaterialsCompanion(
          finishedProductId: Value(printedShirt),
          name: const Value('Mixed Shirt BOM'),
        ),
        items: [
          BomItemsCompanion(
            rawMaterialProductId: Value(custCloth),
            quantityRequired: const Value(2.0),
          ),
          BomItemsCompanion(
            rawMaterialProductId: Value(factoryInk),
            quantityRequired: const Value(1.0),
          ),
        ],
      );

      final orderId = await db.manufacturingOrderDao.createOrder(
        ManufacturingOrdersCompanion(
          orderNumber: const Value('MO-B3-MIX'),
          bomId: Value(bomId),
          finishedProductId: Value(printedShirt),
          plannedQuantity: const Value(30.0),
          orderType: const Value('mixed'),
          customerId: const Value('cust-b3'),
        ),
      );

      await db.manufacturingOrderDao.completeForOthersOrder(
        orderId: orderId,
        customerOwnedProductIds: {custCloth},
      );

      final completedMo = await db.manufacturingOrderDao.getById(orderId);
      expect(completedMo!.productionCompletedAt, isNotNull);

      final recs = await db.consumptionRecordDao.getForOrder(orderId);
      expect(recs.length, 2);

      final custRec = recs.firstWhere((r) => r.materialProductId == custCloth);
      expect(custRec.ownershipType, 'customer_owned');
      expect(custRec.actualQty, 60.0);
      expect(custRec.unitCostSnapshot, 0.0);
      expect(custRec.customerStockMovementId, isNotNull);
      expect(custRec.stockMovementId, isNull);

      final facRec = recs.firstWhere((r) => r.materialProductId == factoryInk);
      expect(facRec.ownershipType, 'factory_owned');
      expect(facRec.actualQty, 30.0);
      expect(facRec.unitCostSnapshot, 25.0);
      expect(facRec.stockMovementId, isNotNull);
      expect(facRec.customerStockMovementId, isNull);

      expect(await db.reconciliationDao.checkCustodyEquations(orderId), isEmpty);

      // Also verify Job Work (JW) branch
      final jwOrderId = await db.manufacturingOrderDao.createJobWorkOrder(
        orderNumber: 'JW-B3-01',
        orderType: 'for_others',
        customerId: 'cust-b3',
        inputProductId: custCloth,
        inputQuantity: 20.0,
      );
      await db.manufacturingOrderDao.startOrder(jwOrderId);
      await db.manufacturingOrderDao.completeForOthersOrder(
        orderId: jwOrderId,
        goodQuantity: 18.0,
        scrapQuantity: 2.0,
      );

      final jwMo = await db.manufacturingOrderDao.getById(jwOrderId);
      expect(jwMo!.productionCompletedAt, isNotNull);

      final jwRecs = await db.consumptionRecordDao.getForOrder(jwOrderId);
      expect(jwRecs.length, 1);
      expect(jwRecs.first.ownershipType, 'customer_owned');
      expect(jwRecs.first.actualQty, 20.0);
      expect(jwRecs.first.unitCostSnapshot, 0.0);
      expect(jwRecs.first.customerStockMovementId, isNotNull);
      expect(await db.reconciliationDao.checkCustodyEquations(jwOrderId), isEmpty);
    });

    test('returnExcessFromOrder restores balance, records +return_excess, trims ConsumptionRecord (D-03), and guards over-return', () async {
      await db.into(db.customers).insert(
            CustomersCompanion.insert(id: 'cust-ex', name: 'Excess Customer'),
          );
      final fabricId = await seedProduct('Cotton Roll', qty: 0);
      final shirtId = await seedProduct('Shirt', qty: 0);

      await db.customerMaterialReceiptDao.receiveCustomerMaterial(
        customerId: 'cust-ex',
        items: [ReceiptItemInput(productId: fabricId, quantityReceived: 100.0)],
      );

      final bomId = await db.bomDao.insertBomWithItems(
        bom: BillOfMaterialsCompanion(
          finishedProductId: Value(shirtId),
          name: const Value('Shirt BOM'),
        ),
        items: [
          BomItemsCompanion(
            rawMaterialProductId: Value(fabricId),
            quantityRequired: const Value(1.0),
          ),
        ],
      );

      final orderId = await db.manufacturingOrderDao.createOrder(
        ManufacturingOrdersCompanion(
          orderNumber: const Value('MO-EX-01'),
          bomId: Value(bomId),
          finishedProductId: Value(shirtId),
          plannedQuantity: const Value(80.0),
          orderType: const Value('for_others'),
          customerId: const Value('cust-ex'),
        ),
      );

      await db.manufacturingOrderDao.completeForOthersOrder(orderId: orderId);
      // Custody balance before excess return: 100 - 80 = 20
      expect(
        await db.customerMaterialReceiptDao.getCustomerAvailableQuantity(
          customerId: 'cust-ex',
          productId: fabricId,
        ),
        20.0,
      );

      // Return 15m unused excess from MO back into warehouse custody balance
      final move = await db.customerMaterialReceiptDao.returnExcessFromOrder(
        orderId: orderId,
        productId: fabricId,
        quantity: 15.0,
        notes: 'Unused end-of-roll fabric',
      );
      expect(move.movementType, 'return_excess');
      expect(move.quantity, 15.0);
      expect(move.referenceType, 'manufacturing_order');
      expect(move.referenceId, 'MO-EX-01');

      // Balance incremented: 20 + 15 = 35
      expect(
        await db.customerMaterialReceiptDao.getCustomerAvailableQuantity(
          customerId: 'cust-ex',
          productId: fabricId,
        ),
        35.0,
      );

      // D-03 automatic reconciliation trimmed ConsumptionRecord from 80 -> 65
      final recs = await db.consumptionRecordDao.getForOrder(orderId);
      expect(recs.single.actualQty, 65.0);

      final summary = await db.reconciliationDao.reconcile(orderId);
      final line = summary.custody[fabricId]!;
      expect(line.issued, 80.0);
      expect(line.consumed, 65.0);
      expect(line.returnedExcess, 15.0);
      expect(line.remaining, 0.0);
      expect(await db.reconciliationDao.checkCustodyEquations(orderId), isEmpty);

      // Returning more than remaining issued (80 - 15 = 65) throws StateError with zero writes
      await expectLater(
        () => db.customerMaterialReceiptDao.returnExcessFromOrder(
          orderId: orderId,
          productId: fabricId,
          quantity: 70.0,
        ),
        throwsStateError,
      );
      expect(
        await db.customerMaterialReceiptDao.getCustomerAvailableQuantity(
          customerId: 'cust-ex',
          productId: fabricId,
        ),
        35.0,
      );
    });

    test('returnCustodyToCustomer physically returns custody (-return_custody) without breaking order reconciliation and respects allocations', () async {
      await db.into(db.customers).insert(
            CustomersCompanion.insert(id: 'cust-ret', name: 'Custody Return Customer'),
          );
      final fabricId = await seedProduct('Denim Fabric', qty: 0);
      final jeansId = await seedProduct('Jeans', qty: 0);

      await db.customerMaterialReceiptDao.receiveCustomerMaterial(
        customerId: 'cust-ret',
        items: [ReceiptItemInput(productId: fabricId, quantityReceived: 100.0)],
      );

      final bomId = await db.bomDao.insertBomWithItems(
        bom: BillOfMaterialsCompanion(
          finishedProductId: Value(jeansId),
          name: const Value('Jeans BOM'),
        ),
        items: [
          BomItemsCompanion(
            rawMaterialProductId: Value(fabricId),
            quantityRequired: const Value(1.0),
          ),
        ],
      );
      final orderId = await db.manufacturingOrderDao.createOrder(
        ManufacturingOrdersCompanion(
          orderNumber: const Value('MO-RET-01'),
          bomId: Value(bomId),
          finishedProductId: Value(jeansId),
          plannedQuantity: const Value(60.0),
          orderType: const Value('for_others'),
          customerId: const Value('cust-ret'),
        ),
      );
      await db.manufacturingOrderDao.completeForOthersOrder(orderId: orderId);

      // Reserve 10 units on custody balance to verify allocation guard
      final bal = (await db.customerMaterialReceiptDao.getCustomerBalance(
        customerId: 'cust-ret',
        productId: fabricId,
      ))!;
      await (db.update(db.customerStockBalances)
            ..where((b) => b.id.equals(bal.id)))
          .write(const CustomerStockBalancesCompanion(quantityAllocated: Value(10.0)));

      // onHand = 40, allocated = 10 -> available = 30. Asking for 35 must fail.
      await expectLater(
        () => db.customerMaterialReceiptDao.returnCustodyToCustomer(
          customerId: 'cust-ret',
          productId: fabricId,
          quantity: 35.0,
        ),
        throwsStateError,
      );
      expect(
        await db.customerMaterialReceiptDao.getCustomerAvailableQuantity(
          customerId: 'cust-ret',
          productId: fabricId,
        ),
        40.0,
      );

      // Asking for 30 succeeds -> onHand drops 40 -> 10
      final retMove = await db.customerMaterialReceiptDao.returnCustodyToCustomer(
        customerId: 'cust-ret',
        productId: fabricId,
        quantity: 30.0,
      );
      expect(retMove.movementType, 'return_custody');
      expect(retMove.quantity, -30.0);
      expect(retMove.referenceType, 'customer_custody_return');

      expect(
        await db.customerMaterialReceiptDao.getCustomerAvailableQuantity(
          customerId: 'cust-ret',
          productId: fabricId,
        ),
        10.0,
      );

      // Order custody equation stays completely intact
      final summary = await db.reconciliationDao.reconcile(orderId);
      expect(summary.custody[fabricId]!.issued, 60.0);
      expect(summary.custody[fabricId]!.consumed, 60.0);
      expect(summary.custody[fabricId]!.returnedExcess, 0.0);
      expect(summary.custody[fabricId]!.remaining, 0.0);
      expect(await db.reconciliationDao.checkCustodyEquations(orderId), isEmpty);
    });
  });
}
