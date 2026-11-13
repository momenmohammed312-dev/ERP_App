import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import '../database/tables/supplier_table.dart';
import '../database/tables/vegetable_shipments_table.dart';
import 'shipment_pricing_service.dart';

/// Computed financial & quantity statement for a single vegetable shipment.
///
/// Formula (for `commission` mode):
/// `netSupplierDue = totalSales - commissionAmount - shipmentExpenses`
/// where `totalSales = cashSales + creditSales` (supplier is settled on all
/// sold crates, cash and credit alike).
class ShipmentStatement {
  final VegetableShipment shipment;
  final Supplier? supplier;
  final int totalReceived;
  final int soldCount;
  final int toppingCount;
  final int remainingCount;
  final double cashSales;
  final double creditSales;
  final double totalSales;
  final double commissionPercentage;
  final double commissionAmount;
  final double shipmentExpenses;
  final List<Expense> expenses;
  final double netSupplierDue;
  final double paidForShipment;
  final double remainingForShipment;

  const ShipmentStatement({
    required this.shipment,
    required this.supplier,
    required this.totalReceived,
    required this.soldCount,
    required this.toppingCount,
    required this.remainingCount,
    required this.cashSales,
    required this.creditSales,
    required this.totalSales,
    required this.commissionPercentage,
    required this.commissionAmount,
    required this.shipmentExpenses,
    required this.expenses,
    required this.netSupplierDue,
    required this.paidForShipment,
    required this.remainingForShipment,
  });

  bool get isClosed => shipment.status == VegetableShipmentStatus.closed;
  bool get hasUnknownSupplier =>
      shipment.supplierId == DefaultSupplier.unknownId;
}

/// Computes shipment settlement statements, closes shipments with atomic
/// supplier ledger postings, reassigns default/unknown suppliers prior to
/// closing, and records supplier settlement payments.
class ShipmentSettlementService {
  final AppDatabase _db;
  static const _uuid = Uuid();

  ShipmentSettlementService(this._db);

  /// Canonical receipt reference used on [LedgerTransactions] for shipment
  /// settlement and shipment-linked supplier payments.
  static String shipmentReceiptNumber(int shipmentId) => 'SHP-$shipmentId';

