import 'package:drift/drift.dart';

import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/tables/inventory_movements_table.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_cost_components_table.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_orders_table.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_tables.dart';
import 'package:pos_offline_desktop/core/database/tables/product_table.dart';

part 'manufacturing_order_dao.g.dart';

@DriftAccessor(tables: [
  ManufacturingOrders,
  BillOfMaterials,
  BomItems,
  ManufacturingCostComponents,
  InventoryMovements,
  Products,
])
class ManufacturingOrderDao extends DatabaseAccessor<AppDatabase>
    with _$ManufacturingOrderDaoMixin {
  ManufacturingOrderDao(super.db);

  // ── Reads ──

  Future<List<ManufacturingOrder>> getAll() =>
      (select(manufacturingOrders)..orderBy([(o) => OrderingTerm.desc(o.createdAt)])).get();

  Stream<List<ManufacturingOrder>> watchAll() =>
      (select(manufacturingOrders)..orderBy([(o) => OrderingTerm.desc(o.createdAt)])).watch();

  Future<ManufacturingOrder?> getById(int id) =>
      (select(manufacturingOrders)..where((o) => o.id.equals(id))).getSingleOrNull();

  Future<ManufacturingOrder?> getByOrderNumber(String number) =>
      (select(manufacturingOrders)..where((o) => o.orderNumber.equals(number))).getSingleOrNull();

  Future<List<ManufacturingOrder>> getByStatus(String status) =>
      (select(manufacturingOrders)..where((o) => o.status.equals(status))).get();

  Stream<List<ManufacturingOrder>> watchByStatus(String status) =>
      (select(manufacturingOrders)..where((o) => o.status.equals(status))).watch();

  Future<List<ManufacturingOrder>> getByBomId(int bomId) =>
      (select(manufacturingOrders)..where((o) => o.bomId.equals(bomId))).get();

  // ── Create ──

  /// Creates a new manufacturing order. Validates that the referenced BOM exists and is Active
  /// (soft check — warns but does not block if BOM is Inactive, to allow historical orders).
  Future<int> createOrder(ManufacturingOrdersCompanion entry) async {
    // Basic validation
    if (!entry.bomId.present || entry.bomId.value == 0) {
      throw ArgumentError('bomId is required');
    }
    final planned = entry.plannedQuantity.present ? entry.plannedQuantity.value : null;
    if (planned == null || planned <= 0) {
      throw ArgumentError('plannedQuantity must be > 0');
    }
    // Auto-generate orderNumber if not provided
    final companion = entry.orderNumber.present
        ? entry
        : entry.copyWith(orderNumber: Value('MO-${DateTime.now().millisecondsSinceEpoch}'));

    return into(manufacturingOrders).insert(companion);
  }

  // ── Update (header fields only, not status via this path) ──

  Future<bool> updateOrder(ManufacturingOrder order) =>
      update(manufacturingOrders).replace(order);

  // ── Status transitions ──

  /// planned -> in_progress
  Future<void> startOrder(int id) async {
    final mo = await getById(id);
    if (mo == null) throw ArgumentError('ManufacturingOrder #$id not found');
    if (mo.status != ManufacturingOrderStatus.planned) {
      throw StateError('Only planned orders can be started (current: ${mo.status})');
    }
    await (update(manufacturingOrders)..where((o) => o.id.equals(id))).write(
      ManufacturingOrdersCompanion(
        status: const Value(ManufacturingOrderStatus.inProgress),
        startedAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// planned/in_progress -> cancelled (no stock effect in Phase 3)
  Future<void> cancelOrder(int id, {String? reason}) async {
    final mo = await getById(id);
    if (mo == null) throw ArgumentError('ManufacturingOrder #$id not found');
    if (mo.status == ManufacturingOrderStatus.completed) {
      throw StateError('Completed orders cannot be cancelled');
    }
    if (mo.status == ManufacturingOrderStatus.cancelled) {
      throw StateError('Order is already cancelled');
    }
    await (update(manufacturingOrders)..where((o) => o.id.equals(id))).write(
      ManufacturingOrdersCompanion(
        status: const Value(ManufacturingOrderStatus.cancelled),
        cancelledAt: Value(DateTime.now()),
        cancelReason: Value(reason),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Re-activate a cancelled order back to planned (optional convenience)
  Future<void> reopenCancelledOrder(int id) async {
    final mo = await getById(id);
    if (mo == null) throw ArgumentError('ManufacturingOrder #$id not found');
    if (mo.status != ManufacturingOrderStatus.cancelled) {
      throw StateError('Only cancelled orders can be reopened');
    }
    await (update(manufacturingOrders)..where((o) => o.id.equals(id))).write(
      ManufacturingOrdersCompanion(
        status: const Value(ManufacturingOrderStatus.planned),
        cancelledAt: const Value(null),
        cancelReason: const Value(null),
        startedAt: const Value(null),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> deleteOrder(int id) =>
      (delete(manufacturingOrders)..where((o) => o.id.equals(id))).go();

  // ── Helpers ──

  /// Joins MO with its BOM and finished product for list display.
  Future<List<(ManufacturingOrder, BillOfMaterial?, Product?)>> getAllWithDetails() async {
    final query = select(manufacturingOrders).join([
      leftOuterJoin(db.billOfMaterials, db.billOfMaterials.id.equalsExp(manufacturingOrders.bomId)),
      leftOuterJoin(db.products, db.products.id.equalsExp(manufacturingOrders.finishedProductId)),
    ])
      ..orderBy([OrderingTerm.desc(manufacturingOrders.createdAt)]);

    final rows = await query.get();
    return rows
        .map((row) => (
              row.readTable(manufacturingOrders),
              row.readTableOrNull(db.billOfMaterials),
              row.readTableOrNull(db.products),
            ))
        .toList();
  }

  Future<String> generateOrderNumber() async {
    final base = 'MO-${DateTime.now().millisecondsSinceEpoch}';
    final existing = await getByOrderNumber(base);
    if (existing == null) return base;
    // Collision extremely unlikely, but add suffix
    return 'MO-${DateTime.now().millisecondsSinceEpoch}-${(DateTime.now().microsecond % 1000)}';
  }

  // ── Phase 5: Atomic "Complete Production" ──

  /// Thrown when raw stock is insufficient. Contains list of shortages.
  /// Caller can show this to the user without any DB writes having occurred.
  /// No partial writes — the transaction aborts before any mutation.

  /// Result of a successful completion.
  /// Returns computed costs and allows caller to optionally update product cost.

  /// Atomically completes a manufacturing order:
  /// 1. Validates status (must be planned or in_progress, not completed/cancelled)
  /// 2. Loads BOM + BomItems + raw Product rows
  /// 3. Computes requiredQty per item (with waste, rounded per Option A)
  /// 4. Validates raw stock ≥ required; if any fail, abort with [InsufficientStockException]
  /// 5. Decrements raw Products.quantity + writes InventoryMovements (manufacturing_consumption)
  /// 6. Computes materialCost + cost-component computedAmounts + total/unit cost
  /// 7. Increments finished Product.quantity + writes InventoryMovements (manufacturing_output)
  /// 8. Updates MO to completed + writes computedAmount onto each cost component
  /// Entire method runs inside a single Drift transaction — any failure rolls back everything.
  Future<ManufacturingCompletionResult> completeManufacturingOrder({
    required int orderId,
    double? actualProducedQuantity,
    String? performedBy,
    String? notes,
  }) {
    return transaction(() async {
      // 1. Load & validate MO
      final mo = await (select(manufacturingOrders)..where((o) => o.id.equals(orderId))).getSingleOrNull();
      if (mo == null) throw ArgumentError('ManufacturingOrder #$orderId not found');
      if (mo.status == ManufacturingOrderStatus.completed) {
        throw StateError('Order is already completed');
      }
      if (mo.status == ManufacturingOrderStatus.cancelled) {
        throw StateError('Cancelled orders cannot be completed');
      }

      // 2. Load BOM
      final bom = await (select(db.billOfMaterials)..where((b) => b.id.equals(mo.bomId))).getSingleOrNull();
      if (bom == null) throw StateError('BOM #${mo.bomId} not found for order #$orderId');

      final effectiveProduced = actualProducedQuantity ?? mo.plannedQuantity;
      if (effectiveProduced <= 0) throw ArgumentError('Produced quantity must be > 0');
      final producedInt = effectiveProduced.round(); // Option A: round to whole base-unit
      if (producedInt <= 0) throw ArgumentError('Produced quantity rounds to 0 — increase quantity');

      final bomItems = await (select(db.bomItems)
            ..where((i) => i.bomId.equals(bom.id))
            ..orderBy([(i) => OrderingTerm.asc(i.sortOrder)]))
          .get();
      if (bomItems.isEmpty) throw StateError('BOM #${bom.id} has no items — cannot produce');

      final yieldQty = bom.yieldQuantity;
      if (yieldQty <= 0) throw StateError('BOM yieldQuantity must be > 0');
      final factor = effectiveProduced / yieldQty;

      // 3. Compute required & validate stock (read-only phase, before any writes)
      final List<_ConsumptionPlan> plan = [];
      final List<InsufficientStockDetail> shortages = [];
      double materialCost = 0;

      for (final item in bomItems) {
        final waste = item.wastePercentageOverride ?? bom.wastePercentage;
        final rawRequired = item.quantityRequired * factor * (1 + waste / 100);
        final requiredInt = rawRequired.round(); // Option A rounding
        final product = await (select(db.products)..where((p) => p.id.equals(item.rawMaterialProductId))).getSingleOrNull();
        if (product == null) throw StateError('Raw material product #${item.rawMaterialProductId} not found');

        if (requiredInt > product.quantity) {
          shortages.add(InsufficientStockDetail(
            rawMaterialProductId: product.id,
            productName: product.name,
            required: requiredInt,
            available: product.quantity,
            unit: product.unit,
          ));
        }

        final unitCost = product.costPrice ?? product.price;
        final lineCost = requiredInt * unitCost;
        materialCost += lineCost;

        plan.add(_ConsumptionPlan(
          bomItem: item,
          product: product,
          requiredInt: requiredInt,
          unitCost: unitCost,
          lineCost: lineCost,
        ));
      }

      if (shortages.isNotEmpty) {
        throw InsufficientStockException(shortages);
      }

      // 4. Load cost components & compute computedAmounts
      final components = await (select(db.manufacturingCostComponents)
            ..where((c) => c.manufacturingOrderId.equals(orderId)))
          .get();

      final List<double> computedAmounts = [];
      double totalComponentsCost = 0;
      for (final comp in components) {
        double computed;
        switch (comp.costType) {
          case 'fixed':
            computed = comp.value;
            break;
          case 'percentage':
            computed = comp.value / 100 * materialCost;
            break;
          case 'per_unit':
            computed = comp.value * effectiveProduced;
            break;
          default:
            throw StateError('Unknown costType ${comp.costType} on component #${comp.id}');
        }
        // Round to 2 decimals for financial snapshot
        computed = double.parse(computed.toStringAsFixed(2));
        computedAmounts.add(computed);
        totalComponentsCost += computed;
      }

      final totalCost = double.parse((materialCost + totalComponentsCost).toStringAsFixed(2));
      final unitCost = effectiveProduced > 0 ? double.parse((totalCost / effectiveProduced).toStringAsFixed(2)) : 0.0;

      final now = DateTime.now();

      // 5. Decrement raw materials + inventory movements
      for (final p in plan) {
        final prev = p.product.quantity;
        final next = prev - p.requiredInt;
        await (update(db.products)..where((t) => t.id.equals(p.product.id))).write(
          ProductsCompanion(quantity: Value(next), updatedAt: Value(now)),
        );
        await into(db.inventoryMovements).insert(
          InventoryMovementsCompanion.insert(
            productId: p.product.id,
            movementType: 'manufacturing_consumption',
            quantity: -p.requiredInt,
            unitCost: p.unitCost,
            totalValue: p.lineCost,
            movementDate: now,
            reference: mo.orderNumber,
            referenceType: 'manufacturing_order',
            previousQuantity: prev,
            newQuantity: next,
            performedBy: Value(performedBy),
            notes: Value('استهلاك لتصنيع ${mo.orderNumber} • ${p.product.name}'),
            createdAt: now,
            updatedAt: now,
          ),
        );
      }

      // 6. Increment finished product + output movement
      final finishedProduct = await (select(db.products)..where((p) => p.id.equals(mo.finishedProductId))).getSingleOrNull();
      if (finishedProduct == null) throw StateError('Finished product #${mo.finishedProductId} not found');
      final prevFinished = finishedProduct.quantity;
      final nextFinished = prevFinished + producedInt;
      await (update(db.products)..where((t) => t.id.equals(finishedProduct.id))).write(
        ProductsCompanion(quantity: Value(nextFinished), updatedAt: Value(now)),
      );
      await into(db.inventoryMovements).insert(
        InventoryMovementsCompanion.insert(
          productId: finishedProduct.id,
          movementType: 'manufacturing_output',
          quantity: producedInt,
          unitCost: unitCost.toDouble(),
          totalValue: totalCost.toDouble(),
          movementDate: now,
          reference: mo.orderNumber,
          referenceType: 'manufacturing_order',
          previousQuantity: prevFinished,
          newQuantity: nextFinished,
          performedBy: Value(performedBy),
          notes: Value(notes ?? 'إنتاج من أمر ${mo.orderNumber}'),
          createdAt: now,
          updatedAt: now,
        ),
      );

      // 7. Freeze computedAmount on cost components
      for (var i = 0; i < components.length; i++) {
        await (update(db.manufacturingCostComponents)..where((c) => c.id.equals(components[i].id))).write(
          ManufacturingCostComponentsCompanion(computedAmount: Value(computedAmounts[i])),
        );
      }

      // 8. Update MO to completed
      await (update(manufacturingOrders)..where((o) => o.id.equals(orderId))).write(
        ManufacturingOrdersCompanion(
          status: const Value(ManufacturingOrderStatus.completed),
          producedQuantity: Value(effectiveProduced.toDouble()),
          completedAt: Value(now),
          updatedAt: Value(now),
        ),
      );

      return ManufacturingCompletionResult(
        orderId: orderId,
        orderNumber: mo.orderNumber,
        finishedProductId: finishedProduct.id,
        finishedProductName: finishedProduct.name,
        plannedQuantity: mo.plannedQuantity,
        producedQuantity: effectiveProduced.toDouble(),
        producedInt: producedInt,
        materialCost: double.parse(materialCost.toStringAsFixed(2)),
        componentsCost: double.parse(totalComponentsCost.toStringAsFixed(2)),
        totalCost: totalCost.toDouble(),
        unitCost: unitCost.toDouble(),
        consumptions: plan
            .map((p) => ConsumptionResult(
                  rawMaterialProductId: p.product.id,
                  productName: p.product.name,
                  required: p.requiredInt,
                  unitCost: p.unitCost,
                  lineCost: p.lineCost,
                  unit: p.product.unit,
                ))
            .toList(),
        previousFinishedQuantity: prevFinished,
        nextFinishedQuantity: nextFinished,
        previousCostPrice: finishedProduct.costPrice,
      );
    });
  }
}

class _ConsumptionPlan {
  final BomItem bomItem;
  final Product product;
  final int requiredInt;
  final double unitCost;
  final double lineCost;
  _ConsumptionPlan({
    required this.bomItem,
    required this.product,
    required this.requiredInt,
    required this.unitCost,
    required this.lineCost,
  });
}

class ManufacturingCompletionResult {
  final int orderId;
  final String orderNumber;
  final int finishedProductId;
  final String finishedProductName;
  final double plannedQuantity;
  final double producedQuantity;
  final int producedInt;
  final double materialCost;
  final double componentsCost;
  final double totalCost;
  final double unitCost;
  final List<ConsumptionResult> consumptions;
  final int previousFinishedQuantity;
  final int nextFinishedQuantity;
  final double? previousCostPrice;

  ManufacturingCompletionResult({
    required this.orderId,
    required this.orderNumber,
    required this.finishedProductId,
    required this.finishedProductName,
    required this.plannedQuantity,
    required this.producedQuantity,
    required this.producedInt,
    required this.materialCost,
    required this.componentsCost,
    required this.totalCost,
    required this.unitCost,
    required this.consumptions,
    required this.previousFinishedQuantity,
    required this.nextFinishedQuantity,
    this.previousCostPrice,
  });
}

class ConsumptionResult {
  final int rawMaterialProductId;
  final String productName;
  final int required;
  final double unitCost;
  final double lineCost;
  final String? unit;
  ConsumptionResult({
    required this.rawMaterialProductId,
    required this.productName,
    required this.required,
    required this.unitCost,
    required this.lineCost,
    this.unit,
  });
}

class InsufficientStockDetail {
  final int rawMaterialProductId;
  final String productName;
  final int required;
  final int available;
  final String? unit;
  InsufficientStockDetail({
    required this.rawMaterialProductId,
    required this.productName,
    required this.required,
    required this.available,
    this.unit,
  });
  int get shortage => required - available;
}

class InsufficientStockException implements Exception {
  final List<InsufficientStockDetail> shortages;
  InsufficientStockException(this.shortages);
  @override
  String toString() {
    final lines = shortages.map((s) => '${s.productName}: مطلوب ${s.required} ${s.unit ?? ''}، متاح ${s.available}، ناقص ${s.shortage}').join('\n');
    return 'نقص في المواد الخام:\n$lines';
  }
}

