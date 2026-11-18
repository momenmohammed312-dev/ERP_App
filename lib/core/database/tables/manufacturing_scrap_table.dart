import 'package:drift/drift.dart';
import 'manufacturing_orders_table.dart';
import 'product_table.dart';
import 'manufacturing_tables.dart';

/// Reasons a production line can be written off as scrap.
abstract final class ManufacturingScrapReason {
  static const defective = 'defective';
  static const materialShortage = 'material_shortage';
  static const processError = 'process_error';
  static const wrongSpec = 'wrong_spec';
  static const expired = 'expired';
  static const other = 'other';

  static const all = [
    defective,
    materialShortage,
    processError,
    wrongSpec,
    expired,
    other,
  ];

  static bool isValid(String? reason) => reason != null && all.contains(reason);

  static String label(String reason) {
    switch (reason) {
      case defective:
        return 'تالف';
      case materialShortage:
        return 'عجز في الخام';
      case processError:
        return 'خطأ في التصنيع';
      case wrongSpec:
        return 'مواصفة غلط';
      case expired:
        return 'منتهي الصلاحية';
      case other:
        return 'أخرى';
      default:
        return reason;
    }
  }
}

/// A written-off quantity from a manufacturing order or stage.
@DataClassName('ManufacturingScrap')
class ManufacturingScraps extends Table {
  @override
  String get tableName => 'manufacturing_scrap';

  IntColumn get id => integer().autoIncrement()();

  IntColumn get manufacturingOrderId =>
      integer().references(ManufacturingOrders, #id, onDelete: KeyAction.cascade)();

  /// What was thrown away or set aside. May be a raw material or the finished good itself.
  IntColumn get productId => integer().references(Products, #id)();

  /// The recipe line, when the scrap came from raw material.
  IntColumn get bomItemId =>
      integer().references(BomItems, #id, onDelete: KeyAction.setNull).nullable()();

  /// How many units were written off.
  RealColumn get quantity => real()();

  /// One of [ManufacturingScrapReason].
  TextColumn get reason => text()();

  /// Who is accountable.
  TextColumn get responsibleParty => text()();

  /// Free text, typically an authorisation reference for the write-off.
  TextColumn get dispositionNote => text().nullable()();

  /// ── Phase B1: Manufacturing-for-others additions (v76) ──
  /// 'factory' | 'customer'
  TextColumn get faultParty =>
      text().nullable().withDefault(const Constant('factory'))();

  /// 'deducted_from_invoice' | 'replaced' | 'labour_waived' | 'none'
  TextColumn get compensationAction => text().nullable()();

  /// Amount to credit customer or financial loss
  RealColumn get compensationAmount =>
      real().nullable().withDefault(const Constant(0.0))();

  TextColumn get performedBy => text().nullable()();

  /// ── FEAT-026: Multi-stage, Variants & Sellable Scrap (v81) ──
  IntColumn get stageId => integer().nullable()();
  IntColumn get variantId => integer().nullable()();
  TextColumn get variantName => text().nullable()();
  BoolColumn get isSellable =>
      boolean().nullable().withDefault(const Constant(false))();
  RealColumn get estimatedSellPrice =>
      real().nullable().withDefault(const Constant(0.0))();
  IntColumn get scrapProductId =>
      integer().nullable().references(Products, #id, onDelete: KeyAction.setNull)();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
