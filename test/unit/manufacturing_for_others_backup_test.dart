import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/dao/customer_material_receipt_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/manufacturing_delivery_dao.dart';
import 'package:pos_offline_desktop/core/models/user_model.dart';
import 'package:pos_offline_desktop/core/services/backup_service.dart';

/// Test Phase B1 (C6): Backup & Restore coverage and round-trip verification
/// for Manufacturing for Others tables.
@Timeout(Duration(minutes: 3))
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('mfg_backup_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        return tempDir.path;
      },
    );
  });

  tearDownAll(() async {
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  const phaseB1Tables = [
    'customer_material_receipts',
    'customer_material_receipt_items',
    'customer_stock_balances',
    'customer_stock_movements',
    'manufacturing_deliveries',
    'manufacturing_delivery_items',
  ];

  User adminUser() => User(
        id: 1,
        username: 'admin',
        passwordHash: 'dummy',
        fullName: 'Admin User',
        role: UserRole.admin,
        createdAt: DateTime.now(),
      );

  group('J3 & J4: Phase B1 Backup Coverage & Round-Trip', () {
    String readBackupService() =>
        File('lib/core/services/backup_service.dart').readAsStringSync();

    Set<String> extractList(String source, String listStartMarker) {
      final start = source.indexOf(listStartMarker);
      expect(start, greaterThanOrEqualTo(0),
          reason: 'Marker not found: $listStartMarker');
      final openBracket = source.indexOf('[', start);
      final closeBracket = source.indexOf('];', openBracket);
      expect(closeBracket, greaterThan(openBracket));
      final body = source.substring(openBracket, closeBracket);
      return RegExp(r"'([a-z_]+)'")
          .allMatches(body)
          .map((m) => m.group(1)!)
          .toSet();
    }

    test('J3 backup set and restore order include all six Phase B1 tables in FK-safe order', () {
      final src = readBackupService();
      final backupList = extractList(src, 'final tables = [');
      final restoreList = extractList(src, 'final tableOrder = [');

      for (final t in phaseB1Tables) {
        expect(backupList, contains(t),
            reason: '$t missing from backup_service tables export list');
        expect(restoreList, contains(t),
            reason: '$t missing from backup_service tableOrder restore list');
      }

      // Check FK ordering
      final order = RegExp(r"'([a-z_]+)'")
          .allMatches(
              src.substring(src.indexOf('final tableOrder = [')))
          .map((m) => m.group(1)!)
          .toList();

      int indexOf(String t) {
        final i = order.indexOf(t);
        expect(i, greaterThanOrEqualTo(0), reason: '$t missing from tableOrder');
        return i;
      }

      // Parents must restore before children
      final custIdx = indexOf('customers');
      final prodIdx = indexOf('products');
      final moIdx = indexOf('manufacturing_orders');
      final invIdx = indexOf('invoices');

      final cmrIdx = indexOf('customer_material_receipts');
      final cmriIdx = indexOf('customer_material_receipt_items');
      final csbIdx = indexOf('customer_stock_balances');
      final csmIdx = indexOf('customer_stock_movements');
      final delIdx = indexOf('manufacturing_deliveries');
      final deliIdx = indexOf('manufacturing_delivery_items');

      expect(cmrIdx, greaterThan(custIdx));
      expect(cmriIdx, greaterThan(cmrIdx));
      expect(cmriIdx, greaterThan(prodIdx));

      expect(csbIdx, greaterThan(custIdx));
      expect(csbIdx, greaterThan(prodIdx));

      expect(csmIdx, greaterThan(custIdx));
      expect(csmIdx, greaterThan(prodIdx));

      expect(delIdx, greaterThan(moIdx));
      expect(delIdx, greaterThan(custIdx));

      expect(deliIdx, greaterThan(delIdx));
      expect(deliIdx, greaterThan(prodIdx));

      // Also ensure parent core tables exist before Phase B1
      expect(invIdx, lessThan(cmrIdx));
    });

    test('J4 real round-trip backup and restore preserves all Phase B1 data and satisfies foreign keys', () async {
      final dbFile = File('${tempDir.path}/test_source.db');
      final db = AppDatabase(NativeDatabase(dbFile));

      // 1. Seed Customer
      const custId = 'CUST-B1-001';
      await db.into(db.customers).insert(
        CustomersCompanion.insert(
          id: custId,
          name: 'Global Fabrics Ltd',
        ),
      );

      // 2. Seed Products
      final rawMaterialId = await db.productDao.insertProduct(
        ProductsCompanion.insert(
          name: 'Raw Cotton Fabric',
          quantity: 0,
          price: 50.0,
          costPrice: const Value(30.0),
          productType: const Value('raw_material'),
        ),
      );

      final finishedProductId = await db.productDao.insertProduct(
        ProductsCompanion.insert(
          name: 'Printed Cotton Shirt',
          quantity: 0,
          price: 150.0,
          costPrice: const Value(90.0),
          productType: const Value('finished_product'),
        ),
      );

      // 3. Receipt with defective units
      final receipt = await db.customerMaterialReceiptDao.receiveCustomerMaterial(
        customerId: custId,
        items: [
          ReceiptItemInput(
            productId: rawMaterialId,
            quantityReceived: 100,
            quantityDefectiveAtReceipt: 10,
            color: 'White',
            size: 'Standard',
          ),
        ],
        receivedBy: 'Warehouse Inspector 1',
        notes: 'Initial consignment',
      );

      expect(receipt.receiptNumber, startsWith('CMR-'));
      final preBal = await db.customerMaterialReceiptDao.getCustomerAvailableQuantity(
        customerId: custId,
        productId: rawMaterialId,
        color: 'White',
        size: 'Standard',
      );
      expect(preBal, 90.0);

      // 4. Create BOM and Manufacturing Order (for_others)
      final bomId = await db.bomDao.insertBomWithItems(
        bom: BillOfMaterialsCompanion(
          finishedProductId: Value(finishedProductId),
          name: const Value('Shirt Standard BOM'),
          yieldQuantity: const Value(1.0),
          status: const Value('Active'),
        ),
        items: [
          BomItemsCompanion(
            rawMaterialProductId: Value(rawMaterialId),
            quantityRequired: const Value(2.0),
          ),
        ],
      );

      final orderId = await db.manufacturingOrderDao.createOrder(
        ManufacturingOrdersCompanion(
          orderNumber: const Value('MO-FOR-OTHERS-001'),
          bomId: Value(bomId),
          finishedProductId: Value(finishedProductId),
          plannedQuantity: const Value(40.0),
          orderType: const Value('for_others'),
          customerId: const Value(custId),
          pricingMode: const Value('inclusive'),
          serviceUnitPrice: const Value(15.0),
        ),
      );

      // Complete order
      await db.manufacturingOrderDao.completeForOthersOrder(
        orderId: orderId,
        notes: 'Batch 1 completed cleanly',
      );

      final postCompletionBal = await db.customerMaterialReceiptDao.getCustomerAvailableQuantity(
        customerId: custId,
        productId: rawMaterialId,
        color: 'White',
        size: 'Standard',
      );
      // 90 - (40 * 2) = 10
      expect(postCompletionBal, 10.0);

      // 5. Create Delivery note for 30 units
      final delivery = await db.manufacturingDeliveryDao.createDelivery(
        orderId: orderId,
        deliveredBy: 'Courier Express',
        notes: 'Partial shipment 30 units',
        items: [
          DeliveryItemInput(
            productId: finishedProductId,
            quantity: 30.0,
          ),
        ],
      );

      expect(delivery.deliveryNumber, startsWith('DN-'));

      // 6. Generate Service Invoice
      final invoice = await db.manufacturingDeliveryDao.generateServiceInvoice(
        orderId,
      );

      expect(invoice.id, isNotNull);
      expect(invoice.totalAmount, 450.0);

      // Snapshot data before backup
      final preReceipts = await db.select(db.customerMaterialReceipts).get();
      final preReceiptItems = await db.select(db.customerMaterialReceiptItems).get();
      final preBalances = await db.select(db.customerStockBalances).get();
      final preMovements = await db.select(db.customerStockMovements).get();
      final preDeliveries = await db.select(db.manufacturingDeliveries).get();
      final preDeliveryItems = await db.select(db.manufacturingDeliveryItems).get();
      final preOrders = await db.select(db.manufacturingOrders).get();
      final preInvoices = await db.select(db.invoices).get();

      // 7. Perform Backup
      final backupService = BackupService(db);
      final backupInfo = await backupService.createBackup(
        adminUser(),
        description: 'Phase B1 Backup Test',
      );
      expect(backupInfo.filename, isNotEmpty);

      // 8. Wipe DB / Re-open clean and Restore
      await db.close();

      // Reopen clean DB on a new file
      final restoreDbFile = File('${tempDir.path}/test_target.db');
      if (await restoreDbFile.exists()) {
        await restoreDbFile.delete();
      }
      final restoreDb = AppDatabase(NativeDatabase(restoreDbFile));

      final restoreService = BackupService(restoreDb);
      await restoreService.restoreBackup(adminUser(), backupInfo.filename);

      // 9. Foreign key check
      final fkViolations = await restoreDb.customSelect('PRAGMA foreign_key_check').get();
      expect(fkViolations, isEmpty, reason: 'PRAGMA foreign_key_check reported violations after restore');

      // 10. Assert row counts and data integrity
      final postReceipts = await restoreDb.select(restoreDb.customerMaterialReceipts).get();
      expect(postReceipts.length, preReceipts.length);
      expect(postReceipts.first.receiptNumber, preReceipts.first.receiptNumber);
      expect(postReceipts.first.customerId, custId);

      final postReceiptItems = await restoreDb.select(restoreDb.customerMaterialReceiptItems).get();
      expect(postReceiptItems.length, preReceiptItems.length);
      expect(postReceiptItems.first.quantityReceived, 100.0);
      expect(postReceiptItems.first.quantityDefectiveAtReceipt, 10.0);

      final postBalances = await restoreDb.select(restoreDb.customerStockBalances).get();
      expect(postBalances.length, preBalances.length);
      expect(postBalances.first.quantityOnHand, 10.0);

      final postMovements = await restoreDb.select(restoreDb.customerStockMovements).get();
      expect(postMovements.length, preMovements.length);

      final postDeliveries = await restoreDb.select(restoreDb.manufacturingDeliveries).get();
      expect(postDeliveries.length, preDeliveries.length);
      expect(postDeliveries.first.deliveryNumber, preDeliveries.first.deliveryNumber);

      final postDeliveryItems = await restoreDb.select(restoreDb.manufacturingDeliveryItems).get();
      expect(postDeliveryItems.length, preDeliveryItems.length);
      expect(postDeliveryItems.first.quantity, 30.0);

      final postOrders = await restoreDb.select(restoreDb.manufacturingOrders).get();
      expect(postOrders.length, preOrders.length);
      expect(postOrders.first.orderType, 'for_others');
      expect(postOrders.first.pricingMode, 'inclusive');
      expect(postOrders.first.deliveryStatus, 'partially_delivered');

      final postInvoices = await restoreDb.select(restoreDb.invoices).get();
      expect(postInvoices.length, preInvoices.length);
      expect(postInvoices.first.totalAmount, 450.0); // 30 * 15

      // Balance read helper works on restored DB
      final restoredStockBalance = await restoreDb.customerMaterialReceiptDao.getCustomerAvailableQuantity(
        customerId: custId,
        productId: rawMaterialId,
        color: 'White',
        size: 'Standard',
      );
      expect(restoredStockBalance, 10.0);

      await restoreDb.close();
    });
  });
}
