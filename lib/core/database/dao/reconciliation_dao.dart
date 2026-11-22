import 'dart:math' as math;

import 'package:drift/drift.dart';

import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/tables/consumption_record.dart';
import 'package:pos_offline_desktop/core/database/tables/customer_material_receipts_table.dart';
import 'package:pos_offline_desktop/core/database/tables/external_operation_records.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_orders_table.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_scrap_table.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_stages_table.dart';
import 'package:pos_offline_desktop/core/database/tables/stage_yield.dart';

part 'reconciliation_dao.g.dart';

/// Per-material custody reconciliation line for customer-owned raw materials
/// on one manufacturing order (FEAT-039 Phase 1, plan §2.1 + D-02).
///
/// Equation per raw-material product:
/// `Issued = Consumed + ReturnedExcess + Remaining`
class CustodyLine {
  final int productId;

  /// Σ abs(quantity) from [CustomerStockMovements] issued to this order.
  final double issued;

  /// Σ actualQty from [ConsumptionRecords] (`ownershipType == 'customer_owned'`).
  final double consumed;

  /// Σ abs(quantity) from [CustomerStockMovements] (`movementType == 'return_excess'`).
  final double returnedExcess;

  CustodyLine({
    required this.productId,
    required this.issued,
    required this.consumed,
    required this.returnedExcess,
  });

  /// Unaccounted custody balance: `issued − consumed − returnedExcess` (≥ −tol).
  double get remaining => issued - consumed - returnedExcess;
}

/// Computed reconciliation summary for one order (FEAT-039 Phase 1,
/// plan §2.1 + §2.3 + D-02).
class ReconciliationSummary {
  /// Per-product customer-owned raw-material custody lines (D-02).
  final Map<int, CustodyLine> custody;

  /// Σ stage outputs (`disposition == 'returned_to_customer'`).producedQuantity.
  final double returnedOutputs;

  /// Σ [ManufacturingScraps.quantity] where `faultParty == 'customer'` and
  /// `productId == mo.finishedProductId` — accepted final Lost disposition (§2.3(e)).
  final double scrapped;

  /// Σ `(sentQty − receivedQty − scrapQty)` of [ExternalOperationRecords].
  final double atVendor;

  /// Σ [ManufacturingStageOutput.producedQuantity] across all dispositions.
  final double produced;

  /// `mo.producedQuantity − Σ outputs.producedQuantity` — produced units not
  /// yet assigned a stage output disposition (the WIP term of §2.3).
  final double remainingWip;

  /// Whether reconciliation-flow data (stage outputs, scraps, or external ops)
  /// exists for the order — i.e. whether the WIP/closure gates apply.
  final bool hasReconciliationData;

  ReconciliationSummary({
    required this.custody,
    required this.returnedOutputs,
    required this.scrapped,
    required this.atVendor,
    required this.produced,
    required this.remainingWip,
    required this.hasReconciliationData,
  });
}

/// Small absolute tolerance for reconciliation residues (plan O-1).
const double _reconTolerance = 0.01;

