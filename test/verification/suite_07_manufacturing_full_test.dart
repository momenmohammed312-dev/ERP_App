import '../helpers/license_grant.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/dao/bom_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/customer_material_receipt_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/manufacturing_order_dao.dart';
import 'package:pos_offline_desktop/core/services/unified_print_service.dart';

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

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/shared_preferences'),
    (MethodCall methodCall) async => <String, Object>{},
  );

  late AppDatabase db;
  late ManufacturingOrderDao moDao;
  late BomDao bomDao;
  late CustomerMaterialReceiptDao receiptDao;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    moDao = db.manufacturingOrderDao;
    bomDao = db.bomDao;
    receiptDao = db.customerMaterialReceiptDao;
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> seedCustomer(String id, String name) async {
    await db.into(db.customers).insert(
          CustomersCompanion.insert(id: id, name: name),
        );
  }

  Future<int> seedProduct(String name, {int qty = 0}) async {
    return db.into(db.products).insert(
          ProductsCompanion.insert(name: name, quantity: qty, price: 100),
        );
  }

  group('Suite 7: Manufacturing Module E2E (FEAT-002..010, BUG-004..008)', () {
    test('1. Customer material receipt records custody inventory and balances accurately', () async {
      await seedCustomer('CUST-M1', 'مصنع الأمل');
      final rawFabricId = await seedProduct('قماش خام', qty: 0);

      // Receive 500 units of customer material
      final receipt = await receiptDao.receiveCustomerMaterial(
        customerId: 'CUST-M1',
        items: [ReceiptItemInput(productId: rawFabricId, quantityReceived: 500)],
      );

      expect(receipt.id, greaterThan(0));
      expect(receipt.customerId, equals('CUST-M1'));

      // Check customer stock balance in custody table
      final balance = await (db.select(db.customerStockBalances)
            ..where((tbl) =>
                tbl.customerId.equals('CUST-M1'))
            ..where((tbl) =>
                tbl.productId.equals(rawFabricId)))
          .getSingle();
      expect(balance.quantityOnHand, equals(500.0));

      // Standard factory inventory of product remains untouched at 0
      final factoryProduct = await db.productDao.getProductById(rawFabricId);
      expect(factoryProduct!.quantity, equals(0));
    });

    test('2. Real BOM Recipe links to Job Work Order without creating redundant placeholder', () async {
      await seedCustomer('CUST-M2', 'شركة النيل');
      final rawId = await seedProduct('خيوط بوليستر', qty: 100);
      final finishedId = await seedProduct('تيشيرت مطبوع', qty: 0);

      final bomId = await bomDao.insertBomWithItems(
        bom: BillOfMaterialsCompanion(
          finishedProductId: Value(finishedId),
          name: const Value('وصفة تيشيرت النيل'),
        ),
        items: [
          BomItemsCompanion(
            rawMaterialProductId: Value(rawId),
            quantityRequired: const Value(2.0),
          ),
        ],
      );

      final bomsCountBefore = (await bomDao.getAllBoms()).length;

      final orderId = await moDao.createJobWorkOrder(
        orderNumber: 'MO-JW-2026-01',
        orderType: 'for_others',
        customerId: 'CUST-M2',
        bomId: bomId,
        finishedProductId: finishedId,
        plannedQuantity: 50,
        pricingMode: 'separate',
        scrapPolicy: 'customer_bears',
        pieceUnitValue: 10,
        serviceUnitPrice: 35,
      );

      final order = await moDao.getById(orderId);
      expect(order, isNotNull);
      expect(order!.bomId, equals(bomId));
      expect(order.customerId, equals('CUST-M2'));
      expect(order.finishedProductId, equals(finishedId));
      expect(order.plannedQuantity, equals(50));
      expect(order.pricingMode, equals('separate'));
      expect(order.scrapPolicy, equals('customer_bears'));

      // Verify no placeholder BOM created
      final bomsCountAfter = (await bomDao.getAllBoms()).length;
      expect(bomsCountAfter, equals(bomsCountBefore));
    });

    test('3. Manufacturing Card PDF generation produces valid bytes without throwing', () async {
      final pdf = await UnifiedPrintService.generateUnifiedDocument(
        documentType: DocumentType.manufacturingCard,
        data: <String, dynamic>{
          'orderNumber': 'MO-TEST-FULL-01',
          'status': 'مكتمل',
          'orderType': 'تصنيع للغير',
          'customerName': 'مصنع النجوم',
          'bomName': 'وصفة تيشيرت صيفي',
          'finishedProductName': 'تيشيرت أبيض',
          'createdDate': '2026/10/18',
          'startedDate': '2026/10/18',
          'completedDate': '2026/10/19',
          'plannedQuantity': 100.0,
          'producedQuantity': 100.0,
          'deliveredQuantity': 100.0,
          'consumedQuantity': 200.0,
          'custodyOnHand': 300.0,
        },
        additionalData: <String, dynamic>{
          'movements': <Map<String, dynamic>>[
            {
              'date': '2026/10/18 10:00',
              'movementType': 'صرف للأمر',
              'productName': 'قماش قطن',
              'quantity': 200.0,
              'reference': 'MO-TEST-FULL-01',
            },
          ],
          'balances': <Map<String, dynamic>>[
            {
              'productName': 'قماش قطن',
              'currentBalance': 300.0,
              'reservedQuantity': 0.0,
              'availableQuantity': 300.0,
            },
          ],
        },
      );

      final bytes = await pdf.save();
      expect(bytes, isNotEmpty);
      expect(bytes.length, greaterThan(1000));
    });
  });
}
