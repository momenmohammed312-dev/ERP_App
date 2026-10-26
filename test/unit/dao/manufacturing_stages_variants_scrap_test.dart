import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_stages_table.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_scrap_table.dart';
import '../../helpers/license_grant.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (MethodCall methodCall) async {
          return '.';
        },
      );

  late AppDatabase db;

  setUp(() async {
    grantLicensedModules();
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    revokeLicensedModules();
    await db.close();
  });

  Future<int> createTestBom({
    required String name,
    required int finishedProductId,
    required int rawMaterialId,
    double yieldQuantity = 1.0,
    double quantityRequired = 1.0,
  }) async {
    final bomId = await db.bomDao.insertBom(
      BillOfMaterialsCompanion.insert(
        name: name,
        finishedProductId: finishedProductId,
        yieldQuantity: Value(yieldQuantity),
      ),
    );
    await db.bomDao.insertBomItem(
      BomItemsCompanion.insert(
        bomId: bomId,
        rawMaterialProductId: rawMaterialId,
        quantityRequired: quantityRequired,
      ),
    );
    return bomId;
  }

  group('Manufacturing Stages, Variants, and Sellable Scrap Tests', () {
    test('createOrder with initialStageName inserts initial stage row and sets currentStageName', () async {
      // 1. Create a product and a BOM
      final finishedProductId = await db.productDao.insertProduct(
        ProductsCompanion.insert(
          name: 'تيشيرت رجالي صيفي',
          quantity: 0,
          price: 150.0,
          costPrice: const Value(80.0),
        ),
      );

      final rawMaterialId = await db.productDao.insertProduct(
        ProductsCompanion.insert(
          name: 'قماش قطن مصري',
          quantity: 200,
          price: 50.0,
          costPrice: const Value(40.0),
        ),
      );

      final bomId = await createTestBom(
        name: 'وصفة تيشيرت رجالي',
        finishedProductId: finishedProductId,
        rawMaterialId: rawMaterialId,
        yieldQuantity: 1.0,
        quantityRequired: 1.5,
      );

      // 2. Create order with initialStageName
      final orderId = await db.manufacturingOrderDao.createOrder(
        ManufacturingOrdersCompanion(
          orderNumber: const Value('MO-STAGE-001'),
          bomId: Value(bomId),
          finishedProductId: Value(finishedProductId),
          plannedQuantity: const Value(50.0),
          pricingMode: const Value('actual_cost_plus_margin'),
          targetMarginPercent: const Value(25.0),
        ),
        initialStageName: 'القص والتفصيل',
      );

      // Verify order header
      final order = await db.manufacturingOrderDao.getById(orderId);
      expect(order, isNotNull);
      expect(order!.currentStageName, 'القص والتفصيل');
      expect(order.targetMarginPercent, 25.0);

      // Verify initial stage
      final stages = await db.manufacturingStageDao.getStagesForOrder(orderId);
      expect(stages.length, 1);
      expect(stages.first.stageName, 'القص والتفصيل');
      expect(stages.first.stageOrder, 1);
      expect(stages.first.status, ManufacturingStageStatus.inProgress);
      expect(stages.first.inputQuantity, 50.0);
    });

    test('addStage appends subsequent stage and updates currentStageName on order', () async {
      final finishedProductId = await db.productDao.insertProduct(
        ProductsCompanion.insert(name: 'بنطلون جينز', quantity: 0, price: 300.0),
      );
      final rawMaterialId = await db.productDao.insertProduct(
        ProductsCompanion.insert(name: 'قماش دنيم', quantity: 100, price: 90.0),
      );
      final bomId = await createTestBom(
        name: 'وصفة بنطلون',
        finishedProductId: finishedProductId,
        rawMaterialId: rawMaterialId,
        yieldQuantity: 1.0,
        quantityRequired: 2.0,
      );

      final orderId = await db.manufacturingOrderDao.createOrder(
        ManufacturingOrdersCompanion(
          orderNumber: const Value('MO-STAGE-002'),
          bomId: Value(bomId),
          finishedProductId: Value(finishedProductId),
          plannedQuantity: const Value(30.0),
        ),
        initialStageName: 'مرحلة 1: القص',
      );

      // Add stage 2
      final stage2Id = await db.manufacturingStageDao.addStage(
        orderId: orderId,
        stageName: 'مرحلة 2: الخياطة والتقفيل',
        inputQuantity: 28.0,
        notes: 'تم استلام 28 قطعة مقصوصة',
      );

      expect(stage2Id, isPositive);

      final stages = await db.manufacturingStageDao.getStagesForOrder(orderId);
      expect(stages.length, 2);
      expect(stages[0].stageName, 'مرحلة 1: القص');
      expect(stages[0].stageOrder, 1);
      expect(stages[1].stageName, 'مرحلة 2: الخياطة والتقفيل');
      expect(stages[1].stageOrder, 2);
      expect(stages[1].inputQuantity, 28.0);

      final updatedOrder = await db.manufacturingOrderDao.getById(orderId);
      expect(updatedOrder!.currentStageName, 'مرحلة 2: الخياطة والتقفيل');
    });

    test('createVariantAndAddToStage and upsertStageOutput track outputs and update stage totals', () async {
      final finishedProductId = await db.productDao.insertProduct(
        ProductsCompanion.insert(name: 'قميص كاجوال', quantity: 0, price: 200.0),
      );
      final rawMaterialId = await db.productDao.insertProduct(
        ProductsCompanion.insert(name: 'قماش كتان', quantity: 100, price: 60.0),
      );
      final bomId = await createTestBom(
        name: 'وصفة قميص',
        finishedProductId: finishedProductId,
        rawMaterialId: rawMaterialId,
        yieldQuantity: 1.0,
        quantityRequired: 1.8,
      );

      final orderId = await db.manufacturingOrderDao.createOrder(
        ManufacturingOrdersCompanion(
          orderNumber: const Value('MO-STAGE-003'),
          bomId: Value(bomId),
          finishedProductId: Value(finishedProductId),
          plannedQuantity: const Value(40.0),
        ),
        initialStageName: 'التشطيب',
      );

      final stages = await db.manufacturingStageDao.getStagesForOrder(orderId);
      final stageId = stages.first.id;

      // Create new variant "مقاس L" directly from stage
      final output1Id = await db.manufacturingStageDao.createVariantAndAddToStage(
        stageId: stageId,
        orderId: orderId,
        productId: finishedProductId,
        variantName: 'مقاس L',
        plannedQuantity: 20.0,
        sellingPrice: 220.0,
      );

      expect(output1Id, isPositive);

      // Verify variant created in product_variants
      final variants = await db.productVariantDao.getVariantsByProduct(finishedProductId);
      expect(variants.length, 1);
      expect(variants.first.name, 'مقاس L');

      // Update output quantity for output1
      await db.manufacturingStageDao.upsertStageOutput(
        id: output1Id,
        stageId: stageId,
        orderId: orderId,
        productId: finishedProductId,
        variantId: variants.first.id,
        variantName: 'مقاس L',
        plannedQuantity: 20.0,
        producedQuantity: 18.0,
        scrapQuantity: 2.0,
      );

      // Check recalculated stage totals
      final stage = await db.manufacturingStageDao.getStageById(stageId);
      expect(stage!.outputQuantity, 18.0);
      expect(stage.scrapQuantity, 2.0);
    });

    test('recordScrap supports stage, variant, and sellable scrap (second-choice) recording', () async {
      final finishedProductId = await db.productDao.insertProduct(
        ProductsCompanion.insert(name: 'جاكيت جيليه', quantity: 20, price: 400.0),
      );
      final rawMaterialId = await db.productDao.insertProduct(
        ProductsCompanion.insert(name: 'قماش ووتربروف', quantity: 100, price: 80.0),
      );
      final bomId = await createTestBom(
        name: 'وصفة جاكيت',
        finishedProductId: finishedProductId,
        rawMaterialId: rawMaterialId,
        yieldQuantity: 1.0,
        quantityRequired: 1.2,
      );

      final orderId = await db.manufacturingOrderDao.createOrder(
        ManufacturingOrdersCompanion(
          orderNumber: const Value('MO-SCRAP-001'),
          bomId: Value(bomId),
          finishedProductId: Value(finishedProductId),
          plannedQuantity: const Value(20.0),
        ),
        initialStageName: 'القص',
      );

      // Transition order to inProgress so scrap can be recorded
      await db.manufacturingOrderDao.startOrder(orderId);

      final stages = await db.manufacturingStageDao.getStagesForOrder(orderId);
      final stageId = stages.first.id;

      // 1. Record sellable scrap (فرز ثاني بقيمة)
      final sellableScrap = await db.manufacturingScrapDao.recordScrap(
        orderId: orderId,
        productId: rawMaterialId,
        quantity: 5.0,
        reason: ManufacturingScrapReason.defective,
        responsibleParty: 'فني القص أحمد',
        stageId: stageId,
        variantName: 'عوادم قماش صالحة للبيع',
        isSellable: true,
        estimatedSellPrice: 35.0,
      );

      expect(sellableScrap.isSellable, isTrue);
      expect(sellableScrap.estimatedSellPrice, 35.0);
      expect(sellableScrap.stageId, stageId);

      // 2. Record defective scrap (تالف غير صالح للبيع)
      final defectiveScrap = await db.manufacturingScrapDao.recordScrap(
        orderId: orderId,
        productId: rawMaterialId,
        quantity: 2.0,
        reason: ManufacturingScrapReason.expired,
        responsibleParty: 'أمين المخزن',
        stageId: stageId,
        isSellable: false,
      );

      expect(defectiveScrap.isSellable, isFalse);
      expect(defectiveScrap.estimatedSellPrice, 0.0);

      // Verify scrap list
      final allScraps = await db.manufacturingScrapDao.getForOrder(orderId);
      expect(allScraps.length, 2);
    });

    test('FEAT-028: updateStage and deleteStage work correctly', () async {
      final pId = await db.productDao.insertProduct(
        ProductsCompanion.insert(name: 'طاولة خشبية', quantity: 0, price: 500.0),
      );
      final rawId = await db.productDao.insertProduct(
        ProductsCompanion.insert(name: 'لوح خشب زان', quantity: 10, price: 200.0),
      );
      final bomId = await createTestBom(
        name: 'وصفة طاولة خشب',
        finishedProductId: pId,
        rawMaterialId: rawId,
        yieldQuantity: 1.0,
      );
      final orderId = await db.manufacturingOrderDao.createOrder(
        ManufacturingOrdersCompanion(
          orderNumber: const Value('MO-STAGE-UPD'),
          bomId: Value(bomId),
          finishedProductId: Value(pId),
          plannedQuantity: const Value(10.0),
        ),
        initialStageName: 'تقطيع أخشاب',
      );

      final stages = await db.manufacturingStageDao.getStagesForOrder(orderId);
      expect(stages.length, 1);
      final stage = stages.first;

      // Update stage
      await db.manufacturingStageDao.updateStage(
        stageId: stage.id,
        stageName: 'تقطيع وتجهيز أخشاب',
        inputQuantity: 12.0,
        notes: 'تم تعديل الكمية الداخلة',
      );
      final updated = await db.manufacturingStageDao.getStageById(stage.id);
      expect(updated!.stageName, 'تقطيع وتجهيز أخشاب');
      expect(updated.inputQuantity, 12.0);
      expect(updated.notes, 'تم تعديل الكمية الداخلة');

      // Test getDistinctStageNames
      final distinctNames = await db.manufacturingStageDao.getDistinctStageNames();
      expect(distinctNames.contains('تقطيع وتجهيز أخشاب'), isTrue);

      // Add output then delete stage
      await db.manufacturingStageDao.upsertStageOutput(
        stageId: stage.id,
        orderId: orderId,
        productId: pId,
        variantName: 'طاولة 120سم',
        plannedQuantity: 5.0,
        producedQuantity: 5.0,
      );
      var outputs = await db.manufacturingStageDao.getOutputsForStage(stage.id);
      expect(outputs.length, 1);

      // Delete stage and verify cascading deletion of outputs
      await db.manufacturingStageDao.deleteStage(stage.id);
      final remainingStages = await db.manufacturingStageDao.getStagesForOrder(orderId);
      expect(remainingStages.isEmpty, isTrue);
      outputs = await db.manufacturingStageDao.getOutputsForStage(stage.id);
      expect(outputs.isEmpty, isTrue);
    });

    test('FEAT-028: upsertStageOutput prevents duplicates and producedQuantity defaults to plannedQuantity', () async {
      final pId = await db.productDao.insertProduct(
        ProductsCompanion.insert(name: 'كرسي سفرة', quantity: 0, price: 300.0),
      );
      final rawId = await db.productDao.insertProduct(
        ProductsCompanion.insert(name: 'خشب سويد', quantity: 20, price: 100.0),
      );
      final bomId = await createTestBom(
        name: 'وصفة كرسي',
        finishedProductId: pId,
        rawMaterialId: rawId,
        yieldQuantity: 1.0,
      );
      final orderId = await db.manufacturingOrderDao.createOrder(
        ManufacturingOrdersCompanion(
          orderNumber: const Value('MO-DEDUP-001'),
          bomId: Value(bomId),
          finishedProductId: Value(pId),
          plannedQuantity: const Value(8.0),
        ),
        initialStageName: 'نجارة وتجميع',
      );
      final stages = await db.manufacturingStageDao.getStagesForOrder(orderId);
      final stageId = stages.first.id;

      // 1. Create output without explicit producedQuantity -> must NOT be 0.0, defaults to plannedQuantity
      await db.manufacturingStageDao.upsertStageOutput(
        stageId: stageId,
        orderId: orderId,
        productId: pId,
        variantName: 'كرسي بني',
        plannedQuantity: 4.0,
      );

      var outs = await db.manufacturingStageDao.getOutputsForStage(stageId);
      expect(outs.length, 1);
      expect(outs.first.producedQuantity, 4.0);

      // 2. Upsert same variantName -> must update existing row without duplicating
      await db.manufacturingStageDao.upsertStageOutput(
        stageId: stageId,
        orderId: orderId,
        productId: pId,
        variantName: 'كرسي بني',
        plannedQuantity: 6.0,
        producedQuantity: 6.0,
        scrapQuantity: 1.0,
      );

      outs = await db.manufacturingStageDao.getOutputsForStage(stageId);
      expect(outs.length, 1);
      expect(outs.first.producedQuantity, 6.0);
      expect(outs.first.scrapQuantity, 1.0);
    });

    test('FEAT-028: custody_only products are excluded from store but included in custody methods', () async {
      // Standard product
      await db.productDao.insertProduct(
        ProductsCompanion.insert(name: 'منتج عادي بالمحل', quantity: 15, price: 50.0),
      );

      // Third-party custody product
      final custodyId = await db.productDao.insertProduct(
        ProductsCompanion.insert(
          name: 'قماش عميل أمانة',
          quantity: 0,
          price: 0.0,
          productType: const Value('custody_only'),
          status: const Value('Custody'),
        ),
      );

      final normalProducts = await db.productDao.getAllProducts();
      expect(normalProducts.any((p) => p.id == custodyId), isFalse);

      final searchResults = await db.productDao.searchProducts('قماش عميل');
      expect(searchResults.any((p) => p.id == custodyId), isFalse);

      final allIncludingCustody = await db.productDao.getAllProductsIncludingCustody();
      expect(allIncludingCustody.any((p) => p.id == custodyId), isTrue);
    });

    test('FEAT-028: updateOrder plannedQuantity automatically syncs Stage 1 inputQuantity', () async {
      final pId = await db.productDao.insertProduct(
        ProductsCompanion.insert(name: 'قميص أكسفورد', quantity: 0, price: 200.0),
      );
      final rawId = await db.productDao.insertProduct(
        ProductsCompanion.insert(name: 'قماش أكسفورد', quantity: 50, price: 90.0),
      );
      final bomId = await createTestBom(
        name: 'وصفة قميص',
        finishedProductId: pId,
        rawMaterialId: rawId,
        yieldQuantity: 1.0,
      );
      final orderId = await db.manufacturingOrderDao.createOrder(
        ManufacturingOrdersCompanion(
          orderNumber: const Value('MO-SYNC-QTY'),
          bomId: Value(bomId),
          finishedProductId: Value(pId),
          plannedQuantity: const Value(100.0),
        ),
        initialStageName: 'مرحلة 1: قص',
      );

      var stages = await db.manufacturingStageDao.getStagesForOrder(orderId);
      expect(stages.first.inputQuantity, 100.0);

      // Update order plannedQuantity from 100 to 500
      final order = await db.manufacturingOrderDao.getById(orderId);
      await db.manufacturingOrderDao.updateOrder(
        order!.copyWith(plannedQuantity: 500.0),
      );

      stages = await db.manufacturingStageDao.getStagesForOrder(orderId);
      expect(stages.first.inputQuantity, 500.0);
    });
  });
}
