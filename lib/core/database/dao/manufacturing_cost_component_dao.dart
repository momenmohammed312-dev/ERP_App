import 'package:drift/drift.dart';

import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_cost_components_table.dart';

part 'manufacturing_cost_component_dao.g.dart';

@DriftAccessor(tables: [ManufacturingCostComponents])
class ManufacturingCostComponentDao extends DatabaseAccessor<AppDatabase>
    with _$ManufacturingCostComponentDaoMixin {
  ManufacturingCostComponentDao(super.db);

  Future<List<ManufacturingCostComponent>> getForOrder(int orderId) =>
      (select(manufacturingCostComponents)
            ..where((c) => c.manufacturingOrderId.equals(orderId))
            ..orderBy([(c) => OrderingTerm.asc(c.sortOrder), (c) => OrderingTerm.asc(c.id)]))
          .get();

  Stream<List<ManufacturingCostComponent>> watchForOrder(int orderId) =>
      (select(manufacturingCostComponents)
            ..where((c) => c.manufacturingOrderId.equals(orderId))
            ..orderBy([(c) => OrderingTerm.asc(c.sortOrder), (c) => OrderingTerm.asc(c.id)]))
          .watch();

  Future<ManufacturingCostComponent?> getById(int id) =>
      (select(manufacturingCostComponents)..where((c) => c.id.equals(id))).getSingleOrNull();

  Future<int> insertComponent(ManufacturingCostComponentsCompanion entry) =>
      into(manufacturingCostComponents).insert(entry);

  Future<bool> updateComponent(ManufacturingCostComponent comp) =>
      update(manufacturingCostComponents).replace(comp);

  Future<void> deleteComponent(int id) =>
      (delete(manufacturingCostComponents)..where((c) => c.id.equals(id))).go();

  Future<void> deleteAllForOrder(int orderId) =>
      (delete(manufacturingCostComponents)..where((c) => c.manufacturingOrderId.equals(orderId))).go();

  /// Copy all cost components from [sourceOrderId] to [targetOrderId].
  /// Preserves name/costType/value/notes, resets computedAmount and sortOrder.
  Future<void> copyFromOrder({required int sourceOrderId, required int targetOrderId}) async {
    final source = await getForOrder(sourceOrderId);
    if (source.isEmpty) return;
    await batch((b) {
      for (var i = 0; i < source.length; i++) {
        final s = source[i];
        b.insert(
          manufacturingCostComponents,
          ManufacturingCostComponentsCompanion(
            manufacturingOrderId: Value(targetOrderId),
            name: Value(s.name),
            costType: Value(s.costType),
            value: Value(s.value),
            computedAmount: const Value(null),
            sortOrder: Value(i),
            notes: Value(s.notes),
          ),
        );
      }
    });
  }

  /// Returns the most recent order (by createdAt desc) that has at least one cost component,
  /// excluding [excludeOrderId] if provided. Used for "copy from last order" convenience.
  Future<int?> findMostRecentOrderWithComponents({int? excludeOrderId}) async {
    final query = selectOnly(manufacturingCostComponents)
      ..addColumns([manufacturingCostComponents.manufacturingOrderId])
      ..groupBy([manufacturingCostComponents.manufacturingOrderId])
      ..orderBy([OrderingTerm.desc(manufacturingCostComponents.manufacturingOrderId.max())]);

    // Simpler: scan manufacturingOrders ordered by createdAt desc and check which has components
    final orders = await (select(db.manufacturingOrders)
          ..orderBy([(o) => OrderingTerm.desc(o.createdAt)]))
        .get();
    for (final o in orders) {
      if (excludeOrderId != null && o.id == excludeOrderId) continue;
      final comps = await getForOrder(o.id);
      if (comps.isNotEmpty) return o.id;
    }
    return null;
  }

  // ── Computation helpers (pure logic, no DB write) ──

  /// Computes [computedAmount] for a single component given [materialCost] and [producedQuantity].
  /// Mirrors logic in E: fixed = value, percentage = value/100 * materialCost, per_unit = value * producedQuantity.
  static double computeAmount({
    required String costType,
    required double value,
    required double materialCost,
    required double producedQuantity,
  }) {
    switch (costType) {
      case ManufacturingCostType.fixed:
        return value;
      case ManufacturingCostType.percentage:
        return value / 100 * materialCost;
      case ManufacturingCostType.perUnit:
        return value * producedQuantity;
      default:
        throw ArgumentError('Unknown costType: $costType');
    }
  }
}
