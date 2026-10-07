import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/dao/customer_material_receipt_dao.dart';
import 'package:pos_offline_desktop/core/services/backup_service.dart';
import 'package:uuid/uuid.dart';

/// Test Phase B1.5/B2: Job Work (for_others) DAO logic with input tracking.
/// These tests are EXPECTED TO BE RED initially because the API extensions
/// (v77 schema, new DAO methods) do not exist yet. We use `dynamic` to bypass
/// Dart's static analysis for the missing API methods, simulating how they
/// will be called once implemented.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('job_work_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async => tempDir.path,
    );
  });

  tearDownAll(() async {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  Future<AppDatabase> setupDb() async {
    return AppDatabase(NativeDatabase.memory());
  }

  group('Job Work B1.5/B2 DAO Tests', () {
    test('createOrder without BOM creates placeholder BOM and sets input fields', () async {
      final db = await setupDb();
      final customerId = const Uuid().v4();
      await db.customerDao.insertCustomer(
          CustomersCompanion.insert(id: customerId, name: 'Test Customer'));
      final productId = await db.productDao.insertProduct(
          ProductsCompanion.insert(name: 'Raw Fabric', price: 0, quantity: 0));

      // Note: Using dynamic wrapper for Job Work order creation
      final orderId = await (db.manufacturingOrderDao as dynamic).createJobWorkOrder(
        orderNumber: 'JW-001',
        customerId: customerId,
        inputProductId: productId,
        inputQuantity: 100.0,
      ) as int;

      final order = await db.manufacturingOrderDao.getById(orderId);
      expect(order, isNotNull);
      expect(order!.orderType, 'for_others');
      
      final bom = await db.bomDao.getBomById(order.bomId);
      expect(bom, isNotNull);
      expect((bom as dynamic).type, 'system_placeholder');

      expect((order as dynamic).inputProductId, productId);
      expect((order as dynamic).inputQuantity, 100.0);

      await db.close();
    });

    test('Customer filter: getCustomersForManufacturing hides __SYNC_CUST_', () async {
      final db = await setupDb();
      await db.customerDao.insertCustomer(CustomersCompanion.insert(id: const Uuid().v4(), name: 'Real Customer'));
      await db.customerDao.insertCustomer(CustomersCompanion.insert(id: const Uuid().v4(), name: '__SYNC_CUST_123'));

      final customers = await (db.customerDao as dynamic).getCustomersForManufacturing() as List;
      
      expect(customers.length, 1);
      expect(customers.first.name, 'Real Customer');

      await db.close();
    });

    test('Allocation on start and release on cancel', () async {
      final db = await setupDb();
      final customerId = const Uuid().v4();
      await db.customerDao.insertCustomer(
          CustomersCompanion.insert(id: customerId, name: 'Test Customer'));
      final productId = await db.productDao.insertProduct(
          ProductsCompanion.insert(name: 'Raw Fabric', price: 0, quantity: 0));

      await db.customerMaterialReceiptDao.receiveCustomerMaterial(
        customerId: customerId,
        items: [
          ReceiptItemInput(
            productId: productId,
            quantityReceived: 200.0,
            quantityDefectiveAtReceipt: 0.0,
          )
        ],
      );

      final orderId = await (db.manufacturingOrderDao as dynamic).createJobWorkOrder(
        orderNumber: 'JW-002',
        customerId: customerId,
        inputProductId: productId,
        inputQuantity: 50.0,
      ) as int;

      await db.manufacturingOrderDao.startOrder(orderId);
      
      var bal = await db.customerMaterialReceiptDao.getCustomerBalance(
        customerId: customerId,
        productId: productId,
      );
      expect(bal, isNotNull);
      expect(bal!.quantityAllocated, 50.0);
      expect(bal.quantityOnHand, 200.0);

      await db.manufacturingOrderDao.cancelOrder(orderId);
      
      bal = await db.customerMaterialReceiptDao.getCustomerBalance(
        customerId: customerId,
        productId: productId,
      );
      expect(bal, isNotNull);
      expect(bal!.quantityAllocated, 0.0);
      expect(bal.quantityOnHand, 200.0);

      await db.close();
    });

    test('completeForOthersOrder deducts inputQuantity, no double deduction, readable error on shortage', () async {
      final db = await setupDb();
      final customerId = const Uuid().v4();
      await db.customerDao.insertCustomer(
          CustomersCompanion.insert(id: customerId, name: 'Test Customer'));
      final productId = await db.productDao.insertProduct(
          ProductsCompanion.insert(name: 'Raw Fabric', price: 0, quantity: 0));

      await db.customerMaterialReceiptDao.receiveCustomerMaterial(
        customerId: customerId,
        items: [
          ReceiptItemInput(
            productId: productId,
            quantityReceived: 40.0,
            quantityDefectiveAtReceipt: 0.0,
          )
        ],
      );

      final orderId = await (db.manufacturingOrderDao as dynamic).createJobWorkOrder(
        orderNumber: 'JW-003',
        customerId: customerId,
        inputProductId: productId,
        inputQuantity: 50.0,
      ) as int;

      await db.manufacturingOrderDao.startOrder(orderId);

      try {
        await (db.manufacturingOrderDao as dynamic).completeForOthersOrder(
          orderId: orderId,
          goodQuantity: 50.0,
          scrapQuantity: 0.0,
          completedByUserId: 'test-user',
        );
        fail('Should throw exception for insufficient stock');
      } catch (e) {
        expect(e.toString(), contains('رصيد العميل غير كافٍ'));
      }

      await db.customerMaterialReceiptDao.receiveCustomerMaterial(
        customerId: customerId,
        items: [
          ReceiptItemInput(
            productId: productId,
            quantityReceived: 20.0,
            quantityDefectiveAtReceipt: 0.0,
          )
        ],
      );

      await (db.manufacturingOrderDao as dynamic).completeForOthersOrder(
        orderId: orderId,
        goodQuantity: 50.0,
        scrapQuantity: 0.0,
        completedByUserId: 'test-user',
      );

      var bal = await db.customerMaterialReceiptDao.getCustomerBalance(
        customerId: customerId,
        productId: productId,
      );
      expect(bal, isNotNull);
      expect(bal!.quantityOnHand, 10.0);
      expect(bal.quantityAllocated, 0.0);

      await db.close();
    });

    test('Backup round-trip of new input columns and placeholder BOM', () async {
      final db = await setupDb();
      final backupService = BackupService(db);
      
      final customerId = const Uuid().v4();
      await db.customerDao.insertCustomer(
          CustomersCompanion.insert(id: customerId, name: 'Test Customer'));
      final productId = await db.productDao.insertProduct(
          ProductsCompanion.insert(name: 'Raw Fabric', price: 0, quantity: 0));

      final orderId = await (db.manufacturingOrderDao as dynamic).createJobWorkOrder(
        orderNumber: 'JW-BACKUP',
        customerId: customerId,
        inputProductId: productId,
        inputColor: 'Red',
        inputSize: 'XL',
        inputQuantity: 100.0,
      ) as int;

      final backupFile = await backupService.createBackup(null);
      
      final newDb = AppDatabase(NativeDatabase.memory());
      final newBackupService = BackupService(newDb);
      await newBackupService.restoreBackup(null, backupFile.filename);

      final order = await newDb.manufacturingOrderDao.getById(orderId);
      expect(order, isNotNull);
      expect((order as dynamic).inputProductId, productId);
      expect((order as dynamic).inputColor, 'Red');
      expect((order as dynamic).inputSize, 'XL');
      expect((order as dynamic).inputQuantity, 100.0);

      // Assert BOM type is preserved
      final bom = await newDb.bomDao.getBomById(order!.bomId);
      expect(bom, isNotNull);
      expect((bom as dynamic).type, 'system_placeholder');

      await db.close();
      await newDb.close();
    });

    test('Placeholder BOM is hidden from active list and refuses edit/delete', () async {
      final db = await setupDb();

      // Insert a normal BOM
      final productId = await db.productDao.insertProduct(
          ProductsCompanion.insert(name: 'Raw Fabric', price: 0, quantity: 0));
      final normalBomId = await db.bomDao.insertBom(
          BillOfMaterialsCompanion.insert(name: 'Normal BOM', finishedProductId: productId));

      // Insert placeholder BOM (simulating DAO)
      final placeholderBomId = await (db.bomDao as dynamic).createSystemPlaceholderBom() as int;

      // 1. Hidden from BOM lists
      final activeBoms = await db.bomDao.getActiveBoms();
      expect(activeBoms.any((b) => b.id == normalBomId), isTrue);
      expect(activeBoms.any((b) => b.id == placeholderBomId), isFalse);

      // 2. Refuses edit
      try {
        await (db.bomDao as dynamic).updateBomGuarded(
            BillOfMaterialsCompanion(id: Value(placeholderBomId), name: const Value('Hacked')));
        fail('Should throw exception when editing placeholder BOM');
      } catch (e) {
        expect(e.toString(), contains('لا يمكن تعديل وصفة النظام الأساسية'));
      }

      // 3. Refuses delete
      try {
        await (db.bomDao as dynamic).deleteBomGuarded(placeholderBomId);
        fail('Should throw exception when deleting placeholder BOM');
      } catch (e) {
        expect(e.toString(), contains('لا يمكن حذف وصفة النظام الأساسية'));
      }

      await db.close();
    });
  });
}
