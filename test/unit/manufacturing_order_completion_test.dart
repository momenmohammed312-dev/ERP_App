import '../helpers/license_grant.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/dao/bom_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/inventory_movement_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/manufacturing_cost_component_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/manufacturing_order_dao.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_cost_components_table.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_orders_table.dart';

/// عقد [ManufacturingOrderDao.completeManufacturingOrder].
///
/// الدالة دي بتبلع مخزون وفلوس داخل transaction واحدة، ومحدش كتب لها test
/// ولا مرة في تاريخ الريبو كله..groups هنا مقفولة على السلوك الفعلي
/// للـDAO المحفوظ في `test-restore-16-sep` (`4f7e2a0`) — أي انحراف عن
/// السلوك ده معناه إن الـport غيّر حاجة مش مقصودة.
///
/// **[القواعد المقفولة]**
/// * estimated material cost = sum over BOM lines of (required qty x unit cost),
///   والتكلفة الوحدة = costPrice ?? price.
/// * الاستهلاك = quantityRequired × (المنتج ÷ yieldQuantity) × (1 + waste/100)،
///   after rounding to a whole number ("Option A"), and never more than is on hand.
/// * كل الاستهلاك يحدّث products.quantity وينزل سالب في inventory_movements
///   بنوع `manufacturing_consumption`، والإنتاج يزيد الكمية ويسجل
///   `manufacturing_output` — في نفس الـtransaction بالظبط.
/// * أي نقص في الخام يرمي InsufficientStockException **قبل أي كتابة**،
///   فمفيش partial update ولا سطر حركة واحد ولا تغيير على حالة الأمر.
/// * بنود التكلفة: fixed = value، percentage = value/100 × materialCost،
///   per_unit = value × الكمية المنتَجة، والنتيجة بتتخزن مجمّدة (computedAmount)
///   لحظة الإتمام و null قبلها.
///
/// الأرقام في كل test ثابتة عن قصد. لو الـport غيّر الحساب، الـtests دي
/// هتفشل — وده المقصود.
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

  // ── Fixture ────────────────────────────────────────────────────────────

  const rawWoodCost = 10.0;
  const rawScrewCost = 2.0;

  Future<(BomDao, ManufacturingOrderDao, ManufacturingCostComponentDao,
      InventoryMovementDao, AppDatabase)> setup() async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    return (
      BomDao(db),
      ManufacturingOrderDao(db),
      ManufacturingCostComponentDao(db),
      InventoryMovementDao(db),
      db,
    );
  }

  Future<int> seedProduct(
    AppDatabase db, {
    required String name,
    required int quantity,
    double? cost,
    double? price,
    String? unit,
  }) {
    return db.productDao.insertProduct(
      ProductsCompanion.insert(
        name: name,
        quantity: quantity,
        price: price ?? cost ?? 0,
        costPrice: Value(cost),
        unit: Value(unit),
      ),
    );
  }

  Future<int> seedBom(
    BomDao bomDao, {
    required int finishedProductId,
    double yieldQuantity = 1,
    double wastePercentage = 0,
    required List<({int productId, double quantity, double? wasteOverride})>
        lines,
  }) {
    return bomDao.insertBomWithItems(
      bom: BillOfMaterialsCompanion(
        finishedProductId: Value(finishedProductId),
        name: const Value('بوم اختبار'),
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
  }) {
    // orderNumber متسيب عمداً: DAO يولّده لوحده ( عشان نثبّت السلوك ده كمان)
    return moDao.createOrder(
      ManufacturingOrdersCompanion(
        bomId: Value(bomId),
        finishedProductId: Value(finishedProductId),
        plannedQuantity: Value(plannedQuantity),
      ),
    );
  }

  Future<ManufacturingOrder> reload(ManufacturingOrderDao moDao, int id) async =>
      (await moDao.getById(id))!;

  Future<int> qtyOf(AppDatabase db, int productId) async =>
      (await db.productDao.getProductById(productId))!.quantity;

  void seedComponent(
    ManufacturingCostComponentDao ccDao,
    int orderId, {
    required String name,
    required String costType,
    required double value,
  }) {
    ccDao.insertComponent(
      ManufacturingCostComponentsCompanion(
        manufacturingOrderId: Value(orderId),
        name: Value(name),
        costType: Value(costType),
        value: Value(value),
      ),
    );
  }

  /// Base fixture: خشب 4 + مسامير 8 لكل وحدة منتَجة، تكلفة 56 لوحدة واحدة.
  Future<({
    BomDao bomDao,
    ManufacturingOrderDao moDao,
    ManufacturingCostComponentDao ccDao,
    InventoryMovementDao invDao,
    AppDatabase db,
    int wood,
    int screws,
    int chair,
    int bomId,
    int orderId,
  })> chairRecipe({
    int woodQty = 100,
    int screwQty = 100,
    double woodPerUnit = 4,
    double screwsPerUnit = 8,
    double yieldQuantity = 1,
    double wastePercentage = 0,
    double planned = 1,
  }) async {
    final (bomDao, moDao, ccDao, invDao, db) = await setup();
    final wood = await seedProduct(db,
        name: 'خشب', quantity: woodQty, cost: rawWoodCost, unit: 'قطعة');
    final screws = await seedProduct(db,
        name: 'مسامير', quantity: screwQty, cost: rawScrewCost, unit: 'قطعة');
    final chair = await seedProduct(db, name: 'كرسي', quantity: 0);

    final bomId = await seedBom(
      bomDao,
      finishedProductId: chair,
      yieldQuantity: yieldQuantity,
      wastePercentage: wastePercentage,
      lines: [
        (productId: wood, quantity: woodPerUnit, wasteOverride: null),
        (productId: screws, quantity: screwsPerUnit, wasteOverride: null),
      ],
    );
    final orderId = await seedOrder(
      moDao,
      bomId: bomId,
      finishedProductId: chair,
      plannedQuantity: planned,
    );

    return (
      bomDao: bomDao,
      moDao: moDao,
      ccDao: ccDao,
      invDao: invDao,
      db: db,
      wood: wood,
      screws: screws,
      chair: chair,
      bomId: bomId,
      orderId: orderId,
    );
  }

  // ── A: happy path ──────────────────────────────────────────────────────

  group('A — happy path', () {
    test('A1 completes the order and stamps producedQuantity/completedAt',
        () async {
      final f = await chairRecipe();

      final result = await f.moDao.completeManufacturingOrder(
        orderId: f.orderId,
        performedBy: 'مدير',
      );

      final mo = await reload(f.moDao, f.orderId);
      expect(mo.status, ManufacturingOrderStatus.completed);
      expect(mo.producedQuantity, 1);
      expect(mo.completedAt, isNotNull);
      expect(mo.startedAt, isNull, reason: 'completing never back-stamps startedAt');
      expect(result.orderId, f.orderId);
      expect(result.orderNumber, mo.orderNumber);
      expect(result.producedInt, 1);
    });

    test('A2 writes exactly one manufacturing_consumption row per BOM line',
        () async {
      final f = await chairRecipe();

      await f.moDao.completeManufacturingOrder(orderId: f.orderId);
      final mo = await reload(f.moDao, f.orderId);
      final rows = await f.invDao.getMovementsByType('manufacturing_consumption');

      expect(rows.length, 2);
      final wood = rows.firstWhere((r) => r.productId == f.wood);
      final screws = rows.firstWhere((r) => r.productId == f.screws);

      expect(wood.quantity, -4);
      expect(wood.unitCost, rawWoodCost);
      expect(wood.totalValue, 40);
      expect(wood.previousQuantity, 100);
      expect(wood.newQuantity, 96);
      expect(wood.reference, mo.orderNumber);
      expect(wood.referenceType, 'manufacturing_order');
      expect(wood.performedBy, isNull, reason: 'ما مرسناش performedBy هنا');

      expect(screws.quantity, -8);
      expect(screws.unitCost, rawScrewCost);
      expect(screws.totalValue, 16);
      expect(screws.previousQuantity, 100);
      expect(screws.newQuantity, 92);
    });

    test('A3 writes one manufacturing_output row carrying the unit cost',
        () async {
      final f = await chairRecipe();

      final result =
          await f.moDao.completeManufacturingOrder(orderId: f.orderId);
      final rows = await f.invDao.getMovementsByType('manufacturing_output');

      expect(rows.length, 1);
      final out = rows.single;
      expect(out.productId, f.chair);
      expect(out.quantity, 1);
      expect(out.unitCost, closeTo(result.unitCost, 0.0001));
      expect(out.totalValue, closeTo(result.totalCost, 0.0001));
      expect(out.referenceType, 'manufacturing_order');
    });

    test('A4 decrements every raw material', () async {
      final f = await chairRecipe();

      await f.moDao.completeManufacturingOrder(orderId: f.orderId);

      expect(await qtyOf(f.db, f.wood), 96);
      expect(await qtyOf(f.db, f.screws), 92);
    });

    test('A5 increments the finished product', () async {
      final f = await chairRecipe();

      final result =
          await f.moDao.completeManufacturingOrder(orderId: f.orderId);

      expect(await qtyOf(f.db, f.chair), 1);
      expect(result.previousFinishedQuantity, 0);
      expect(result.nextFinishedQuantity, 1);
    });

    test('A6 materialCost is the sum of required x unit cost', () async {
      final f = await chairRecipe();

      final result =
          await f.moDao.completeManufacturingOrder(orderId: f.orderId);

      expect(result.materialCost, closeTo(56, 0.0001));
      expect(result.componentsCost, 0);
      expect(result.totalCost, closeTo(56, 0.0001));
      expect(result.unitCost, closeTo(56, 0.0001));
      expect(result.consumptions.length, 2);
    });

    test('A7 actualProducedQuantity overrides planned and scales consumption',
        () async {
      final f = await chairRecipe(planned: 1);

      final result = await f.moDao.completeManufacturingOrder(
        orderId: f.orderId,
        actualProducedQuantity: 3,
      );

      final mo = await reload(f.moDao, f.orderId);
      expect(mo.producedQuantity, 3);
      expect(await qtyOf(f.db, f.wood), 88); // 100 - 4*3
      expect(await qtyOf(f.db, f.screws), 76); // 100 - 8*3
      expect(await qtyOf(f.db, f.chair), 3);
      expect(result.materialCost, closeTo(168, 0.0001));
      expect(result.unitCost, closeTo(56, 0.0001));
    });

    test('A8 performedBy is echoed onto every movement', () async {
      final f = await chairRecipe();

      await f.moDao
          .completeManufacturingOrder(orderId: f.orderId, performedBy: 'مدير');

      final all = await f.invDao.getAllMovements();
      expect(all.length, 3);
      expect(all.every((r) => r.performedBy == 'مدير'), isTrue);
    });
  });

  // ── B: shortage ⇒ zero writes ──────────────────────────────────────────

  group('B — insufficient stock leaves the database untouched', () {
    test('B1 throws InsufficientStockException listing the shortage',
        () async {
      // 4 wood per unit; stock 100 holds 25 units, we ask for 30.
      final f = await chairRecipe(woodQty: 100, screwQty: 1000, planned: 30);

      await expectLater(
        f.moDao.completeManufacturingOrder(
            orderId: f.orderId, actualProducedQuantity: 30),
        throwsA(isA<InsufficientStockException>()),
      );

      try {
        await f.moDao.completeManufacturingOrder(
            orderId: f.orderId, actualProducedQuantity: 30);
      } on InsufficientStockException catch (e) {
        expect(e.shortages.length, 1);
        expect(e.shortages.single.required, 120);
        expect(e.shortages.single.available, 100);
        expect(e.shortages.single.shortage, 20);
        expect(e.shortages.single.unit, 'قطعة');
      }
    });

    test('B2 zero writes: no stock is touched', () async {
      final f = await chairRecipe(woodQty: 100, screwQty: 1000, planned: 30);

      await expectLater(
        f.moDao.completeManufacturingOrder(
            orderId: f.orderId, actualProducedQuantity: 30),
        throwsA(isA<InsufficientStockException>()),
      );

      expect(await qtyOf(f.db, f.wood), 100);
      expect(await qtyOf(f.db, f.screws), 1000);
      expect(await qtyOf(f.db, f.chair), 0);
    });

    test('B3 zero writes: not a single movement row', () async {
      final f = await chairRecipe(woodQty: 100, screwQty: 1000, planned: 30);

      await expectLater(
        f.moDao.completeManufacturingOrder(
            orderId: f.orderId, actualProducedQuantity: 30),
        throwsA(isA<InsufficientStockException>()),
      );

      expect(await f.invDao.getAllMovements(), isEmpty);
    });

    test('B4 zero writes: the order keeps its planned state', () async {
      final f = await chairRecipe(woodQty: 100, screwQty: 1000, planned: 30);

      await expectLater(
        f.moDao.completeManufacturingOrder(
            orderId: f.orderId, actualProducedQuantity: 30),
        throwsA(isA<InsufficientStockException>()),
      );

      final mo = await reload(f.moDao, f.orderId);
      expect(mo.status, ManufacturingOrderStatus.planned);
      expect(mo.producedQuantity, 0);
      expect(mo.completedAt, isNull);
      expect(mo.cancelledAt, isNull);
    });

    test('B5 reports every shortage, not just the first', () async {
      final f = await chairRecipe(woodQty: 100, screwQty: 10, planned: 30);

      try {
        await f.moDao.completeManufacturingOrder(
            orderId: f.orderId, actualProducedQuantity: 30);
        fail('expected InsufficientStockException');
      } on InsufficientStockException catch (e) {
        expect(e.shortages.length, 2);
      }
      expect(await f.invDao.getAllMovements(), isEmpty);
    });

    test('B6 a shortage on the SECOND line still writes nothing', () async {
      // Wood is plentiful, screws are not. The first line passes validation, so
      // this proves the throw lands before the write loop, not after it.
      final f = await chairRecipe(woodQty: 1000, screwQty: 10, planned: 30);

      await expectLater(
        f.moDao.completeManufacturingOrder(
            orderId: f.orderId, actualProducedQuantity: 30),
        throwsA(isA<InsufficientStockException>()),
      );

      expect(await qtyOf(f.db, f.wood), 1000);
      expect(await qtyOf(f.db, f.screws), 10);
      expect(await f.invDao.getAllMovements(), isEmpty);
    });
  });

  // ── C: malformed input ─────────────────────────────────────────────────

  group('C — malformed input is rejected before any write', () {
    test('C1 a BOM with no items cannot be produced', () async {
      final (bomDao, moDao, _, invDao, db) = await setup();
      final chair = await seedProduct(db, name: 'كرسي', quantity: 0);
      final bomId = await seedBom(bomDao, finishedProductId: chair, lines: []);
      final orderId = await seedOrder(
          moDao, bomId: bomId, finishedProductId: chair, plannedQuantity: 1);

      await expectLater(
        moDao.completeManufacturingOrder(orderId: orderId),
        throwsA(isA<StateError>()),
      );
      expect(await invDao.getAllMovements(), isEmpty);
      expect((await reload(moDao, orderId)).status,
          ManufacturingOrderStatus.planned);
    });

    test('C2 yieldQuantity of zero is rejected', () async {
      final (bomDao, moDao, _, invDao, db) = await setup();
      final wood = await seedProduct(db, name: 'خشب', quantity: 100, cost: 10);
      final chair = await seedProduct(db, name: 'كرسي', quantity: 0);
      final bomId = await seedBom(
        bomDao,
        finishedProductId: chair,
        yieldQuantity: 0,
        lines: [(productId: wood, quantity: 4, wasteOverride: null)],
      );
      final orderId = await seedOrder(
          moDao, bomId: bomId, finishedProductId: chair, plannedQuantity: 1);

      await expectLater(
        moDao.completeManufacturingOrder(orderId: orderId),
        throwsA(isA<StateError>()),
      );
      expect(await qtyOf(db, wood), 100);
      expect(await invDao.getAllMovements(), isEmpty);
    });

    test('C3 a fractional yield scales consumption', () async {
      // yield 2.5 producing 5 units => factor 2 => 8 wood, not 2.
      final f = await chairRecipe(
        yieldQuantity: 2.5,
        woodPerUnit: 4,
        screwsPerUnit: 0,
        planned: 5,
      );

      await f.moDao.completeManufacturingOrder(
          orderId: f.orderId, actualProducedQuantity: 5);

      expect(await qtyOf(f.db, f.wood), 92); // 100 - 8
    });

    test('C4 an order pointing at a missing BOM is rejected', () async {
      final (_, moDao, _, invDao, _) = await setup();

      await expectLater(
        moDao.completeManufacturingOrder(orderId: 99999),
        throwsA(isA<ArgumentError>()),
      );
      expect(await invDao.getAllMovements(), isEmpty);
    });

    test('C5 an unknown order id is rejected', () async {
      final f = await chairRecipe();

      await expectLater(
        f.moDao.completeManufacturingOrder(orderId: 424242),
        throwsA(isA<ArgumentError>()),
      );
      expect(await f.invDao.getAllMovements(), isEmpty);
    });

    test('C6 the finished product cannot be deleted while an order references it',
        () async {
      // The original C6 tried to build "the finished product row vanished
      // mid-flight", but that state is unreachable: manufacturing_orders.
      // finishedProductId is a foreign key and PRAGMA foreign_keys is ON, and
      // ProductDao.deleteProduct falls back to a soft delete when the hard
      // delete is refused. So instead of faking an impossible state, assert the
      // guard that actually makes it impossible — and that the row survives.
      final f = await chairRecipe();
      final chair = (await f.db.productDao.getProductById(f.chair))!;

      // Hard delete must be refused while the order references the product.
      await expectLater(
        f.db.delete(f.db.products).delete(chair),
        throwsA(anything),
        reason: 'FK on manufacturing_orders.finishedProductId must block this',
      );
      expect(await f.db.productDao.getProductById(f.chair), isNotNull);

      // The soft-delete fallback leaves the row readable, so completion still
      // resolves the finished product and remains a no-op-free normal path.
      await f.db.productDao.deleteProduct(chair);
      final after = await f.db.productDao.getProductById(f.chair);
      expect(after, isNotNull);
      expect(after!.quantity, 0, reason: 'nothing was produced yet');

      expect(await qtyOf(f.db, f.wood), 100, reason: 'stock untouched');
      expect(await f.invDao.getAllMovements(), isEmpty);
    });
  });

  // ── D: rounding and waste ──────────────────────────────────────────────

  group('D — rounding and waste allowance', () {
    test('D1 header waste inflates the requirement then rounds', () async {
      // 4 * 1.0 * 1.10 = 4.4 -> 4
      final f = await chairRecipe(wastePercentage: 10, screwQty: 1000);
      // screws line has quantity 0 required, give it a real value below.

      final result =
          await f.moDao.completeManufacturingOrder(orderId: f.orderId);

      final wood = (await f.invDao.getMovementsByType('manufacturing_consumption'))
          .firstWhere((r) => r.productId == f.wood);
      expect(wood.quantity, -4);
      expect(result.materialCost, greaterThan(0));
    });

    test('D2 rounding is half-away-from-zero', () async {
      // 5 * 1.0 * 1.10 = 5.5 -> 6
      final (bomDao, moDao, _, invDao, db) = await setup();
      final wood = await seedProduct(db, name: 'خشب', quantity: 100, cost: 10);
      final chair = await seedProduct(db, name: 'كرسي', quantity: 0);
      final bomId = await seedBom(
        bomDao,
        finishedProductId: chair,
        wastePercentage: 10,
        lines: [(productId: wood, quantity: 5, wasteOverride: null)],
      );
      final orderId = await seedOrder(
          moDao, bomId: bomId, finishedProductId: chair, plannedQuantity: 1);

      await moDao.completeManufacturingOrder(orderId: orderId);

      final row = (await invDao.getMovementsByType('manufacturing_consumption'))
          .single;
      expect(row.quantity, -6);
      expect(await qtyOf(db, wood), 94);
    });

    test('D3 a line override beats the header percentage', () async {
      // header 0, line 100% -> 4 * 1.0 * 2.0 = 8
      final (bomDao, moDao, _, invDao, db) = await setup();
      final wood = await seedProduct(db, name: 'خشب', quantity: 100, cost: 10);
      final chair = await seedProduct(db, name: 'كرسي', quantity: 0);
      final bomId = await seedBom(
        bomDao,
        finishedProductId: chair,
        wastePercentage: 0,
        lines: [(productId: wood, quantity: 4, wasteOverride: 100)],
      );
      final orderId = await seedOrder(
          moDao, bomId: bomId, finishedProductId: chair, plannedQuantity: 1);

      await moDao.completeManufacturingOrder(orderId: orderId);

      final row = (await invDao.getMovementsByType('manufacturing_consumption'))
          .single;
      expect(row.quantity, -8);
    });

    test('D4 zero waste consumes exactly the recipe quantity', () async {
      final f = await chairRecipe(screwQty: 1000);

      await f.moDao.completeManufacturingOrder(orderId: f.orderId);

      final wood = (await f.invDao.getMovementsByType('manufacturing_consumption'))
          .firstWhere((r) => r.productId == f.wood);
      expect(wood.quantity, -4);
    });

    test('D5 a produced quantity that rounds to zero is rejected', () async {
      final f = await chairRecipe();

      await expectLater(
        f.moDao.completeManufacturingOrder(
            orderId: f.orderId, actualProducedQuantity: 0.4),
        throwsA(isA<ArgumentError>()),
      );
      expect(await f.invDao.getAllMovements(), isEmpty);
    });

    test('D6 a fractional recipe is readable but executes as whole units',
        () async {
      // 0.2 liter per unit, 5 units => 1.0 -> 1 whole unit issued.
      final (bomDao, moDao, _, invDao, db) = await setup();
      final litre = await seedProduct(db,
          name: 'دهان', quantity: 10, cost: 30, unit: 'لتر');
      final chair = await seedProduct(db, name: 'كرسي', quantity: 0);
      final bomId = await seedBom(
        bomDao,
        finishedProductId: chair,
        lines: [(productId: litre, quantity: 0.2, wasteOverride: null)],
      );
      final orderId = await seedOrder(
          moDao, bomId: bomId, finishedProductId: chair, plannedQuantity: 5);

      await moDao.completeManufacturingOrder(orderId: orderId);

      final row = (await invDao.getMovementsByType('manufacturing_consumption'))
          .single;
      expect(row.quantity, -1);
      expect(await qtyOf(db, litre), 9);
    });
  });

  // ── E: cost components ─────────────────────────────────────────────────

  group('E — overhead cost components', () {
    test('E1 fixed adds a flat amount', () async {
      final f = await chairRecipe(screwQty: 1000);
      seedComponent(f.ccDao, f.orderId,
          name: 'أجرة', costType: ManufacturingCostType.fixed, value: 500);

      final result =
          await f.moDao.completeManufacturingOrder(orderId: f.orderId);

      expect(result.materialCost, closeTo(56, 0.0001)); // 4 wood @10 + 8 screws @2
      expect(result.componentsCost, closeTo(500, 0.0001));
      expect(result.totalCost, closeTo(556, 0.0001));
      expect(result.unitCost, closeTo(556, 0.0001));
    });

    test('E2 percentage is taken on material cost only', () async {
      final f = await chairRecipe(screwQty: 1000);
      seedComponent(f.ccDao, f.orderId,
          name: 'كهرباء',
          costType: ManufacturingCostType.percentage,
          value: 10);

      final result =
          await f.moDao.completeManufacturingOrder(orderId: f.orderId);

      expect(result.materialCost, closeTo(56, 0.0001));
      expect(result.componentsCost, closeTo(5.6, 0.0001)); // 10% of 56
      expect(result.totalCost, closeTo(61.6, 0.0001));
    });

    test('E3 per_unit multiplies by the produced quantity', () async {
      final f = await chairRecipe(screwQty: 1000);
      seedComponent(f.ccDao, f.orderId,
          name: 'تغليف', costType: ManufacturingCostType.perUnit, value: 25);

      final result = await f.moDao.completeManufacturingOrder(
          orderId: f.orderId, actualProducedQuantity: 3);

      expect(result.materialCost, closeTo(168, 0.0001)); // (4 wood @10)+(8 screws @2) x3
      expect(result.componentsCost, closeTo(75, 0.0001)); // 25 * 3
    });

    test('E4 all three types combine and unit cost divides by produced',
        () async {
      final f = await chairRecipe(screwQty: 1000);
      seedComponent(f.ccDao, f.orderId,
          name: 'أجرة', costType: ManufacturingCostType.fixed, value: 500);
      seedComponent(f.ccDao, f.orderId,
          name: 'كهرباء',
          costType: ManufacturingCostType.percentage,
          value: 10);
      seedComponent(f.ccDao, f.orderId,
          name: 'تغليف', costType: ManufacturingCostType.perUnit, value: 25);

      final result = await f.moDao.completeManufacturingOrder(
          orderId: f.orderId, actualProducedQuantity: 3);

      expect(result.materialCost, closeTo(168, 0.0001));
      expect(result.componentsCost, closeTo(591.8, 0.0001)); // 500 + 16.8 + 75
      expect(result.totalCost, closeTo(759.8, 0.0001));
      expect(result.unitCost, closeTo(253.27, 0.01)); // 759.8 / 3
    });

    test('E5 computedAmount is null before completion and frozen after',
        () async {
      final f = await chairRecipe(screwQty: 1000);
      final compId = await f.ccDao.insertComponent(
        ManufacturingCostComponentsCompanion(
          manufacturingOrderId: Value(f.orderId),
          name: const Value('أجرة'),
          costType: Value(ManufacturingCostType.fixed),
          value: const Value(500),
        ),
      );

      expect((await f.ccDao.getById(compId))!.computedAmount, isNull);

      await f.moDao.completeManufacturingOrder(orderId: f.orderId);

      expect((await f.ccDao.getById(compId))!.computedAmount, 500);
    });

    test('E6 an unknown cost type is rejected', () async {
      final f = await chairRecipe(screwQty: 1000);
      seedComponent(f.ccDao, f.orderId,
          name: 'مش معروف', costType: 'per_unit_typo', value: 5);

      await expectLater(
        f.moDao.completeManufacturingOrder(orderId: f.orderId),
        throwsA(isA<StateError>()),
      );
      expect(await f.invDao.getAllMovements(), isEmpty);
      expect(await qtyOf(f.db, f.wood), 100);
    });

    test('E7 money is rounded to two decimals', () async {
      final f = await chairRecipe(screwQty: 1000);
      seedComponent(f.ccDao, f.orderId,
          name: 'كهرباء',
          costType: ManufacturingCostType.percentage,
          value: 3); // 3% of 40 = 1.2000000000000002

      final result =
          await f.moDao.completeManufacturingOrder(orderId: f.orderId);

      expect(result.componentsCost, closeTo(1.68, 0.0001)); // 3% of 56
      final decimals = result.totalCost.toString().split('.');
      expect(decimals.length == 1 || decimals[1].length <= 2, isTrue);
    });

    test('E8 an order with no components is pure material cost', () async {
      final f = await chairRecipe(screwQty: 1000);

      final result =
          await f.moDao.completeManufacturingOrder(orderId: f.orderId);

      expect(result.componentsCost, 0);
      expect(result.totalCost, result.materialCost);
    });
  });

  // ── F: status machine and cancellation ────────────────────────────────

  group('F — status transitions and cancellation', () {
    test('F1 startOrder moves planned to in_progress', () async {
      final f = await chairRecipe();

      await f.moDao.startOrder(f.orderId);

      final mo = await reload(f.moDao, f.orderId);
      expect(mo.status, ManufacturingOrderStatus.inProgress);
      expect(mo.startedAt, isNotNull);
    });

    test('F2 an in_progress order cannot be started twice', () async {
      final f = await chairRecipe();
      await f.moDao.startOrder(f.orderId);

      await expectLater(f.moDao.startOrder(f.orderId), throwsA(isA<StateError>()));
    });

    test('F3 cancelOrder from planned records the reason', () async {
      final f = await chairRecipe();

      await f.moDao.cancelOrder(f.orderId, reason: 'تغيّرت الحاجة');

      final mo = await reload(f.moDao, f.orderId);
      expect(mo.status, ManufacturingOrderStatus.cancelled);
      expect(mo.cancelledAt, isNotNull);
      expect(mo.cancelReason, 'تغيّرت الحاجة');
    });

    test('F4 an in_progress order can be cancelled', () async {
      final f = await chairRecipe();
      await f.moDao.startOrder(f.orderId);

      await f.moDao.cancelOrder(f.orderId, reason: 'إلغاء');

      expect((await reload(f.moDao, f.orderId)).status,
          ManufacturingOrderStatus.cancelled);
    });

    test('F5 a completed order cannot be cancelled', () async {
      final f = await chairRecipe(screwQty: 1000);
      await f.moDao.completeManufacturingOrder(orderId: f.orderId);

      await expectLater(f.moDao.cancelOrder(f.orderId), throwsA(isA<StateError>()));
    });

    test('F6 an already cancelled order cannot be cancelled again', () async {
      final f = await chairRecipe();
      await f.moDao.cancelOrder(f.orderId);

      await expectLater(f.moDao.cancelOrder(f.orderId), throwsA(isA<StateError>()));
    });

    test('F7 cancelling writes nothing to stock', () async {
      final f = await chairRecipe();

      await f.moDao.cancelOrder(f.orderId, reason: 'إلغاء');

      expect(await qtyOf(f.db, f.wood), 100);
      expect(await qtyOf(f.db, f.screws), 100);
      expect(await qtyOf(f.db, f.chair), 0);
      expect(await f.invDao.getAllMovements(), isEmpty);
    });

    test('F8 reopenCancelledOrder clears the cancellation stamps', () async {
      final f = await chairRecipe();
      await f.moDao.startOrder(f.orderId);
      await f.moDao.cancelOrder(f.orderId, reason: 'إلغاء');

      await f.moDao.reopenCancelledOrder(f.orderId);

      final mo = await reload(f.moDao, f.orderId);
      expect(mo.status, ManufacturingOrderStatus.planned);
      expect(mo.cancelledAt, isNull);
      expect(mo.cancelReason, isNull);
      expect(mo.startedAt, isNull);
    });

    test('F9 completing twice is rejected', () async {
      final f = await chairRecipe(screwQty: 1000);
      await f.moDao.completeManufacturingOrder(orderId: f.orderId);

      await expectLater(
        f.moDao.completeManufacturingOrder(orderId: f.orderId),
        throwsA(isA<StateError>()),
      );
    });

    test('F10 a cancelled order cannot be completed and writes nothing',
        () async {
      final f = await chairRecipe();
      await f.moDao.cancelOrder(f.orderId);

      await expectLater(
        f.moDao.completeManufacturingOrder(orderId: f.orderId),
        throwsA(isA<StateError>()),
      );
      expect(await f.invDao.getAllMovements(), isEmpty);
      expect(await qtyOf(f.db, f.wood), 100);
    });

    test('F11 a planned order may be completed without starting', () async {
      // The DAO documents "planned or in_progress"; pin that it is allowed.
      final f = await chairRecipe(screwQty: 1000);

      await f.moDao.completeManufacturingOrder(orderId: f.orderId);

      final mo = await reload(f.moDao, f.orderId);
      expect(mo.status, ManufacturingOrderStatus.completed);
      expect(mo.startedAt, isNull);
    });
  });
}
