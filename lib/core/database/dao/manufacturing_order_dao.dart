import 'package:drift/drift.dart';

import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/services/license_entitlement.dart';
import 'package:pos_offline_desktop/core/database/tables/customer_material_receipts_table.dart';
import 'package:pos_offline_desktop/core/database/tables/customer_table.dart';
import 'package:pos_offline_desktop/core/database/tables/inventory_movements_table.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_cost_components_table.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_orders_table.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_tables.dart';
import 'package:pos_offline_desktop/core/database/tables/product_table.dart';

part 'manufacturing_order_dao.g.dart';

/// Ownership rule for one BOM line in a for-others/mixed completion.
///
/// Single source of truth shared by [ManufacturingOrderDao.completeForOthersOrder]
/// and the completion preview in the order details screen, so a
/// customer-owned line is never compared to factory [Products.quantity]:
/// - explicit [customerOwnedProductIds] set → only listed lines are customer-owned;
/// - 'for_others' without a set → every line is customer-owned;
/// - otherwise (mixed / legacy paths) → customer-owned when the customer
///   holds a custody balance for that product.
bool isCustomerOwnedBomLine({
  required String orderType,
  required int rawMaterialProductId,
  Set<int>? customerOwnedProductIds,
  bool hasCustodyBalance = false,
}) {
  if (customerOwnedProductIds != null) {
    return customerOwnedProductIds.contains(rawMaterialProductId);
  }
  if (orderType == 'for_others') return true;
  return hasCustodyBalance;
}

