import 'package:drift/drift.dart';
import 'manufacturing_orders_table.dart';

/// Cost type constants for [ManufacturingCostComponents].
abstract final class ManufacturingCostType {
  static const fixed = 'fixed';
  static const percentage = 'percentage';
  static const perUnit = 'per_unit';

  static const all = [fixed, percentage, perUnit];

  static String label(String type) {
    switch (type) {
      case fixed:
        return 'مبلغ ثابت';
      case percentage:
        return 'نسبة %';
      case perUnit:
        return 'لكل وحدة';
      default:
        return type;
    }
  }
}

/// Manufacturing cost component — child of a Manufacturing Order.
/// Configuration is stored in [value]; [computedAmount] is frozen on completion.
@DataClassName('ManufacturingCostComponent')
class ManufacturingCostComponents extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get manufacturingOrderId =>
      integer().references(ManufacturingOrders, #id, onDelete: KeyAction.cascade)();

  /// e.g. Labor, Electricity, Packaging
  TextColumn get name => text().withLength(min: 1, max: 255)();

  /// 'fixed' | 'percentage' | 'per_unit'
  TextColumn get costType => text()();

  /// Meaning depends on costType: flat EGP, percent, or EGP per unit
  RealColumn get value => real()();

  /// Snapshot computed on MO completion; null until then
  RealColumn get computedAmount => real().nullable()();

  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  TextColumn get notes => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
