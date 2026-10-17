import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/dao/bom_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/customer_material_receipt_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/manufacturing_order_dao.dart';

/// FEAT-002 flow rules: a for-others order created from a customer receipt
/// carries the receipt's customer, a REAL recipe BOM (no placeholder), the
/// recipe's finished product, and pricing metadata.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (MethodCall methodCall) async => '.',
  );

  Future<(
    AppDatabase,
    ManufacturingOrderDao,
    BomDao,
    CustomerMaterialReceiptDao,
  )> setup() async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    return (
      db,
      db.manufacturingOrderDao,
      db.bomDao,
      db.customerMaterialReceiptDao,
    );
  }

  Future<void> seedCustomer(AppDatabase db,
      {required String id, required String name}) async {
    await db.into(db.customers).insert(
          CustomersCompanion.insert(id: id, name: name),
        );
  }

  Future<int> seedProduct(AppDatabase db,
      {required String name, int qty = 0}) async {
    return db.into(db.products).insert(
          ProductsCompanion.insert(name: name, quantity: qty, price: 100),
        );
  }

  Future<int> bomCount(AppDatabase db) async {
    return (await db.bomDao.getAllBoms()).length;
  }

  test('R1: createJobWorkOrder with bomId uses the real recipe, no placeholder',
      () async {
    final (db, moDao, bomDao, receiptDao) = await setup();
    await seedCustomer(db, id: 'cust-1', name: 'Test Customer');
    final blankId = await seedProduct(db, name: 'Blank', qty: 0);
    final printedId = await seedProduct(db, name: 'Printed', qty: 0);

    final receipt = await receiptDao.receiveCustomerMaterial(
      customerId: 'cust-1',
      items: [ReceiptItemInput(productId: blankId, quantityReceived: 100)],
    );

    final bomId = await bomDao.insertBomWithItems(
      bom: BillOfMaterialsCompanion(
        finishedProductId: Value(printedId),
        name: const Value('receipt recipe'),
      ),
      items: [
        BomItemsCompanion(
          rawMaterialProductId: Value(blankId),
          quantityRequired: const Value(1.0),
        ),
      ],
    );
    final bomsBefore = await bomCount(db);

    final orderId = await moDao.createJobWorkOrder(
      orderNumber: 'MO-RECEIPT-1',
      orderType: 'for_others',
      customerId: receipt.customerId,
      bomId: bomId,
      finishedProductId: printedId,
      plannedQuantity: 50,
      pricingMode: 'separate',
      scrapPolicy: 'customer_bears',
      pieceUnitValue: 5,
      serviceUnitPrice: 20,
    );

    final order = await moDao.getById(orderId);
    expect(order, isNotNull);
    // Real recipe kept…
    expect(order!.bomId, bomId);
    // …no placeholder BOM created…
    expect(await bomCount(db), bomsBefore);
    final bom = await bomDao.getBomById(order.bomId);
    expect(bom?.type, isNot('system_placeholder'));
    // …receipt customer + finished product + pricing persisted…
    expect(order.customerId, 'cust-1');
    expect(order.finishedProductId, printedId);
    expect(order.plannedQuantity, 50);
    expect(order.pricingMode, 'separate');
    expect(order.scrapPolicy, 'customer_bears');
    expect(order.pieceUnitValue, 5);
    expect(order.serviceUnitPrice, 20);
    // …and direct-input tracking stays null so completion uses the BOM path.
    expect(order.inputProductId, isNull);
    expect(order.inputQuantity, isNull);
  });

  test('R2: legacy call without bomId still creates a placeholder (compat)',
      () async {
    final (db, moDao, _, _) = await setup();
    await seedCustomer(db, id: 'cust-1', name: 'Test Customer');
    final rawId = await seedProduct(db, name: 'Raw Fabric', qty: 0);

    final orderId = await moDao.createJobWorkOrder(
      orderNumber: 'JW-COMPAT',
      orderType: 'for_others',
      customerId: 'cust-1',
      inputProductId: rawId,
      inputQuantity: 100,
    );

    final order = await moDao.getById(orderId);
    expect(order, isNotNull);
    final bom = await db.bomDao.getBomById(order!.bomId);
    expect(bom, isNotNull);
    expect(bom!.type, 'system_placeholder');
    expect(order.inputProductId, rawId);
    expect(order.inputQuantity, 100);
  });

  test('R3: receipt-context order completes from custody, factory untouched',
      () async {
    final (db, moDao, bomDao, receiptDao) = await setup();
    await seedCustomer(db, id: 'cust-1', name: 'Test Customer');
    final blankId = await seedProduct(db, name: 'Blank', qty: 0);
    final printedId = await seedProduct(db, name: 'Printed', qty: 0);

    final receipt = await receiptDao.receiveCustomerMaterial(
      customerId: 'cust-1',
      items: [ReceiptItemInput(productId: blankId, quantityReceived: 100)],
    );

    final bomId = await bomDao.insertBomWithItems(
      bom: BillOfMaterialsCompanion(
        finishedProductId: Value(printedId),
        name: const Value('receipt recipe 2'),
      ),
      items: [
        BomItemsCompanion(
          rawMaterialProductId: Value(blankId),
          quantityRequired: const Value(2.0),
        ),
      ],
    );

    final orderId = await moDao.createJobWorkOrder(
      orderNumber: 'MO-RECEIPT-2',
      orderType: 'for_others',
      customerId: receipt.customerId,
      bomId: bomId,
      finishedProductId: printedId,
      plannedQuantity: 30,
    );

    await moDao.completeForOthersOrder(orderId: orderId);

    // 30 × 2 = 60 consumed from custody…
    expect(
      await receiptDao.getCustomerAvailableQuantity(
          customerId: 'cust-1', productId: blankId),
      40.0,
    );
    // …factory stock of both products still 0.
    final blank =
        await (db.select(db.products)..where((p) => p.id.equals(blankId)))
            .getSingle();
    final printed =
        await (db.select(db.products)..where((p) => p.id.equals(printedId)))
            .getSingle();
    expect(blank.quantity, 0);
    expect(printed.quantity, 0);
  });
}
