import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/dao/bom_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/inventory_movement_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/manufacturing_order_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/manufacturing_scrap_dao.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_orders_table.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_scrap_table.dart';
import 'package:pos_offline_desktop/core/services/unified_print_service.dart';

import '../helpers/license_grant.dart';

void main() {
  grantLicensedModules();
  SharedPreferences.setMockInitialValues({});
  TestWidgetsFlutterBinding.ensureInitialized();

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (MethodCall methodCall) async => '.',
      );

  Future<(BomDao, ManufacturingOrderDao, ManufacturingScrapDao,
      InventoryMovementDao, AppDatabase)> setup() async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    return (
      BomDao(db),
      ManufacturingOrderDao(db),
      ManufacturingScrapDao(db),
      InventoryMovementDao(db),
      db,
    );
  }

  Future<int> seedProduct(
    AppDatabase db, {
    required String name,
    int quantity = 0,
    double? cost,
    String? productType,
  }) {
    return db.productDao.insertProduct(
      ProductsCompanion.insert(
        name: name,
        quantity: quantity,
        price: cost ?? 0,
        costPrice: Value(cost),
        productType: Value(productType),
      ),
    );
  }

  Future<int> seedOrder(
    ManufacturingOrderDao moDao,
    int bomId,
    int finishedId,
  ) {
    return moDao.createOrder(
      ManufacturingOrdersCompanion(
        bomId: Value(bomId),
        finishedProductId: Value(finishedId),
        plannedQuantity: const Value(10),
      ),
    );
  }

  group('FEAT-022 — Manufacturing Scrap Lifecycle & Reports', () {
    test('1. recordScrap allows raw material scrap during in_progress order', () async {
      final (bomDao, moDao, scrapDao, invDao, db) = await setup();
      final fabric = await seedProduct(db, name: 'قماش قطن', quantity: 100, cost: 50, productType: 'raw_material');
      final shirt = await seedProduct(db, name: 'قميص صيفي', productType: 'finished_product');

      final bomId = await bomDao.insertBomWithItems(
        bom: BillOfMaterialsCompanion(
          finishedProductId: Value(shirt),
          name: const Value('وصفة القميص'),
        ),
        items: [
          BomItemsCompanion(
            rawMaterialProductId: Value(fabric),
            quantityRequired: const Value(2),
          ),
        ],
      );

      final orderId = await seedOrder(moDao, bomId, shirt);

      // Start the order -> in_progress
      await moDao.startOrder(orderId);
      final mo = await moDao.getById(orderId);
      expect(mo!.status, equals(ManufacturingOrderStatus.inProgress));

      // Record scrap on raw material while order is in_progress
      final scrap = await scrapDao.recordScrap(
        orderId: orderId,
        productId: fabric,
        quantity: 5,
        reason: ManufacturingScrapReason.defective,
        responsibleParty: 'فني القص',
        dispositionNote: 'قماش به عيب صباغة أثناء القص',
        performedBy: 'tester',
      );

      expect(scrap, isNotNull);
      expect(scrap.quantity, equals(5));
      expect(scrap.responsibleParty, equals('فني القص'));

      // Stock reduced from 100 to 95
      final updatedProduct = await db.productDao.getProductById(fabric);
      expect(updatedProduct!.quantity, equals(95));

      // Inventory movement recorded
      final movements = await invDao.getMovementsByProduct(fabric);
      expect(movements.length, equals(1));
      expect(movements.first.movementType, equals('manufacturing_scrap'));
      expect(movements.first.quantity, equals(-5));
    });

    test('2. Finished product scrap rejected when order has not produced any units yet', () async {
      final (bomDao, moDao, scrapDao, _, db) = await setup();
      final fabric = await seedProduct(db, name: 'قماش', quantity: 100, cost: 50, productType: 'raw_material');
      final shirt = await seedProduct(db, name: 'قميص', quantity: 10, productType: 'finished_product');

      final bomId = await bomDao.insertBomWithItems(
        bom: BillOfMaterialsCompanion(
          finishedProductId: Value(shirt),
          name: const Value('وصفة'),
        ),
        items: [
          BomItemsCompanion(
            rawMaterialProductId: Value(fabric),
            quantityRequired: const Value(2),
          ),
        ],
      );

      final orderId = await seedOrder(moDao, bomId, shirt);
      await moDao.startOrder(orderId);

      // Finished product scrap on in-progress order with 0 produced units must throw StateError
      expect(
        () => scrapDao.recordScrap(
          orderId: orderId,
          productId: shirt,
          quantity: 1,
          reason: ManufacturingScrapReason.defective,
          responsibleParty: 'مفتش الجودة',
        ),
        throwsStateError,
      );
    });

    test('3. getScrapsInRange returns scraps filtered by date window', () async {
      final (bomDao, moDao, scrapDao, _, db) = await setup();
      final wood = await seedProduct(db, name: 'خشب', quantity: 50, cost: 20, productType: 'raw_material');
      final table = await seedProduct(db, name: 'طاولة', productType: 'finished_product');

      final bomId = await bomDao.insertBomWithItems(
        bom: BillOfMaterialsCompanion(
          finishedProductId: Value(table),
          name: const Value('بوم طاولة'),
        ),
        items: [
          BomItemsCompanion(
            rawMaterialProductId: Value(wood),
            quantityRequired: const Value(5),
          ),
        ],
      );

      final orderId = await seedOrder(moDao, bomId, table);
      await moDao.startOrder(orderId);

      await scrapDao.recordScrap(
        orderId: orderId,
        productId: wood,
        quantity: 2,
        reason: ManufacturingScrapReason.defective,
        responsibleParty: 'النجار',
      );

      final now = DateTime.now();
      final rangeScraps = await scrapDao.getScrapsInRange(
        start: now.subtract(const Duration(hours: 1)),
        end: now.add(const Duration(hours: 1)),
      );

      expect(rangeScraps.length, equals(1));
      expect(rangeScraps.first.quantity, equals(2));

      // Query past window returns empty
      final pastScraps = await scrapDao.getScrapsInRange(
        start: now.subtract(const Duration(days: 30)),
        end: now.subtract(const Duration(days: 10)),
      );
      expect(pastScraps, isEmpty);
    });

    test('4. UnifiedPrintService includes scraps table in manufacturingCard PDF without errors', () async {
      final pdf = await UnifiedPrintService.generateUnifiedDocument(
        documentType: DocumentType.manufacturingCard,
        data: <String, dynamic>{
          'orderNumber': 'MO-20261022-001',
          'status': 'مكتمل',
          'orderType': 'تصنيع للغير',
          'customerName': 'شركة النصر',
          'bomName': 'تشغيل أقمشة',
          'finishedProductName': 'ثوب جاهز',
          'createdDate': '2026/10/22',
          'startedDate': '2026/10/22',
          'completedDate': '2026/10/22',
          'plannedQuantity': 100.0,
          'producedQuantity': 98.0,
          'deliveredQuantity': 95.0,
          'consumedQuantity': 200.0,
          'custodyOnHand': 50.0,
        },
        additionalData: <String, dynamic>{
          'movements': [
            {
              'date': '2026/10/22',
              'movementType': 'صرف تشغيل',
              'productName': 'قماش صوف',
              'quantity': 200.0,
              'reference': 'MO-001',
            }
          ],
          'balances': [
            {
              'productName': 'قماش صوف',
              'quantityOnHand': 50.0,
              'quantityAllocated': 0.0,
              'colorSize': 'كحلي',
            }
          ],
          'scraps': [
            {
              'date': '2026/10/22',
              'productName': 'قماش صوف',
              'quantity': 2.0,
              'reason': 'عيب خامة',
              'faultParty': 'المصنع',
              'responsibleParty': 'خط التشغيل',
              'compensationAction': 'deducted_from_invoice',
              'compensationAmount': 150.0,
            }
          ],
        },
      );

      final bytes = await pdf.save();
      expect(bytes, isNotEmpty);
      expect(bytes.length, greaterThan(100));
    });
  });
}
