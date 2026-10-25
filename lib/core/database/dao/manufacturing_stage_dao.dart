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

  /// إضافة أو تحديث سطر مخرجات مقاس داخل مرحلة
  Future<int> upsertStageOutput({
    int? id,
    required int stageId,
    required int orderId,
    required int productId,
    int? variantId,
    String? variantName,
    required double plannedQuantity,
    double producedQuantity = 0.0,
    double scrapQuantity = 0.0,
    double? unitCostOverride,
    double? sellingPriceOverride,
    String? notes,
  }) async {
    _requireLicense('تسجيل مخرجات المقاسات');
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

      if (id != null && id > 0) {
        await (update(manufacturingStageOutputs)..where((o) => o.id.equals(id))).write(
          ManufacturingStageOutputsCompanion(
            variantId: Value(variantId),
            variantName: Value(effectiveVariantName),
            plannedQuantity: Value(plannedQuantity),
            producedQuantity: Value(producedQuantity),
            scrapQuantity: Value(scrapQuantity),
            unitCostOverride: Value(unitCostOverride),
            sellingPriceOverride: Value(sellingPriceOverride),
            notes: Value(notes),
          ),
        );
        await _recalcStageTotals(stageId);
        return id;
      } else {
        final newId = await into(manufacturingStageOutputs).insert(
          ManufacturingStageOutputsCompanion.insert(
            stageId: stageId,
            manufacturingOrderId: orderId,
            productId: productId,
            variantId: Value(variantId),
            variantName: Value(effectiveVariantName),
            plannedQuantity: Value(plannedQuantity),
            producedQuantity: Value(producedQuantity),
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

  /// إنشاء مقاس/صنف جديد للمنتج الأب فوراً من داخل المرحلة وإضافته للمخرجات
  Future<int> createVariantAndAddToStage({
    required int stageId,
    required int orderId,
    required int productId,
    required String variantName,
    required double plannedQuantity,
    double? sellingPrice,
  }) async {
    _requireLicense('إضافة مقاس جديد للمنتج');
    return transaction(() async {
      // 1. إنشاء المقاس في product_variants
      final variantId = await db.productVariantDao.insertVariant(
        ProductVariantsCompanion.insert(
          productId: productId,
          name: variantName,
          quantity: const Value(0),
          price: Value(sellingPrice),
        ),
      );

      // 2. إضافته في مخرجات المرحلة
      return upsertStageOutput(
        stageId: stageId,
        orderId: orderId,
        productId: productId,
        variantId: variantId,
        variantName: variantName,
        plannedQuantity: plannedQuantity,
        sellingPriceOverride: sellingPrice,
      );
    });
  }

  Future<void> deleteStageOutput(int outputId, int stageId) async {
    _requireLicense('حذف مخرج من المرحلة');
    await (delete(manufacturingStageOutputs)..where((o) => o.id.equals(outputId))).go();
    await _recalcStageTotals(stageId);
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
