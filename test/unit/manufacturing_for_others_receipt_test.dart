import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/dao/customer_material_receipt_dao.dart';
import 'package:drift/native.dart';

/// Test Phase B1: Customer Material Receipts & Custody Balance.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (MethodCall methodCall) async => '.',
  );

  Future<(CustomerMaterialReceiptDao, AppDatabase)> setup() async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    return (db.customerMaterialReceiptDao, db);
  }

  Future<void> seedCustomer(AppDatabase db, {required String id, required String name}) async {
    await db.into(db.customers).insert(
      CustomersCompanion.insert(
        id: id,
        name: name,
      ),
    );
  }

  Future<int> seedProduct(AppDatabase db, {required String name, int qty = 0, double price = 100}) {
    return db.into(db.products).insert(
      ProductsCompanion.insert(
        name: name,
        quantity: qty,
        price: price,
      ),
    );
  }

  test('CMR-1: customer material receipt creates header and line items with generated sequence', () async {
    final (dao, db) = await setup();
    await seedCustomer(db, id: 'cust-1', name: 'Al-Madar Textiles');
    final productId = await seedProduct(db, name: 'Blank T-Shirt', qty: 0);

    final receipt = await dao.receiveCustomerMaterial(
      customerId: 'cust-1',
      items: [
        ReceiptItemInput(
          productId: productId,
          quantityReceived: 300,
          quantityDefectiveAtReceipt: 0,
          color: 'White',
          size: 'L',
        ),
      ],
      receivedBy: 'Inspector A',
      notes: 'Job #123 Delivery',
    );

    final year = DateTime.now().year;
    expect(receipt.receiptNumber, 'CMR-$year-0001');
    expect(receipt.customerId, 'cust-1');
    expect(receipt.status, 'received');

    final items = await dao.getItemsForReceipt(receipt.id);
    expect(items.length, 1);
    expect(items.first.productId, productId);
    expect(items.first.quantityReceived, 300.0);
    expect(items.first.quantityDefectiveAtReceipt, 0.0);
    expect(items.first.quantityAccepted, 300.0);
    expect(items.first.color, 'White');
    expect(items.first.size, 'L');
  });

  test('CMR-2: receipt inspects defective material and returns it immediately at receipt', () async {
    final (dao, db) = await setup();
    await seedCustomer(db, id: 'cust-1', name: 'Al-Madar Textiles');
    final productId = await seedProduct(db, name: 'Blank T-Shirt', qty: 0);

    final receipt = await dao.receiveCustomerMaterial(
      customerId: 'cust-1',
      items: [
        ReceiptItemInput(
          productId: productId,
          quantityReceived: 310,
          quantityDefectiveAtReceipt: 10,
          color: 'White',
          rejectionReason: 'Stained fabric',
        ),
      ],
    );

    // Defective pieces (10) are returned immediately and never enter custody balance
    final balance = await dao.getCustomerAvailableQuantity(
      customerId: 'cust-1',
      productId: productId,
      color: 'White',
    );
    expect(balance, 300.0); // 310 received - 10 defective = 300 accepted

    // Verify movements ledger recorded both 'return_defect' (-10) and 'receipt' (+300)
    final movements = await (db.select(db.customerStockMovements)
          ..where((m) => m.referenceId.equals(receipt.receiptNumber)))
        .get();

    expect(movements.length, 2);
    final defectMove = movements.firstWhere((m) => m.movementType == 'return_defect');
    expect(defectMove.quantity, -10.0);
    expect(defectMove.notes, 'Stained fabric');

    final receiptMove = movements.firstWhere((m) => m.movementType == 'receipt');
    expect(receiptMove.quantity, 300.0);
  });

  test('CMR-3: accepted material increments customer_stock_balances without touching products.quantity', () async {
    final (dao, db) = await setup();
    await seedCustomer(db, id: 'cust-1', name: 'Al-Madar Textiles');
    final productId = await seedProduct(db, name: 'Blank T-Shirt', qty: 50); // Factory owns 50

    await dao.receiveCustomerMaterial(
      customerId: 'cust-1',
      items: [
        ReceiptItemInput(
          productId: productId,
          quantityReceived: 200,
          quantityDefectiveAtReceipt: 0,
        ),
      ],
    );

    // Factory products.quantity is strictly untouched
    final product = await (db.select(db.products)..where((p) => p.id.equals(productId))).getSingle();
    expect(product.quantity, 50, reason: 'Factory asset stock must not be altered by customer custody receipt');

    // Factory inventory_movements is completely untouched
    final invMovements = await db.select(db.inventoryMovements).get();
    expect(invMovements.isEmpty, isTrue, reason: 'inventory_movements must not record customer custody movements');

    // Customer balance is updated
    final custBalance = await dao.getCustomerAvailableQuantity(
      customerId: 'cust-1',
      productId: productId,
    );
    expect(custBalance, 200.0);
  });

  test('CMR-4: receipt requires valid text customerId existing in customers table', () async {
    final (dao, db) = await setup();
    final productId = await seedProduct(db, name: 'Blank T-Shirt');

    // Attempt receipt with unknown customer
    expect(
      () => dao.receiveCustomerMaterial(
        customerId: 'unknown-uuid-999',
        items: [
          ReceiptItemInput(
            productId: productId,
            quantityReceived: 100,
          ),
        ],
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('CMR-5: multiple receipts for the same customer accumulate rolling balance', () async {
    final (dao, db) = await setup();
    await seedCustomer(db, id: 'cust-1', name: 'Al-Madar Textiles');
    final productId = await seedProduct(db, name: 'Blank T-Shirt');

    // Receipt 1: 150 pieces
    await dao.receiveCustomerMaterial(
      customerId: 'cust-1',
      items: [
        ReceiptItemInput(
          productId: productId,
          quantityReceived: 150,
          color: 'Black',
        ),
      ],
    );

    // Receipt 2: 250 pieces (same customer & color)
    await dao.receiveCustomerMaterial(
      customerId: 'cust-1',
      items: [
        ReceiptItemInput(
          productId: productId,
          quantityReceived: 250,
          color: 'Black',
        ),
      ],
    );

    final balance = await dao.getCustomerAvailableQuantity(
      customerId: 'cust-1',
      productId: productId,
      color: 'Black',
    );
    expect(balance, 400.0, reason: 'Customer custody balance rolls across receipts');
  });

  test('CMR-6: atomic rollback on failed receipt (defective > received or invalid product) leaves zero writes', () async {
    final (dao, db) = await setup();
    await seedCustomer(db, id: 'cust-1', name: 'Al-Madar Textiles');
    final productId = await seedProduct(db, name: 'Blank T-Shirt');

    // Defective exceeds received
    expect(
      () => dao.receiveCustomerMaterial(
        customerId: 'cust-1',
        items: [
          ReceiptItemInput(
            productId: productId,
            quantityReceived: 100,
            quantityDefectiveAtReceipt: 120, // Invalid!
          ),
        ],
      ),
      throwsA(isA<ArgumentError>()),
    );

    // Assert zero writes across all receipt and custody tables
    final receipts = await db.select(db.customerMaterialReceipts).get();
    expect(receipts.isEmpty, isTrue);

    final receiptItems = await db.select(db.customerMaterialReceiptItems).get();
    expect(receiptItems.isEmpty, isTrue);

    final balances = await db.select(db.customerStockBalances).get();
    expect(balances.isEmpty, isTrue);

    final movements = await db.select(db.customerStockMovements).get();
    expect(movements.isEmpty, isTrue);
  });
}