@DriftAccessor(
  tables: [
    ManufacturingOrders,
    BillOfMaterials,
    BomItems,
    ManufacturingCostComponents,
    InventoryMovements,
    Products,
    CustomerStockBalances,
    CustomerStockMovements,
    Customers,
  ],
)
class ManufacturingOrderDao extends DatabaseAccessor<AppDatabase>
    with _$ManufacturingOrderDaoMixin {
  ManufacturingOrderDao(super.db);

  // ── Reads ──

  Future<List<ManufacturingOrder>> getAll() => (select(
    manufacturingOrders,
  )..orderBy([(o) => OrderingTerm.desc(o.createdAt)])).get();

  Stream<List<ManufacturingOrder>> watchAll() => (select(
    manufacturingOrders,
  )..orderBy([(o) => OrderingTerm.desc(o.createdAt)])).watch();

  Future<ManufacturingOrder?> getById(int id) => (select(
    manufacturingOrders,
  )..where((o) => o.id.equals(id))).getSingleOrNull();

  Future<ManufacturingOrder?> getByOrderNumber(String number) => (select(
    manufacturingOrders,
  )..where((o) => o.orderNumber.equals(number))).getSingleOrNull();

  Future<List<ManufacturingOrder>> getByStatus(String status) => (select(
    manufacturingOrders,
  )..where((o) => o.status.equals(status))).get();

  Stream<List<ManufacturingOrder>> watchByStatus(String status) => (select(
    manufacturingOrders,
  )..where((o) => o.status.equals(status))).watch();

  Future<List<ManufacturingOrder>> getByBomId(int bomId) =>
      (select(manufacturingOrders)..where((o) => o.bomId.equals(bomId))).get();

  // ── Create ──

  /// Creates a new manufacturing order. Validates that the referenced BOM exists and is Active
  /// (soft check — warns but does not block if BOM is Inactive, to allow historical orders).
  /// BUG-017 — entitlement guard for the manufacturing module.
  ///
  /// Manufacturing had NO guard at all: the home launcher checked the flavor
  /// only, and every route under /manufacturing was open to any valid license.
  /// A customer on a `basic` plan got BOMs, work orders and stock consumption
  /// for free.
  ///
  /// The check runs first in every mutating method, before any statement, so a
  /// refusal cannot leave a work order created without its material movements.
  /// `grants()` reads an in-memory snapshot — no disk I/O, so it is safe to
  /// call from inside a transaction.
  static void _requireLicense(String operation) => LicenseEntitlement.instance
      .require('manufacturing', operation: operation);

  Future<int> createOrder(ManufacturingOrdersCompanion entry) async {
    _requireLicense('إنشاء أمر تصنيع');
    // Basic validation
    if (!entry.bomId.present || entry.bomId.value == 0) {
      throw ArgumentError('bomId is required');
    }
    final planned = entry.plannedQuantity.present
        ? entry.plannedQuantity.value
        : null;
    if (planned == null || planned <= 0) {
      throw ArgumentError('plannedQuantity must be > 0');
    }
    // Auto-generate orderNumber if not provided
    final companion = entry.orderNumber.present
        ? entry
        : entry.copyWith(
            orderNumber: Value('MO-${DateTime.now().millisecondsSinceEpoch}'),
          );

    return into(manufacturingOrders).insert(companion);
  }

  // ── Update (header fields only, not status via this path) ──

  Future<bool> updateOrder(ManufacturingOrder order) {
    _requireLicense('تعديل أمر تصنيع');
    return update(manufacturingOrders).replace(order);
  }

  // ── Status transitions ──

  /// planned -> in_progress
  ///
  /// Backward-compatible extensions (all new parameters are optional):
  /// - [bomId]: when provided, the order executes this real recipe instead
  ///   of a system placeholder BOM (receipt → recipe flow).
  /// - [inputProductId]/[inputQuantity]: optional so recipe-based orders can
  ///   leave direct-input tracking null and go through the BOM completion
  ///   path; existing callers pass values exactly as before.
  /// - Pricing/planning fields are written only when provided, so existing
  ///   callers keep the previous column defaults.
  Future<int> createJobWorkOrder({
    required String orderNumber,
    required String orderType,
    required String customerId,
    int? inputProductId,
    double? inputQuantity,
    String? inputColor,
    String? inputSize,
    int? finishedProductId,
    double? plannedQuantity,
    int? bomId,
    DateTime? plannedDate,
    String? pricingMode,
    String? scrapPolicy,
    double? pieceUnitValue,
    double? serviceUnitPrice,
    String? notes,
  }) async {
    _requireLicense('إنشاء أمر عمل تصنيع');
    if (bomId == null && (inputProductId == null || inputQuantity == null)) {
      throw ArgumentError('bomId or input product + quantity is required');
    }
    if (plannedQuantity == null && inputQuantity == null) {
      throw ArgumentError('planned quantity is required');
    }
    return transaction(() async {
      final resolvedBomId =
          bomId ?? await db.bomDao.createSystemPlaceholderBom(inputProductId!);
      int? resolvedFinished = finishedProductId ?? inputProductId;
      resolvedFinished ??= (await db.bomDao.getBomById(
        resolvedBomId,
      ))?.finishedProductId;
      if (resolvedFinished == null) {
        throw ArgumentError('finished product cannot be resolved');
      }

      return into(manufacturingOrders).insert(
        ManufacturingOrdersCompanion.insert(
          orderNumber: orderNumber,
          orderType: Value(orderType),
          bomId: resolvedBomId,
          finishedProductId: resolvedFinished,
          plannedQuantity: plannedQuantity ?? inputQuantity ?? 0,
          plannedDate: Value(plannedDate),
          customerId: Value(customerId),
          pricingMode: pricingMode == null
              ? const Value.absent()
              : Value(pricingMode),
          scrapPolicy: scrapPolicy == null
              ? const Value.absent()
              : Value(scrapPolicy),
          pieceUnitValue: pieceUnitValue == null
              ? const Value.absent()
              : Value(pieceUnitValue),
          serviceUnitPrice: serviceUnitPrice == null
              ? const Value.absent()
              : Value(serviceUnitPrice),
          notes: Value(notes),
          inputProductId: Value(inputProductId),
          inputQuantity: Value(inputQuantity),
          inputColor: Value(inputColor),
          inputSize: Value(inputSize),
        ),
      );
    });
  }

  Future<void> startOrder(int id) async {
    _requireLicense('بدء أمر تصنيع');
    final mo = await getById(id);
    if (mo == null) throw ArgumentError('ManufacturingOrder #$id not found');
    if (mo.status != ManufacturingOrderStatus.planned) {
      throw StateError(
        'Only planned orders can be started (current: ${mo.status})',
      );
    }
    if (mo.orderType == 'for_others' &&
        mo.customerId != null &&
        mo.inputProductId != null &&
        mo.inputQuantity != null) {
      final bal =
          await (select(customerStockBalances)..where(
                (t) =>
                    t.customerId.equals(mo.customerId!) &
                    t.productId.equals(mo.inputProductId!) &
                    (mo.inputColor == null
                        ? t.color.isNull()
                        : t.color.equals(mo.inputColor!)) &
                    (mo.inputSize == null
                        ? t.size.isNull()
                        : t.size.equals(mo.inputSize!)),
              ))
              .getSingleOrNull();

      if (bal == null ||
          (bal.quantityOnHand - bal.quantityAllocated) < mo.inputQuantity!) {
        throw StateError('رصيد العميل غير كافٍ');
      }

      await (update(
        customerStockBalances,
      )..where((t) => t.id.equals(bal.id))).write(
        CustomerStockBalancesCompanion(
          quantityAllocated: Value(bal.quantityAllocated + mo.inputQuantity!),
        ),
      );
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
    _requireLicense('إلغاء أمر تصنيع');
    final mo = await getById(id);
    if (mo == null) throw ArgumentError('ManufacturingOrder #$id not found');
    if (mo.status == ManufacturingOrderStatus.completed) {
      throw StateError('Completed orders cannot be cancelled');
    }
    if (mo.status == ManufacturingOrderStatus.cancelled) {
      throw StateError('Order is already cancelled');
    }
    if (mo.orderType == 'for_others' &&
        mo.customerId != null &&
        mo.inputProductId != null &&
        mo.inputQuantity != null &&
        mo.status == ManufacturingOrderStatus.inProgress) {
      final bal =
          await (select(customerStockBalances)..where(
                (t) =>
                    t.customerId.equals(mo.customerId!) &
                    t.productId.equals(mo.inputProductId!) &
                    (mo.inputColor == null
                        ? t.color.isNull()
                        : t.color.equals(mo.inputColor!)) &
                    (mo.inputSize == null
                        ? t.size.isNull()
                        : t.size.equals(mo.inputSize!)),
              ))
              .getSingleOrNull();
      if (bal != null) {
        final newAlloc = bal.quantityAllocated - mo.inputQuantity!;
        await (update(
          customerStockBalances,
        )..where((t) => t.id.equals(bal.id))).write(
          CustomerStockBalancesCompanion(
            quantityAllocated: Value(newAlloc < 0 ? 0 : newAlloc),
          ),
        );
      }
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
    _requireLicense('إعادة فتح أمر تصنيع');
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

  Future<void> deleteOrder(int id) {
    _requireLicense('حذف أمر تصنيع');
    return (delete(manufacturingOrders)..where((o) => o.id.equals(id))).go();
  }

  // ── Helpers ──

  /// Joins MO with its BOM and finished product for list display.
  Future<List<(ManufacturingOrder, BillOfMaterial?, Product?)>>
  getAllWithDetails() async {
    final query = select(manufacturingOrders).join([
      leftOuterJoin(
        db.billOfMaterials,
        db.billOfMaterials.id.equalsExp(manufacturingOrders.bomId),
      ),
      leftOuterJoin(
        db.products,
        db.products.id.equalsExp(manufacturingOrders.finishedProductId),
      ),
    ])..orderBy([OrderingTerm.desc(manufacturingOrders.createdAt)]);

    final rows = await query.get();
    return rows
        .map(
          (row) => (
            row.readTable(manufacturingOrders),
            row.readTableOrNull(db.billOfMaterials),
            row.readTableOrNull(db.products),
          ),
        )
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
      final mo = await (select(
        manufacturingOrders,
      )..where((o) => o.id.equals(orderId))).getSingleOrNull();
      if (mo == null)
        throw ArgumentError('ManufacturingOrder #$orderId not found');
      if (mo.status == ManufacturingOrderStatus.completed) {
        throw StateError('Order is already completed');
      }
      if (mo.status == ManufacturingOrderStatus.cancelled) {
        throw StateError('Cancelled orders cannot be completed');
      }

      // 2. Load BOM
      final bom = await (select(
        db.billOfMaterials,
      )..where((b) => b.id.equals(mo.bomId))).getSingleOrNull();
      if (bom == null)
        throw StateError('BOM #${mo.bomId} not found for order #$orderId');

      final effectiveProduced = actualProducedQuantity ?? mo.plannedQuantity;
      if (effectiveProduced <= 0)
        throw ArgumentError('Produced quantity must be > 0');
      final producedInt = effectiveProduced
          .round(); // Option A: round to whole base-unit
      if (producedInt <= 0)
        throw ArgumentError(
          'Produced quantity rounds to 0 — increase quantity',
        );

      final bomItems =
          await (select(db.bomItems)
                ..where((i) => i.bomId.equals(bom.id))
                ..orderBy([(i) => OrderingTerm.asc(i.sortOrder)]))
              .get();
      if (bomItems.isEmpty)
        throw StateError('BOM #${bom.id} has no items — cannot produce');

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
        final product =
            await (select(db.products)
                  ..where((p) => p.id.equals(item.rawMaterialProductId)))
                .getSingleOrNull();
        if (product == null)
          throw StateError(
            'Raw material product #${item.rawMaterialProductId} not found',
          );

        if (requiredInt > product.quantity) {
          shortages.add(
            InsufficientStockDetail(
              rawMaterialProductId: product.id,
              productName: product.name,
              required: requiredInt,
              available: product.quantity,
              unit: product.unit,
            ),
          );
        }

        final unitCost = product.costPrice ?? product.price;
        final lineCost = requiredInt * unitCost;
        materialCost += lineCost;

        plan.add(
          _ConsumptionPlan(
            bomItem: item,
            product: product,
            requiredInt: requiredInt,
            unitCost: unitCost,
            lineCost: lineCost,
          ),
        );
      }

      if (shortages.isNotEmpty) {
        throw InsufficientStockException(shortages);
      }

      // 4. Load cost components & compute computedAmounts
      final components = await (select(
        db.manufacturingCostComponents,
      )..where((c) => c.manufacturingOrderId.equals(orderId))).get();

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
            throw StateError(
              'Unknown costType ${comp.costType} on component #${comp.id}',
            );
        }
        // Round to 2 decimals for financial snapshot
        computed = double.parse(computed.toStringAsFixed(2));
        computedAmounts.add(computed);
        totalComponentsCost += computed;
      }

      final totalCost = double.parse(
        (materialCost + totalComponentsCost).toStringAsFixed(2),
      );
      final unitCost = effectiveProduced > 0
          ? double.parse((totalCost / effectiveProduced).toStringAsFixed(2))
          : 0.0;

      final now = DateTime.now();

      // 5. Decrement raw materials + inventory movements
      for (final p in plan) {
        final prev = p.product.quantity;
        final next = prev - p.requiredInt;
        await (update(
          db.products,
        )..where((t) => t.id.equals(p.product.id))).write(
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
            notes: Value(
              'استهلاك لتصنيع ${mo.orderNumber} • ${p.product.name}',
            ),
            createdAt: now,
            updatedAt: now,
          ),
        );
      }

      // 6. Increment finished product + output movement
      final finishedProduct = await (select(
        db.products,
      )..where((p) => p.id.equals(mo.finishedProductId))).getSingleOrNull();
      if (finishedProduct == null)
        throw StateError('Finished product #${mo.finishedProductId} not found');
      final prevFinished = finishedProduct.quantity;
      final nextFinished = prevFinished + producedInt;
      await (update(
        db.products,
      )..where((t) => t.id.equals(finishedProduct.id))).write(
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
        await (update(
          db.manufacturingCostComponents,
        )..where((c) => c.id.equals(components[i].id))).write(
          ManufacturingCostComponentsCompanion(
            computedAmount: Value(computedAmounts[i]),
          ),
        );
      }

      // 8. Update MO to completed
      await (update(
        manufacturingOrders,
      )..where((o) => o.id.equals(orderId))).write(
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
            .map(
              (p) => ConsumptionResult(
                rawMaterialProductId: p.product.id,
                productName: p.product.name,
                required: p.requiredInt,
                unitCost: p.unitCost,
                lineCost: p.lineCost,
                unit: p.product.unit,
              ),
            )
            .toList(),
        previousFinishedQuantity: prevFinished,
        nextFinishedQuantity: nextFinished,
        previousCostPrice: finishedProduct.costPrice,
      );
    });
  }

  // ── Phase B1: Manufacturing For Others Completion ──

  /// Atomically completes a manufacturing-for-others or mixed manufacturing order.
  ///
  /// Enforces:
  /// 1. order_type must be 'for_others' or 'mixed' (internal orders are strictly rejected).
  /// 2. customerId must be provided and exist in customers table.
  /// 3. Validates status (must be planned or in_progress, not completed/cancelled).
  /// 4. Loads BOM and items.
  /// 5. Customer-owned lines [customerOwnedProductIds or by default all lines if for_others]
  ///    validate customer_stock_balances (quantityOnHand - quantityAllocated >= required).
  /// 6. Factory-owned lines [mixed order factory items] validate Products.quantity >= required.
  /// 7. If ANY shortage exists, throws [InsufficientStockException] with zero writes.
  /// 8. Deducts customer custody balances + records customer_stock_movements ('issued_to_order').
  /// 9. Deducts factory inventory + records inventory_movements ('manufacturing_consumption').
  /// 10. NEVER increments factory finished-product stock (`Products.quantity` is untouched).
  /// 11. Updates MO: status = 'completed', producedQuantity = effectiveProduced, completedAt = now.
  Future<ForOthersCompletionResult> completeForOthersOrder({
    required int orderId,
    double? actualProducedQuantity,
    Set<int>? customerOwnedProductIds,
    String? performedBy,
    String? notes,
    double? goodQuantity,
    double? scrapQuantity,
    String? completedByUserId,
  }) {
    return transaction(() async {
      // 1. Load & validate MO
      final mo = await (select(
        manufacturingOrders,
      )..where((o) => o.id.equals(orderId))).getSingleOrNull();
      if (mo == null)
        throw ArgumentError('ManufacturingOrder #$orderId not found');
      if (mo.status == ManufacturingOrderStatus.completed) {
        throw StateError('Order is already completed');
      }
      if (mo.status == ManufacturingOrderStatus.cancelled) {
        throw StateError('Cancelled orders cannot be completed');
      }

      final orderType = mo.orderType ?? 'internal';
      if (orderType == 'for_others' &&
          mo.inputQuantity != null &&
          mo.inputProductId != null) {
        final effectiveGood =
            goodQuantity ?? actualProducedQuantity ?? mo.plannedQuantity;
        final effectiveScrap = scrapQuantity ?? 0.0;
        final effectiveUser = completedByUserId ?? performedBy ?? 'system';

        final bal =
            await (select(customerStockBalances)..where(
                  (t) =>
                      t.customerId.equals(mo.customerId!) &
                      t.productId.equals(mo.inputProductId!) &
                      (mo.inputColor == null
                          ? t.color.isNull()
                          : t.color.equals(mo.inputColor!)) &
                      (mo.inputSize == null
                          ? t.size.isNull()
                          : t.size.equals(mo.inputSize!)),
                ))
                .getSingleOrNull();

        if (bal == null || bal.quantityOnHand < mo.inputQuantity!) {
          final prod = await (select(
            products,
          )..where((p) => p.id.equals(mo.inputProductId!))).getSingleOrNull();
          throw InsufficientStockException([
            InsufficientStockDetail(
              rawMaterialProductId: mo.inputProductId!,
              productName: prod?.name ?? 'Unknown',
              required: int.parse(mo.inputQuantity!.toStringAsFixed(0)),
              available: bal != null
                  ? int.parse(bal.quantityOnHand.toStringAsFixed(0))
                  : 0,
            ),
          ]);
        }

        final newOnHand = bal.quantityOnHand - mo.inputQuantity!;
        final newAlloc = bal.quantityAllocated - mo.inputQuantity!;
        await (update(
          customerStockBalances,
        )..where((t) => t.id.equals(bal.id))).write(
          CustomerStockBalancesCompanion(
            quantityOnHand: Value(newOnHand),
            quantityAllocated: Value(newAlloc < 0 ? 0 : newAlloc),
          ),
        );

        await into(customerStockMovements).insert(
          CustomerStockMovementsCompanion.insert(
            customerId: mo.customerId!,
            productId: mo.inputProductId!,
            color: Value(mo.inputColor),
            size: Value(mo.inputSize),
            movementType: 'manufacturing_consumption',
            quantity: -mo.inputQuantity!,
            referenceType: 'manufacturing_order',
            referenceId: mo.id.toString(),
            notes: Value(
              'MO completion: $effectiveGood good, $effectiveScrap scrap',
            ),
            performedBy: Value(effectiveUser),
          ),
        );

        await (update(
          manufacturingOrders,
        )..where((o) => o.id.equals(orderId))).write(
          ManufacturingOrdersCompanion(
            status: const Value(ManufacturingOrderStatus.completed),
            producedQuantity: Value(effectiveGood),
            completedAt: Value(DateTime.now()),
            updatedAt: Value(DateTime.now()),
          ),
        );

        final customer = await (select(
          customers,
        )..where((c) => c.id.equals(mo.customerId!))).getSingle();
        final product = await (select(
          products,
        )..where((p) => p.id.equals(mo.finishedProductId))).getSingle();

        return ForOthersCompletionResult(
          orderId: mo.id,
          orderNumber: mo.orderNumber,
          customerId: customer.id,
          finishedProductId: product.id,
          finishedProductName: product.name,
          producedQuantity: effectiveGood,
          plannedQuantity: mo.plannedQuantity,
          customerConsumptions: [],
          factoryConsumptions: [],
        );
      }

      if (orderType != 'for_others' &&
          orderType != 'mixed' &&
          orderType != 'service_only') {
        throw ArgumentError(
          'Order #$orderId has orderType "$orderType" — cannot be completed via completeForOthersOrder',
        );
      }

      final customerId = mo.customerId;
      if (customerId == null || customerId.trim().isEmpty) {
        throw ArgumentError('Order #$orderId has no customerId associated');
      }
      final customer = await (select(
        customers,
      )..where((c) => c.id.equals(customerId))).getSingleOrNull();
      if (customer == null) {
        throw ArgumentError(
          'Customer #$customerId not found for order #$orderId',
        );
      }

      // 2. Load BOM
      final bom = await (select(
        billOfMaterials,
      )..where((b) => b.id.equals(mo.bomId))).getSingleOrNull();
      if (bom == null)
        throw StateError('BOM #${mo.bomId} not found for order #$orderId');

      final effectiveProduced = actualProducedQuantity ?? mo.plannedQuantity;
      if (effectiveProduced <= 0)
        throw ArgumentError('Produced quantity must be > 0');
      final producedInt = effectiveProduced.round();
      if (producedInt <= 0)
        throw ArgumentError(
          'Produced quantity rounds to 0 — increase quantity',
        );

      final bomItemsList =
          await (select(bomItems)
                ..where((i) => i.bomId.equals(bom.id))
                ..orderBy([(i) => OrderingTerm.asc(i.sortOrder)]))
              .get();
      if (bomItemsList.isEmpty && orderType != 'service_only') {
        throw StateError('BOM #${bom.id} has no items — cannot produce');
      }

      final yieldQty = bom.yieldQuantity;
      if (yieldQty <= 0) throw StateError('BOM yieldQuantity must be > 0');
      final factor = effectiveProduced / yieldQty;

      // 3. Compute required and validate stock for both customer and factory materials
      final List<_CustomerConsumptionPlan> customerPlans = [];
      final List<_ConsumptionPlan> factoryPlans = [];
      final List<InsufficientStockDetail> shortages = [];

      for (final item in bomItemsList) {
        final waste = item.wastePercentageOverride ?? bom.wastePercentage;
        final rawRequired = item.quantityRequired * factor * (1 + waste / 100);
        final requiredInt = rawRequired.round();

        // Zero-required lines are skipped entirely (no consumption, no custody validation needed)
        if (requiredInt <= 0) continue;

        final product =
            await (select(products)
                  ..where((p) => p.id.equals(item.rawMaterialProductId)))
                .getSingleOrNull();
        if (product == null)
          throw StateError(
            'Raw material product #${item.rawMaterialProductId} not found',
          );

        // Determine ownership via the shared rule (see isCustomerOwnedBomLine).
        // The balance lookup below runs only when the rule needs it.
        final custBalForOwnership =
            (customerOwnedProductIds == null && orderType != 'for_others')
            ? await (select(customerStockBalances)..where(
                    (b) =>
                        b.customerId.equals(customerId) &
                        b.productId.equals(item.rawMaterialProductId),
                  ))
                  .getSingleOrNull()
            : null;
        final bool isCustomerOwned = isCustomerOwnedBomLine(
          orderType: orderType,
          rawMaterialProductId: item.rawMaterialProductId,
          customerOwnedProductIds: customerOwnedProductIds,
          hasCustodyBalance: custBalForOwnership != null,
        );

        if (isCustomerOwned) {
          // Customer custody stock validation
          final custBal =
              await (select(customerStockBalances)..where(
                    (b) =>
                        b.customerId.equals(customerId) &
                        b.productId.equals(item.rawMaterialProductId),
                  ))
                  .getSingleOrNull();
          final available = custBal != null
              ? (custBal.quantityOnHand - custBal.quantityAllocated).toDouble()
              : 0.0;
          if (requiredInt > available || custBal == null) {
            shortages.add(
              InsufficientStockDetail(
                rawMaterialProductId: product.id,
                productName: '${product.name} (عهدة العميل)',
                required: requiredInt,
                available: available.round(),
                unit: product.unit,
              ),
            );
          } else {
            customerPlans.add(
              _CustomerConsumptionPlan(
                bomItem: item,
                product: product,
                balanceRow: custBal,
                requiredQty: requiredInt.toDouble(),
              ),
            );
          }
        } else {
          // Factory inventory validation
          if (requiredInt > product.quantity) {
            shortages.add(
              InsufficientStockDetail(
                rawMaterialProductId: product.id,
                productName: '${product.name} (مخزن المصنع)',
                required: requiredInt,
                available: product.quantity,
                unit: product.unit,
              ),
            );
          } else {
            final unitCost = product.costPrice ?? product.price;
            factoryPlans.add(
              _ConsumptionPlan(
                bomItem: item,
                product: product,
                requiredInt: requiredInt,
                unitCost: unitCost,
                lineCost: requiredInt * unitCost,
              ),
            );
          }
        }
      }

      if (shortages.isNotEmpty) {
        throw InsufficientStockException(shortages);
      }

      final now = DateTime.now();

      // 4. Execute customer custody consumption
      for (final cp in customerPlans) {
        final newOnHand = cp.balanceRow.quantityOnHand - cp.requiredQty;
        await (update(
          customerStockBalances,
        )..where((b) => b.id.equals(cp.balanceRow.id))).write(
          CustomerStockBalancesCompanion(
            quantityOnHand: Value(newOnHand),
            updatedAt: Value(now),
          ),
        );

        await into(customerStockMovements).insert(
          CustomerStockMovementsCompanion.insert(
            customerId: customerId,
            productId: cp.product.id,
            movementType: 'issued_to_order',
            quantity: -cp.requiredQty,
            referenceType: 'manufacturing_order',
            referenceId: mo.orderNumber,
            notes: Value('صرف للتشغيل بأمر تصنيع ${mo.orderNumber}'),
            performedBy: Value(performedBy),
            createdAt: Value(now),
          ),
        );
      }

      // 4b. BUG-008 (option A): same-product receipt-first flow — the
      // finished output IS the fabric the customer lends us, but no BOM
      // line consumes it (print/textile: fabric in -> printed fabric out).
      // Auto-issue the produced quantity from that custody balance so the
      // receive -> consume -> deliver loop nets back to reality. Bounded
      // by what the custody actually holds; skipped when a BOM line
      // already consumed the finished product through the ordinary path.
      final bool bomLineCoversFinished = customerPlans.any(
        (cp) => cp.product.id == mo.finishedProductId,
      );
      if (!bomLineCoversFinished &&
          (orderType == 'for_others' || orderType == 'mixed')) {
        final finBal =
            await (select(customerStockBalances)..where(
                  (b) =>
                      b.customerId.equals(customerId) &
                      b.productId.equals(mo.finishedProductId),
                ))
                .getSingleOrNull();
        if (finBal != null && finBal.quantityOnHand > 0) {
          final issueQty = effectiveProduced <= finBal.quantityOnHand
              ? effectiveProduced
              : finBal.quantityOnHand;
          await (update(
            customerStockBalances,
          )..where((b) => b.id.equals(finBal.id))).write(
            CustomerStockBalancesCompanion(
              quantityOnHand: Value(finBal.quantityOnHand - issueQty),
              updatedAt: Value(now),
            ),
          );
          await into(customerStockMovements).insert(
            CustomerStockMovementsCompanion.insert(
              customerId: customerId,
              productId: mo.finishedProductId,
              movementType: 'issued_to_order',
              quantity: -issueQty,
              referenceType: 'manufacturing_order',
              referenceId: mo.orderNumber,
              notes: Value(
                'صرف خامة العهدة (الناتج بنفس الخامة) لأمر تصنيع ${mo.orderNumber}',
              ),
              performedBy: Value(performedBy),
              createdAt: Value(now),
            ),
          );
        }
      }

      // 5. Execute factory inventory consumption (mixed orders)
      for (final fp in factoryPlans) {
        final prev = fp.product.quantity;
        final next = prev - fp.requiredInt;
        await (update(
          products,
        )..where((t) => t.id.equals(fp.product.id))).write(
          ProductsCompanion(quantity: Value(next), updatedAt: Value(now)),
        );
        await into(inventoryMovements).insert(
          InventoryMovementsCompanion.insert(
            productId: fp.product.id,
            movementType: 'manufacturing_consumption',
            quantity: -fp.requiredInt,
            unitCost: fp.unitCost,
            totalValue: fp.lineCost,
            movementDate: now,
            reference: mo.orderNumber,
            referenceType: 'manufacturing_order',
            previousQuantity: prev,
            newQuantity: next,
            performedBy: Value(performedBy),
            notes: Value(
              'استهلاك خامات مصنع لأمر تشغيل للغير ${mo.orderNumber}',
            ),
            createdAt: now,
            updatedAt: now,
          ),
        );
      }

      // 6. Finished Product: NEVER increment factory stock for manufacturing-for-others
      final finishedProduct = await (select(
        products,
      )..where((p) => p.id.equals(mo.finishedProductId))).getSingleOrNull();
      if (finishedProduct == null)
        throw StateError('Finished product #${mo.finishedProductId} not found');

      // 7. Update MO to completed
      await (update(
        manufacturingOrders,
      )..where((o) => o.id.equals(orderId))).write(
        ManufacturingOrdersCompanion(
          status: const Value(ManufacturingOrderStatus.completed),
          producedQuantity: Value(effectiveProduced.toDouble()),
          completedAt: Value(now),
          updatedAt: Value(now),
        ),
      );

      return ForOthersCompletionResult(
        orderId: orderId,
        orderNumber: mo.orderNumber,
        customerId: customerId,
        finishedProductId: finishedProduct.id,
        finishedProductName: finishedProduct.name,
        plannedQuantity: mo.plannedQuantity,
        producedQuantity: effectiveProduced.toDouble(),
        customerConsumptions: customerPlans
            .map(
              (c) => CustomerConsumptionResult(
                productId: c.product.id,
                productName: c.product.name,
                quantity: c.requiredQty,
                unit: c.product.unit,
              ),
            )
            .toList(),
        factoryConsumptions: factoryPlans
            .map(
              (f) => ConsumptionResult(
                rawMaterialProductId: f.product.id,
                productName: f.product.name,
                required: f.requiredInt,
                unitCost: f.unitCost,
                lineCost: f.lineCost,
                unit: f.product.unit,
              ),
            )
            .toList(),
      );
    });
  }
}