  /// Computes the up-to-date [ShipmentStatement] for [shipmentId].
  Future<ShipmentStatement> getShipmentStatement(int shipmentId) async {
    final shipment = await _db.vegetableShipmentDao.getById(shipmentId);
    if (shipment == null) {
      throw ArgumentError('الشحنة #$shipmentId غير موجودة');
    }

    final supplier = await _db.supplierDao.getSupplierById(shipment.supplierId);

    // Non-voided invoice items linked to this shipment.
    final itemRows = await (_db.select(_db.invoiceItems).join([
      innerJoin(_db.invoices, _db.invoices.id.equalsExp(_db.invoiceItems.invoiceId)),
    ])
          ..where(_db.invoiceItems.shipmentId.equals(shipmentId))
          ..where(_db.invoices.status.equals('voided').not()))
        .get();

    // Any partial sales returns linked to this shipment (on non-voided invoices).
    final returnRows = await (_db.select(_db.salesReturnItems).join([
      innerJoin(
        _db.salesReturns,
        _db.salesReturns.id.equalsExp(_db.salesReturnItems.returnId),
      ),
      innerJoin(
        _db.invoices,
        _db.invoices.id.equalsExp(_db.salesReturns.originalInvoiceId),
      ),
    ])
          ..where(_db.salesReturnItems.shipmentId.equals(shipmentId))
          ..where(_db.invoices.status.equals('voided').not()))
        .get();

    final returnedByInvoiceItemId = <int, List<SalesReturnItem>>{};
    double unlinkedReturnTotal = 0.0;
    double unlinkedReturnCommission = 0.0;
    int unlinkedReturnQty = 0;

    for (final row in returnRows) {
      final ri = row.readTable(_db.salesReturnItems);
      if (ri.invoiceItemId != null) {
        returnedByInvoiceItemId.putIfAbsent(ri.invoiceItemId!, () => []).add(ri);
      } else {
        unlinkedReturnTotal += ri.totalPrice;
        unlinkedReturnCommission += ri.commission;
        unlinkedReturnQty += ri.quantity;
      }
    }

    int soldCount = 0;
    double cashSales = 0.0;
    double creditSales = 0.0;
    double totalSales = 0.0;
    double recordedCommission = 0.0;

    // Group net shipment sales per invoice so cash/credit ratio stays exact.
    final invoiceNetByInvoice = <int, (Invoice, double)>{};

    for (final row in itemRows) {
      final item = row.readTable(_db.invoiceItems);
      final inv = row.readTable(_db.invoices);

      final itemReturns = returnedByInvoiceItemId[item.id] ?? const [];
      final retQty = itemReturns.fold<int>(0, (s, r) => s + r.quantity);
      final retTotal = itemReturns.fold<double>(0.0, (s, r) => s + r.totalPrice);
      final retCommission =
          itemReturns.fold<double>(0.0, (s, r) => s + r.commission);

      final netQty = (item.quantity - retQty).clamp(0, 1 << 30);
      final grossLine = (item.price * item.quantity) - item.discount;
      final netLine = (grossLine - retTotal).clamp(0.0, double.infinity);

      soldCount += netQty;
      totalSales += netLine;
      recordedCommission +=
          (item.commission - retCommission).clamp(0.0, double.infinity);

      final existing = invoiceNetByInvoice[inv.id];
      invoiceNetByInvoice[inv.id] = (
        inv,
        (existing?.$2 ?? 0.0) + netLine,
      );
    }

    if (unlinkedReturnTotal > 0 || unlinkedReturnQty > 0) {
      soldCount = (soldCount - unlinkedReturnQty).clamp(0, 1 << 30);
      totalSales = (totalSales - unlinkedReturnTotal).clamp(0.0, double.infinity);
      recordedCommission = (recordedCommission - unlinkedReturnCommission)
          .clamp(0.0, double.infinity);
    }

    for (final entry in invoiceNetByInvoice.values) {
      final inv = entry.$1;
      final invShipSales = entry.$2;
      if (inv.totalAmount > 0) {
        final paidRatio = (inv.paidAmount / inv.totalAmount).clamp(0.0, 1.0);
        final cashPart = invShipSales * paidRatio;
        cashSales += cashPart;
        creditSales += invShipSales - cashPart;
      } else {
        if (inv.paymentMethod == 'credit') {
          creditSales += invShipSales;
        } else {
          cashSales += invShipSales;
        }
      }
    }

    // Re-normalize cash/credit if unlinked returns adjusted totalSales.
    final splitSum = cashSales + creditSales;
    if (splitSum > 0 && (splitSum - totalSales).abs() > 0.001) {
      final ratio = totalSales / splitSum;
      cashSales *= ratio;
      creditSales *= ratio;
    }

    final commPct = shipment.commissionPercentage ?? 0.0;
    double commissionAmount = 0.0;
    if (shipment.pricingMode == ShipmentPricingMode.commission) {
      if (recordedCommission > 0) {
        commissionAmount = recordedCommission;
      } else if (totalSales > 0 && commPct > 0) {
        commissionAmount =
            ShipmentPricingService.calculateCommission(totalSales, commPct);
      }
    }

    final expenses = await _db.expenseDao.getExpensesByShipment(shipmentId);
    final shipmentExpenses =
        expenses.fold<double>(0.0, (sum, e) => sum + e.amount);

    final double netSupplierDue;
    switch (shipment.pricingMode) {
      case ShipmentPricingMode.commission:
        netSupplierDue = totalSales - commissionAmount - shipmentExpenses;
      case ShipmentPricingMode.perUnit:
        netSupplierDue =
            (soldCount * (shipment.costPricePerBarnika ?? 0.0)) -
                shipmentExpenses;
      case ShipmentPricingMode.lumpSum:
        netSupplierDue =
            (shipment.lumpSumCost ?? shipment.totalCost) - shipmentExpenses;
      default:
        netSupplierDue = totalSales - commissionAmount - shipmentExpenses;
    }

    final receiptNo = shipmentReceiptNumber(shipmentId);
    final paidRows = await (_db.select(_db.ledgerTransactions)
          ..where(
            (t) =>
                t.entityType.equals('Supplier') &
                t.origin.equals('payment') &
                t.receiptNumber.equals(receiptNo),
          ))
        .get();
    final paidForShipment =
        paidRows.fold<double>(0.0, (sum, t) => sum + (t.debit - t.credit));

    final remainingCount = (shipment.totalBarnikaCount -
            shipment.barnikaSoldCount -
            shipment.toppingCount)
        .clamp(0, 1 << 30);

    return ShipmentStatement(
      shipment: shipment,
      supplier: supplier,
      totalReceived: shipment.totalBarnikaCount,
      soldCount: soldCount,
      toppingCount: shipment.toppingCount,
      remainingCount: remainingCount,
      cashSales: cashSales,
      creditSales: creditSales,
      totalSales: totalSales,
      commissionPercentage: commPct,
      commissionAmount: commissionAmount,
      shipmentExpenses: shipmentExpenses,
      expenses: expenses,
      netSupplierDue: netSupplierDue,
      paidForShipment: paidForShipment,
      remainingForShipment: netSupplierDue - paidForShipment,
    );
  }

