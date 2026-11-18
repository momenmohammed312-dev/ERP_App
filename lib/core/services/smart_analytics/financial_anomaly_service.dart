import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';
import '../../database/app_database.dart';

/// Represents a detected financial anomaly or potential leakage.
class FinancialAnomalyItem {
  final String id;
  final String type; // 'high_returns' | 'sequential_refunds' | 'abnormal_discounts' | 'void_spike'
  final String title;
  final String description;
  final String severity; // 'critical' | 'warning'
  final double metricValue;
  final double baselineValue;
  final DateTime detectedAt;

  const FinancialAnomalyItem({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    required this.severity,
    required this.metricValue,
    required this.baselineValue,
    required this.detectedAt,
  });
}

/// Service that evaluates cash sessions and daily transactions to detect financial anomalies,
/// cash leakage, or unusual transaction patterns using adaptive statistical baselines.
class FinancialAnomalyService {
  final AppDatabase _db;

  FinancialAnomalyService(this._db);

  /// Analyzes the active session or today's sales for statistical deviations.
  Future<List<FinancialAnomalyItem>> checkSessionAnomalies({
    DateTime? sessionStartTime,
    DateTime? sessionEndTime,
  }) async {
    try {
      final now = DateTime.now();
      final start = sessionStartTime ?? DateTime(now.year, now.month, now.day);
      final end = sessionEndTime ?? now;

      // 1. Fetch current session invoices
      final currentInvoices = await (_db.select(_db.invoices)
            ..where((i) => i.date.isBiggerOrEqualValue(start))
            ..where((i) => i.date.isSmallerOrEqualValue(end)))
          .get();

      // Guard: Needs at least 3 transactions to evaluate any pattern
      if (currentInvoices.length < 3) return [];

      // 2. Fetch 30-day baseline data for the store
      final baselineStart = now.subtract(const Duration(days: 30));
      final baselineInvoices = await (_db.select(_db.invoices)
            ..where((i) => i.date.isBiggerOrEqualValue(baselineStart))
            ..where((i) => i.date.isSmallerThanValue(start)))
          .get();

      final List<FinancialAnomalyItem> anomalies = [];

      // A. Check Returns Spike
      final returnAnomaly = _evaluateReturnSpike(
        currentInvoices,
        baselineInvoices,
        now,
      );
      if (returnAnomaly != null) anomalies.add(returnAnomaly);

      // B. Check Sequential Rapid Refunds
      final sequentialRefundsAnomaly = _evaluateSequentialRefunds(
        currentInvoices,
        now,
      );
      if (sequentialRefundsAnomaly != null) anomalies.add(sequentialRefundsAnomaly);

      // C. Check High Voided Invoices
      final voidAnomaly = _evaluateVoidSpike(
        currentInvoices,
        baselineInvoices,
        now,
      );
      if (voidAnomaly != null) anomalies.add(voidAnomaly);

      return anomalies;
    } catch (e, st) {
      debugPrint('Error in FinancialAnomalyService: $e\n$st');
      return [];
    }
  }

  /// Evaluates if returns in the current session significantly exceed store historical baseline.
  FinancialAnomalyItem? _evaluateReturnSpike(
    List<Invoice> currentInvoices,
    List<Invoice> baselineInvoices,
    DateTime now,
  ) {
    double currentSalesTotal = 0;
    double currentReturnsTotal = 0;
    int returnCount = 0;

    for (final inv in currentInvoices) {
      if (inv.status != 'voided') {
        currentSalesTotal += inv.totalAmount;
      }
      if (inv.returnedAmount > 0) {
        currentReturnsTotal += inv.returnedAmount;
        returnCount++;
      }
    }

    final totalVolume = currentSalesTotal + currentReturnsTotal;
    if (totalVolume <= 0 || returnCount < 2) return null;

    final currentReturnRate = (currentReturnsTotal / totalVolume) * 100;

    // Calculate store baseline return rate
    double baseSales = 0;
    double baseReturns = 0;
    for (final inv in baselineInvoices) {
      if (inv.status != 'voided') baseSales += inv.totalAmount;
      if (inv.returnedAmount > 0) baseReturns += inv.returnedAmount;
    }
    final baseVolume = baseSales + baseReturns;
    final baselineReturnRate =
        baseVolume > 0 ? (baseReturns / baseVolume) * 100 : 3.0; // fallback default 3%

    // Anomaly condition: current return rate is at least 3x baseline AND >= 12%, with meaningful amount
    if (currentReturnRate >= 12.0 &&
        currentReturnRate >= (baselineReturnRate * 2.5) &&
        currentReturnsTotal >= 200) {
      final isCritical = currentReturnRate >= 25.0 || currentReturnsTotal >= 1500;
      return FinancialAnomalyItem(
        id: 'anomaly_returns_${now.millisecondsSinceEpoch}',
        type: 'high_returns',
        title: isCritical ? 'شذوذ مالي حرج: طفرة مرتجعات' : 'تحذير مالي: ارتفاع نسبة المرتجعات',
        description:
            'بلغت نسبة المرتجعات في الفترة الحالية ${currentReturnRate.toStringAsFixed(1)}% '
            'بقيمة إجمالية ${currentReturnsTotal.toStringAsFixed(0)} ج ($returnCount عمليات). '
            'المعدل المعتاد للمحل هو ${baselineReturnRate.toStringAsFixed(1)}%.',
        severity: isCritical ? 'critical' : 'warning',
        metricValue: double.parse(currentReturnRate.toStringAsFixed(1)),
        baselineValue: double.parse(baselineReturnRate.toStringAsFixed(1)),
        detectedAt: now,
      );
    }

    return null;
  }

