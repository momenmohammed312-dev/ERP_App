import '../helpers/license_grant.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/dao/bom_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/customer_material_receipt_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/ledger_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/manufacturing_delivery_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/manufacturing_order_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/manufacturing_scrap_dao.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_scrap_table.dart';

/// Test Phase B1 (C5): Manufacturing Delivery Notes, Over-delivery Validation,
/// and Service Invoicing with Customer Ledger Posting.
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
    ManufacturingDeliveryDao,
    ManufacturingOrderDao,
    ManufacturingScrapDao,
    BomDao,
    CustomerMaterialReceiptDao,
    LedgerDao,
  )> setup() async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    return (
      db,
      db.manufacturingDeliveryDao,
      db.manufacturingOrderDao,
      db.manufacturingScrapDao,
      db.bomDao,
      db.customerMaterialReceiptDao,
      db.ledgerDao,
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

  Future<int> seedProduct(AppDatabase db, {
    required String name,
    int qty = 0,
    double price = 100,
    double? costPrice,
    String? productType,
  }) {
    return db.productDao.insertProduct(
      ProductsCompanion.insert(
        name: name,
        quantity: qty,
        price: price,
        costPrice: Value(costPrice ?? price),
        productType: Value(productType),
      ),
    );
  }

  Future<int> seedBom(
    BomDao bomDao, {
    required int finishedProductId,
    required List<({int productId, double quantity, double? wasteOverride})> lines,
    double yieldQuantity = 1.0,
    double wastePercentage = 0.0,
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
    String pricingMode = 'inclusive',
    double serviceUnitPrice = 0.0,
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
        pricingMode: Value(pricingMode),
        serviceUnitPrice: Value(serviceUnitPrice),
        scrapPolicy: Value(scrapPolicy),
        pieceUnitValue: Value(pieceUnitValue),
      ),
    );
  }

  group('Phase B1 (C5) — Manufacturing Deliveries & Service Invoicing', () {
    test('DN-1: Over-quantity delivery rejected with StateError and zero writes', () async {
      final (db, deliveryDao, moDao, _, bomDao, cmrDao, _) = await setup();
      const custId = 'cust-dn-1';
      await seedCustomer(db, id: custId, name: 'DN Customer 1');
      final rawMatId = await seedProduct(db, name: 'Cust Fabric');
      final finishedId = await seedProduct(db, name: 'Finished Dress');

      await cmrDao.receiveCustomerMaterial(
        customerId: custId,
        items: [ReceiptItemInput(productId: rawMatId, quantityReceived: 100)],
      );

      final bomId = await seedBom(
        bomDao,
        finishedProductId: finishedId,
        lines: [(productId: rawMatId, quantity: 2.0, wasteOverride: null)],
      );

      final moId = await seedOrder(
        moDao,
        bomId: bomId,
        finishedProductId: finishedId,
        plannedQuantity: 40,
        orderType: 'for_others',
        customerId: custId,
        serviceUnitPrice: 25.0,
      );

      await moDao.completeForOthersOrder(orderId: moId);

      // Attempt to deliver 45 when produced is 40 -> must throw StateError
      expect(
        () => deliveryDao.createDelivery(
          orderId: moId,
          items: [DeliveryItemInput(productId: finishedId, quantity: 45)],
        ),
        throwsA(isA<StateError>()),
      );

      // Verify zero writes: no delivery note created, order remains undelivered, zero movements
      final deliveries = await deliveryDao.getDeliveriesForOrder(moId);
      expect(deliveries, isEmpty);

      final refreshedOrder = await (db.select(db.manufacturingOrders)..where((o) => o.id.equals(moId))).getSingle();
      expect(refreshedOrder.deliveryStatus, 'undelivered');

      final movements = await (db.select(db.customerStockMovements)
            ..where((m) => m.customerId.equals(custId) & m.movementType.equals('delivered')))
          .get();
      expect(movements, isEmpty);
    });

    test('DN-2: Partial delivery followed by remaining delivery updates deliveryStatus accurately', () async {
      final (db, deliveryDao, moDao, _, bomDao, cmrDao, _) = await setup();
      const custId = 'cust-dn-2';
      await seedCustomer(db, id: custId, name: 'DN Customer 2');
      final rawMatId = await seedProduct(db, name: 'Cust Fabric 2');
      final finishedId = await seedProduct(db, name: 'Finished Shirt');

      await cmrDao.receiveCustomerMaterial(
        customerId: custId,
        items: [ReceiptItemInput(productId: rawMatId, quantityReceived: 200)],
      );

      final bomId = await seedBom(
        bomDao,
        finishedProductId: finishedId,
        lines: [(productId: rawMatId, quantity: 2.0, wasteOverride: null)],
      );

      final moId = await seedOrder(
        moDao,
        bomId: bomId,
        finishedProductId: finishedId,
        plannedQuantity: 50,
        orderType: 'for_others',
        customerId: custId,
        serviceUnitPrice: 30.0,
      );

      await moDao.completeForOthersOrder(orderId: moId);

      // 1. Partial delivery of 20 units
      final d1 = await deliveryDao.createDelivery(
        orderId: moId,
        items: [DeliveryItemInput(productId: finishedId, quantity: 20)],
      );
      expect(d1.deliveryNumber, startsWith('DN-'));

      var refreshedOrder = await (db.select(db.manufacturingOrders)..where((o) => o.id.equals(moId))).getSingle();
      expect(refreshedOrder.deliveryStatus, 'partially_delivered');
      expect(await deliveryDao.getTotalDeliveredQuantity(moId), 20.0);

      // 2. Deliver remaining 30 units
      final d2 = await deliveryDao.createDelivery(
        orderId: moId,
        items: [DeliveryItemInput(productId: finishedId, quantity: 30)],
      );
      expect(d2.id, isNot(d1.id));

      refreshedOrder = await (db.select(db.manufacturingOrders)..where((o) => o.id.equals(moId))).getSingle();
      expect(refreshedOrder.deliveryStatus, 'delivered');
      expect(await deliveryDao.getTotalDeliveredQuantity(moId), 50.0);

      // Verify customer stock movements: two delivery movements recorded
      final movements = await (db.select(db.customerStockMovements)
            ..where((m) => m.customerId.equals(custId) & m.movementType.equals('delivered')))
          .get();
      expect(movements.length, 2);
      expect(movements.fold<double>(0.0, (sum, m) => sum + m.quantity), 50.0);
    });

    test('INV-1: Inclusive pricing mode calculates deliveredQty * service_unit_price and posts ledger', () async {
      final (db, deliveryDao, moDao, _, bomDao, cmrDao, ledgerDao) = await setup();
      const custId = 'cust-inv-1';
      await seedCustomer(db, id: custId, name: 'INV Customer 1');
      final rawMatId = await seedProduct(db, name: 'Raw Mat');
      final finishedId = await seedProduct(db, name: 'Finished Product');

      await cmrDao.receiveCustomerMaterial(
        customerId: custId,
        items: [ReceiptItemInput(productId: rawMatId, quantityReceived: 100)],
      );

      final bomId = await seedBom(
        bomDao,
        finishedProductId: finishedId,
        lines: [(productId: rawMatId, quantity: 1.0, wasteOverride: null)],
      );

      final moId = await seedOrder(
        moDao,
        bomId: bomId,
        finishedProductId: finishedId,
        plannedQuantity: 40,
        orderType: 'for_others',
        customerId: custId,
        pricingMode: 'inclusive',
        serviceUnitPrice: 15.0,
      );

      await moDao.completeForOthersOrder(orderId: moId);

      // Deliver 30 units
      await deliveryDao.createDelivery(
        orderId: moId,
        items: [DeliveryItemInput(productId: finishedId, quantity: 30)],
      );

      // Generate service invoice: 30 delivered * 15.0 service price = 450.0
      final inv = await deliveryDao.generateServiceInvoice(moId);
      expect(inv.totalAmount, 450.0);
      expect(inv.paidAmount, 0.0);
      expect(inv.status, 'pending');
      expect(inv.customerId, custId);

      // Manufacturing order linked to invoice
      final refreshedOrder = await (db.select(db.manufacturingOrders)..where((o) => o.id.equals(moId))).getSingle();
      expect(refreshedOrder.invoiceId, inv.id);

      // Verify customer ledger debit & balance
      final balance = await ledgerDao.getCustomerBalance(custId);
      expect(balance, 450.0);

      final statement = await ledgerDao.getTransactionsWithRunningBalance(
        'Customer',
        custId,
        DateTime(2020),
        DateTime(2030),
      );
      expect(statement.length, 1);
      expect(statement.first.transaction.debit, 450.0);
      expect(statement.first.runningBalance, 450.0);
    });

    test('INV-2: Separate pricing mode adds factory material lines for mixed order', () async {
      final (db, deliveryDao, moDao, _, bomDao, cmrDao, ledgerDao) = await setup();
      const custId = 'cust-inv-2';
      await seedCustomer(db, id: custId, name: 'INV Customer 2');
      final custFabricId = await seedProduct(db, name: 'Cust Linen');
      final factoryButtonsId = await seedProduct(db, name: 'Factory Buttons', qty: 200, price: 5.0, costPrice: 3.0);
      final finishedId = await seedProduct(db, name: 'Finished Jacket');

      await cmrDao.receiveCustomerMaterial(
        customerId: custId,
        items: [ReceiptItemInput(productId: custFabricId, quantityReceived: 100)],
      );

      // BOM: 2 fabric (customer) + 4 buttons (factory @ 5.0 price)
      final bomId = await seedBom(
        bomDao,
        finishedProductId: finishedId,
        lines: [
          (productId: custFabricId, quantity: 2.0, wasteOverride: null),
          (productId: factoryButtonsId, quantity: 4.0, wasteOverride: null),
        ],
      );

      final moId = await seedOrder(
        moDao,
        bomId: bomId,
        finishedProductId: finishedId,
        plannedQuantity: 10,
        orderType: 'mixed',
        customerId: custId,
        pricingMode: 'separate',
        serviceUnitPrice: 50.0,
      );

      await moDao.completeForOthersOrder(
        orderId: moId,
        customerOwnedProductIds: {custFabricId},
      );

      await deliveryDao.createDelivery(
        orderId: moId,
        items: [DeliveryItemInput(productId: finishedId, quantity: 10)],
      );

      // Separate pricing calculation:
      // Labour / service: 10 delivered * 50.0 = 500.0
      // Factory material: 4 buttons * 10 produced = 40 buttons * 5.0 = 200.0
      // Total = 700.0
      final inv = await deliveryDao.generateServiceInvoice(moId);
      expect(inv.totalAmount, 700.0);

      final balance = await ledgerDao.getCustomerBalance(custId);
      expect(balance, 700.0);
    });

    test('INV-3: Compensation from factory_pays_piece_value is deducted from invoice', () async {
      final (db, deliveryDao, moDao, scrapDao, bomDao, cmrDao, ledgerDao) = await setup();
      const custId = 'cust-inv-3';
      await seedCustomer(db, id: custId, name: 'INV Customer 3');
      final rawMatId = await seedProduct(db, name: 'Cust Silk');
      final finishedId = await seedProduct(db, name: 'Finished Scarf');

      await cmrDao.receiveCustomerMaterial(
        customerId: custId,
        items: [ReceiptItemInput(productId: rawMatId, quantityReceived: 100)],
      );

      final bomId = await seedBom(
        bomDao,
        finishedProductId: finishedId,
        lines: [(productId: rawMatId, quantity: 1.0, wasteOverride: null)],
      );

      final moId = await seedOrder(
        moDao,
        bomId: bomId,
        finishedProductId: finishedId,
        plannedQuantity: 20,
        orderType: 'for_others',
        customerId: custId,
        pricingMode: 'inclusive',
        serviceUnitPrice: 20.0,
        scrapPolicy: 'factory_pays_piece_value',
        pieceUnitValue: 30.0, // Factory owes 30 per piece scrapped by factory fault
      );

      await moDao.completeForOthersOrder(orderId: moId);

      // Record scrap: 2 pieces spoiled by factory fault -> compensation = 2 * 30.0 = 60.0
      await scrapDao.recordOrderScrapWithPolicy(
        orderId: moId,
        productId: finishedId,
        quantity: 2.0,
        reason: ManufacturingScrapReason.processError,
        responsibleParty: 'Worker Tarek',
        faultParty: 'factory',
      );

      // Deliver the 18 intact pieces
      await deliveryDao.createDelivery(
        orderId: moId,
        items: [DeliveryItemInput(productId: finishedId, quantity: 18)],
      );

      // Invoice computation:
      // Gross service fee = 18 delivered * 20.0 = 360.0
      // Compensation deduction = 60.0
      // Net invoice total = 360.0 - 60.0 = 300.0
      final inv = await deliveryDao.generateServiceInvoice(moId);
      expect(inv.totalAmount, 300.0);

      final balance = await ledgerDao.getCustomerBalance(custId);
      expect(balance, 300.0);
    });

    test('INV-4: factory_bears_labour_only bills labour only on delivered (non-scrapped) units', () async {
      final (db, deliveryDao, moDao, scrapDao, bomDao, cmrDao, ledgerDao) = await setup();
      const custId = 'cust-inv-4';
      await seedCustomer(db, id: custId, name: 'INV Customer 4');
      final rawMatId = await seedProduct(db, name: 'Cust Wool');
      final finishedId = await seedProduct(db, name: 'Finished Coat');

      await cmrDao.receiveCustomerMaterial(
        customerId: custId,
        items: [ReceiptItemInput(productId: rawMatId, quantityReceived: 100)],
      );

      final bomId = await seedBom(
        bomDao,
        finishedProductId: finishedId,
        lines: [(productId: rawMatId, quantity: 1.0, wasteOverride: null)],
      );

      final moId = await seedOrder(
        moDao,
        bomId: bomId,
        finishedProductId: finishedId,
        plannedQuantity: 25,
        orderType: 'for_others',
        customerId: custId,
        pricingMode: 'inclusive',
        serviceUnitPrice: 40.0,
        scrapPolicy: 'factory_bears_labour_only',
      );

      await moDao.completeForOthersOrder(orderId: moId);

      // 5 units scrapped due to manufacturing fault (labour waived on scrapped)
      await scrapDao.recordOrderScrapWithPolicy(
        orderId: moId,
        productId: finishedId,
        quantity: 5.0,
        reason: ManufacturingScrapReason.processError,
        responsibleParty: 'Worker Ahmed',
        faultParty: 'factory',
      );

      // Deliver only the 20 sound units
      await deliveryDao.createDelivery(
        orderId: moId,
        items: [DeliveryItemInput(productId: finishedId, quantity: 20)],
      );

      // Billed labour on delivered units: 20 * 40.0 = 800.0 (no fee billed on the 5 scrapped)
      final inv = await deliveryDao.generateServiceInvoice(moId);
      expect(inv.totalAmount, 800.0);

      final balance = await ledgerDao.getCustomerBalance(custId);
      expect(balance, 800.0);
    });

    test('INV-5: Double invoicing is rejected with StateError', () async {
      final (db, deliveryDao, moDao, _, bomDao, cmrDao, _) = await setup();
      const custId = 'cust-inv-5';
      await seedCustomer(db, id: custId, name: 'INV Customer 5');
      final rawMatId = await seedProduct(db, name: 'Cust Mat');
      final finishedId = await seedProduct(db, name: 'Finished Item');

      await cmrDao.receiveCustomerMaterial(
        customerId: custId,
        items: [ReceiptItemInput(productId: rawMatId, quantityReceived: 50)],
      );

      final bomId = await seedBom(
        bomDao,
        finishedProductId: finishedId,
        lines: [(productId: rawMatId, quantity: 1.0, wasteOverride: null)],
      );

      final moId = await seedOrder(
        moDao,
        bomId: bomId,
        finishedProductId: finishedId,
        plannedQuantity: 20,
        orderType: 'for_others',
        customerId: custId,
        serviceUnitPrice: 10.0,
      );

      await moDao.completeForOthersOrder(orderId: moId);

      await deliveryDao.createDelivery(
        orderId: moId,
        items: [DeliveryItemInput(productId: finishedId, quantity: 20)],
      );

      // First invoice succeeds
      final inv1 = await deliveryDao.generateServiceInvoice(moId);
      expect(inv1.id, isPositive);

      // Second attempt must fail to prevent duplicate billing
      expect(
        () => deliveryDao.generateServiceInvoice(moId),
        throwsA(isA<StateError>()),
      );
    });

    test('REC-1: Reconciliation audit: received = delivered + scrap + balance', () async {
      final (db, deliveryDao, moDao, scrapDao, bomDao, cmrDao, _) = await setup();
      const custId = 'cust-rec-1';
      await seedCustomer(db, id: custId, name: 'Reconciliation Customer');
      final fabricId = await seedProduct(db, name: 'Roll of Denim');
      final finishedId = await seedProduct(db, name: 'Jeans Pants');

      // 1. Receive 100 metres of denim
      await cmrDao.receiveCustomerMaterial(
        customerId: custId,
        items: [ReceiptItemInput(productId: fabricId, quantityReceived: 100)],
      );
      final receivedBalance = await cmrDao.getCustomerAvailableQuantity(customerId: custId, productId: fabricId);
      expect(receivedBalance, 100.0);

      // 2. MO: Produce 30 jeans (requires 2 metres per jean = 60 metres)
      final bomId = await seedBom(
        bomDao,
        finishedProductId: finishedId,
        lines: [(productId: fabricId, quantity: 2.0, wasteOverride: null)],
      );

      final moId = await seedOrder(
        moDao,
        bomId: bomId,
        finishedProductId: finishedId,
        plannedQuantity: 30,
        orderType: 'for_others',
        customerId: custId,
        serviceUnitPrice: 35.0,
      );

      await moDao.completeForOthersOrder(orderId: moId);

      // Fabric remaining on hand should be 100 - 60 = 40 metres
      final fabricRemaining = await cmrDao.getCustomerAvailableQuantity(customerId: custId, productId: fabricId);
      expect(fabricRemaining, 40.0);

      // 3. Scrap 2 jeans (customer bears)
      await scrapDao.recordOrderScrapWithPolicy(
        orderId: moId,
        productId: finishedId,
        quantity: 2.0,
        reason: ManufacturingScrapReason.processError,
        responsibleParty: 'Sewing Operator',
        faultParty: 'customer',
      );

      // 4. Deliver 28 sound jeans
      await deliveryDao.createDelivery(
        orderId: moId,
        items: [DeliveryItemInput(productId: finishedId, quantity: 28)],
      );

      // Finished goods accounting:
      // Produced (30) = Delivered (28) + Scrapped (2)
      final totalDelivered = await deliveryDao.getTotalDeliveredQuantity(moId);
      expect(totalDelivered, 28.0);

      final scrapRows = await (db.select(db.manufacturingScraps)..where((s) => s.manufacturingOrderId.equals(moId))).get();
      final totalScrapped = scrapRows.fold<double>(0.0, (sum, s) => sum + s.quantity);
      expect(totalScrapped, 2.0);

      expect(totalDelivered + totalScrapped, 30.0);

      // Raw materials accounting:
      // Received (100) = Consumed in MO (60) + Rolling Balance (40)
      expect(60.0 + fabricRemaining, 100.0);
    });

    test('SYNC-1: generateServiceInvoice queues outbox entries, formats invoice number, and matches ledger fields', () async {
      final (db, deliveryDao, moDao, _, bomDao, cmrDao, _) = await setup();
      const custId = 'cust-sync-1';
      await seedCustomer(db, id: custId, name: 'Sync Cust');
      final rawMatId = await seedProduct(db, name: 'Raw Material');
      final finishedId = await seedProduct(db, name: 'Finished Product');

      await cmrDao.receiveCustomerMaterial(
        customerId: custId,
        items: [ReceiptItemInput(productId: rawMatId, quantityReceived: 50)],
      );

      final bomId = await seedBom(
        bomDao,
        finishedProductId: finishedId,
        lines: [(productId: rawMatId, quantity: 1.0, wasteOverride: null)],
      );

      final moId = await seedOrder(
        moDao,
        bomId: bomId,
        finishedProductId: finishedId,
        plannedQuantity: 15,
        orderType: 'for_others',
        customerId: custId,
        serviceUnitPrice: 20.0,
      );

      await moDao.completeForOthersOrder(orderId: moId);

      await deliveryDao.createDelivery(
        orderId: moId,
        items: [DeliveryItemInput(productId: finishedId, quantity: 15)],
      );

      final inv = await deliveryDao.generateServiceInvoice(moId);

      // 1. Invoice number format: 6-digit canonical format via formatInvoiceNumber
      expect(inv.invoiceNumber != null, isTrue);
      expect(RegExp(r'^\d{6}$').hasMatch(inv.invoiceNumber!), isTrue);
      expect(inv.invoiceNumber, inv.id.toString().padLeft(6, '0'));

      // 2. Sync outbox: sync_queue must contain insert rows for invoice and invoice_items
      final syncRows = await (db.select(db.syncQueue)).get();
      final invoiceSyncRows = syncRows.where((r) => r.tableRef == 'invoices').toList();
      final itemSyncRows = syncRows.where((r) => r.tableRef == 'invoice_items').toList();

      expect(invoiceSyncRows, hasLength(1));
      expect(invoiceSyncRows.single.operation, 'insert');
      expect(invoiceSyncRows.single.recordSyncId, inv.syncId);

      expect(itemSyncRows, hasLength(1));
      expect(itemSyncRows.single.operation, 'insert');

      // 3. Customer ledger entry fields match standard invoice format
      final ledgerTx = await (db.select(db.ledgerTransactions)
            ..where((t) => t.refId.equals(custId) & t.origin.equals('sale')))
          .getSingle();

      expect(ledgerTx.entityType, 'Customer');
      expect(ledgerTx.refId, custId);
      expect(ledgerTx.debit, 300.0); // 15 * 20.0
      expect(ledgerTx.credit, 0.0);
      expect(ledgerTx.origin, 'sale');
      expect(ledgerTx.paymentMethod, 'credit');
      expect(ledgerTx.receiptNumber, 'INV${inv.id}');
      expect(ledgerTx.description, 'فاتورة ${inv.invoiceNumber}');

      // 4. MO notes contain MO number and invoice number
      final updatedMo = await (db.select(db.manufacturingOrders)..where((o) => o.id.equals(moId))).getSingle();
      expect(updatedMo.invoiceId, inv.id);
      expect(updatedMo.notes, contains(updatedMo.orderNumber));
      expect(updatedMo.notes, contains(inv.invoiceNumber!));
    });
  });
}
