import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';
import '../../database/app_database.dart';

/// Represents a customer retention risk analysis item.
class CustomerRetentionItem {
  final String customerId;
  final String customerName;
  final String? phone;
  final int daysSinceLastPurchase;
  final double averageCadenceDays;
  final double outstandingDebt;
  final String riskLevel; // 'high' | 'medium'
  final String suggestedAction;

  const CustomerRetentionItem({
    required this.customerId,
    required this.customerName,
    this.phone,
    required this.daysSinceLastPurchase,
    required this.averageCadenceDays,
    required this.outstandingDebt,
    required this.riskLevel,
    required this.suggestedAction,
  });
}

/// Represents a customer who keeps purchasing goods on credit without making payments.
class CustomerCreditStagnationItem {
  final String customerId;
  final String customerName;
  final String? phone;
  final double currentDebt;
  final int daysSinceLastPayment;
  final int purchasesWithoutPaymentCount;
  final String severity; // 'critical' | 'warning'
  final String title;
  final String recommendation;

  const CustomerCreditStagnationItem({
    required this.customerId,
    required this.customerName,
    this.phone,
    required this.currentDebt,
    required this.daysSinceLastPayment,
    required this.purchasesWithoutPaymentCount,
    required this.severity,
    required this.title,
    required this.recommendation,
  });
}

/// Service that analyzes customer purchasing patterns, detects churn risks,
/// and identifies customers accumulating credit without making payments.
class CustomerRetentionService {
  final AppDatabase _db;

  CustomerRetentionService(this._db);

  /// Analyzes active customers and returns those with broken purchasing cadences.
  Future<List<CustomerRetentionItem>> analyzeCustomerCadences({
    DateTime? referenceDate,
    int minimumInvoicesRequired = 2,
  }) async {
    try {
      final now = referenceDate ?? DateTime.now();

      // 1. Fetch active customers
      final customers = await (_db.select(_db.customers)
            ..where((c) => c.status.equals('Active')))
          .get();

      if (customers.isEmpty) return [];

      // 2. Fetch past 90 days invoices associated with customers (excluding voided)
      final ninetyDaysAgo = now.subtract(const Duration(days: 90));
      final customerInvoices = await (_db.select(_db.invoices)
            ..where((i) => i.customerId.isNotNull())
            ..where((i) => i.status.isNotValue('voided'))
            ..where((i) => i.date.isBiggerOrEqualValue(ninetyDaysAgo))
            ..orderBy([(i) => OrderingTerm.asc(i.date)]))
          .get();

      // Group invoices by customerId
      final Map<String, List<Invoice>> invoicesByCustomer = {};
      for (final inv in customerInvoices) {
        if (inv.customerId == null || inv.customerId!.isEmpty) continue;
        invoicesByCustomer.putIfAbsent(inv.customerId!, () => []).add(inv);
      }

      final List<CustomerRetentionItem> atRiskCustomers = [];

      for (final customer in customers) {
        final invoices = invoicesByCustomer[customer.id] ?? [];

        // Need at least minimumInvoicesRequired to establish a cadence
        if (invoices.length < minimumInvoicesRequired) {
          final debt = customer.totalDebt - customer.totalPaid;
          if (debt > 100) {
            final lastDate = invoices.isNotEmpty ? invoices.last.date : (customer.createdAt ?? ninetyDaysAgo);
            final daysSince = now.difference(lastDate).inDays;
            if (daysSince >= 30) {
              atRiskCustomers.add(
                CustomerRetentionItem(
                  customerId: customer.id,
                  customerName: customer.name,
                  phone: customer.phone,
                  daysSinceLastPurchase: daysSince,
                  averageCadenceDays: 30.0,
                  outstandingDebt: debt,
                  riskLevel: 'high',
                  suggestedAction: 'متابعة سداد المديونية المتأخرة (${debt.toStringAsFixed(0)} ج)',
                ),
              );
            }
          }
          continue;
        }

        // Calculate average gap between invoices in days
        final gaps = <int>[];
        for (int i = 0; i < invoices.length - 1; i++) {
          final diff = invoices[i + 1].date.difference(invoices[i].date).inDays;
          if (diff > 0) gaps.add(diff);
        }

        if (gaps.isEmpty) continue;

        final averageCadence = gaps.reduce((a, b) => a + b) / gaps.length;
        final lastInvoiceDate = invoices.last.date;
        final daysSinceLastPurchase = now.difference(lastInvoiceDate).inDays;

        // Broken cadence threshold: exceeded 2.5x their average cadence AND at least 10 days
        final thresholdDays = math.max(10, (averageCadence * 2.5).ceil());

        if (daysSinceLastPurchase >= thresholdDays) {
          final debt = math.max(0.0, customer.totalDebt - customer.totalPaid);
          final isHighRisk = debt > 200 || daysSinceLastPurchase >= (averageCadence * 4);

          atRiskCustomers.add(
            CustomerRetentionItem(
              customerId: customer.id,
              customerName: customer.name,
              phone: customer.phone,
              daysSinceLastPurchase: daysSinceLastPurchase,
              averageCadenceDays: double.parse(averageCadence.toStringAsFixed(1)),
              outstandingDebt: debt,
              riskLevel: isHighRisk ? 'high' : 'medium',
              suggestedAction: debt > 0
                  ? 'تواصل لتجديد الطلب وتحصيل مديونية ${debt.toStringAsFixed(0)} ج'
                  : 'تواصل لمعرفة سبب الانقطاع وتقديم عرض خاص',
            ),
          );
        }
      }

      // Sort by risk (high first) then debt
      atRiskCustomers.sort((a, b) {
        if (a.riskLevel != b.riskLevel) {
          return a.riskLevel == 'high' ? -1 : 1;
        }
        return b.outstandingDebt.compareTo(a.outstandingDebt);
      });

      return atRiskCustomers;
    } catch (e, st) {
      debugPrint('Error in CustomerRetentionService: $e\n$st');
      return [];
    }
  }