  /// Detects rapid succession of refunds (e.g., 3 refunds within 30 minutes).
  FinancialAnomalyItem? _evaluateSequentialRefunds(
    List<Invoice> currentInvoices,
    DateTime now,
  ) {
    final returnedInvoices = currentInvoices
        .where((i) => i.returnedAmount > 0)
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    if (returnedInvoices.length < 3) return null;

    // Check sliding window of 3 refunds
    for (int i = 0; i <= returnedInvoices.length - 3; i++) {
      final first = returnedInvoices[i];
      final third = returnedInvoices[i + 2];
      final diffMinutes = third.date.difference(first.date).inMinutes.abs();

      if (diffMinutes <= 30) {
        final totalBurstAmount = returnedInvoices
            .sublist(i, i + 3)
            .fold<double>(0, (sum, inv) => sum + inv.returnedAmount);

        return FinancialAnomalyItem(
          id: 'anomaly_sequential_refunds_${now.millisecondsSinceEpoch}',
          type: 'sequential_refunds',
          title: 'تحذير رقابي: تكرار سريع للمرتجعات',
          description:
              'تم تسجيل 3 عمليات استرجاع متتالية خلال $diffMinutes دقيقة فقط '
              'بإجمالي ${totalBurstAmount.toStringAsFixed(0)} ج. يُرجى مراجعة سبب الاسترجاع مع الكاشير.',
          severity: 'warning',
          metricValue: totalBurstAmount,
          baselineValue: 30.0, // 30 minutes window
          detectedAt: now,
        );
      }
    }

    return null;
  }

  /// Detects unusual surge in voided invoices.
  FinancialAnomalyItem? _evaluateVoidSpike(
    List<Invoice> currentInvoices,
    List<Invoice> baselineInvoices,
    DateTime now,
  ) {
    int currentVoids = 0;
    for (final inv in currentInvoices) {
      if (inv.status == 'voided') currentVoids++;
    }

    if (currentInvoices.length < 5 || currentVoids < 3) return null;

    final currentVoidRate = (currentVoids / currentInvoices.length) * 100;

    int baseVoids = 0;
    for (final inv in baselineInvoices) {
      if (inv.status == 'voided') baseVoids++;
    }
    final baseVoidRate = baselineInvoices.isNotEmpty
        ? (baseVoids / baselineInvoices.length) * 100
        : 2.0;

    if (currentVoidRate >= 15.0 && currentVoidRate >= (baseVoidRate * 2.5)) {
      return FinancialAnomalyItem(
        id: 'anomaly_void_spike_${now.millisecondsSinceEpoch}',
        type: 'void_spike',
        title: 'تنبيه أمان: نسبة إلغاء فواتير غير معتادة',
        description:
            'تم إلغاء $currentVoids فواتير من إجمالي ${currentInvoices.length} بنسبة '
            '${currentVoidRate.toStringAsFixed(1)}%. المعدل الطبيعي هو ${baseVoidRate.toStringAsFixed(1)}%.',
        severity: 'warning',
        metricValue: double.parse(currentVoidRate.toStringAsFixed(1)),
        baselineValue: double.parse(baseVoidRate.toStringAsFixed(1)),
        detectedAt: now,
      );
    }

    return null;
  }
}
