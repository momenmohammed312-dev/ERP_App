import '../helpers/license_grant.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/dao/bom_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/customer_material_receipt_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/manufacturing_order_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/manufacturing_scrap_dao.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_orders_table.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_scrap_table.dart';

/// Test Phase B1: Manufacturing Order For-Others Completion & Scrap Policies.
void main() {
  // BUG-017: this suite exercises a licensed module directly, bypassing the
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
    ManufacturingScrapDao,
    BomDao,
    CustomerMaterialReceiptDao,
  )> setup() async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    return (
      db,
      db.manufacturingOrderDao,
      db.manufacturingScrapDao,
      db.bomDao,
      db.customerMaterialReceiptDao,
    );
  }

  Future<void> seedCustomer(AppDatabase db, {required String id, required String name}) async {
    await db.into(db.customers).insert(
      CustomersCompanion.insert(
        id: id,
        name: name,
      ),
    );
  }

  Future<int> seedProduct(AppDatabase db, {required String name, int qty = 0, double price = 100, double? costPrice}) {
    return db.into(db.products).insert(
      ProductsCompanion.insert(
        name: name,
        quantity: qty,
        price: price,
        costPrice: Value(costPrice ?? price),
      ),
    );
  }

  Future<int> seedBom(
    BomDao bomDao, {
    required int finishedProductId,
    double yieldQuantity = 1.0,
    double wastePercentage = 0.0,
    required List<({int productId, double quantity, double? wasteOverride})> lines,
  }) {
    return bomDao.insertBomWithItems(
      bom: BillOfMaterialsCompanion(
        finishedProductId: Value(finishedProductId),
        name: const Value('بوم اختبار للغير'),
        yieldQuantity: Value(yieldQuantity),
        wastePercentage: Value(wastePercentage),
      ),
      items: lines
          .map(
            (l) => BomItemsCompanion(
              rawMaterialProductId: Value(l.productId),
              quantityRequired: Value(l.quantity),
              wastePercentageOverride: Value(l.wasteOverride),
            ),
          )
          .toList(),
    );
  }

  Future<int> seedOrder(
    ManufacturingOrderDao moDao, {
    required int bomId,
    required int finishedProductId,
    required double plannedQuantity,
    String orderType = 'for_others',
    String? customerId,
    String scrapPolicy = 'customer_bears',
    double pieceUnitValue = 0.0,
  }) {
    return moDao.createOrder(
      ManufacturingOrdersCompanion(
        bomId: Value(bomId),
        finishedProductId: Value(finishedProductId),
        plannedQuantity: Value(plannedQuantity),
        orderType: Value(orderType),
        customerId: Value(customerId),
        scrapPolicy: Value(scrapPolicy),
        pieceUnitValue: Value(pieceUnitValue),
      ),
    );
  }

  test('MOC-1: completeForOthersOrder fails when customer has insufficient custody balance', () async {
    final (db, moDao, _, bomDao, _) = await setup();
    await seedCustomer(db, id: 'cust-1', name: 'Al-Madar Textiles');
    final blankShirtId = await seedProduct(db, name: 'Blank T-Shirt', qty: 0);
    final printedShirtId = await seedProduct(db, name: 'Printed T-Shirt', qty: 0);

    // BOM: 1 Blank Shirt -> 1 Printed Shirt
    final bomId = await seedBom(
      bomDao,
      finishedProductId: printedShirtId,
      lines: [(productId: blankShirtId, quantity: 1.0, wasteOverride: null)],
    );

    // Order for 300 pieces for customer, but customer has 0 custody balance
    final orderId = await seedOrder(
      moDao,
      bomId: bomId,
      finishedProductId: printedShirtId,
      plannedQuantity: 300.0,
      customerId: 'cust-1',
    );

    expect(
      () => moDao.completeForOthersOrder(orderId: orderId),
      throwsA(isA<InsufficientStockException>()),
    );
  });

  test('MOC-2: completeForOthersOrder deducts customer custody stock and records customer_stock_movements', () async {
    final (db, moDao, _, bomDao, receiptDao) = await setup();
    await seedCustomer(db, id: 'cust-1', name: 'Al-Madar Textiles');
    final blankShirtId = await seedProduct(db, name: 'Blank T-Shirt', qty: 0);
    final printedShirtId = await seedProduct(db, name: 'Printed T-Shirt', qty: 0);

    // Customer delivers 300 blank shirts
    await receiptDao.receiveCustomerMaterial(
      customerId: 'cust-1',
      items: [
        ReceiptItemInput(
          productId: blankShirtId,
          quantityReceived: 300.0,
        ),
      ],
    );

    final bomId = await seedBom(
      bomDao,
      finishedProductId: printedShirtId,
      lines: [(productId: blankShirtId, quantity: 1.0, wasteOverride: null)],
    );

    final orderId = await seedOrder(
      moDao,
      bomId: bomId,
      finishedProductId: printedShirtId,
      plannedQuantity: 200.0,
      customerId: 'cust-1',
    );

    final result = await moDao.completeForOthersOrder(orderId: orderId);
    expect(result.producedQuantity, 200.0);

    // Customer balance: 300 - 200 = 100
    final balance = await receiptDao.getCustomerAvailableQuantity(
      customerId: 'cust-1',
      productId: blankShirtId,
    );
    expect(balance, 100.0);

    // Custody movements ledger recorded 'issued_to_order'
    final movements = await (db.select(db.customerStockMovements)
          ..where((m) => m.movementType.equals('issued_to_order')))
        .get();
    expect(movements.length, 1);
    expect(movements.first.quantity, -200.0);
    expect(movements.first.customerId, 'cust-1');
  });

  test('MOC-3: completeForOthersOrder does not increment factory finished product stock', () async {
    final (db, moDao, _, bomDao, receiptDao) = await setup();
    await seedCustomer(db, id: 'cust-1', name: 'Al-Madar Textiles');
    final blankShirtId = await seedProduct(db, name: 'Blank T-Shirt', qty: 0);
    final printedShirtId = await seedProduct(db, name: 'Printed T-Shirt', qty: 10); // Factory owns 10

    await receiptDao.receiveCustomerMaterial(
      customerId: 'cust-1',
      items: [
        ReceiptItemInput(productId: blankShirtId, quantityReceived: 100.0),
      ],
    );

    final bomId = await seedBom(
      bomDao,
      finishedProductId: printedShirtId,
      lines: [(productId: blankShirtId, quantity: 1.0, wasteOverride: null)],
    );

    final orderId = await seedOrder(
      moDao,
      bomId: bomId,
      finishedProductId: printedShirtId,
      plannedQuantity: 100.0,
      customerId: 'cust-1',
    );

    await moDao.completeForOthersOrder(orderId: orderId);

    // Factory finished product stock remains strictly 10 (not 10 + 100)
    final product = await (db.select(db.products)..where((p) => p.id.equals(printedShirtId))).getSingle();
    expect(product.quantity, 10, reason: 'Factory stock must NEVER increment on for_others order completion');

    // No factory output movement in inventory_movements
    final outputMovements = await (db.select(db.inventoryMovements)
          ..where((m) => m.movementType.equals('manufacturing_output')))
        .get();
    expect(outputMovements.isEmpty, isTrue);
  });

  test('MOC-4: mixed order consumes customer blank piece and factory ink inventory atomically', () async {
    final (db, moDao, _, bomDao, receiptDao) = await setup();
    await seedCustomer(db, id: 'cust-1', name: 'Al-Madar Textiles');
    final blankShirtId = await seedProduct(db, name: 'Blank T-Shirt', qty: 0);
    final inkId = await seedProduct(db, name: 'Screen Ink Cyan', qty: 50, price: 20); // Factory ink
    final printedShirtId = await seedProduct(db, name: 'Printed T-Shirt', qty: 0);

    // Customer provides 100 shirts
    await receiptDao.receiveCustomerMaterial(
      customerId: 'cust-1',
      items: [
        ReceiptItemInput(productId: blankShirtId, quantityReceived: 100.0),
      ],
    );

    // BOM: 1 blank shirt (customer) + 1 unit ink (factory) -> 1 printed shirt
    final bomId = await seedBom(
      bomDao,
      finishedProductId: printedShirtId,
      lines: [
        (productId: blankShirtId, quantity: 1.0, wasteOverride: null),
        (productId: inkId, quantity: 1.0, wasteOverride: null),
      ],
    );

    final orderId = await seedOrder(
      moDao,
      bomId: bomId,
      finishedProductId: printedShirtId,
      plannedQuantity: 40.0,
      orderType: 'mixed',
      customerId: 'cust-1',
    );

    final result = await moDao.completeForOthersOrder(
      orderId: orderId,
      customerOwnedProductIds: {blankShirtId},
    );

    expect(result.producedQuantity, 40.0);

    // Customer balance: 100 - 40 = 60
    final custBal = await receiptDao.getCustomerAvailableQuantity(
      customerId: 'cust-1',
      productId: blankShirtId,
    );
    expect(custBal, 60.0);

    // Factory ink: 50 - 40 = 10
    final inkProduct = await (db.select(db.products)..where((p) => p.id.equals(inkId))).getSingle();
    expect(inkProduct.quantity, 10);

    // Factory inventory movement recorded consumption of ink
    final inkMovements = await (db.select(db.inventoryMovements)
          ..where((m) => m.productId.equals(inkId) & m.movementType.equals('manufacturing_consumption')))
        .get();
    expect(inkMovements.length, 1);
    expect(inkMovements.first.quantity, -40);
  });

  test('MSP-1: scrap policy customer_bears does not credit customer on service invoice', () async {
    final (db, moDao, scrapDao, bomDao, receiptDao) = await setup();
    await seedCustomer(db, id: 'cust-1', name: 'Al-Madar Textiles');
    final blankShirtId = await seedProduct(db, name: 'Blank T-Shirt', qty: 0);
    final printedShirtId = await seedProduct(db, name: 'Printed T-Shirt', qty: 0);

    await receiptDao.receiveCustomerMaterial(
      customerId: 'cust-1',
      items: [ReceiptItemInput(productId: blankShirtId, quantityReceived: 100.0)],
    );

    final bomId = await seedBom(
      bomDao,
      finishedProductId: printedShirtId,
      lines: [(productId: blankShirtId, quantity: 1.0, wasteOverride: null)],
    );

    final orderId = await seedOrder(
      moDao,
      bomId: bomId,
      finishedProductId: printedShirtId,
      plannedQuantity: 100.0,
      customerId: 'cust-1',
      scrapPolicy: 'customer_bears',
      pieceUnitValue: 80.0,
    );

    await moDao.completeForOthersOrder(orderId: orderId);

    final scrap = await scrapDao.recordOrderScrapWithPolicy(
      orderId: orderId,
      productId: blankShirtId,
      quantity: 5.0,
      reason: ManufacturingScrapReason.defective,
      responsibleParty: 'Customer defect in fabric weave',
      faultParty: 'customer',
    );

    expect(scrap.faultParty, 'customer');
    expect(scrap.compensationAction, 'none');
    expect(scrap.compensationAmount, 0.0);
  });

  test('MSP-2: scrap policy factory_pays_piece_value calculates compensation_amount when fault is factory', () async {
    final (db, moDao, scrapDao, bomDao, receiptDao) = await setup();
    await seedCustomer(db, id: 'cust-1', name: 'Al-Madar Textiles');
    final blankShirtId = await seedProduct(db, name: 'Blank T-Shirt', qty: 0);
    final printedShirtId = await seedProduct(db, name: 'Printed T-Shirt', qty: 0);

    await receiptDao.receiveCustomerMaterial(
      customerId: 'cust-1',
      items: [ReceiptItemInput(productId: blankShirtId, quantityReceived: 100.0)],
    );

    final bomId = await seedBom(
      bomDao,
      finishedProductId: printedShirtId,
      lines: [(productId: blankShirtId, quantity: 1.0, wasteOverride: null)],
    );

    final orderId = await seedOrder(
      moDao,
      bomId: bomId,
      finishedProductId: printedShirtId,
      plannedQuantity: 100.0,
      customerId: 'cust-1',
      scrapPolicy: 'factory_pays_piece_value',
      pieceUnitValue: 75.50,
    );

    await moDao.completeForOthersOrder(orderId: orderId);

    // 4 pieces damaged due to machine misalignment (factory fault)
    final scrap = await scrapDao.recordOrderScrapWithPolicy(
      orderId: orderId,
      productId: blankShirtId,
      quantity: 4.0,
      reason: ManufacturingScrapReason.processError,
      responsibleParty: 'Operator B',
      faultParty: 'factory',
    );

    expect(scrap.faultParty, 'factory');
    expect(scrap.compensationAction, 'deducted_from_invoice');
    // 4 * 75.50 = 302.00
    expect(scrap.compensationAmount, 302.0);
  });

  test('MSP-3: scrap policy factory_bears_labour_only bills service fee only for delivered units', () async {
    final (db, moDao, scrapDao, bomDao, receiptDao) = await setup();
    await seedCustomer(db, id: 'cust-1', name: 'Al-Madar Textiles');
    final blankShirtId = await seedProduct(db, name: 'Blank T-Shirt', qty: 0);
    final printedShirtId = await seedProduct(db, name: 'Printed T-Shirt', qty: 0);

    await receiptDao.receiveCustomerMaterial(
      customerId: 'cust-1',
      items: [ReceiptItemInput(productId: blankShirtId, quantityReceived: 100.0)],
    );

    final bomId = await seedBom(
      bomDao,
      finishedProductId: printedShirtId,
      lines: [(productId: blankShirtId, quantity: 1.0, wasteOverride: null)],
    );

    final orderId = await seedOrder(
      moDao,
      bomId: bomId,
      finishedProductId: printedShirtId,
      plannedQuantity: 100.0,
      customerId: 'cust-1',
      scrapPolicy: 'factory_bears_labour_only',
    );

    await moDao.completeForOthersOrder(orderId: orderId);

    final scrap = await scrapDao.recordOrderScrapWithPolicy(
      orderId: orderId,
      productId: blankShirtId,
      quantity: 5.0,
      reason: ManufacturingScrapReason.processError,
      responsibleParty: 'Printer Shift 2',
      faultParty: 'factory',
    );

    expect(scrap.compensationAction, 'labour_waived');
    expect(scrap.compensationAmount, 0.0);
  });

  test('MSP-4: scrap policy factory_replaces_piece consumes factory inventory to replace customer item', () async {
    final (db, moDao, scrapDao, bomDao, receiptDao) = await setup();
    await seedCustomer(db, id: 'cust-1', name: 'Al-Madar Textiles');
    final blankShirtId = await seedProduct(db, name: 'Blank T-Shirt', qty: 10); // Factory owns 10 blanks in stock
    final printedShirtId = await seedProduct(db, name: 'Printed T-Shirt', qty: 0);

    await receiptDao.receiveCustomerMaterial(
      customerId: 'cust-1',
      items: [ReceiptItemInput(productId: blankShirtId, quantityReceived: 100.0)],
    );

    final bomId = await seedBom(
      bomDao,
      finishedProductId: printedShirtId,
      lines: [(productId: blankShirtId, quantity: 1.0, wasteOverride: null)],
    );

    final orderId = await seedOrder(
      moDao,
      bomId: bomId,
      finishedProductId: printedShirtId,
      plannedQuantity: 100.0,
      customerId: 'cust-1',
      scrapPolicy: 'factory_replaces_piece',
    );

    await moDao.completeForOthersOrder(orderId: orderId);

    // Factory replaces 2 damaged customer pieces with 2 from its own inventory
    final scrap = await scrapDao.recordOrderScrapWithPolicy(
      orderId: orderId,
      productId: blankShirtId,
      quantity: 2.0,
      reason: ManufacturingScrapReason.processError,
      responsibleParty: 'Press Team',
      faultParty: 'factory',
    );

    expect(scrap.compensationAction, 'replaced');

    // Factory blank stock was decremented: 10 - 2 = 8
    final factoryProduct = await (db.select(db.products)..where((p) => p.id.equals(blankShirtId))).getSingle();
    expect(factoryProduct.quantity, 8);

    // Consumption movement recorded
    final moves = await (db.select(db.inventoryMovements)
          ..where((m) => m.productId.equals(blankShirtId) & m.movementType.equals('manufacturing_consumption')))
        .get();
    expect(moves.length, 1);
    expect(moves.first.quantity, -2);
  });

  test('MSP-5: scrap record validates fault_party (factory vs customer)', () async {
    final (db, moDao, scrapDao, bomDao, receiptDao) = await setup();
    await seedCustomer(db, id: 'cust-1', name: 'Al-Madar Textiles');
    final blankShirtId = await seedProduct(db, name: 'Blank T-Shirt', qty: 0);
    final printedShirtId = await seedProduct(db, name: 'Printed T-Shirt', qty: 0);

    await receiptDao.receiveCustomerMaterial(
      customerId: 'cust-1',
      items: [ReceiptItemInput(productId: blankShirtId, quantityReceived: 50.0)],
    );

    final bomId = await seedBom(
      bomDao,
      finishedProductId: printedShirtId,
      lines: [(productId: blankShirtId, quantity: 1.0, wasteOverride: null)],
    );

    final orderId = await seedOrder(
      moDao,
      bomId: bomId,
      finishedProductId: printedShirtId,
      plannedQuantity: 50.0,
      customerId: 'cust-1',
    );

    await moDao.completeForOthersOrder(orderId: orderId);

    expect(
      () => scrapDao.recordOrderScrapWithPolicy(
        orderId: orderId,
        productId: blankShirtId,
        quantity: 1.0,
        reason: ManufacturingScrapReason.defective,
        responsibleParty: 'Anyone',
        faultParty: 'invalid_party', // Invalid!
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  // ── Additional Edge Cases mandated by prompt ──

  test('MOC-EDGE-1: shortage on customer custody balance leaves zero writes', () async {
    final (db, moDao, _, bomDao, receiptDao) = await setup();
    await seedCustomer(db, id: 'cust-1', name: 'Al-Madar Textiles');
    final blankShirtId = await seedProduct(db, name: 'Blank T-Shirt', qty: 0);
    final printedShirtId = await seedProduct(db, name: 'Printed T-Shirt', qty: 0);

    // Customer only delivered 20, but order wants 50
    await receiptDao.receiveCustomerMaterial(
      customerId: 'cust-1',
      items: [ReceiptItemInput(productId: blankShirtId, quantityReceived: 20.0)],
    );

    final bomId = await seedBom(
      bomDao,
      finishedProductId: printedShirtId,
      lines: [(productId: blankShirtId, quantity: 1.0, wasteOverride: null)],
    );

    final orderId = await seedOrder(
      moDao,
      bomId: bomId,
      finishedProductId: printedShirtId,
      plannedQuantity: 50.0,
      customerId: 'cust-1',
    );

    expect(
      () => moDao.completeForOthersOrder(orderId: orderId),
      throwsA(isA<InsufficientStockException>()),
    );

    // Assert zero writes: customer balance is unchanged (20)
    final bal = await receiptDao.getCustomerAvailableQuantity(
      customerId: 'cust-1',
      productId: blankShirtId,
    );
    expect(bal, 20.0);

    // Order status remains planned
    final order = await moDao.getById(orderId);
    expect(order!.status, ManufacturingOrderStatus.planned);

    // Zero customer stock movements issued to order
    final moves = await (db.select(db.customerStockMovements)
          ..where((m) => m.movementType.equals('issued_to_order')))
        .get();
    expect(moves.isEmpty, isTrue);
  });

  test('MSP-EDGE-1: replace-piece with insufficient factory stock is rejected with clear message and zero writes', () async {
    final (db, moDao, scrapDao, bomDao, receiptDao) = await setup();
    await seedCustomer(db, id: 'cust-1', name: 'Al-Madar Textiles');
    final blankShirtId = await seedProduct(db, name: 'Blank T-Shirt', qty: 2); // Factory only has 2
    final printedShirtId = await seedProduct(db, name: 'Printed T-Shirt', qty: 0);

    await receiptDao.receiveCustomerMaterial(
      customerId: 'cust-1',
      items: [ReceiptItemInput(productId: blankShirtId, quantityReceived: 50.0)],
    );

    final bomId = await seedBom(
      bomDao,
      finishedProductId: printedShirtId,
      lines: [(productId: blankShirtId, quantity: 1.0, wasteOverride: null)],
    );

    final orderId = await seedOrder(
      moDao,
      bomId: bomId,
      finishedProductId: printedShirtId,
      plannedQuantity: 50.0,
      customerId: 'cust-1',
      scrapPolicy: 'factory_replaces_piece',
    );

    await moDao.completeForOthersOrder(orderId: orderId);

    // Trying to replace 5 pieces when factory only has 2
    expect(
      () => scrapDao.recordOrderScrapWithPolicy(
        orderId: orderId,
        productId: blankShirtId,
        quantity: 5.0,
        reason: ManufacturingScrapReason.processError,
        responsibleParty: 'Press Team',
        faultParty: 'factory',
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Cannot replace customer scrap with factory stock: required 5'),
        ),
      ),
    );

    // Factory stock is intact (2)
    final prod = await (db.select(db.products)..where((p) => p.id.equals(blankShirtId))).getSingle();
    expect(prod.quantity, 2);

    // Zero scrap records created
    final scraps = await scrapDao.getForOrder(orderId);
    expect(scraps.isEmpty, isTrue);
  });

  test('MOC-EDGE-2: completing an internal order via completeForOthersOrder is rejected', () async {
    final (db, moDao, _, bomDao, _) = await setup();
    final woodId = await seedProduct(db, name: 'Wood', qty: 50);
    final chairId = await seedProduct(db, name: 'Chair', qty: 0);

    final bomId = await seedBom(
      bomDao,
      finishedProductId: chairId,
      lines: [(productId: woodId, quantity: 2.0, wasteOverride: null)],
    );

    final orderId = await seedOrder(
      moDao,
      bomId: bomId,
      finishedProductId: chairId,
      plannedQuantity: 10.0,
      orderType: 'internal', // Internal order!
    );

    expect(
      () => moDao.completeForOthersOrder(orderId: orderId),
      throwsA(isA<ArgumentError>().having((e) => e.message, 'message', contains('cannot be completed via completeForOthersOrder'))),
    );
  });

  test('MOC-BUG-1: screenshot reproduction - fabric required 3 available 0 (or less), color required > 0 with NO balance row at all throws InsufficientStockException with readable per-material message', () async {
    final (db, moDao, _, bomDao, receiptDao) = await setup();
    await seedCustomer(db, id: 'cust-1', name: 'Al-Madar');
    final fabricId = await seedProduct(db, name: 'قماش ميلتون', qty: 0);
    final colorId = await seedProduct(db, name: 'لون طباعة أسود', qty: 0);
    final hoodieId = await seedProduct(db, name: 'هودي مطبوع', qty: 0);

    // Customer delivered fabric (e.g. 183 in custody as in screenshot)
    await receiptDao.receiveCustomerMaterial(
      customerId: 'cust-1',
      items: [
        ReceiptItemInput(productId: fabricId, quantityReceived: 183.0),
      ],
    );
    // Customer delivered NO colorId at all -> customerStockBalances has NO row for colorId!

    // BOM: yieldQuantity=100. Fabric requires 2 per yield (planned 150 -> 3 required), color requires 5 per yield (planned 150 -> 8 required).
    final bomId = await seedBom(
      bomDao,
      finishedProductId: hoodieId,
      yieldQuantity: 100.0,
      lines: [
        (productId: fabricId, quantity: 2.0, wasteOverride: null),
        (productId: colorId, quantity: 5.0, wasteOverride: null),
      ],
    );

    final orderId = await seedOrder(
      moDao,
      bomId: bomId,
      finishedProductId: hoodieId,
      plannedQuantity: 150.0,
      customerId: 'cust-1',
      scrapPolicy: 'factory_pays_piece_value',
    );

    // Color is missing from custody (custBal is null, available is 0, required is 8).
    // Fabric has 183 (sufficient).
    // Completing must NOT throw Null check operator, but InsufficientStockException with readable per-material message.
    try {
      await moDao.completeForOthersOrder(orderId: orderId);
      fail('Expected InsufficientStockException but completed without error');
    } on InsufficientStockException catch (e) {
      expect(e.shortages.length, 1);
      final s = e.shortages.first;
      expect(s.rawMaterialProductId, colorId);
      expect(s.productName, contains('لون طباعة أسود'));
      expect(s.required, 8);
      expect(s.available, 0);
      expect(s.shortage, 8);
      expect(e.toString(), contains('لون طباعة أسود (عهدة العميل): مطلوب 8'));
    }
  });

  test('MOC-BUG-2: BOM line with required quantity = 0 and NO balance row is skipped without error when other items are sufficient', () async {
    final (db, moDao, _, bomDao, receiptDao) = await setup();
    await seedCustomer(db, id: 'cust-1', name: 'Al-Madar');
    final fabricId = await seedProduct(db, name: 'قماش ميلتون', qty: 0);
    final colorId = await seedProduct(db, name: 'لون اختياري', qty: 0);
    final hoodieId = await seedProduct(db, name: 'هودي مطبوع', qty: 0);

    // Customer delivered sufficient fabric (183)
    await receiptDao.receiveCustomerMaterial(
      customerId: 'cust-1',
      items: [
        ReceiptItemInput(productId: fabricId, quantityReceived: 183.0),
      ],
    );
    // Customer delivered NO colorId -> no custody row

    // BOM: Fabric requires 2 (150*2/100 = 3), color requires 0.0
    final bomId = await seedBom(
      bomDao,
      finishedProductId: hoodieId,
      yieldQuantity: 100.0,
      lines: [
        (productId: fabricId, quantity: 2.0, wasteOverride: null),
        (productId: colorId, quantity: 0.0, wasteOverride: null),
      ],
    );

    final orderId = await seedOrder(
      moDao,
      bomId: bomId,
      finishedProductId: hoodieId,
      plannedQuantity: 150.0,
      customerId: 'cust-1',
      scrapPolicy: 'factory_pays_piece_value',
    );

    // Required quantity for color is 0, so it must be SKIPPED, custBal! must NOT be invoked,
    // and completion succeeds cleanly!
    final result = await moDao.completeForOthersOrder(orderId: orderId);
    expect(result.producedQuantity, 150.0);

    // Fabric was consumed: 183 - 3 = 180
    final fabricBal = await receiptDao.getCustomerAvailableQuantity(customerId: 'cust-1', productId: fabricId);
    expect(fabricBal, 180.0);
  });

  test('MOC-BUG-3: readable shortages message when multiple custody materials are missing or short', () async {
    final (db, moDao, _, bomDao, _) = await setup();
    await seedCustomer(db, id: 'cust-1', name: 'Al-Madar');
    final fabricId = await seedProduct(db, name: 'قماش ميلتون', qty: 0);
    final zipperId = await seedProduct(db, name: 'سوستة', qty: 0);
    final hoodieId = await seedProduct(db, name: 'هودي مطبوع', qty: 0);

    // BOM: Fabric requires 3, zipper requires 150
    final bomId = await seedBom(
      bomDao,
      finishedProductId: hoodieId,
      yieldQuantity: 100.0,
      lines: [
        (productId: fabricId, quantity: 2.0, wasteOverride: null),
        (productId: zipperId, quantity: 100.0, wasteOverride: null),
      ],
    );

    final orderId = await seedOrder(
      moDao,
      bomId: bomId,
      finishedProductId: hoodieId,
      plannedQuantity: 150.0,
      customerId: 'cust-1',
      scrapPolicy: 'factory_pays_piece_value',
    );

    // Neither fabric nor zipper in custody
    try {
      await moDao.completeForOthersOrder(orderId: orderId);
      fail('Expected InsufficientStockException');
    } on InsufficientStockException catch (e) {
      expect(e.shortages.length, 2);
      final msg = e.toString();
      expect(msg, contains('قماش ميلتون (عهدة العميل): مطلوب 3'));
      expect(msg, contains('سوستة (عهدة العميل): مطلوب 150'));
    }
  });
}

