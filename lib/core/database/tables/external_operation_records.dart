import 'package:drift/drift.dart';

import 'manufacturing_orders_table.dart';
import 'manufacturing_stages_table.dart';

/// External Operation Record — routed work done outside the factory
/// (vendor, outsourced processing, foundry, etc.) — FEAT-039 Phase 1 D-06.
///
/// Quantity reconciliation: `sentQty = receivedQty + scrapQty + atVendor + sold`.
@DataClassName('ExternalOperationRecord')
class ExternalOperationRecords extends Table {
  @override
  String get tableName => 'external_operation_records';

  IntColumn get id => integer().autoIncrement()();

  IntColumn get manufacturingOrderId =>
      integer().references(ManufacturingOrders, #id, onDelete: KeyAction.cascade)();

  IntColumn? get operationId => integer().references(ManufacturingStages, #id, onDelete: KeyAction.setNull).nullable()();

  /// Vendor/business name (NOT NULL — someone owns the work)
  TextColumn get vendor => text().withLength(min: 1, max: 255)();

  /// Quantity sent to the vendor
  RealColumn get sentQty => real().withDefault(const Constant(0.0))();

  /// Quantity received back (excluding scrap)
  RealColumn get receivedQty => real().withDefault(const Constant(0.0))();

  /// Quantity scrapped on return
  RealColumn get scrapQty => real().withDefault(const Constant(0.0))();

  /// External processing cost (incl. vendee fees, freight)
  RealColumn get cost => real().withDefault(const Constant(0.0))();

  DateTimeColumn get sentAt => dateTime().nullable()();
  DateTimeColumn get receivedAt => dateTime().nullable()();
}