  /// Reassigns the supplier on an open shipment (for example replacing the
  /// default «مورد غير محدد» once the shipment's supplier is confirmed).
  Future<VegetableShipment> reassignSupplier({
    required int shipmentId,
    required String newSupplierId,
  }) async {
    final trimmedId = newSupplierId.trim();
    if (trimmedId.isEmpty) {
      throw ArgumentError('معرف المورد مطلوب');
    }

    return _db.transaction(() async {
      final shipment = await _db.vegetableShipmentDao.getById(shipmentId);
      if (shipment == null) {
        throw ArgumentError('الشحنة #$shipmentId غير موجودة');
      }
      if (shipment.status == VegetableShipmentStatus.closed) {
        throw StateError('لا يمكن تغيير المورد بعد قفل الشحنة');
      }

      if (trimmedId == DefaultSupplier.unknownId) {
        await _db.supplierDao.ensureUnknownSupplier();
      } else {
        final supplier = await _db.supplierDao.getSupplierById(trimmedId);
        if (supplier == null) {
          throw ArgumentError('المورد غير موجود ($trimmedId)');
        }
      }

      final updated = shipment.copyWith(supplierId: trimmedId);
      await _db.vegetableShipmentDao.updateShipment(updated);
      return updated;
    });
  }

  /// Atomically closes [shipmentId], computes its final [ShipmentStatement],
  /// and posts the net supplier payable (`netSupplierDue`) to
  /// [LedgerTransactions] under a deterministic ID (`shp_settle_<id>`) so a
  /// shipment can never be double-settled.
  Future<ShipmentStatement> closeShipment({
    required int shipmentId,
    DateTime? closedAt,
    String? notes,
  }) async {
    final resolvedClosedAt = closedAt ?? DateTime.now();

    return _db.transaction(() async {
      final shipment = await _db.vegetableShipmentDao.getById(shipmentId);
      if (shipment == null) {
        throw ArgumentError('الشحنة #$shipmentId غير موجودة');
      }
      if (shipment.status == VegetableShipmentStatus.closed) {
        throw StateError('الشحنة #${shipment.shipmentNumber} مقفولة بالفعل');
      }

      final statement = await getShipmentStatement(shipmentId);

      final mergedNotes = (notes != null && notes.trim().isNotEmpty)
          ? notes.trim()
          : shipment.notes;

      await (_db.update(_db.vegetableShipments)
            ..where((t) => t.id.equals(shipmentId)))
          .write(
        VegetableShipmentsCompanion(
          status: const Value(VegetableShipmentStatus.closed),
          closedAt: Value(resolvedClosedAt),
          notes: Value(mergedNotes),
        ),
      );

      final settleId = 'shp_settle_$shipmentId';
      final receiptNo = shipmentReceiptNumber(shipmentId);
      final netDue = statement.netSupplierDue;

      if (netDue > 0.0001) {
        await _db.ledgerDao.insertTransaction(
          LedgerTransactionsCompanion.insert(
            id: settleId,
            entityType: 'Supplier',
            refId: shipment.supplierId,
            date: resolvedClosedAt,
            description:
                'تسوية شحنة #${shipment.shipmentNumber} '
                '(مبيعات ${statement.totalSales.toStringAsFixed(2)} '
                '− عمولة ${statement.commissionAmount.toStringAsFixed(2)} '
                '− مصروفات ${statement.shipmentExpenses.toStringAsFixed(2)})',
            debit: const Value(0.0),
            credit: Value(netDue),
            origin: 'shipment_settlement',
            paymentMethod: const Value('credit'),
            receiptNumber: Value(receiptNo),
          ),
        );
      } else if (netDue < -0.0001) {
        await _db.ledgerDao.insertTransaction(
          LedgerTransactionsCompanion.insert(
            id: settleId,
            entityType: 'Supplier',
            refId: shipment.supplierId,
            date: resolvedClosedAt,
            description:
                'تسوية شحنة #${shipment.shipmentNumber} (مصروفات/عمولة زائدة عن المبيعات)',
            debit: Value(-netDue),
            credit: const Value(0.0),
            origin: 'shipment_settlement',
            paymentMethod: const Value('credit'),
            receiptNumber: Value(receiptNo),
          ),
        );
      }

      return getShipmentStatement(shipmentId);
    });
  }

