import '../helpers/license_grant.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/dao/bom_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/customer_material_receipt_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/manufacturing_order_dao.dart';

/// BUG-004 regression: customer-owned lines must NEVER be validated against
/// or mutate factory Products.quantity — even when factory stock is 0.
void main() {
  // BUG-018: this suite exercises a licensed module directly, bypassing the
  // splash screen that normally loads the license before any module opens.
  grantLicensedModules();
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

  Future<int> seedOrder(
    ManufacturingOrderDao moDao, {
    required int bomId,
    required int finishedProductId,
    required double plannedQuantity,
    String orderType = 'for_others',
    String? customerId,
  }) {
    return moDao.createOrder(
      ManufacturingOrdersCompanion(
        bomId: Value(bomId),
        finishedProductId: Value(finishedProductId),
        plannedQuantity: Value(plannedQuantity),
        orderType: Value(orderType),
        customerId: Value(customerId),
      ),
    );
  }

  Future<int> factoryQty(AppDatabase db, int productId) async {
    final p = await (db.select(db.products)
          ..where((t) => t.id.equals(productId)))
        .getSingle();
    return p.quantity;
  }

  group('isCustomerOwnedBomLine — shared ownership rule', () {
    test('for_others defaults every line to customer-owned', () {
      expect(
        isCustomerOwnedBomLine(
            orderType: 'for_others', rawMaterialProductId: 7),
        isTrue,
      );
    });

    test('explicit set wins over the for_others default', () {
      expect(
        isCustomerOwnedBomLine(
          orderType: 'for_others',
          rawMaterialProductId: 7,
          customerOwnedProductIds: {9},
        ),
        isFalse,
      );
      expect(
        isCustomerOwnedBomLine(
          orderType: 'for_others',
          rawMaterialProductId: 9,
          customerOwnedProductIds: {9},
        ),
        isTrue,
      );
    });

    test('mixed uses the custody balance signal', () {
      expect(
        isCustomerOwnedBomLine(
          orderType: 'mixed',
          rawMaterialProductId: 7,
          hasCustodyBalance: true,
        ),
        isTrue,
      );
      expect(
        isCustomerOwnedBomLine(
          orderType: 'mixed',
          rawMaterialProductId: 7,
          hasCustodyBalance: false,
        ),
        isFalse,
      );
    });

    test('internal is never customer-owned', () {
      expect(
        isCustomerOwnedBomLine(
          orderType: 'internal',
          rawMaterialProductId: 7,
        ),
        isFalse,
      );
    });
  });

  test('E1: for_others completes with factory stock at 0; factory untouched',
      () async {
    final (db, moDao, bomDao, receiptDao) = await setup();
    await seedCustomer(db, id: 'cust-1', name: 'Test Customer');
    // Factory owns NOTHING of either product.
    final blankId = await seedProduct(db, name: 'Blank', qty: 0);
    final printedId = await seedProduct(db, name: 'Printed', qty: 0);

    await receiptDao.receiveCustomerMaterial(
      customerId: 'cust-1',
      items: [ReceiptItemInput(productId: blankId, quantityReceived: 300)],
    );

    final bomId = await bomDao.insertBomWithItems(
      bom: BillOfMaterialsCompanion(
        finishedProductId: Value(printedId),
        name: const Value('exemption bom'),
      ),
      items: [
        BomItemsCompanion(
          rawMaterialProductId: Value(blankId),
          quantityRequired: const Value(1.0),
        ),
      ],
    );

    final orderId = await seedOrder(
      moDao,
      bomId: bomId,
      finishedProductId: printedId,
      plannedQuantity: 200,
      customerId: 'cust-1',
    );

    await moDao.completeForOthersOrder(orderId: orderId);

    // Factory stock unchanged (still 0) for both input and finished goods.
    expect(await factoryQty(db, blankId), 0);
    expect(await factoryQty(db, printedId), 0);

    // Custody deducted: 300 - 200 = 100 on hand.
    expect(
      await receiptDao.getCustomerAvailableQuantity(
          customerId: 'cust-1', productId: blankId),
      100.0,
    );

    // No factory inventory movements for either product.
    final movements = await (db.select(db.inventoryMovements)
          ..where((m) => m.productId.isIn([blankId, printedId])))
        .get();
    expect(movements, isEmpty);
  });

  test('E2: mixed order consumes factory stock only for factory-owned lines',
      () async {
    final (db, moDao, bomDao, receiptDao) = await setup();
    await seedCustomer(db, id: 'cust-1', name: 'Test Customer');
    final custMatId = await seedProduct(db, name: 'Customer Fabric', qty: 0);
    final factoryMatId =
        await seedProduct(db, name: 'Factory Thread', qty: 50);
    final finishedId = await seedProduct(db, name: 'Finished', qty: 0);

    await receiptDao.receiveCustomerMaterial(
      customerId: 'cust-1',
      items: [ReceiptItemInput(productId: custMatId, quantityReceived: 100)],
    );

    final bomId = await bomDao.insertBomWithItems(
      bom: BillOfMaterialsCompanion(
        finishedProductId: Value(finishedId),
        name: const Value('mixed bom'),
      ),
      items: [
        BomItemsCompanion(
          rawMaterialProductId: Value(custMatId),
          quantityRequired: const Value(1.0),
        ),
        BomItemsCompanion(
          rawMaterialProductId: Value(factoryMatId),
          quantityRequired: const Value(1.0),
        ),
      ],
    );

    final orderId = await seedOrder(
      moDao,
      bomId: bomId,
      finishedProductId: finishedId,
      plannedQuantity: 10,
      orderType: 'mixed',
      customerId: 'cust-1',
    );

    final result = await moDao.completeForOthersOrder(orderId: orderId);
    expect(result.customerConsumptions.length, 1);
    expect(result.factoryConsumptions.length, 1);

    // Factory-owned line consumed from factory stock…
    expect(await factoryQty(db, factoryMatId), 40);
    // …customer line untouched in factory stock, deducted from custody…
    expect(await factoryQty(db, custMatId), 0);
    expect(
      await receiptDao.getCustomerAvailableQuantity(
          customerId: 'cust-1', productId: custMatId),
      90.0,
    );
    // …and finished output never increments factory stock.
    expect(await factoryQty(db, finishedId), 0);
  });

  test('E3: mixed factory shortage still aborts with zero writes', () async {
    final (db, moDao, bomDao, receiptDao) = await setup();
    await seedCustomer(db, id: 'cust-1', name: 'Test Customer');
    final custMatId = await seedProduct(db, name: 'Customer Fabric', qty: 0);
    final factoryMatId =
        await seedProduct(db, name: 'Factory Thread', qty: 2);

    await receiptDao.receiveCustomerMaterial(
      customerId: 'cust-1',
      items: [ReceiptItemInput(productId: custMatId, quantityReceived: 100)],
    );

    final bomId = await bomDao.insertBomWithItems(
      bom: BillOfMaterialsCompanion(
        finishedProductId: Value(custMatId),
        name: const Value('mixed short bom'),
      ),
      items: [
        BomItemsCompanion(
          rawMaterialProductId: Value(custMatId),
          quantityRequired: const Value(1.0),
        ),
        BomItemsCompanion(
          rawMaterialProductId: Value(factoryMatId),
          quantityRequired: const Value(1.0),
        ),
      ],
    );

    final orderId = await seedOrder(
      moDao,
      bomId: bomId,
      finishedProductId: custMatId,
      plannedQuantity: 10,
      orderType: 'mixed',
      customerId: 'cust-1',
    );

    expect(
      () => moDao.completeForOthersOrder(orderId: orderId),
      throwsA(isA<InsufficientStockException>()),
    );
    // Zero writes: custody and factory stock intact.
    expect(
      await receiptDao.getCustomerAvailableQuantity(
          customerId: 'cust-1', productId: custMatId),
      100.0,
    );
    expect(await factoryQty(db, factoryMatId), 2);
  });
}
