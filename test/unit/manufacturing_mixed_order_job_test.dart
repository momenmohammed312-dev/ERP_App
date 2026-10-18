import 'package:drift/drift.dart' show Value;

import 'package:drift/native.dart';

import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:pos_offline_desktop/core/database/app_database.dart';

import 'package:pos_offline_desktop/core/database/dao/bom_dao.dart';

import 'package:pos_offline_desktop/core/database/dao/customer_material_receipt_dao.dart';

import 'package:pos_offline_desktop/core/database/dao/manufacturing_order_dao.dart';

/// FEAT-004: the manufacturing-order dialog auto-escalates receipt-based

/// for-others orders to `mixed` when any BOM line is factory-supplied.

/// These tests lock the DAO layer behind that UI decision:

///  - M1: `mixed` is a valid persisted order type on create.

///  - M2: in `mixed`, custody-balance presence wins over factory stock

///        (shortage aborts atomically even though factory stock existed).

///  - M3: `mixed` with an all-custody recipe behaves exactly like

///        for_others: factory stock untouched.

///  - M4 (FEAT-007): a raw-material custody product is accepted as the

///        BOM finished output (with a warning) in the receipt-first flow.

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),

        (MethodCall methodCall) async => '.',
      );

  Future<
    (AppDatabase, ManufacturingOrderDao, BomDao, CustomerMaterialReceiptDao)
  >
  setup() async {
    final db = AppDatabase(NativeDatabase.memory());

    addTearDown(db.close);

    return (
      db,

      db.manufacturingOrderDao,

      db.bomDao,

      db.customerMaterialReceiptDao,
    );
  }

  Future<void> seedCustomer(
    AppDatabase db, {
    required String id,
    required String name,
  }) async {
    await db
        .into(db.customers)
        .insert(CustomersCompanion.insert(id: id, name: name));
  }

  Future<int> seedProduct(
    AppDatabase db, {
    required String name,
    int qty = 0,
  }) async {
    return db
        .into(db.products)
        .insert(
          ProductsCompanion.insert(name: name, quantity: qty, price: 100),
        );
  }

  Future<int> factoryQty(AppDatabase db, int productId) async {
    final p = await (db.select(
      db.products,
    )..where((t) => t.id.equals(productId))).getSingle();

    return p.quantity;
  }

  Future<double> custodyQty(
    CustomerMaterialReceiptDao receiptDao, {

    required String customerId,

    required int productId,
  }) {
    return receiptDao.getCustomerAvailableQuantity(
      customerId: customerId,

      productId: productId,
    );
  }

  test(
    'M1: createJobWorkOrder persists orderType=mixed with a real recipe',

    () async {
      final (db, moDao, bomDao, receiptDao) = await setup();

      await seedCustomer(db, id: 'cust-1', name: 'Test Customer');

      final blankId = await seedProduct(db, name: 'Blank', qty: 0);

      final printedId = await seedProduct(db, name: 'Printed', qty: 0);

      await receiptDao.receiveCustomerMaterial(
        customerId: 'cust-1',

        items: [ReceiptItemInput(productId: blankId, quantityReceived: 100)],
      );

      final bomId = await bomDao.insertBomWithItems(
        bom: BillOfMaterialsCompanion(
          finishedProductId: Value(printedId),

          name: const Value('mixed recipe'),
        ),

        items: [
          BomItemsCompanion(
            rawMaterialProductId: Value(blankId),

            quantityRequired: const Value(1.0),
          ),
        ],
      );

      // This mirrors the split-preview decision: partial custody + a factory

      // material line => the dialog saves the order as `mixed`.

      final orderId = await moDao.createJobWorkOrder(
        orderNumber: 'MO-MIXED-1',

        orderType: 'mixed',

        customerId: 'cust-1',

        bomId: bomId,

        finishedProductId: printedId,

        plannedQuantity: 20,

        pricingMode: 'separate',

        scrapPolicy: 'customer_bears',

        pieceUnitValue: 2,

        serviceUnitPrice: 15,
      );

      final order = await moDao.getById(orderId);

      expect(order, isNotNull);

      expect(order!.orderType, 'mixed');

      expect(order.customerId, 'cust-1');

      expect(order.bomId, bomId);

      expect(order.plannedQuantity, 20);
    },
  );

  test(
    'M2: custody-balance presence beats factory stock; shortage aborts clean',
    () async {
      final (db, moDao, bomDao, receiptDao) = await setup();
      await seedCustomer(db, id: 'cust-1', name: 'Test Customer');
      final fabricId = await seedProduct(db, name: 'Customer Fabric', qty: 0);
      final threadId = await seedProduct(db, name: 'Thread', qty: 50);
      await receiptDao.receiveCustomerMaterial(
        customerId: 'cust-1',
        items: [
          ReceiptItemInput(productId: fabricId, quantityReceived: 100),
          ReceiptItemInput(productId: threadId, quantityReceived: 5),
        ],
      );
      final finishedId = await seedProduct(db, name: 'Printed', qty: 0);
      final bomId = await bomDao.insertBomWithItems(
        bom: BillOfMaterialsCompanion(
          finishedProductId: Value(finishedId),
          name: const Value('m2 recipe'),
        ),
        items: [
          BomItemsCompanion(
            rawMaterialProductId: Value(fabricId),
            quantityRequired: const Value(1.0),
          ),
          BomItemsCompanion(
            rawMaterialProductId: Value(threadId),
            quantityRequired: const Value(1.0),
          ),
        ],
      );
      final orderId = await moDao.createOrder(
        ManufacturingOrdersCompanion(
          bomId: Value(bomId),
          finishedProductId: Value(finishedId),
          plannedQuantity: const Value(10.0),
          orderType: const Value('mixed'),
          customerId: const Value('cust-1'),
        ),
      );
      // Thread has a custody balance (5) AND factory stock (50). The shared
      // ownership rule must classify it as customer-owned and fail hard:
      // silently eating the customer's 5 or the factory's 50 is unacceptable.
      expect(
        () => moDao.completeForOthersOrder(orderId: orderId),
        throwsA(isA<InsufficientStockException>()),
      );
      // Zero writes everywhere.
      expect(await factoryQty(db, fabricId), 0);
      expect(await factoryQty(db, threadId), 50);
      expect(await factoryQty(db, finishedId), 0);
      expect(
        await custodyQty(receiptDao, customerId: 'cust-1', productId: fabricId),
        100.0,
      );
      expect(
        await custodyQty(receiptDao, customerId: 'cust-1', productId: threadId),
        5.0,
      );
    },
  );
  test(
    'M3: mixed with an all-custody recipe leaves factory stock untouched',
    () async {
      final (db, moDao, bomDao, receiptDao) = await setup();
      await seedCustomer(db, id: 'cust-1', name: 'Test Customer');
      final fabricId = await seedProduct(db, name: 'Customer Fabric', qty: 0);
      final labelsId = await seedProduct(db, name: 'Customer Labels', qty: 0);
      await receiptDao.receiveCustomerMaterial(
        customerId: 'cust-1',
        items: [
          ReceiptItemInput(productId: fabricId, quantityReceived: 100),
          ReceiptItemInput(productId: labelsId, quantityReceived: 30),
        ],
      );
      final finishedId = await seedProduct(db, name: 'Printed', qty: 0);
      final bomId = await bomDao.insertBomWithItems(
        bom: BillOfMaterialsCompanion(
          finishedProductId: Value(finishedId),
          name: const Value('m3 recipe'),
        ),
        items: [
          BomItemsCompanion(
            rawMaterialProductId: Value(fabricId),
            quantityRequired: const Value(1.0),
          ),
          BomItemsCompanion(
            rawMaterialProductId: Value(labelsId),
            quantityRequired: const Value(1.0),
          ),
        ],
      );
      final orderId = await moDao.createOrder(
        ManufacturingOrdersCompanion(
          bomId: Value(bomId),
          finishedProductId: Value(finishedId),
          plannedQuantity: const Value(10.0),
          orderType: const Value('mixed'),
          customerId: const Value('cust-1'),
        ),
      );
      await moDao.completeForOthersOrder(orderId: orderId);
      // Factory parity with for_others: nothing in the factory moved.
      expect(await factoryQty(db, fabricId), 0);
      expect(await factoryQty(db, labelsId), 0);
      expect(await factoryQty(db, finishedId), 0);
      // Custody deducted per line.
      expect(
        await custodyQty(receiptDao, customerId: 'cust-1', productId: fabricId),
        90.0,
      );
      expect(
        await custodyQty(receiptDao, customerId: 'cust-1', productId: labelsId),
        20.0,
      );
    },
  );

  test(
    'M4: FEAT-007 raw-material custody product is an accepted BOM output',
    () async {
      final (db, moDao, bomDao, receiptDao) = await setup();
      await seedCustomer(db, id: 'cust-1', name: 'Cust Four');

      // The on-the-fly custody product created by the receipt dialog is a
      // raw_material — the printing flow expects it to also be the output.
      final fabricId = await db
          .into(db.products)
          .insert(
            ProductsCompanion.insert(
              name: 'Fabric Custody',
              quantity: 0,
              price: 100,
              productType: const Value('raw_material'),
            ),
          );

      final (:bomId, :warnings) = await bomDao.insertBomWithItemsChecked(
        bom: BillOfMaterialsCompanion(
          finishedProductId: Value(fabricId),
          name: const Value('fabric in -> fabric out'),
        ),
        items: [
          BomItemsCompanion(
            rawMaterialProductId: Value(fabricId),
            quantityRequired: const Value(1.0),
          ),
        ],
      );
      expect(bomId, greaterThan(0));
      expect(warnings, isNotEmpty);

      await receiptDao.receiveCustomerMaterial(
        customerId: 'cust-1',
        items: [ReceiptItemInput(productId: fabricId, quantityReceived: 25)],
      );
      final orderId = await moDao.createJobWorkOrder(
        orderNumber: 'MO-M4',
        orderType: 'mixed',
        customerId: 'cust-1',
        bomId: bomId,
        finishedProductId: fabricId,
        plannedQuantity: 25,
        pricingMode: 'separate',
        scrapPolicy: 'customer_bears',
        pieceUnitValue: 2,
        serviceUnitPrice: 15,
      );
      final order = await moDao.getById(orderId);
      expect(order, isNotNull);
      expect(order!.orderType, 'mixed');
      expect(order.finishedProductId, fabricId);
    },
  );
}
