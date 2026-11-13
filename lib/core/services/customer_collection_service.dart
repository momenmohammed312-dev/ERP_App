import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import 'invoice_number_formatter.dart';

/// How much of a customer collection was applied to a single unpaid invoice.
class InvoiceCollectionAllocation {
  final int invoiceId;
  final String invoiceNumber;
  final double appliedPaid;
  final double appliedDiscount;
  final String newStatus;
  final double remainingOnInvoice;

  const InvoiceCollectionAllocation({
    required this.invoiceId,
    required this.invoiceNumber,
    required this.appliedPaid,
    required this.appliedDiscount,
    required this.newStatus,
    required this.remainingOnInvoice,
  });

  double get totalApplied => appliedPaid + appliedDiscount;
}

/// Result returned by [CustomerCollectionService.collectPayment].
class CustomerCollectionResult {
  final String customerId;
  final double paidAmount;
  final double discountAmount;
  final double totalCredited;
  final List<InvoiceCollectionAllocation> allocations;
  final double unallocatedCredit;
  final double newCustomerBalance;

  const CustomerCollectionResult({
    required this.customerId,
    required this.paidAmount,
    required this.discountAmount,
    required this.totalCredited,
    required this.allocations,
    required this.unallocatedCredit,
    required this.newCustomerBalance,
  });
}

/// Handles customer-level credit collections with automatic FIFO allocation
/// across oldest unpaid invoices and optional settlement discount.
class CustomerCollectionService {
  final AppDatabase _db;
  static const _uuid = Uuid();

  CustomerCollectionService(this._db);

