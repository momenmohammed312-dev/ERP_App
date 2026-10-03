import 'package:drift/drift.dart';
import 'product_table.dart';
import 'manufacturing_tables.dart';

/// Status constants for [ManufacturingOrders].
abstract final class ManufacturingOrderStatus {
  static const planned = 'planned';
  static const inProgress = 'in_progress';
  static const completed = 'completed';
  static const cancelled = 'cancelled';

  static const all = [planned, inProgress, completed, cancelled];
}

/// Manufacturing Order — production document linking a BOM to a planned quantity.
/// Phase 3: status transitions only (no stock movement).
@DataClassName('ManufacturingOrder')
class ManufacturingOrders extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Unique human-readable number, e.g. MO-123456789
  TextColumn get orderNumber => text().unique()();

  /// Which BOM this order is executing
  IntColumn get bomId => integer().references(BillOfMaterials, #id)();

  /// Snapshot of BillOfMaterials.finishedProductId for query convenience/history
  IntColumn get finishedProductId => integer().references(Products, #id)();

  /// How many finished units this order intends to produce
  RealColumn get plannedQuantity => real()();

  /// Filled in on completion (default 0 until completed)
  RealColumn get producedQuantity => real().withDefault(const Constant(0))();

  /// planned | in_progress | completed | cancelled
  TextColumn get status => text().withDefault(const Constant(ManufacturingOrderStatus.planned))();

  DateTimeColumn get plannedDate => dateTime().nullable()();
  DateTimeColumn get startedAt => dateTime().nullable()();
  DateTimeColumn get completedAt => dateTime().nullable()();
  DateTimeColumn get cancelledAt => dateTime().nullable()();

  TextColumn get cancelReason => text().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get createdBy => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