  /// Atomically records a payment made to [supplierId], optionally linked to
  /// [shipmentId] via `SHP-<id>` for shipment-level balance tracking.
  Future<LedgerTransaction> recordSupplierPayment({
    required String supplierId,
    required double amount,
    int? shipmentId,
    String paymentMethod = 'cash',
    DateTime? date,
    String? notes,
  }) async {
    if (supplierId.trim().isEmpty) {
      throw ArgumentError('معرف المورد مطلوب');
    }
    if (amount <= 0) {
      throw ArgumentError('مبلغ الدفعة يجب أن يكون أكبر من صفر');
    }

    return _db.transaction(() async {
      final supplier = await _db.supplierDao.getSupplierById(supplierId);
      if (supplier == null) {
        throw ArgumentError('المورد غير موجود ($supplierId)');
      }

      String? receiptNo;
      String defaultDesc = 'دفعة سداد للمورد';
      if (shipmentId != null) {
        final shipment = await _db.vegetableShipmentDao.getById(shipmentId);
        if (shipment == null) {
          throw ArgumentError('الشحنة #$shipmentId غير موجودة');
        }
        receiptNo = shipmentReceiptNumber(shipmentId);
        defaultDesc = 'دفعة للمورد على شحنة #${shipment.shipmentNumber}';
      }

      final desc = (notes != null && notes.trim().isNotEmpty)
          ? notes.trim()
          : defaultDesc;

      return _db.ledgerDao.insertTransaction(
        LedgerTransactionsCompanion.insert(
          id: 'shp_pay_${_uuid.v4()}',
          entityType: 'Supplier',
          refId: supplierId,
          date: date ?? DateTime.now(),
          description: desc,
          debit: Value(amount),
          credit: const Value(0.0),
          origin: 'payment',
          paymentMethod: Value(paymentMethod),
          receiptNumber: Value(receiptNo),
        ),
      );
    });
  }
}
