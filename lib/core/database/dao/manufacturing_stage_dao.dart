import 'package:drift/drift.dart';

import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/services/license_entitlement.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_orders_table.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_stages_table.dart';
import 'package:pos_offline_desktop/core/database/tables/product_table.dart';
import 'package:pos_offline_desktop/core/database/tables/product_variants_table.dart';

part 'manufacturing_stage_dao.g.dart';

@DriftAccessor(
  tables: [
    ManufacturingStages,
    ManufacturingStageOutputs,
    ManufacturingOrders,
    Products,
    ProductVariants,
  ],
)
class ManufacturingStageDao extends DatabaseAccessor<AppDatabase>
    with _$ManufacturingStageDaoMixin {
  ManufacturingStageDao(super.db);

  static void _requireLicense(String op) =>
      LicenseEntitlement.instance.require('manufacturing', operation: op);

  // ── Reads ──

  Future<List<ManufacturingStage>> getStagesForOrder(int orderId) {
    return (select(manufacturingStages)
          ..where((s) => s.manufacturingOrderId.equals(orderId))
          ..orderBy([(s) => OrderingTerm.asc(s.stageOrder)]))
        .get();
  }

  Stream<List<ManufacturingStage>> watchStagesForOrder(int orderId) {
    return (select(manufacturingStages)
          ..where((s) => s.manufacturingOrderId.equals(orderId))
          ..orderBy([(s) => OrderingTerm.asc(s.stageOrder)]))
        .watch();
  }

  Future<ManufacturingStage?> getStageById(int stageId) {
    return (select(manufacturingStages)..where((s) => s.id.equals(stageId)))
        .getSingleOrNull();
  }

  Future<List<ManufacturingStageOutput>> getOutputsForStage(int stageId) {
    return (select(manufacturingStageOutputs)
          ..where((o) => o.stageId.equals(stageId))
          ..orderBy([(o) => OrderingTerm.asc(o.id)]))
        .get();
  }

  Stream<List<ManufacturingStageOutput>> watchOutputsForStage(int stageId) {
    return (select(manufacturingStageOutputs)
          ..where((o) => o.stageId.equals(stageId))
          ..orderBy([(o) => OrderingTerm.asc(o.id)]))
        .watch();
  }

  Future<List<ManufacturingStageOutput>> getOutputsForOrder(int orderId) {
    return (select(manufacturingStageOutputs)
          ..where((o) => o.manufacturingOrderId.equals(orderId))
          ..orderBy([(o) => OrderingTerm.asc(o.id)]))
        .get();
  }

  // ── Mutating Operations (Atomic) ──

  /// إنشاء مرحلة جديدة لأمر تصنيع وتعيينها كمرحلة حالية
  Future<int> addStage({
    required int orderId,
    required String stageName,
    int? stageOrder,
    double inputQuantity = 0.0,
    double stageCost = 0.0,
    String? assignedTo,
    String? notes,
  }) async {
    _requireLicense('إضافة مرحلة تصنيع');
    return transaction(() async {
      int nextOrder = stageOrder ?? 1;
      if (stageOrder == null) {
        final existing = await getStagesForOrder(orderId);
        if (existing.isNotEmpty) {
          nextOrder = existing.map((s) => s.stageOrder).reduce((a, b) => a > b ? a : b) + 1;
        }
      }

      final stageId = await into(manufacturingStages).insert(
        ManufacturingStagesCompanion.insert(
          manufacturingOrderId: orderId,
          stageName: stageName,
          stageOrder: Value(nextOrder),
          status: const Value(ManufacturingStageStatus.inProgress),
          inputQuantity: Value(inputQuantity),
          stageCost: Value(stageCost),
          assignedTo: Value(assignedTo),
          notes: Value(notes),
          startedAt: Value(DateTime.now()),
        ),
      );

      // تحديث اسم المرحلة الحالية على الأمر للوصول السريع
      await (update(manufacturingOrders)..where((o) => o.id.equals(orderId))).write(
        ManufacturingOrdersCompanion(
          currentStageName: Value(stageName),
          updatedAt: Value(DateTime.now()),
        ),
      );

      return stageId;
    });
  }

  /// تعديل بيانات مرحلة تصنيع (الاسم، الكمية الداخلة، التكلفة، الملاحظات)
  Future<void> updateStage({
    required int stageId,
    required String stageName,
    double? inputQuantity,
    double? stageCost,
    String? notes,
  }) async {
    _requireLicense('تعديل مرحلة تصنيع');
    final stage = await getStageById(stageId);
    if (stage == null) return;

    await (update(manufacturingStages)..where((s) => s.id.equals(stageId))).write(
      ManufacturingStagesCompanion(
        stageName: Value(stageName),
        inputQuantity: inputQuantity != null ? Value(inputQuantity) : const Value.absent(),
        stageCost: stageCost != null ? Value(stageCost) : const Value.absent(),
        notes: Value(notes),
        updatedAt: Value(DateTime.now()),
      ),
    );

    // إذا تم تعديل اسم المرحلة وكانت هي المرحلة الحالية للأمر، نحدثها على الأمر
    final mo = await (select(manufacturingOrders)..where((o) => o.id.equals(stage.manufacturingOrderId))).getSingleOrNull();
    if (mo != null && mo.currentStageName == stage.stageName) {
      await (update(manufacturingOrders)..where((o) => o.id.equals(stage.manufacturingOrderId))).write(
        ManufacturingOrdersCompanion(
          currentStageName: Value(stageName),
          updatedAt: Value(DateTime.now()),
        ),
      );
    }
  }

  /// حذف مرحلة تصنيع ومخرجاتها
  Future<void> deleteStage(int stageId) async {
    _requireLicense('حذف مرحلة تصنيع');
    await transaction(() async {
      await (delete(manufacturingStageOutputs)..where((o) => o.stageId.equals(stageId))).go();
      await (delete(manufacturingStages)..where((s) => s.id.equals(stageId))).go();
    });
  }

  /// تحديث حالة المرحلة
  Future<void> updateStageStatus({
    required int stageId,
    required String status,
    double? outputQuantity,
    double? scrapQuantity,
    double? stageCost,
  }) async {
    _requireLicense('تحديث مرحلة تصنيع');
    final now = DateTime.now();
    await (update(manufacturingStages)..where((s) => s.id.equals(stageId))).write(
      ManufacturingStagesCompanion(
        status: Value(status),
        outputQuantity: outputQuantity != null ? Value(outputQuantity) : const Value.absent(),
        scrapQuantity: scrapQuantity != null ? Value(scrapQuantity) : const Value.absent(),
        stageCost: stageCost != null ? Value(stageCost) : const Value.absent(),
        completedAt: status == ManufacturingStageStatus.completed ? Value(now) : const Value.absent(),
        updatedAt: Value(now),
      ),
    );
  }

  /// إضافة أو تحديث سطر مخرجات (مواصفة / جزء / مقاس) داخل مرحلة مع منع التكرار
  Future<int> upsertStageOutput({
    int? id,
    required int stageId,
    required int orderId,
    required int productId,
    int? variantId,
    String? variantName,
    required double plannedQuantity,
    double? producedQuantity,
    double scrapQuantity = 0.0,
    double? unitCostOverride,
    double? sellingPriceOverride,
    String? notes,
  }) async {
    _requireLicense('تسجيل مخرجات المرحلة');
    final effectiveProduced = producedQuantity ?? plannedQuantity;
    return transaction(() async {
      int effectiveVariantId = variantId ?? 0;
      String? effectiveVariantName = variantName;

      // لو تم تحديد مقاس موجود، نقتبس اسمه
      if (variantId != null && variantId > 0) {
        final variant = await (select(productVariants)..where((v) => v.id.equals(variantId))).getSingleOrNull();
        if (variant != null && (effectiveVariantName == null || effectiveVariantName.isEmpty)) {
          effectiveVariantName = variant.name;
        }
      }

      int? targetId = id;
      // منع التكرار: إذا لم يُمرر id نبحث عن سطر موجود لنفس المقاس/المواصفة في نفس المرحلة لتحديثه
      if (targetId == null || targetId <= 0) {
        final existingOutputs = await getOutputsForStage(stageId);
        final match = existingOutputs.where((o) =>
          (variantId != null && variantId > 0 && o.variantId == variantId) ||
          (effectiveVariantName != null && effectiveVariantName.trim().isNotEmpty && o.variantName?.trim() == effectiveVariantName.trim())
        ).firstOrNull;
        if (match != null) {
          targetId = match.id;
        }
      }

      if (targetId != null && targetId > 0) {
        await (update(manufacturingStageOutputs)..where((o) => o.id.equals(targetId!))).write(
          ManufacturingStageOutputsCompanion(
            variantId: Value(variantId),
            variantName: Value(effectiveVariantName),
            plannedQuantity: Value(plannedQuantity),
            producedQuantity: Value(effectiveProduced),
            scrapQuantity: Value(scrapQuantity),
            unitCostOverride: Value(unitCostOverride),
            sellingPriceOverride: Value(sellingPriceOverride),
            notes: Value(notes),
          ),
        );
        await _recalcStageTotals(stageId);
        return targetId!;
      } else {
        final newId = await into(manufacturingStageOutputs).insert(
          ManufacturingStageOutputsCompanion.insert(
            stageId: stageId,
            manufacturingOrderId: orderId,
            productId: productId,
            variantId: Value(variantId),
            variantName: Value(effectiveVariantName),
            plannedQuantity: Value(plannedQuantity),
            producedQuantity: Value(effectiveProduced),
            scrapQuantity: Value(scrapQuantity),
            unitCostOverride: Value(unitCostOverride),
            sellingPriceOverride: Value(sellingPriceOverride),
            notes: Value(notes),
            createdAt: Value(DateTime.now()),
          ),
        );
        await _recalcStageTotals(stageId);
        return newId;
      }
    });
  }

  /// إنشاء مواصفة / جزء / مقاس جديد للمنتج الأب فوراً من داخل المرحلة وإضافته للمخرجات
  Future<int> createVariantAndAddToStage({
    required int stageId,
    required int orderId,
    required int productId,
    required String variantName,
    required double plannedQuantity,
    double? producedQuantity,
    double? sellingPrice,
  }) async {
    _requireLicense('إضافة مواصفة/مقاس جديد للمنتج');
    return transaction(() async {
      // 1. إنشاء المقاس في product_variants لو مش موجود
      final existingVariant = await (select(productVariants)
            ..where((v) => v.productId.equals(productId) & v.name.equals(variantName.trim())))
          .getSingleOrNull();

      final int variantId;
      if (existingVariant != null) {
        variantId = existingVariant.id;
      } else {
        variantId = await db.productVariantDao.insertVariant(
          ProductVariantsCompanion.insert(
            productId: productId,
            name: variantName.trim(),
            quantity: const Value(0),
            price: Value(sellingPrice),
          ),
        );
      }

      // 2. إضافته في مخرجات المرحلة مع حفظ الكمية في plannedQuantity و producedQuantity
      return upsertStageOutput(
        stageId: stageId,
        orderId: orderId,
        productId: productId,
        variantId: variantId,
        variantName: variantName.trim(),
        plannedQuantity: plannedQuantity,
        producedQuantity: producedQuantity ?? plannedQuantity,
        sellingPriceOverride: sellingPrice,
      );
    });
  }

  Future<void> deleteStageOutput(int outputId, int stageId) async {
    _requireLicense('حذف مخرج من المرحلة');
    await (delete(manufacturingStageOutputs)..where((o) => o.id.equals(outputId))).go();
    await _recalcStageTotals(stageId);
  }

  /// استرجاع كل مسميات المراحل المسجلة مسبقاً لاقتراحها كأزرار سريعة
  Future<List<String>> getDistinctStageNames() async {
    try {
      final q = selectOnly(manufacturingStages, distinct: true)
        ..addColumns([manufacturingStages.stageName]);
      final rows = await q.map((r) => r.read(manufacturingStages.stageName)!).get();
      return rows.where((name) => name.trim().isNotEmpty).toList();
    } catch (_) {
      return [];
    }
  }

  /// استرجاع كل مسميات المخرجات/المواصفات المسجلة مسبقاً لاقتراحها كأزرار سريعة
  Future<List<String>> getDistinctOutputNames() async {
    try {
      final q = selectOnly(manufacturingStageOutputs, distinct: true)
        ..addColumns([manufacturingStageOutputs.variantName]);
      final rows = await q.map((r) => r.read(manufacturingStageOutputs.variantName)).get();
      return rows.whereType<String>().where((name) => name.trim().isNotEmpty).toList();
    } catch (_) {
      return [];
    }
  }

  /// إعادة حساب إجمالي مخرجات المرحلة وهالكها تلقائياً من سطور المقاسات
  Future<void> _recalcStageTotals(int stageId) async {
    final outputs = await getOutputsForStage(stageId);
    final totalProduced = outputs.fold<double>(0.0, (sum, o) => sum + o.producedQuantity);
    final totalScrap = outputs.fold<double>(0.0, (sum, o) => sum + o.scrapQuantity);

    await (update(manufacturingStages)..where((s) => s.id.equals(stageId))).write(
      ManufacturingStagesCompanion(
        outputQuantity: Value(totalProduced),
        scrapQuantity: Value(totalScrap),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }
}
