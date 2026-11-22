import 'package:drift/drift.dart';
import '../../database/app_database.dart';

class SupplierPayableItem {
  final String supplierId;
  final String supplierName;
  final String? supplierPhone;
  final double outstandingBalance; // المبلغ المستحق للمورد علينا
  final int daysSinceLastPayment;
  final int unpaidsPurchasesCount;
  final String severity; // 'critical' | 'warning' | 'info'
  final String title;
  final String recommendation;

  const SupplierPayableItem({
    required this.supplierId,
    required this.supplierName,
    this.supplierPhone,
    required this.outstandingBalance,
    required this.daysSinceLastPayment,
    required this.unpaidsPurchasesCount,
    required this.severity,
    required this.title,
    required this.recommendation,
  });
}

/// Service that analyzes supplier payables, aging debt, and overdue payments.
class SupplierPayablesService {
  final AppDatabase _db;

  SupplierPayablesService(this._db);

  /// Analyzes active suppliers to find those with overdue payables and no payments for >= 15 days.
  Future<List<SupplierPayableItem>> analyzeOverduePayables({
    DateTime? referenceDate,
    int thresholdDays = 15,
  }) async {
    final now = referenceDate ?? DateTime.now();

    // 1. Fetch active suppliers
    final suppliers = await (_db.select(_db.suppliers)
          ..where((s) => s.status.equals('Active')))
        .get();

    if (suppliers.isEmpty) return [];

    final results = <SupplierPayableItem>[];

    for (final supplier in suppliers) {
      // 2. Fetch ledger transactions for this supplier
      final transactions = await (_db.select(_db.ledgerTransactions)
            ..where((t) =>
                t.entityType.equals('Supplier') & t.refId.equals(supplier.id))
            ..orderBy([(t) => OrderingTerm(expression: t.date, mode: OrderingMode.asc)]))
          .get();

      // Calculate running balance: opening + credits (purchases) - debits (payments)
      double totalCredit = 0.0;
      double totalDebit = 0.0;
      DateTime? lastPaymentDate;
      int purchasesAfterLastPayment = 0;

      for (final tx in transactions) {
        totalCredit += tx.credit;
        totalDebit += tx.debit;
        if (tx.debit > 0) {
          if (lastPaymentDate == null || tx.date.isAfter(lastPaymentDate)) {
            lastPaymentDate = tx.date;
          }
        }
      }

      final currentBalance = supplier.openingBalance + totalCredit - totalDebit;

      // Only interested if we owe the supplier money
      if (currentBalance <= 1.0) continue;

      // Count purchases after last payment
      for (final tx in transactions) {
        if (tx.credit > 0) {
          if (lastPaymentDate == null || tx.date.isAfter(lastPaymentDate)) {
            purchasesAfterLastPayment++;
          }
        }
      }

      // Calculate days overdue
      int daysSincePayment;
      if (lastPaymentDate != null) {
        daysSincePayment = now.difference(lastPaymentDate).inDays;
      } else {
        // If no payment was ever made, measure from earliest purchase or opening
        final firstDate = transactions.isNotEmpty ? transactions.first.date : supplier.createdAt;
        daysSincePayment = now.difference(firstDate).inDays;
      }

      if (daysSincePayment >= thresholdDays) {
        final isCritical = daysSincePayment >= 30 || currentBalance >= 15000;
        final severity = isCritical ? 'critical' : 'warning';

        results.add(SupplierPayableItem(
          supplierId: supplier.id,
          supplierName: supplier.name,
          supplierPhone: supplier.phone,
          outstandingBalance: currentBalance,
          daysSinceLastPayment: daysSincePayment,
          unpaidsPurchasesCount: purchasesAfterLastPayment,
          severity: severity,
          title: 'مستحقات مورد متأخرة: ${supplier.name}',
          recommendation:
              'مستحق للمورد ${currentBalance.toStringAsFixed(0)} ج ولم نسدد له منذ $daysSincePayment يوماً ($purchasesAfterLastPayment فواتير مشتريات). يُنصح بجدولة سداد للحفاظ على استمرارية التوريد.',
        ));
      }
    }

    // Sort: highest balance and critical first
    results.sort((a, b) {
      if (a.severity == 'critical' && b.severity != 'critical') return -1;
      if (a.severity != 'critical' && b.severity == 'critical') return 1;
      return b.outstandingBalance.compareTo(a.outstandingBalance);
    });

    return results;
  }
}