@DriftAccessor(tables: [
  ConsumptionRecords,
  CustomerStockMovements,
  StageYieldRecords,
  ExternalOperationRecords,
  ManufacturingOrders,
  ManufacturingScraps,
  ManufacturingStageOutputs,
])
class ReconciliationDao extends DatabaseAccessor<AppDatabase>
    with _$ReconciliationDaoMixin {
  ReconciliationDao(super.db);

  static const String _ownerCustomer = 'customer_owned';
  static const String _dispReturnedToCustomer = 'returned_to_customer';
  static const String _refTypeMo = 'manufacturing_order';
  static const List<String> _issuedMovementTypes = [
    'issued_to_order',
    'manufacturing_consumption',
  ];
  static const String _returnExcessMovementType = 'return_excess';

  Future<ManufacturingOrder?> getOrder(int orderId) {
    return (select(db.manufacturingOrders)
          ..where((t) => t.id.equals(orderId)))
        .getSingleOrNull();
  }

  /// Computes per-material customer custody lines and order-level WIP/vendor/scrap
  /// reconciliation state for [orderId] (D-02, plan §2.1 & §2.3).
  Future<ReconciliationSummary> reconcile(int orderId) async {
    final mo = await getOrder(orderId);
    if (mo == null) {
      throw ArgumentError('ManufacturingOrder #$orderId not found');
    }

    // Main flow writes referenceId = mo.orderNumber; JW branch writes mo.id.toString().
    final orderRefs = <String>{mo.orderNumber, mo.id.toString()}.toList();

    final custodyMoves = await (select(db.customerStockMovements)
          ..where(
            (m) =>
                m.referenceType.equals(_refTypeMo) &
                m.referenceId.isIn(orderRefs),
          ))
        .get();

    final issuedByProduct = <int, double>{};
    final returnedExcessByProduct = <int, double>{};
    for (final m in custodyMoves) {
      if (_issuedMovementTypes.contains(m.movementType)) {
        issuedByProduct[m.productId] =
            (issuedByProduct[m.productId] ?? 0.0) + m.quantity.abs();
      } else if (m.movementType == _returnExcessMovementType) {
        // Expansion point for D-02: return_excess custody movements will be
        // emitted when excess raw-material return is wired in a later batch.
        returnedExcessByProduct[m.productId] =
            (returnedExcessByProduct[m.productId] ?? 0.0) + m.quantity.abs();
      }
    }

    // Customer-owned analytical consumption grouped per raw-material product.
    final consumptionRows = await (select(db.consumptionRecords)
          ..where(
            (t) =>
                t.manufacturingOrderId.equals(orderId) &
                t.ownershipType.equals(_ownerCustomer),
          ))
        .get();
    final consumedByProduct = <int, double>{};
    for (final r in consumptionRows) {
      consumedByProduct[r.materialProductId] =
          (consumedByProduct[r.materialProductId] ?? 0.0) +
              (r.actualQty ?? 0.0);
    }

    final productIds = <int>{
      ...issuedByProduct.keys,
      ...consumedByProduct.keys,
      ...returnedExcessByProduct.keys,
    }.toList()
      ..sort();

    final custody = <int, CustodyLine>{
      for (final pid in productIds)
        pid: CustodyLine(
          productId: pid,
          issued: issuedByProduct[pid] ?? 0.0,
          consumed: consumedByProduct[pid] ?? 0.0,
          returnedExcess: returnedExcessByProduct[pid] ?? 0.0,
        ),
    };

    final outputs = await (select(db.manufacturingStageOutputs)
          ..where((t) => t.manufacturingOrderId.equals(orderId)))
        .get();
    final returnedOutputs = outputs
        .where((o) => o.disposition == _dispReturnedToCustomer)
        .fold<double>(0.0, (s, o) => s + o.producedQuantity);
    final produced = outputs.fold<double>(
      0.0,
      (s, o) => s + o.producedQuantity,
    );

    final scraps = await (select(db.manufacturingScraps)
          ..where((t) => t.manufacturingOrderId.equals(orderId)))
        .get();
    // Customer-fault scrap on the finished good counts toward finished disposition.
    final scrapped = scraps
        .where(
          (s) =>
              s.faultParty == 'customer' &&
              s.productId == mo.finishedProductId,
        )
        .fold<double>(0.0, (s, r) => s + r.quantity);

    final externalOps = await (select(db.externalOperationRecords)
          ..where((t) => t.manufacturingOrderId.equals(orderId)))
        .get();
    final atVendor = externalOps
        .map((o) => o.sentQty - o.receivedQty - o.scrapQty)
        .fold<double>(0.0, (s, d) => s + d);

    final remainingWip = mo.producedQuantity - produced;

    return ReconciliationSummary(
      custody: custody,
      returnedOutputs: returnedOutputs,
      scrapped: scrapped,
      atVendor: atVendor,
      produced: produced,
      remainingWip: remainingWip,
      hasReconciliationData:
          outputs.isNotEmpty || scraps.isNotEmpty || externalOps.isNotEmpty,
    );
  }

  /// D-02 per-product custody-equation violations:
  /// For every customer-owned raw material on the order,
  /// `remaining = issued − consumed − returnedExcess` must be ≥ −tol.
  Future<List<String>> checkCustodyEquations(int orderId) async {
    final s = await reconcile(orderId);
    final violations = <String>[];
    for (final line in s.custody.values) {
      if (line.remaining < -_reconTolerance) {
        violations.add(
          'Custody equation (D-02) violated for product #${line.productId}: '
          'Issued (${line.issued}) − Consumed (${line.consumed}) − '
          'ReturnedExcess (${line.returnedExcess}) = Remaining '
          '(${line.remaining.toStringAsFixed(2)}) < −tolerance — factory '
          'consumed more than issued (overconsumption requires a D-04 '
          'extra-material authorization)',
        );
      }
    }
    return violations;
  }

  Future<void> assertCustodyEquation(int orderId) async {
    final violations = await checkCustodyEquations(orderId);
    if (violations.isNotEmpty) {
      throw StateError(violations.join('; '));
    }
  }

  /// Single-disposition check (plan §2.3): for the finished good,
  /// `returnedOutputs + scrapped` must not exceed `mo.producedQuantity`.
  Future<List<String>> checkSingleDisposition(int orderId) async {
    final mo = await getOrder(orderId);
    if (mo == null) {
      throw ArgumentError('ManufacturingOrder #$orderId not found');
    }
    final s = await reconcile(orderId);
    final violations = <String>[];
    final overDispositioned =
        s.returnedOutputs + s.scrapped - mo.producedQuantity;
    if (overDispositioned > _reconTolerance) {
      violations.add(
        'Single disposition (§2.3) violated: returnedOutputs '
        '(${s.returnedOutputs}) + scrapped (${s.scrapped}) exceed produced '
        '(${mo.producedQuantity}) — a unit is double-dispositioned',
      );
    }
    return violations;
  }

  Future<void> assertSingleDisposition(int orderId) async {
    final violations = await checkSingleDisposition(orderId);
    if (violations.isNotEmpty) {
      throw StateError(violations.join('; '));
    }
  }

  /// Order-completion gates (plan §6.3 + §2.3):
  ///
  /// * (a) `produced ≤ planned` for `for_others` orders (plan §6.3 A2).
  /// * (b) At closure (order completed): `max(0, RemainingWIP) + AtExternalVendor ≈ 0`
  ///   (plan §2.3 — `Lost`/scrap is an accepted final disposition and does not
  ///   block order closure). Only checked when reconciliation data exists so
  ///   legacy orders without routing records remain unaffected.
  Future<List<String>> checkCompletionGate(ManufacturingOrder mo) async {
    final violations = <String>[];

    // (a) plan §6.3 A2 — produced ≤ planned (for_others).
    if (mo.orderType == 'for_others' &&
        mo.producedQuantity > mo.plannedQuantity + _reconTolerance) {
      violations.add(
        'Order completion gate (a): produced (${mo.producedQuantity}) exceeds '
        'planned (${mo.plannedQuantity}) — MO #${mo.id} for_others (plan §6.3 A2)',
      );
    }

    // (b) plan §2.3 — at closure: max(0, RemainingWIP) + AtExternalVendor ≈ 0.
    // Lost (customer scrap) is already a final disposition and is excluded.
    if (mo.status == ManufacturingOrderStatus.completed) {
      final s = await reconcile(mo.id);
      if (s.hasReconciliationData) {
        final residue = math.max(0.0, s.remainingWip) + s.atVendor;
        if (residue > _reconTolerance) {
          violations.add(
            'Order closure gate (b): RemainingWIP (${s.remainingWip}) + '
            'AtExternalVendor (${s.atVendor}) ≠ 0 — MO #${mo.id} (plan §2.3)',
          );
        }
      }
    }

    return violations;
  }

  Future<void> assertCompletionGate(ManufacturingOrder mo) async {
    final violations = await checkCompletionGate(mo);
    if (violations.isNotEmpty) {
      throw StateError(violations.join('; '));
    }
  }
}
