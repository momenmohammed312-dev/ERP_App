import 'package:drift/drift.dart';

import 'manufacturing_orders_table.dart';
import 'manufacturing_stages_table.dart';
import 'product_table.dart';

/// Quality inspection outcome constants (FEAT-039 Phase 4 — D-07).
abstract final class InspectionResult {
  static const accepted = 'accepted';
  static const rejectedForRework = 'rejected_for_rework';
  static const secondGrade = 'second_grade';

  static const all = [accepted, rejectedForRework, secondGrade];

  static bool isValid(String? val) => val != null && all.contains(val);

  static String label(String val) {
    switch (val) {
      case accepted:
        return 'مقبول';
      case rejectedForRework:
        return 'مرفوض (إعادة تشغيل)';
      case secondGrade:
        return 'فرز ثاني';
      default:
        return val;
    }
  }
}

/// Internal supervisor/worker quality inspection audit record (FEAT-039 Phase 4 — D-07, D-10).
///
/// Audit-only (no tolerance engine); photos and internal notes never ship to customer documents.
@DataClassName('ManufacturingInspection')
class ManufacturingInspections extends Table {
  @override
  String get tableName => 'manufacturing_inspections';

  IntColumn get id => integer().autoIncrement()();

  IntColumn get manufacturingOrderId =>
      integer().references(ManufacturingOrders, #id, onDelete: KeyAction.cascade)();

  IntColumn? get stageId => integer()
      .references(ManufacturingStages, #id, onDelete: KeyAction.setNull)
      .nullable()();

  IntColumn get productId =>
      integer().references(Products, #id, onDelete: KeyAction.cascade)();

  DateTimeColumn get inspectedAt => dateTime().withDefault(currentDateAndTime)();

  /// Free text inspector name / role (D-07)
  TextColumn get inspectedBy => text().withLength(min: 1, max: 255)();

  /// One of [InspectionResult]
  TextColumn get result => text().withLength(min: 1, max: 32)();

  RealColumn get quantity => real()();
  TextColumn get dispositionNote => text().nullable()();

  /// Internal-only comma-separated or JSON disk paths (D-10)
  TextColumn get photoRefs => text().nullable()();
}
