import 'package:drift/drift.dart';
import 'customer_table.dart';
import 'invoice_table.dart';
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

  /// ── Phase B1: Manufacturing-for-others additions (v76) ──
  /// 'internal' | 'for_others' | 'mixed' | 'service_only'
  TextColumn get orderType =>
      text().nullable().withDefault(const Constant('internal'))();

  /// Customer who owns the materials / ordered the manufacturing (UUID string)
  TextColumn get customerId =>
      text().nullable().references(Customers, #id)();

  /// 'inclusive' (piece includes service) | 'separate' (service fee + materials)
  TextColumn get pricingMode =>
      text().nullable().withDefault(const Constant('inclusive'))();

  /// 'customer_bears' | 'factory_pays_piece_value' | 'factory_bears_labour_only' | 'factory_replaces_piece'
  TextColumn get scrapPolicy =>
      text().nullable().withDefault(const Constant('customer_bears'))();

  /// Agreed valuation per customer piece (for scrap compensation calculations)
  RealColumn get pieceUnitValue =>
      real().nullable().withDefault(const Constant(0.0))();

  /// Service fee per finished unit
  RealColumn get serviceUnitPrice =>
      real().nullable().withDefault(const Constant(0.0))();

  /// Link to generated service invoice in invoices table
  IntColumn get invoiceId =>
      integer().nullable().references(Invoices, #id)();

  /// 'undelivered' | 'partially_delivered' | 'delivered'
  TextColumn get deliveryStatus =>
      text().nullable().withDefault(const Constant('undelivered'))();

  TextColumn get cancelReason => text().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get createdBy => text().nullable()();

  /// ── Phase B1.5: Job Work (for_others) direct input tracking (v77) ──
  IntColumn get inputProductId => integer().nullable().references(Products, #id)();
  TextColumn get inputColor => text().nullable()();
  TextColumn get inputSize => text().nullable()();
  RealColumn get inputQuantity => real().nullable()();

  /// ── FEAT-026: Multi-stage routing & pricing margins (v81) ──
  TextColumn get currentStageName => text().nullable()();
  RealColumn get targetMarginPercent =>
      real().nullable().withDefault(const Constant(0.0))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
