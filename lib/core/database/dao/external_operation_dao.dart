import 'package:drift/drift.dart';

import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/tables/external_operation_records.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_orders_table.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_stages_table.dart';

part 'external_operation_dao.g.dart';

/// DAO for external/vendor routed work (FEAT-039 Phase 1 — D-06, plan §3.1).
///
/// Reconciliation identity for vendored work (table comment):
/// `sentQty = receivedQty + scrapQty + atVendor + sold` —
/// [atVendorQuantityForOrder] returns the `atVendor` term.
@DriftAccessor(tables: [
  ExternalOperationRecords,
  ManufacturingOrders,
  ManufacturingStages,
])
class ExternalOperationDao extends DatabaseAccessor<AppDatabase>
    with _$ExternalOperationDaoMixin {
  ExternalOperationDao(super.db);

  /// Records one routed external operation with pre-write validation
  /// (vendor required, quantities non-negative, can't scrape more than sent).
  Future<int> insertExternalOperationRecord({
    required int manufacturingOrderId,
    int? operationId,
    required String vendor,
    required double sentQty,
    double receivedQty = 0.0,
    double scrapQty = 0.0,
    double cost = 0.0,
    DateTime? sentAt,
    DateTime? receivedAt,
  }) async {
    if (vendor.trim().isEmpty) {
      throw ArgumentError('vendor is required for an external operation');
    }
    if (sentQty <= 0) {
      throw ArgumentError('sentQty must be > 0');
    }
    if (receivedQty < 0 || scrapQty < 0 || cost < 0) {
      throw ArgumentError('receivedQty/scrapQty/cost must be ≥ 0');
    }
    if (receivedQty + scrapQty > sentQty + 0.01) {
      throw StateError('received + scraped cannot exceed sent');
    }
    return into(db.externalOperationRecords).insert(
      ExternalOperationRecordsCompanion.insert(
        manufacturingOrderId: manufacturingOrderId,
        operationId: Value(operationId),
        vendor: vendor.trim(),
        sentQty: Value(sentQty),
        receivedQty: Value(receivedQty),
        scrapQty: Value(scrapQty),
        cost: Value(cost),
        sentAt: Value(sentAt),
        receivedAt: Value(receivedAt),
      ),
    );
  }

  /// All external operations of one order (oldest first).
  Future<List<ExternalOperationRecord>> getForOrder(int orderId) {
    return (select(db.externalOperationRecords)
          ..where((t) => t.manufacturingOrderId.equals(orderId))
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .get();
  }

  /// Σ sentQty — quantity dispatched to vendors for the order.
  Future<double> totalSentForOrder(int orderId) async {
    return (await getForOrder(orderId)).fold<double>(
      0.0,
      (sum, r) => sum + r.sentQty,
    );
  }

  /// Σ receivedQty — quantity back at the factory.
  Future<double> totalReceivedForOrder(int orderId) async {
    return (await getForOrder(orderId)).fold<double>(
      0.0,
      (sum, r) => sum + r.receivedQty,
    );
  }

  /// Σ scrapQty — scrapped while at the vendor.
  Future<double> totalScrapForOrder(int orderId) async {
    return (await getForOrder(orderId)).fold<double>(
      0.0,
      (sum, r) => sum + r.scrapQty,
    );
  }

  /// Σ (sent − received − scrap) — quantity still outside the factory
  /// (the `atVendor` term of the §3.1 reconciliation identity).
  Future<double> atVendorQuantityForOrder(int orderId) async {
    final rows = await getForOrder(orderId);
    return rows.fold<double>(
      0.0,
      (sum, r) => sum + (r.sentQty - r.receivedQty - r.scrapQty),
    );
  }

  Stream<List<ExternalOperationRecord>> watchForOrder(int orderId) {
    return (select(db.externalOperationRecords)
          ..where((t) => t.manufacturingOrderId.equals(orderId))
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .watch();
  }
}
