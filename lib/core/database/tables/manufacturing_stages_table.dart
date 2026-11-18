import 'package:drift/drift.dart';
import 'manufacturing_orders_table.dart';
import 'product_table.dart';
import 'product_variants_table.dart';

/// Status constants for [ManufacturingStages].
abstract final class ManufacturingStageStatus {
  static const pending = 'pending';
  static const inProgress = 'in_progress';
  static const completed = 'completed';

  static const all = [pending, inProgress, completed];
}

/// Manufacturing Stage / Work Order Routing — تتبع مراحل أمر التصنيع (قص، تقفيل، كي وتغليف...).
@DataClassName('ManufacturingStage')
class ManufacturingStages extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get manufacturingOrderId =>
      integer().references(ManufacturingOrders, #id, onDelete: KeyAction.cascade)();

  /// اسم المرحلة (مثلاً: القص، الخياطة والتقفيل، الكي والتغليف، الفحص والجودة)
  TextColumn get stageName => text().withLength(min: 1, max: 255)();

  /// ترتيب المرحلة (1, 2, 3...)
  IntColumn get stageOrder => integer().withDefault(const Constant(1))();

  /// pending | in_progress | completed
  TextColumn get status =>
      text().withDefault(const Constant(ManufacturingStageStatus.pending))();

  /// كمية المدخلات المستلمة في هذه المرحلة
  RealColumn get inputQuantity => real().withDefault(const Constant(0.0))();

  /// كمية المخرجات التامة السليمة من هذه المرحلة
  RealColumn get outputQuantity => real().withDefault(const Constant(0.0))();

  /// كمية الهالك والتوالف في هذه المرحلة
  RealColumn get scrapQuantity => real().withDefault(const Constant(0.0))();

  /// تكلفة تشغيل/مصنعية المرحلة (إضافية على تكلفة الخامات)
  RealColumn get stageCost => real().withDefault(const Constant(0.0))();

  /// المسؤول أو خط الإنتاج / الورشة
  TextColumn get assignedTo => text().nullable()();

  TextColumn get notes => text().nullable()();

  DateTimeColumn get startedAt => dateTime().nullable()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// Stage Outputs by Variant/Size — تفصيل مخرجات ومقاسات المنتج داخل المرحلة
@DataClassName('ManufacturingStageOutput')
class ManufacturingStageOutputs extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get stageId =>
      integer().references(ManufacturingStages, #id, onDelete: KeyAction.cascade)();

  IntColumn get manufacturingOrderId =>
      integer().references(ManufacturingOrders, #id, onDelete: KeyAction.cascade)();

  /// المنتج الأب التابع له المقاس
  IntColumn get productId => integer().references(Products, #id)();

  /// معرف الصنف / المقاس في جدول ProductVariants (nullable لو منتج بدون مقاسات)
  IntColumn get variantId =>
      integer().nullable().references(ProductVariants, #id, onDelete: KeyAction.setNull)();

  /// لقطة لاسم المقاس/اللون وقت الإنتاج (مثل: S, M, L, XL, أو أبيض - قطن)
  TextColumn get variantName => text().nullable()();

  /// الكمية المخططة لهذا المقاس
  RealColumn get plannedQuantity => real().withDefault(const Constant(0.0))();

  /// الكمية المنتجة السليمة
  RealColumn get producedQuantity => real().withDefault(const Constant(0.0))();

  /// كمية الهالك من هذا المقاس
  RealColumn get scrapQuantity => real().withDefault(const Constant(0.0))();

  /// تكلفة تقديرية للوحدة من هذا المقاس
  RealColumn get unitCostOverride => real().nullable()();

  /// سعر بيع مقترح للوحدة من هذا المقاس
  RealColumn get sellingPriceOverride => real().nullable()();

  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
