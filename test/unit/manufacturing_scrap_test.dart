import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/dao/bom_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/inventory_movement_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/manufacturing_order_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/manufacturing_scrap_dao.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_scrap_table.dart';

/// Scrap records and product_type validation at the BOM boundary.
///
/// **Test-first. This whole file is red until C4 lands** — it references the v75
/// `manufacturing_scrap` table and a `BomDao.insertBomWithItems` that returns
/// warnings, neither of which exists yet. That is the point: the suite cannot
/// compile, so there is no way to mistake it for passing coverage.
///
/// **[القواعد المقفولة — scrap]**
/// * الاستهلاك بيقلّل صافي الإنتاج، لكن الـscrap نفسه لازم يتسجّل سطر صريح
///   في inventory_movements بنوع `manufacturing_scrap` — مفيش استهلاك متسرّب.
/// * لازم يبقى atomic: أي تحقق (الكمية، السبب، المسؤول، حالة الأمر) بيحصل
///   **قبل** أي كتابة، زي قاعدة generateAbsencesForRange بالظبط.
/// * لازم يبقى على_amount فقط بعد ما الأمر يبقى completed — مش في النص.
/// * scrap must be its own recorded line in inventory_movements, not a silent consumption gap.
///
/// **[القواعد المقفولة — OQ6]**
/// * `product_type` = NULL يعني "صنف عادي/محل" وما بيتفسّرش — إنذار فقط،
///   والإدراج ينجح. الصنف قديم من قبل العمود ده، فدعّه يمر.
/// * `product_type` غلط صريح (خام كمنتج نهائي، أو العكس) — رفض صريح،
///   صفر كتابة.
/// * النوعين صح — صامت، صفر إنذارات.
void main() {
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
        plannedQuantity: const Value(1),
      ),
    );
  }

  Future<int> qtyOf(AppDatabase db, int productId) async =>
      (await db.productDao.getProductById(productId))!.quantity;

  // ── H: scrap ───────────────────────────────────────────────────────────

  group('H — scrap records', () {
    test('H1 scrapping a raw material reduces stock and writes a movement',
        () async {
      final (bomDao, moDao, scrapDao, invDao, db) = await setup();
      final wood = await seedProduct(db,
          name: 'خشب', quantity: 100, cost: 10, productType: 'raw_material');
      final chair = await seedProduct(db,
          name: 'كرسي', productType: 'finished_product');
      final bomId = await bomDao.insertBomWithItems(
        bom: BillOfMaterialsCompanion(
          finishedProductId: Value(chair),
          name: const Value('بوم'),
        ),
        items: [
          BomItemsCompanion(
            rawMaterialProductId: Value(wood),
            quantityRequired: const Value(4),
          ),
        ],
      );
      final orderId = await seedOrder(moDao, bomId, chair);
      // Scrap is only recordable against a completed order. Completing also
      // consumes 4 wood (100 -> 96), so H1 scrapps one of the remaining 96.
      await moDao.completeManufacturingOrder(orderId: orderId);

      await scrapDao.recordScrap(
        orderId: orderId,
        productId: wood,
        quantity: 2,
        reason: ManufacturingScrapReason.defective,
        responsibleParty: 'عامل المورد',
      );

      expect(await qtyOf(db, wood), 94);
      final rows = await invDao.getMovementsByType('manufacturing_scrap');
      expect(rows.length, 1);
      expect(rows.single.productId, wood);
      expect(rows.single.quantity, -2);
      expect(rows.single.previousQuantity, 96);
      expect(rows.single.newQuantity, 94);
    });

    test('H2 scrapping more than is on hand writes nothing', () async {
      final (bomDao, moDao, scrapDao, invDao, db) = await setup();
      final wood = await seedProduct(db,
          name: 'خشب', quantity: 5, cost: 10, productType: 'raw_material');
      final chair = await seedProduct(db,
          name: 'كرسي', productType: 'finished_product');
      final bomId = await bomDao.insertBomWithItems(
        bom: BillOfMaterialsCompanion(
          finishedProductId: Value(chair),
          name: const Value('بوم'),
        ),
        items: [
          BomItemsCompanion(
            rawMaterialProductId: Value(wood),
            quantityRequired: const Value(4),
          ),
        ],
      );
      final orderId = await seedOrder(moDao, bomId, chair);

      await expectLater(
        scrapDao.recordScrap(
          orderId: orderId,
          productId: wood,
          quantity: 50,
          reason: ManufacturingScrapReason.defective,
          responsibleParty: 'x',
        ),
        throwsA(anything),
      );

      expect(await qtyOf(db, wood), 5);
      expect(await invDao.getAllMovements(), isEmpty);
    });

    test('H3 scrap is only allowed on a completed order', () async {
      final (bomDao, moDao, scrapDao, invDao, db) = await setup();
      final wood = await seedProduct(db,
          name: 'خشب', quantity: 100, cost: 10, productType: 'raw_material');
      final chair = await seedProduct(db,
          name: 'كرسي', productType: 'finished_product');
      final bomId = await bomDao.insertBomWithItems(
        bom: BillOfMaterialsCompanion(
          finishedProductId: Value(chair),
          name: const Value('بوم'),
        ),
        items: [
          BomItemsCompanion(
            rawMaterialProductId: Value(wood),
            quantityRequired: const Value(4),
          ),
        ],
      );
      final orderId = await seedOrder(moDao, bomId, chair);

      // Still planned.
      await expectLater(
        scrapDao.recordScrap(
          orderId: orderId,
          productId: wood,
          quantity: 1,
          reason: ManufacturingScrapReason.defective,
          responsibleParty: 'x',
        ),
        throwsA(anything),
      );

      await moDao.completeManufacturingOrder(orderId: orderId);

      await scrapDao.recordScrap(
        orderId: orderId,
        productId: wood,
        quantity: 1,
        reason: ManufacturingScrapReason.defective,
        responsibleParty: 'x',
      );
      expect(await qtyOf(db, wood), 95);
    });

    test('H4 scrap never rewrites the order produced quantity', () async {
      final (bomDao, moDao, scrapDao, _, db) = await setup();
      final wood = await seedProduct(db,
          name: 'خشب', quantity: 100, cost: 10, productType: 'raw_material');
      final chair = await seedProduct(db,
          name: 'كرسي', productType: 'finished_product');
      final bomId = await bomDao.insertBomWithItems(
        bom: BillOfMaterialsCompanion(
          finishedProductId: Value(chair),
          name: const Value('بوم'),
        ),
        items: [
          BomItemsCompanion(
            rawMaterialProductId: Value(wood),
            quantityRequired: const Value(4),
          ),
        ],
      );
      final orderId = await seedOrder(moDao, bomId, chair);
      await moDao.completeManufacturingOrder(
        orderId: orderId,
        actualProducedQuantity: 3,
      );

      await scrapDao.recordScrap(
        orderId: orderId,
        productId: wood,
        quantity: 1,
        reason: ManufacturingScrapReason.processError,
        responsibleParty: 'ورشة',
      );

      final mo = await moDao.getById(orderId);
      expect(mo!.producedQuantity, 3, reason: 'producedQuantity is what was made');
      expect(await qtyOf(db, wood), 87); // 100 - 4*3 - 1
    });

    test('H5 scrap needs a reason and a responsible party', () async {
      final (bomDao, moDao, scrapDao, invDao, db) = await setup();
      final wood = await seedProduct(db,
          name: 'خشب', quantity: 100, cost: 10, productType: 'raw_material');
      final chair = await seedProduct(db,
          name: 'كرسي', productType: 'finished_product');
      final bomId = await bomDao.insertBomWithItems(
        bom: BillOfMaterialsCompanion(
          finishedProductId: Value(chair),
          name: const Value('بوم'),
        ),
        items: [
          BomItemsCompanion(
            rawMaterialProductId: Value(wood),
            quantityRequired: const Value(4),
          ),
        ],
      );
      final orderId = await seedOrder(moDao, bomId, chair);
      await moDao.completeManufacturingOrder(orderId: orderId);

      await expectLater(
        scrapDao.recordScrap(
          orderId: orderId,
          productId: wood,
          quantity: 1,
          reason: '',
          responsibleParty: 'ورشة',
        ),
        throwsA(anything),
        reason: 'a scrap line with no reason is not auditable',
      );
      await expectLater(
        scrapDao.recordScrap(
          orderId: orderId,
          productId: wood,
          quantity: 1,
          reason: ManufacturingScrapReason.defective,
          responsibleParty: '   ',
        ),
        throwsA(anything),
        reason: 'somebody has to be accountable',
      );

      expect(await qtyOf(db, wood), 96);
      expect(await invDao.getMovementsByType('manufacturing_scrap'), isEmpty);
    });

    test('H6 finished-goods scrap cannot exceed what was produced', () async {
      final (bomDao, moDao, scrapDao, invDao, db) = await setup();
      final wood = await seedProduct(db,
          name: 'خشب', quantity: 100, cost: 10, productType: 'raw_material');
      final chair = await seedProduct(db,
          name: 'كرسي', productType: 'finished_product');
      final bomId = await bomDao.insertBomWithItems(
        bom: BillOfMaterialsCompanion(
          finishedProductId: Value(chair),
          name: const Value('بوم'),
        ),
        items: [
          BomItemsCompanion(
            rawMaterialProductId: Value(wood),
            quantityRequired: const Value(4),
          ),
        ],
      );
      final orderId = await seedOrder(moDao, bomId, chair);
      await moDao.completeManufacturingOrder(orderId: orderId);
      // produced 1 unit, so 1 may be scrapped but not 5.

      await expectLater(
        scrapDao.recordScrap(
          orderId: orderId,
          productId: chair,
          quantity: 5,
          reason: ManufacturingScrapReason.defective,
          responsibleParty: 'ورشة',
        ),
        throwsA(anything),
      );

      expect(await qtyOf(db, chair), 1);
      expect(await invDao.getMovementsByType('manufacturing_scrap'), isEmpty);
    });
  });

  // ── OQ6: product_type at the BOM boundary ──────────────────────────────

  group('C — product_type validation at the BOM boundary', () {
    test('C10 a NULL product_type only warns and still inserts', () async {
      final (bomDao, _, _, _, db) = await setup();
      final raw = await seedProduct(db, name: 'خشب', cost: 10); // no type
      final finished = await seedProduct(db, name: 'كرسي'); // no type

      final result = await bomDao.insertBomWithItemsChecked(
        bom: BillOfMaterialsCompanion(
          finishedProductId: Value(finished),
          name: const Value('بوم بدون أنواع'),
        ),
        items: [
          BomItemsCompanion(
            rawMaterialProductId: Value(raw),
            quantityRequired: const Value(4),
          ),
        ],
      );

      expect(result.bomId, greaterThan(0));
      expect(
        result.warnings,
        isNotEmpty,
        reason: 'untyped products predate the column, so warn rather than block',
      );
      expect(
        await bomDao.getItemsForBom(result.bomId),
        hasLength(1),
        reason: 'the insert must go through',
      );
    });

    test('C11 an explicitly wrong product_type is rejected with zero writes',
        () async {
      final (bomDao, _, _, _, db) = await setup();
      // A raw material cannot be the thing a BOM produces.
      final raw = await seedProduct(db,
          name: 'خشب', cost: 10, productType: 'raw_material');
      final wrongFinished = await seedProduct(db,
          name: 'منتج نهائي', productType: 'raw_material');

      await expectLater(
        bomDao.insertBomWithItemsChecked(
          bom: BillOfMaterialsCompanion(
            finishedProductId: Value(wrongFinished),
            name: const Value('بوم غلط'),
          ),
          items: [
            BomItemsCompanion(
              rawMaterialProductId: Value(raw),
              quantityRequired: const Value(4),
            ),
          ],
        ),
        throwsA(anything),
      );

      expect(await bomDao.getAllBoms(), isEmpty, reason: 'zero writes');
    });

    test('C12 correct product_types insert silently with no warnings',
        () async {
      final (bomDao, _, _, _, db) = await setup();
      final raw = await seedProduct(db,
          name: 'خشب', cost: 10, productType: 'raw_material');
      final finished = await seedProduct(db,
          name: 'كرسي', productType: 'finished_product');

      final result = await bomDao.insertBomWithItemsChecked(
        bom: BillOfMaterialsCompanion(
          finishedProductId: Value(finished),
          name: const Value('بوم صحيح'),
        ),
        items: [
          BomItemsCompanion(
            rawMaterialProductId: Value(raw),
            quantityRequired: const Value(4),
          ),
        ],
      );

      expect(result.bomId, greaterThan(0));
      expect(result.warnings, isEmpty);
      expect(await bomDao.getItemsForBom(result.bomId), hasLength(1));
    });
  });
}