  /// Records a collection of [paidAmount] plus optional [discountAmount] from
  /// [customerId], distributing both FIFO across the customer's oldest unpaid
  /// non-voided invoices inside a single database transaction.
  ///
  /// Also posts the corresponding `LedgerTransactions` credit rows (reducing
  /// customer balance) and `InvoicePayments` rows (for daily cash reporting).
  Future<CustomerCollectionResult> collectPayment({
    required String customerId,
    required double paidAmount,
    double discountAmount = 0.0,
    String paymentMethod = 'cash',
    DateTime? date,
    String? notes,
  }) async {
    if (customerId.trim().isEmpty || customerId == 'cash') {
      throw ArgumentError('يجب تحديد العميل لتسجيل التحصيل');
    }
    if (paidAmount < 0 || discountAmount < 0) {
      throw ArgumentError('المبلغ والخصم لا يمكن أن يكونا سالبين');
    }
    final totalCredited = paidAmount + discountAmount;
    if (totalCredited <= 0) {
      throw ArgumentError('إجمالي التحصيل والخصم يجب أن يكون أكبر من صفر');
    }

    final resolvedDate = date ?? DateTime.now();

    return _db.transaction(() async {
      final customer = await _db.customerDao.getCustomerById(customerId);
      if (customer == null) {
        throw ArgumentError('العميل غير موجود ($customerId)');
      }

      // Oldest non-voided invoices for this customer (FIFO).
      final customerInvoices = await (_db.select(_db.invoices)
            ..where(
              (t) =>
                  t.customerId.equals(customerId) &
                  t.status.equals('voided').not(),
            )
            ..orderBy([
              (t) => OrderingTerm.asc(t.date),
              (t) => OrderingTerm.asc(t.id),
            ]))
          .get();

      var remainingPaid = paidAmount;
      var remainingDiscount = discountAmount;
      final allocations = <InvoiceCollectionAllocation>[];

      for (final inv in customerInvoices) {
        if (remainingPaid <= 0.0001 && remainingDiscount <= 0.0001) break;

        final effectiveTotal =
            (inv.totalAmount - inv.returnedAmount).clamp(0.0, double.infinity);
        final unpaid = effectiveTotal - inv.paidAmount;
        if (unpaid <= 0.005) continue;

        final applyPaid =
            remainingPaid > 0 ? math.min(remainingPaid, unpaid) : 0.0;
        remainingPaid -= applyPaid;

        final unpaidAfterPaid = (unpaid - applyPaid).clamp(0.0, double.infinity);
        final applyDiscount = remainingDiscount > 0 && unpaidAfterPaid > 0
            ? math.min(remainingDiscount, unpaidAfterPaid)
            : 0.0;
        remainingDiscount -= applyDiscount;

        final totalApplied = applyPaid + applyDiscount;
        if (totalApplied <= 0.0001) continue;

        final newPaidAmount = inv.paidAmount + totalApplied;
        final newCreditAmount =
            (inv.creditAmount - totalApplied).clamp(0.0, double.infinity);
        final remainingOnInv =
            (effectiveTotal - newPaidAmount).clamp(0.0, double.infinity);
        final newStatus = remainingOnInv <= 0.005 ? 'paid' : 'partial';

        await (_db.update(_db.invoices)..where((t) => t.id.equals(inv.id)))
            .write(
          InvoicesCompanion(
            paidAmount: Value(newPaidAmount),
            creditAmount: Value(newCreditAmount),
            status: Value(newStatus),
            updatedAt: Value(DateTime.now()),
          ),
        );

        if (applyPaid > 0.0001) {
          await _db.invoicePaymentsDao.insertPayment(
            InvoicePaymentsCompanion.insert(
              invoiceId: inv.id,
              paymentMethod: paymentMethod,
              amount: applyPaid,
              paidAt: Value(resolvedDate),
              notes: Value(
                notes?.trim().isNotEmpty == true ? notes!.trim() : 'تحصيل آجل FIFO',
              ),
            ),
          );
        }

        if (applyDiscount > 0.0001) {
          await _db.invoicePaymentsDao.insertPayment(
            InvoicePaymentsCompanion.insert(
              invoiceId: inv.id,
              paymentMethod: 'discount',
              amount: applyDiscount,
              paidAt: Value(resolvedDate),
              notes: Value(
                notes?.trim().isNotEmpty == true
                    ? 'خصم تحصيل - ${notes!.trim()}'
                    : 'خصم عند التحصيل',
              ),
            ),
          );
        }

        final displayNo =
            displayInvoiceNumber(inv.invoiceNumber, inv.id) ?? '#${inv.id}';
        allocations.add(
          InvoiceCollectionAllocation(
            invoiceId: inv.id,
            invoiceNumber: displayNo,
            appliedPaid: applyPaid,
            appliedDiscount: applyDiscount,
            newStatus: newStatus,
            remainingOnInvoice: remainingOnInv,
          ),
        );
      }

      final trimmedNotes = notes?.trim();
      final invoiceRefs = allocations.map((a) => a.invoiceNumber).join('، ');

      if (paidAmount > 0.0001) {
        final desc = (trimmedNotes != null && trimmedNotes.isNotEmpty)
            ? trimmedNotes
            : (invoiceRefs.isNotEmpty
                ? 'تحصيل من العميل ($invoiceRefs)'
                : 'تحصيل من العميل');
        await _db.ledgerDao.insertTransaction(
          LedgerTransactionsCompanion.insert(
            id: 'col_pay_${_uuid.v4()}',
            entityType: 'Customer',
            refId: customerId,
            date: resolvedDate,
            description: desc,
            debit: const Value(0.0),
            credit: Value(paidAmount),
            origin: 'payment',
            paymentMethod: Value(paymentMethod),
          ),
        );
      }

      if (discountAmount > 0.0001) {
        final desc = (trimmedNotes != null && trimmedNotes.isNotEmpty)
            ? 'خصم تحصيل - $trimmedNotes'
            : (invoiceRefs.isNotEmpty
                ? 'خصم عند التحصيل ($invoiceRefs)'
                : 'خصم عند التحصيل');
        await _db.ledgerDao.insertTransaction(
          LedgerTransactionsCompanion.insert(
            id: 'col_disc_${_uuid.v4()}',
            entityType: 'Customer',
            refId: customerId,
            date: resolvedDate,
            description: desc,
            debit: const Value(0.0),
            credit: Value(discountAmount),
            origin: 'discount',
            paymentMethod: const Value('discount'),
          ),
        );
      }

      final unallocatedCredit = remainingPaid + remainingDiscount;
      final newBalance = await _db.ledgerDao.getCustomerBalance(customerId);

      return CustomerCollectionResult(
        customerId: customerId,
        paidAmount: paidAmount,
        discountAmount: discountAmount,
        totalCredited: totalCredited,
        allocations: allocations,
        unallocatedCredit: unallocatedCredit,
        newCustomerBalance: newBalance,
      );
    });
  }
}
