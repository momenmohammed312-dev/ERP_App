import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/dao/customer_material_receipt_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/manufacturing_delivery_dao.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_cost_components_table.dart';

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

  test('Phase 3 Costing (§5, D-11) excludes customer material value, sums all 5 cost drivers, and freezes snapshot', () async {
    await db.into(db.customers).insert(
          CustomersCompanion.insert(id: 'cust-c3', name: 'Costing Customer'),
        );
    final custFabric = await db.into(db.products).insert(
          ProductsCompanion.insert(
            name: 'Customer Silk',
            price: 500,
            costPrice: const Value(400),
            quantity: 0,
          ),
        );
    final facThread = await db.into(db.products).insert(
          ProductsCompanion.insert(
            name: 'Factory Thread',
            price: 30,
            costPrice: const Value(20),
            quantity: 200,
          ),
        );
    final finDress = await db.into(db.products).insert(
          ProductsCompanion.insert(name: 'Finished Dress', price: 300, quantity: 0),
        );

    await db.customerMaterialReceiptDao.receiveCustomerMaterial(
      customerId: 'cust-c3',
      items: [ReceiptItemInput(productId: custFabric, quantityReceived: 100)],
    );

    final bomId = await db.bomDao.insertBomWithItems(
      bom: BillOfMaterialsCompanion(
        finishedProductId: Value(finDress),
        name: const Value('Dress BOM'),
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

    final orderId = await db.manufacturingOrderDao.createOrder(
      ManufacturingOrdersCompanion(
        orderNumber: const Value('MO-COST-01'),
        bomId: Value(bomId),
        finishedProductId: Value(finDress),
        plannedQuantity: const Value(10.0),
        orderType: const Value('mixed'),
        customerId: const Value('cust-c3'),
        pricingMode: const Value('inclusive'),
        serviceUnitPrice: const Value(100.0),
      ),
    );

    await db.manufacturingOrderDao.completeForOthersOrder(
      orderId: orderId,
      customerOwnedProductIds: {custFabric},
    );

    // Stage labor (4h * 50 = 200) + machine (3h * 40 = 120)
    final stageId = await db.manufacturingStageDao.addStage(
      orderId: orderId,
      stageName: 'Tailoring',
      inputQuantity: 10.0,
    );
    await db.manufacturingStageDao.updateStage(
      stageId: stageId,
      stageName: 'Tailoring',
      laborHours: 4.0,
      laborRate: 50.0,
      machineHours: 3.0,
      machineRate: 40.0,
    );

    // External op cost = 150
    await db.externalOperationDao.insertExternalOperationRecord(
      manufacturingOrderId: orderId,
      operationId: stageId,
      vendor: 'Pleating Vendor',
      sentQty: 10.0,
      receivedQty: 10.0,
      cost: 150.0,
    );

    // Other cost component (fixed = 80)
    await db.manufacturingCostComponentDao.insertComponent(
      ManufacturingCostComponentsCompanion.insert(
        manufacturingOrderId: orderId,
        name: 'Packaging',
        costType: ManufacturingCostType.fixed,
        value: 80.0,
        computedAmount: const Value(80.0),
      ),
    );

    // Deliver all 10 -> revenue = 10 * 100 = 1000
    await db.manufacturingDeliveryDao.createDelivery(
      orderId: orderId,
      items: [DeliveryItemInput(productId: finDress, quantity: 10)],
    );

    final breakdown = await db.manufacturingCostingDao.computeOrderCost(orderId);
    // Factory thread: 10 * 20 = 200; Customer silk = 0.0!
    expect(breakdown.materialCost, 200.0);
    expect(breakdown.laborCost, 200.0);
    expect(breakdown.machineCost, 120.0);
    expect(breakdown.externalCost, 150.0);
    expect(breakdown.otherCost, 80.0);
    expect(breakdown.totalActualCost, 750.0);
    expect(breakdown.deliveredRevenue, 1000.0);
    expect(breakdown.actualMargin, 250.0);

    final snap = await db.manufacturingCostingDao.freezeCostSnapshot(orderId);
    expect(snap.isFrozen, isTrue);
    expect(snap.totalActualCost, 750.0);
    expect(snap.actualMargin, 250.0);
  });

  test('Phase 3 ExtraMaterialApproval (D-04/D-05/D-08): inclusive mode bills ONLY approved extras at costPrice snapshot + freezes snapshot on invoice', () async {
    await db.into(db.customers).insert(
          CustomersCompanion.insert(id: 'cust-ex-bill', name: 'Billing Customer'),
        );
    final custFabric = await db.into(db.products).insert(
          ProductsCompanion.insert(name: 'Cust Fabric', price: 100, quantity: 0),
        );
    // Extra factory zipper: selling price = 15, actual costPrice = 10 (D-08!)
    final extraZipper = await db.into(db.products).insert(
          ProductsCompanion.insert(
            name: 'Extra Heavy Zipper',
            price: 15.0,
            costPrice: const Value(10.0),
            quantity: 50,
          ),
        );
    final extraButtons = await db.into(db.products).insert(
          ProductsCompanion.insert(
            name: 'Unapproved Buttons',
            price: 20.0,
            costPrice: const Value(12.0),
            quantity: 50,
          ),
        );
    final finCoat = await db.into(db.products).insert(
          ProductsCompanion.insert(name: 'Finished Coat', price: 200, quantity: 0),
        );

    await db.customerMaterialReceiptDao.receiveCustomerMaterial(
      customerId: 'cust-ex-bill',
      items: [ReceiptItemInput(productId: custFabric, quantityReceived: 50)],
    );

    final bomId = await db.bomDao.insertBomWithItems(
      bom: BillOfMaterialsCompanion(
        finishedProductId: Value(finCoat),
        name: const Value('Coat BOM'),
      ),
      items: [
        BomItemsCompanion(
          rawMaterialProductId: Value(custFabric),
          quantityRequired: const Value(1.0),
        ),
      ],
    );

    // Inclusive order: 10 units * 50 service = 500
    final orderId = await db.manufacturingOrderDao.createOrder(
      ManufacturingOrdersCompanion(
        orderNumber: const Value('MO-EX-BILL'),
        bomId: Value(bomId),
        finishedProductId: Value(finCoat),
        plannedQuantity: const Value(10.0),
        orderType: const Value('for_others'),
        customerId: const Value('cust-ex-bill'),
        pricingMode: const Value('inclusive'),
        serviceUnitPrice: const Value(50.0),
      ),
    );

    await db.manufacturingOrderDao.completeForOthersOrder(orderId: orderId);
    await db.manufacturingDeliveryDao.createDelivery(
      orderId: orderId,
      items: [DeliveryItemInput(productId: finCoat, quantity: 10)],
    );

    // Request 1: Extra Zipper qty 5 -> default margin 0.0 => 5 * costPrice(10.0) = 50.0 -> APPROVED
    final reqZipper = await db.manufacturingCostingDao.requestExtraMaterial(
      orderId: orderId,
      productId: extraZipper,
      quantity: 5.0,
      requestedBy: 'Supervisor Omar',
    );
    expect(reqZipper.unitCostSnapshot, 10.0);
    expect(reqZipper.marginPercent, 0.0);
    expect(reqZipper.approvedAmount, 50.0);
    await db.manufacturingCostingDao.approveExtraMaterial(
      approvalId: reqZipper.id,
      approvedBy: 'Customer Rep',
      authorizationRef: 'AUTH-WA-441',
    );

    // Request 2: Extra Buttons -> stays PENDING (must NOT be billed!)
    await db.manufacturingCostingDao.requestExtraMaterial(
      orderId: orderId,
      productId: extraButtons,
      quantity: 10.0,
      requestedBy: 'Supervisor Omar',
    );

    // Request 3: Rejected extra -> must NOT be billed!
    final reqRej = await db.manufacturingCostingDao.requestExtraMaterial(
      orderId: orderId,
      productId: extraButtons,
      quantity: 4.0,
      requestedBy: 'Supervisor Omar',
    );
    await db.manufacturingCostingDao.rejectExtraMaterial(
      approvalId: reqRej.id,
      notes: 'Customer declined',
    );

    // Invoice = 500 (service) + 50 (approved zipper) = 550
    final inv = await db.manufacturingDeliveryDao.generateServiceInvoice(orderId);
    expect(inv.totalAmount, 550.0);

    final items = await (db.select(db.invoiceItems)
          ..where((i) => i.invoiceId.equals(inv.id)))
        .get();
    expect(items.length, 2);
    final serviceLine = items.firstWhere((i) => i.productId == finCoat);
    expect(serviceLine.quantity, 10);
    expect(serviceLine.price, 50.0);
    final extraLine = items.firstWhere((i) => i.productId == extraZipper);
    expect(extraLine.quantity, 5);
    expect(extraLine.price, 10.0);

    // Snapshot was auto-frozen on invoicing
    final snap = await db.manufacturingCostingDao.getLatestSnapshot(orderId);
    expect(snap, isNotNull);
    expect(snap!.extraMaterialsRevenue, 50.0);
    expect(snap.deliveredRevenue, 500.0);
  });
}