  /// Detects customers who take goods on credit repeatedly without making payments for >= 14 days.
  Future<List<CustomerCreditStagnationItem>> analyzeCreditAccumulationWithoutPayment({
    DateTime? referenceDate,
    int daysThreshold = 14,
  }) async {
    final now = referenceDate ?? DateTime.now();
    final results = <CustomerCreditStagnationItem>[];

    try {
      final customers = await (_db.select(_db.customers)
            ..where((c) => c.status.equals('Active')))
          .get();

      for (final customer in customers) {
        final txs = await (_db.select(_db.ledgerTransactions)
              ..where((t) =>
                  t.entityType.equals('Customer') & t.refId.equals(customer.id))
              ..orderBy([(t) => OrderingTerm(expression: t.date, mode: OrderingMode.asc)]))
            .get();

        if (txs.isEmpty) continue;

        double totalDebit = 0.0;
        double totalCredit = 0.0;
        DateTime? lastPaymentDate;

        for (final tx in txs) {
          totalDebit += tx.debit;
          totalCredit += tx.credit;
          if (tx.credit > 0) {
            if (lastPaymentDate == null || tx.date.isAfter(lastPaymentDate)) {
              lastPaymentDate = tx.date;
            }
          }
        }

        final debt = customer.openingBalance + totalDebit - totalCredit;
        if (debt <= 100) continue; // No significant debt

        // Count invoices taken after the last payment
        int purchasesAfterLastPayment = 0;
        for (final tx in txs) {
          if (tx.debit > 0) {
            if (lastPaymentDate == null || tx.date.isAfter(lastPaymentDate)) {
              purchasesAfterLastPayment++;
            }
          }
        }

        int daysSincePayment;
        if (lastPaymentDate != null) {
          daysSincePayment = now.difference(lastPaymentDate).inDays;
        } else {
          final firstTxDate = txs.first.date;
          daysSincePayment = now.difference(firstTxDate).inDays;
        }

        // Alert condition: has >= 2 purchases after last payment OR days without payment >= 14
        if ((purchasesAfterLastPayment >= 2 && daysSincePayment >= 10) || daysSincePayment >= daysThreshold) {
          final isCritical = daysSincePayment >= 30 || debt >= 10000;
          results.add(CustomerCreditStagnationItem(
            customerId: customer.id,
            customerName: customer.name,
            phone: customer.phone,
            currentDebt: debt,
            daysSinceLastPayment: daysSincePayment,
            purchasesWithoutPaymentCount: purchasesAfterLastPayment,
            severity: isCritical ? 'critical' : 'warning',
            title: 'سحب آجل متراكم بدون سداد: ${customer.name}',
            recommendation:
                'العميل سحب $purchasesAfterLastPayment فواتير آجلة بإجمالي دين ${debt.toStringAsFixed(0)} ج دون سداد أي دفعة منذ $daysSincePayment يوماً. يُرجى مراجعته قبل السماح بسحب بضاعة جديدة.',
          ));
        }
      }

      results.sort((a, b) {
        if (a.severity == 'critical' && b.severity != 'critical') return -1;
        if (a.severity != 'critical' && b.severity == 'critical') return 1;
        return b.currentDebt.compareTo(a.currentDebt);
      });
    } catch (e, st) {
      debugPrint('Error in analyzeCreditAccumulationWithoutPayment: $e\n$st');
    }

    return results;
  }
}