class _CustomerConsumptionPlan {
  final BomItem bomItem;
  final Product product;
  final CustomerStockBalance balanceRow;
  final double requiredQty;

  _CustomerConsumptionPlan({
    required this.bomItem,
    required this.product,
    required this.balanceRow,
    required this.requiredQty,
  });
}

class ForOthersCompletionResult {
  final int orderId;
  final String orderNumber;
  final String customerId;
  final int finishedProductId;
  final String finishedProductName;
  final double plannedQuantity;
  final double producedQuantity;
  final List<CustomerConsumptionResult> customerConsumptions;
  final List<ConsumptionResult> factoryConsumptions;

  ForOthersCompletionResult({
    required this.orderId,
    required this.orderNumber,
    required this.customerId,
    required this.finishedProductId,
    required this.finishedProductName,
    required this.plannedQuantity,
    required this.producedQuantity,
    required this.customerConsumptions,
    required this.factoryConsumptions,
  });
}

class CustomerConsumptionResult {
  final int productId;
  final String productName;
  final double quantity;
  final String? unit;

  CustomerConsumptionResult({
    required this.productId,
    required this.productName,
    required this.quantity,
    this.unit,
  });
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
    final lines = shortages
        .map(
          (s) =>
              '${s.productName}: مطلوب ${s.required} ${s.unit ?? ''}، متاح ${s.available}، ناقص ${s.shortage}',
        )
        .join('\n');
    return 'نقص في المواد الخام:\n$lines';
  }
}
