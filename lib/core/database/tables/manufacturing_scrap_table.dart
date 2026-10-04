import 'package:drift/drift.dart';
import 'manufacturing_orders_table.dart';
import 'product_table.dart';
import 'manufacturing_tables.dart';

/// Reasons a production line can be written off as scrap.
///
/// Fixed vocabulary so a scrap line is auditable: you can always answer "why
/// was this thrown away and who signed it off". OQ2 settled these six for
/// factory-owned material; customer-owned material adds a separate
/// disposition vocabulary in Phase B and must not reuse these.
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

/// A written-off quantity from a completed manufacturing order.
///
/// Scrap is recorded rather than folded into the recipe's waste allowance.
/// waste_percentage says what to *plan* for; this says what actually happened.
/// Keeping both is the point — the variance between them is the number worth
/// acting on. A BOM that silently absorbs waste cannot tell a good unit from a
/// scrapped one, which makes unit cost fiction.
@DataClassName('ManufacturingScrap')
class ManufacturingScraps extends Table {
  // Drift would pluralise the class name to manufacturing_scraps. Pin the SQL
  // name to the singular so it matches the other manufacturing tables' naming
  // intent and the documented schema contract in the migration tests.
  @override
  String get tableName => 'manufacturing_scrap';

  IntColumn get id => integer().autoIncrement()();

  IntColumn get manufacturingOrderId =>
      integer().references(ManufacturingOrders, #id, onDelete: KeyAction.cascade)();

  /// What was thrown away. May be a raw material or the finished good itself;
  /// use [bomItemId] to tell which recipe line it came from.
  IntColumn get productId => integer().references(Products, #id)();

  /// The recipe line, when the scrap came from raw material.
  IntColumn get bomItemId =>
      integer().references(BomItems, #id, onDelete: KeyAction.setNull).nullable()();

  /// How many units were written off. REAL because a recipe can be fractional
  /// (0.2 litre), and the record must not lose that precision.
  RealColumn get quantity => real()();

  /// One of [ManufacturingScrapReason].
  TextColumn get reason => text()();

  /// Who is accountable. Required and non-blank — a scrap line with no owner
  /// is not auditable.
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

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}