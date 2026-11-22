import 'package:drift/drift.dart';

import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/dao/manufacturing_cost_component_dao.dart';
import 'package:pos_offline_desktop/core/database/tables/consumption_record.dart';
import 'package:pos_offline_desktop/core/database/tables/external_operation_records.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_cost_components_table.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_costing_tables.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_deliveries_table.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_orders_table.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_scrap_table.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_stages_table.dart';
import 'package:pos_offline_desktop/core/database/tables/product_table.dart';

part 'manufacturing_costing_dao.g.dart';

/// Internal cost & margin breakdown computed per FEAT-039 §5 + D-11.
class OrderCostBreakdown {
  /// Σ(ConsumptionRecord.actualQty × unitCostSnapshot) for factory_owned only
  /// (customer-owned materials contribute 0.0).
  final double materialCost;

  /// Σ(stage.laborHours × stage.laborRate).
  final double laborCost;

  /// Σ(stage.machineHours × stage.machineRate).
  final double machineCost;

  /// Σ(ExternalOperationRecord.cost).
  final double externalCost;

  /// Σ(ManufacturingCostComponent computed amount).
  final double otherCost;

  final double totalActualCost;
  final double plannedCost;

  /// plannedCost − totalActualCost (positive = under budget / favorable).
  final double variance;

  final double deliveredRevenue;
  final double extraMaterialsRevenue;
  final double scrapCompensation;

  /// (deliveredRevenue + extraMaterialsRevenue − scrapCompensation) − totalActualCost.
  final double actualMargin;

  const OrderCostBreakdown({
    required this.materialCost,
    required this.laborCost,
    required this.machineCost,
    required this.externalCost,
    required this.otherCost,
    required this.totalActualCost,
    required this.plannedCost,
    required this.variance,
    required this.deliveredRevenue,
    required this.extraMaterialsRevenue,
    required this.scrapCompensation,
    required this.actualMargin,
  });
}

