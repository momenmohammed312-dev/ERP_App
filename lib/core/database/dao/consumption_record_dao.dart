import 'package:drift/drift.dart';

import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/tables/consumption_record.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_orders_table.dart';

part 'consumption_record_dao.g.dart';

/// DAO for the analytical consumption log (FEAT-039 Phase 1 — D-03, plan §3).
///
/// **Single source of truth rule:** [InventoryMovement] is the actual stock
/// change; [ConsumptionRecord] is the analytic line linked to it via
/// [ConsumptionRecord.stockMovementId]. Inserting here never re-writes stock
/// totals — the movement is written by the caller (stage completion / D-03).
@DriftAccessor(tables: [
  ConsumptionRecords,
  ManufacturingOrders,
])
class ConsumptionRecordDao extends DatabaseAccessor<AppDatabase>
    with _$ConsumptionRecordDaoMixin {
  ConsumptionRecordDao(super.db);

  /// Records one consumption line and returns the new row's id.
  ///
  /// [ownershipType] — `'customer_owned'` | `'factory_owned'` (table comment).
  /// [plannedQty]/[actualQty]/[unitCostSnapshot] — D-03 estimated-then-
  /// reconciled: the record keeps the BOM plan line, the actual qty and the
  /// frozen unit cost snapshot; the stock movement remains the truth.
  Future<int> insertConsumptionRecord({
    required int manufacturingOrderId,
    int? bomItemId,
    int? operationId,
    required int materialProductId,
    required String ownershipType,
    String? unit,
    double? plannedQty,
    double? actualQty,
    double? unitCostSnapshot,
    int? stockMovementId,
    int? customerStockMovementId,
    DateTime? performedAt,
  }) {
    return into(db.consumptionRecords).insert(
      ConsumptionRecordsCompanion.insert(
        manufacturingOrderId: manufacturingOrderId,
        bomItemId: Value(bomItemId),
        operationId: Value(operationId),
        materialProductId: materialProductId,
        ownershipType: ownershipType,
        unit: Value(unit),
        plannedQty: Value(plannedQty),
        actualQty: Value(actualQty),
        unitCostSnapshot: Value(unitCostSnapshot),
        stockMovementId: Value(stockMovementId),
        customerStockMovementId: Value(customerStockMovementId),
        performedAt: Value(performedAt ?? DateTime.now()),
      ),
    );
  }

  /// All consumption rows of one order (oldest first).
  Future<List<ConsumptionRecord>> getForOrder(int orderId) {
    return (select(db.consumptionRecords)
          ..where((t) => t.manufacturingOrderId.equals(orderId))
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .get();
  }

  Stream<List<ConsumptionRecord>> watchForOrder(int orderId) {
    return (select(db.consumptionRecords)
          ..where((t) => t.manufacturingOrderId.equals(orderId))
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .watch();
  }

  /// Σ actualQty per material product of one order (optionally filtered by
  /// ownership type — the customer equation uses `'customer_owned'`).
  Future<Map<int, double>> consumedByProductForOrder(
    int orderId, {
    String? ownershipType,
  }) async {
    final query = select(db.consumptionRecords)
      ..where((t) => t.manufacturingOrderId.equals(orderId));
    if (ownershipType != null) {
      query.where((t) => t.ownershipType.equals(ownershipType));
    }
    final rows = await query.get();
    final map = <int, double>{};
    for (final r in rows) {
      map[r.materialProductId] =
          (map[r.materialProductId] ?? 0.0) + (r.actualQty ?? 0.0);
    }
    return map;
  }

  /// Σ actualQty of one order (optionally filtered by ownership type).
  Future<double> totalConsumedForOrder(
    int orderId, {
    String? ownershipType,
  }) async {
    final query = select(db.consumptionRecords)
      ..where((t) => t.manufacturingOrderId.equals(orderId));
    if (ownershipType != null) {
      query.where((t) => t.ownershipType.equals(ownershipType));
    }
    final rows = await query.get();
    return rows.fold<double>(0.0, (sum, r) => sum + (r.actualQty ?? 0.0));
  }
}
