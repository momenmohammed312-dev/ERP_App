import 'package:drift/drift.dart';

import 'customer_material_receipts_table.dart';
import 'manufacturing_orders_table.dart';
import 'manufacturing_stages_table.dart';
import 'inventory_movements_table.dart';
import 'manufacturing_tables.dart';
import 'product_table.dart';

/// Analytical record of actual material consumption during execution.
///
/// Rule (FEAT-039 Phase 1): the single source of truth is `StockMovement`
/// (`InventoryMovements` / `CustomerStockMovements`). `ConsumptionRecord` is
/// an analytical log linked to that movement via [stockMovementId]; it never
/// re-writes stock totals.
@DataClassName('ConsumptionRecord')
class ConsumptionRecords extends Table {
  @override
  String get tableName => 'consumption_records';

  IntColumn get id => integer().autoIncrement()();

  /// Link to ManufacturingOrders
  IntColumn get manufacturingOrderId =>
      integer().references(ManufacturingOrders, #id, onDelete: KeyAction.cascade)();

  /// Line in BOM — the recipe line consumed
  IntColumn? get bomItemId => integer().references(BomItems, #id, onDelete: KeyAction.setNull).nullable()();

  /// Operation instance (ManufacturingStages.id) — stage where consumed
  IntColumn? get operationId => integer().references(ManufacturingStages, #id, onDelete: KeyAction.setNull).nullable()();

  /// Material product (factory or customer-owned)
  IntColumn get materialProductId => integer().references(Products, #id, onDelete: KeyAction.cascade)();

  /// 'customer_owned' | 'factory_owned'
  TextColumn get ownershipType => text().withLength(min: 1, max: 32)();

  /// Snapshot of unit
  TextColumn get unit => text().nullable()();

  /// Planned qty (from BOM)
  RealColumn get plannedQty => real().nullable()();

  /// Actual qty (from stock movement)
  RealColumn get actualQty => real().nullable()();

  /// Unit cost snapshot
  RealColumn get unitCostSnapshot => real().nullable()();


  /// Link to the factory inventory stock movement that realized this consumption
  IntColumn? get stockMovementId => integer().references(InventoryMovements, #id, onDelete: KeyAction.setNull).nullable()();

  /// Link to customer custody movement when ownershipType == 'customer_owned' (v83)
  IntColumn? get customerStockMovementId => integer()
      .references(CustomerStockMovements, #id, onDelete: KeyAction.setNull)
      .nullable()();

  DateTimeColumn get performedAt => dateTime().withDefault(currentDateAndTime)();
}