/// DAO for internal order costing (D-11), frozen cost snapshots, and
/// customer-approved extra factory materials (D-04, D-05, D-08) — FEAT-039 Phase 3.
@DriftAccessor(tables: [
  ManufacturingCostSnapshots,
  ExtraMaterialApprovals,
  ManufacturingOrders,
  ManufacturingStages,
  ConsumptionRecords,
  ExternalOperationRecords,
  ManufacturingCostComponents,
  ManufacturingDeliveries,
  ManufacturingDeliveryItems,
  ManufacturingScraps,
  Products,
])
class ManufacturingCostingDao extends DatabaseAccessor<AppDatabase>
    with _$ManufacturingCostingDaoMixin {
  ManufacturingCostingDao(super.db);

  static double _round2(double v) => double.parse(v.toStringAsFixed(2));

  // ── Internal Costing Formulas (§5, D-11) ──

  Future<OrderCostBreakdown> computeOrderCost(int orderId) async {
    final mo = await (select(manufacturingOrders)
          ..where((o) => o.id.equals(orderId)))
        .getSingleOrNull();
    if (mo == null) {
      throw ArgumentError('ManufacturingOrder #$orderId not found');
    }

    // 1. Material: factory_owned only (customer_owned value = 0.0)
    final consumptions = await (select(consumptionRecords)
          ..where((c) => c.manufacturingOrderId.equals(orderId)))
        .get();
    double materialCost = 0.0;
    double plannedMaterialCost = 0.0;
    for (final c in consumptions) {
      if (c.ownershipType != 'factory_owned') continue;
      final unitCost = c.unitCostSnapshot ?? 0.0;
      materialCost += (c.actualQty ?? 0.0) * unitCost;
      plannedMaterialCost += (c.plannedQty ?? 0.0) * unitCost;
    }

    // 2. Labor & Machine from stages
    final stages = await (select(manufacturingStages)
          ..where((s) => s.manufacturingOrderId.equals(orderId)))
        .get();
    double laborCost = 0.0;
    double machineCost = 0.0;
    for (final s in stages) {
      laborCost += s.laborHours * s.laborRate;
      machineCost += s.machineHours * s.machineRate;
    }

    // 3. External operations
    final extOps = await (select(externalOperationRecords)
          ..where((e) => e.manufacturingOrderId.equals(orderId)))
        .get();
    final externalCost = extOps.fold<double>(0.0, (s, e) => s + e.cost);

    // 4. Other approved cost components
    final components = await (select(manufacturingCostComponents)
          ..where((c) => c.manufacturingOrderId.equals(orderId)))
        .get();
    final refQty =
        mo.producedQuantity > 0 ? mo.producedQuantity : mo.plannedQuantity;
    double otherCost = 0.0;
    for (final comp in components) {
      final storedAmt = comp.computedAmount ?? 0.0;
      otherCost += storedAmt > 0
          ? storedAmt
          : ManufacturingCostComponentDao.computeAmount(
              costType: comp.costType,
              value: comp.value,
              materialCost: materialCost,
              producedQuantity: refQty,
            );
    }

    final totalActualCost =
        _round2(materialCost + laborCost + machineCost + externalCost + otherCost);
    final plannedCost = _round2(plannedMaterialCost + otherCost);
    final variance = _round2(plannedCost - totalActualCost);

    // 5. Margin = (delivered + approved extras - scrap compensation) - totalActualCost
    final deliveredQty =
        await db.manufacturingDeliveryDao.getTotalDeliveredQuantity(orderId);
    final deliveredRevenue = _round2(deliveredQty * (mo.serviceUnitPrice ?? 0.0));

    final approvals = await (select(extraMaterialApprovals)
          ..where(
            (a) =>
                a.manufacturingOrderId.equals(orderId) &
                a.status.equals('approved'),
          ))
        .get();
    final extraMaterialsRevenue = _round2(
      approvals.fold<double>(0.0, (s, a) => s + a.approvedAmount),
    );

    final scraps = await (select(manufacturingScraps)
          ..where((s) => s.manufacturingOrderId.equals(orderId)))
        .get();
    final scrapCompensation = _round2(
      scraps
          .where(
            (s) =>
                s.faultParty == 'factory' &&
                s.compensationAction == 'deducted_from_invoice',
          )
          .fold<double>(0.0, (s, r) => s + (r.compensationAmount ?? 0.0)),
    );

    final actualMargin = _round2(
      (deliveredRevenue + extraMaterialsRevenue - scrapCompensation) -
          totalActualCost,
    );

    return OrderCostBreakdown(
      materialCost: _round2(materialCost),
      laborCost: _round2(laborCost),
      machineCost: _round2(machineCost),
      externalCost: _round2(externalCost),
      otherCost: _round2(otherCost),
      totalActualCost: totalActualCost,
      plannedCost: plannedCost,
      variance: variance,
      deliveredRevenue: deliveredRevenue,
      extraMaterialsRevenue: extraMaterialsRevenue,
      scrapCompensation: scrapCompensation,
      actualMargin: actualMargin,
    );
  }

  /// Freezes the current cost & margin breakdown into [ManufacturingCostSnapshots].
  Future<ManufacturingCostSnapshot> freezeCostSnapshot(
    int orderId, {
    String? notes,
  }) {
    return transaction(() async {
      final breakdown = await computeOrderCost(orderId);
      final id = await into(manufacturingCostSnapshots).insert(
        ManufacturingCostSnapshotsCompanion.insert(
          manufacturingOrderId: orderId,
          materialCost: Value(breakdown.materialCost),
          laborCost: Value(breakdown.laborCost),
          machineCost: Value(breakdown.machineCost),
          externalCost: Value(breakdown.externalCost),
          otherCost: Value(breakdown.otherCost),
          totalActualCost: Value(breakdown.totalActualCost),
          plannedCost: Value(breakdown.plannedCost),
          variance: Value(breakdown.variance),
          deliveredRevenue: Value(breakdown.deliveredRevenue),
          extraMaterialsRevenue: Value(breakdown.extraMaterialsRevenue),
          scrapCompensation: Value(breakdown.scrapCompensation),
          actualMargin: Value(breakdown.actualMargin),
          isFrozen: const Value(true),
          notes: Value(notes),
        ),
      );
      return (select(manufacturingCostSnapshots)
            ..where((s) => s.id.equals(id)))
          .getSingle();
    });
  }

  Future<ManufacturingCostSnapshot?> getLatestSnapshot(int orderId) {
    return (select(manufacturingCostSnapshots)
          ..where((s) => s.manufacturingOrderId.equals(orderId))
          ..orderBy([(s) => OrderingTerm.desc(s.id)])
          ..limit(1))
        .getSingleOrNull();
  }

  Stream<ManufacturingCostSnapshot?> watchLatestSnapshot(int orderId) {
    return (select(manufacturingCostSnapshots)
          ..where((s) => s.manufacturingOrderId.equals(orderId))
          ..orderBy([(s) => OrderingTerm.desc(s.id)])
          ..limit(1))
        .watchSingleOrNull();
  }

  // ── Extra Factory Material Approvals (D-04, D-05, D-08) ──

  /// Requests customer approval for extra factory material supplied to an order.
  ///
  /// Uses [Products.costPrice] snapshot (D-08 — fallback to `price` only if
  /// `costPrice == null`) with default `marginPercent = 0.0`.
  Future<ExtraMaterialApproval> requestExtraMaterial({
    required int orderId,
    required int productId,
    required double quantity,
    required String requestedBy,
    double marginPercent = 0.0,
    String? notes,
  }) {
    return transaction(() async {
      if (quantity <= 0) {
        throw ArgumentError.value(quantity, 'quantity', 'Quantity must be > 0');
      }
      if (marginPercent < 0) {
        throw ArgumentError.value(
          marginPercent,
          'marginPercent',
          'marginPercent must be >= 0',
        );
      }
      if (requestedBy.trim().isEmpty) {
        throw ArgumentError('requestedBy is required');
      }

      final mo = await (select(manufacturingOrders)
            ..where((o) => o.id.equals(orderId)))
          .getSingleOrNull();
      if (mo == null) {
        throw ArgumentError('ManufacturingOrder #$orderId not found');
      }

      final product = await (select(products)
            ..where((p) => p.id.equals(productId)))
          .getSingleOrNull();
      if (product == null) {
        throw ArgumentError('Product #$productId not found');
      }

      final unitCost = product.costPrice ?? product.price;
      final amount = _round2(quantity * unitCost * (1 + marginPercent / 100));

      final id = await into(extraMaterialApprovals).insert(
        ExtraMaterialApprovalsCompanion.insert(
          manufacturingOrderId: orderId,
          productId: productId,
          quantity: quantity,
          unitCostSnapshot: Value(unitCost),
          marginPercent: Value(marginPercent),
          approvedAmount: Value(amount),
          status: const Value('pending'),
          requestedBy: requestedBy.trim(),
          notes: Value(notes),
        ),
      );
      return (select(extraMaterialApprovals)..where((a) => a.id.equals(id)))
          .getSingle();
    });
  }

  Future<ExtraMaterialApproval> approveExtraMaterial({
    required int approvalId,
    required String approvedBy,
    String? authorizationRef,
    double? overrideAmount,
  }) {
    return transaction(() async {
      if (approvedBy.trim().isEmpty) {
        throw ArgumentError('approvedBy is required');
      }
      if (overrideAmount != null && overrideAmount < 0) {
        throw ArgumentError('overrideAmount must be >= 0');
      }

      final row = await (select(extraMaterialApprovals)
            ..where((a) => a.id.equals(approvalId)))
          .getSingleOrNull();
      if (row == null) {
        throw ArgumentError('ExtraMaterialApproval #$approvalId not found');
      }
      if (row.status != 'pending') {
        throw StateError(
          'ExtraMaterialApproval #$approvalId is already "${row.status}"',
        );
      }

      await (update(extraMaterialApprovals)
            ..where((a) => a.id.equals(approvalId)))
          .write(
        ExtraMaterialApprovalsCompanion(
          status: const Value('approved'),
          approvedBy: Value(approvedBy.trim()),
          approvedAt: Value(DateTime.now()),
          authorizationRef: Value(authorizationRef),
          approvedAmount: overrideAmount != null
              ? Value(_round2(overrideAmount))
              : const Value.absent(),
        ),
      );

      return (select(extraMaterialApprovals)
            ..where((a) => a.id.equals(approvalId)))
          .getSingle();
    });
  }

  Future<ExtraMaterialApproval> rejectExtraMaterial({
    required int approvalId,
    String? notes,
  }) {
    return transaction(() async {
      final row = await (select(extraMaterialApprovals)
            ..where((a) => a.id.equals(approvalId)))
          .getSingleOrNull();
      if (row == null) {
        throw ArgumentError('ExtraMaterialApproval #$approvalId not found');
      }
      if (row.status != 'pending') {
        throw StateError(
          'ExtraMaterialApproval #$approvalId is already "${row.status}"',
        );
      }

      await (update(extraMaterialApprovals)
            ..where((a) => a.id.equals(approvalId)))
          .write(
        ExtraMaterialApprovalsCompanion(
          status: const Value('rejected'),
          notes: notes != null ? Value(notes) : const Value.absent(),
        ),
      );

      return (select(extraMaterialApprovals)
            ..where((a) => a.id.equals(approvalId)))
          .getSingle();
    });
  }

  Future<List<ExtraMaterialApproval>> getApprovalsForOrder(int orderId) {
    return (select(extraMaterialApprovals)
          ..where((a) => a.manufacturingOrderId.equals(orderId))
          ..orderBy([(a) => OrderingTerm.desc(a.id)]))
        .get();
  }

  Stream<List<ExtraMaterialApproval>> watchApprovalsForOrder(int orderId) {
    return (select(extraMaterialApprovals)
          ..where((a) => a.manufacturingOrderId.equals(orderId))
          ..orderBy([(a) => OrderingTerm.desc(a.id)]))
        .watch();
  }
}
