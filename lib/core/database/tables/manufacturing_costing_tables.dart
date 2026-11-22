import 'package:drift/drift.dart';

import 'manufacturing_orders_table.dart';
import 'product_table.dart';

/// Frozen internal cost & margin snapshot per manufacturing order (FEAT-039 Phase 3 — §5, D-11).
///
/// Customer-owned materials always contribute `0.0` to factory material cost.
/// Once frozen, `generateServiceInvoice` and historical reports preserve these numbers.
@DataClassName('ManufacturingCostSnapshot')
class ManufacturingCostSnapshots extends Table {
  @override
  String get tableName => 'manufacturing_cost_snapshots';

  IntColumn get id => integer().autoIncrement()();

  IntColumn get manufacturingOrderId =>
      integer().references(ManufacturingOrders, #id, onDelete: KeyAction.cascade)();

  RealColumn get materialCost => real().withDefault(const Constant(0.0))();
  RealColumn get laborCost => real().withDefault(const Constant(0.0))();
  RealColumn get machineCost => real().withDefault(const Constant(0.0))();
  RealColumn get externalCost => real().withDefault(const Constant(0.0))();
  RealColumn get otherCost => real().withDefault(const Constant(0.0))();
  RealColumn get totalActualCost => real().withDefault(const Constant(0.0))();

  RealColumn get plannedCost => real().withDefault(const Constant(0.0))();
  RealColumn get variance => real().withDefault(const Constant(0.0))();

  RealColumn get deliveredRevenue => real().withDefault(const Constant(0.0))();
  RealColumn get extraMaterialsRevenue => real().withDefault(const Constant(0.0))();
  RealColumn get scrapCompensation => real().withDefault(const Constant(0.0))();
  RealColumn get actualMargin => real().withDefault(const Constant(0.0))();

  BoolColumn get isFrozen => boolean().withDefault(const Constant(true))();
  DateTimeColumn get snapshotAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get notes => text().nullable()();
}

/// Customer-approved extra factory material charge on `for_others`/`mixed` orders
/// (FEAT-039 Phase 3 — D-04, D-05, D-08).
///
/// Allowed even in `pricingMode = 'inclusive'` ONLY when `status == 'approved'`
/// with explicit customer authorization audit fields.
@DataClassName('ExtraMaterialApproval')
class ExtraMaterialApprovals extends Table {
  @override
  String get tableName => 'extra_material_approvals';

  IntColumn get id => integer().autoIncrement()();

  IntColumn get manufacturingOrderId =>
      integer().references(ManufacturingOrders, #id, onDelete: KeyAction.cascade)();

  IntColumn get productId =>
      integer().references(Products, #id, onDelete: KeyAction.cascade)();

  RealColumn get quantity => real()();

  /// Actual unit cost frozen from Products.costPrice (D-08 — never uses current selling price)
  RealColumn get unitCostSnapshot => real().withDefault(const Constant(0.0))();

  /// Optional markup margin (default 0.0 per D-08)
  RealColumn get marginPercent => real().withDefault(const Constant(0.0))();

  /// Computed or explicitly approved amount billed on service invoice
  RealColumn get approvedAmount => real().withDefault(const Constant(0.0))();

  /// 'pending' | 'approved' | 'rejected'
  TextColumn get status => text().withDefault(const Constant('pending'))();

  TextColumn get requestedBy => text().withLength(min: 1, max: 255)();
  TextColumn get approvedBy => text().nullable()();
  DateTimeColumn get approvedAt => dateTime().nullable()();
  TextColumn get authorizationRef => text().nullable()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
