import 'package:drift/drift.dart';

import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_inspections_table.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_orders_table.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_stages_table.dart';
import 'package:pos_offline_desktop/core/database/tables/product_table.dart';

part 'manufacturing_inspection_dao.g.dart';

/// DAO for internal supervisor/worker quality inspections (FEAT-039 Phase 4 — D-07, D-10).
@DriftAccessor(tables: [
  ManufacturingInspections,
  ManufacturingOrders,
  ManufacturingStages,
  Products,
])
class ManufacturingInspectionDao extends DatabaseAccessor<AppDatabase>
    with _$ManufacturingInspectionDaoMixin {
  ManufacturingInspectionDao(super.db);

  Future<ManufacturingInspection> recordInspection({
    required int orderId,
    int? stageId,
    required int productId,
    required String inspectedBy,
    required String result,
    required double quantity,
    String? dispositionNote,
    String? photoRefs,
  }) {
    return transaction(() async {
      if (inspectedBy.trim().isEmpty) {
        throw ArgumentError('inspectedBy is required');
      }
      if (!InspectionResult.isValid(result)) {
        throw ArgumentError(
          'Invalid inspection result "$result". Allowed: ${InspectionResult.all.join(', ')}',
        );
      }
      if (quantity <= 0) {
        throw ArgumentError.value(quantity, 'quantity', 'Quantity must be > 0');
      }

      final order = await (select(manufacturingOrders)
            ..where((o) => o.id.equals(orderId)))
          .getSingleOrNull();
      if (order == null) {
        throw ArgumentError('ManufacturingOrder #$orderId not found');
      }

      final product = await (select(products)
            ..where((p) => p.id.equals(productId)))
          .getSingleOrNull();
      if (product == null) {
        throw ArgumentError('Product #$productId not found');
      }

      final id = await into(manufacturingInspections).insert(
        ManufacturingInspectionsCompanion.insert(
          manufacturingOrderId: orderId,
          stageId: Value(stageId),
          productId: productId,
          inspectedBy: inspectedBy.trim(),
          result: result,
          quantity: quantity,
          dispositionNote: Value(dispositionNote),
          photoRefs: Value(photoRefs),
        ),
      );
      return (select(manufacturingInspections)..where((i) => i.id.equals(id)))
          .getSingle();
    });
  }

  Future<List<ManufacturingInspection>> getForOrder(int orderId) {
    return (select(manufacturingInspections)
          ..where((i) => i.manufacturingOrderId.equals(orderId))
          ..orderBy([(i) => OrderingTerm.desc(i.id)]))
        .get();
  }

  Stream<List<ManufacturingInspection>> watchForOrder(int orderId) {
    return (select(manufacturingInspections)
          ..where((i) => i.manufacturingOrderId.equals(orderId))
          ..orderBy([(i) => OrderingTerm.desc(i.id)]))
        .watch();
  }

  Future<List<ManufacturingInspection>> getInRange({
    required DateTime start,
    required DateTime end,
  }) {
    return (select(manufacturingInspections)
          ..where(
            (i) =>
                i.inspectedAt.isBiggerOrEqualValue(start) &
                i.inspectedAt.isSmallerOrEqualValue(end),
          )
          ..orderBy([(i) => OrderingTerm.desc(i.inspectedAt)]))
        .get();
  }
}
