import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';
import '../../database/app_database.dart';

/// Represents a predictive analysis item for product stock.
class StockPredictionItem {
  final int productId;
  final String productName;
  final int? variantId;
  final String? variantName;
  final int currentStock;
  final double dailyVelocity;
  final double daysUntilStockout;
  final int suggestedReorderQuantity;
  final String urgency; // 'out_of_stock' | 'critical' | 'warning' | 'healthy'
  final double trendMomentum; // e.g. +1.2 (+20% acceleration), -0.8 (-20% deceleration)

  const StockPredictionItem({
    required this.productId,
    required this.productName,
    this.variantId,
    this.variantName,
    required this.currentStock,
    required this.dailyVelocity,
    required this.daysUntilStockout,
    required this.suggestedReorderQuantity,
    required this.urgency,
    this.trendMomentum = 1.0,
  });

  bool get isActionRequired => urgency != 'healthy';
}

/// Service that predicts stock run-out and calculates suggested reorder quantities
/// using weighted exponential moving velocity and trend momentum.
class PredictiveStockService {
  final AppDatabase _db;

  PredictiveStockService(this._db);

  /// Performs predictive stock analysis over active products and variants.
  Future<List<StockPredictionItem>> analyzeStockRunRate({
    int analysisDays = 14,
    double criticalDaysThreshold = 3.0,
    double warningDaysThreshold = 7.0,
  }) async {
    try {
      final now = DateTime.now();
      final startDate = now.subtract(Duration(days: analysisDays));

      // 1. Fetch active products eligible for retail sale
      final products = await (_db.select(_db.products)
            ..where((p) => p.status.equals('Active')))
          .get();

      if (products.isEmpty) return [];

      // 2. Fetch sales items from non-voided invoices within the time window using typed join
      final typedQuery = _db.select(_db.invoiceItems).join([
        innerJoin(
          _db.invoices,
          _db.invoices.id.equalsExp(_db.invoiceItems.invoiceId),
        ),
      ])
        ..where(_db.invoices.date.isBiggerOrEqualValue(startDate))
        ..where(_db.invoices.status.equals('voided').not());

      final salesRows = await typedQuery.get();

      // 3. Aggregate sales by (productId, variantId) and calculate daily velocity with time weighting
      // Recent days (last 7 days) have weight 1.5x, older days (8-14) have weight 0.8x
      final Map<String, List<_SalePoint>> itemSalesHistory = {};

      for (final row in salesRows) {
        final item = row.readTable(_db.invoiceItems);
        final invoice = row.readTable(_db.invoices);
        final key = '${item.productId}:${item.variantId ?? 0}';
        itemSalesHistory.putIfAbsent(key, () => []).add(
              _SalePoint(date: invoice.date, quantity: item.quantity),
            );
      }

      // 4. Fetch variants to match names and stocks if variants exist
      final variants = await _db.select(_db.productVariants).get();
      final Map<int, ProductVariant> variantMap = {
        for (final v in variants) v.id: v,
      };

      final List<StockPredictionItem> predictions = [];

      for (final product in products) {
        // Skip raw materials meant only for manufacturing
        if (product.productType == 'raw_material') continue;

        // Check if product has variants
        final productVariantsList =
            variants.where((v) => v.productId == product.id).toList();

        if (productVariantsList.isNotEmpty) {
          for (final variant in productVariantsList) {
            final key = '${product.id}:${variant.id}';
            final sales = itemSalesHistory[key] ?? [];
            final prediction = _calculatePrediction(
              productId: product.id,
              productName: product.name,
              variantId: variant.id,
              variantName: variant.name,
              currentStock: variant.quantity,
              salesHistory: sales,
              analysisDays: analysisDays,
              criticalDaysThreshold: criticalDaysThreshold,
              warningDaysThreshold: warningDaysThreshold,
            );
            predictions.add(prediction);
          }
        } else {
          final key = '${product.id}:0';
          final sales = itemSalesHistory[key] ?? [];
          final prediction = _calculatePrediction(
            productId: product.id,
            productName: product.name,
            variantId: null,
            variantName: null,
            currentStock: product.quantity,
            salesHistory: sales,
            analysisDays: analysisDays,
            criticalDaysThreshold: criticalDaysThreshold,
            warningDaysThreshold: warningDaysThreshold,
          );
          predictions.add(prediction);
        }
      }

      // Sort by urgency: out_of_stock first, then critical, then warning
      predictions.sort((a, b) {
        final rankA = _urgencyRank(a.urgency);
        final rankB = _urgencyRank(b.urgency);
        if (rankA != rankB) return rankB.compareTo(rankA);
        return a.daysUntilStockout.compareTo(b.daysUntilStockout);
      });

      return predictions;
    } catch (e, st) {
      debugPrint('Error in PredictiveStockService: $e\n$st');
      return [];
    }
  }

  StockPredictionItem _calculatePrediction({
    required int productId,
    required String productName,
    required int? variantId,
    required String? variantName,
    required int currentStock,
    required List<_SalePoint> salesHistory,
    required int analysisDays,
    required double criticalDaysThreshold,
    required double warningDaysThreshold,
  }) {
    if (salesHistory.isEmpty) {
      final isOut = currentStock <= 0;
      return StockPredictionItem(
        productId: productId,
        productName: productName,
        variantId: variantId,
        variantName: variantName,
        currentStock: currentStock,
        dailyVelocity: 0.0,
        daysUntilStockout: isOut ? 0.0 : 999.0,
        suggestedReorderQuantity: isOut ? 10 : 0,
        urgency: isOut ? 'out_of_stock' : 'healthy',
        trendMomentum: 1.0,
      );
    }

    final now = DateTime.now();
    double recentQty = 0; // last 7 days
    double priorQty = 0; // 8 to 14 days

    for (final point in salesHistory) {
      final ageInDays = now.difference(point.date).inDays;
      if (ageInDays <= 7) {
        recentQty += point.quantity;
      } else if (ageInDays <= 14) {
        priorQty += point.quantity;
      }
    }

    // Weighted Daily Velocity: gives 65% weight to recent week, 35% to prior
    final recentVelocity = recentQty / 7.0;
    final priorVelocity = priorQty / 7.0;

    double weightedVelocity;
    if (priorVelocity > 0) {
      weightedVelocity = (recentVelocity * 0.65) + (priorVelocity * 0.35);
    } else {
      weightedVelocity = recentVelocity;
    }

    // Prevent division by zero
    weightedVelocity = math.max(0.05, weightedVelocity);

    // Trend momentum: ratio of recent to prior
    double momentum = 1.0;
    if (priorVelocity > 0) {
      momentum = (recentVelocity / priorVelocity).clamp(0.2, 3.0);
    }

    // Calculate days until stockout
    double daysUntilStockout;
    if (currentStock <= 0) {
      daysUntilStockout = 0.0;
    } else {
      daysUntilStockout = currentStock / weightedVelocity;
    }

    // Urgency classification
    String urgency;
    if (currentStock <= 0) {
      urgency = 'out_of_stock';
    } else if (daysUntilStockout <= criticalDaysThreshold) {
      urgency = 'critical';
    } else if (daysUntilStockout <= warningDaysThreshold) {
      urgency = 'warning';
    } else {
      urgency = 'healthy';
    }

    // Suggested reorder: covers 14 days of sales taking trend momentum into account
    int suggestedReorder = 0;
    if (urgency != 'healthy') {
      final targetCoverageDays = 14;
      final neededQty = (weightedVelocity * targetCoverageDays * momentum) - currentStock;
      suggestedReorder = math.max(1, neededQty.ceil());
    }

    return StockPredictionItem(
      productId: productId,
      productName: productName,
      variantId: variantId,
      variantName: variantName,
      currentStock: currentStock,
      dailyVelocity: double.parse(weightedVelocity.toStringAsFixed(2)),
      daysUntilStockout: double.parse(daysUntilStockout.toStringAsFixed(1)),
      suggestedReorderQuantity: suggestedReorder,
      urgency: urgency,
      trendMomentum: double.parse(momentum.toStringAsFixed(2)),
    );
  }

  int _urgencyRank(String urgency) {
    switch (urgency) {
      case 'out_of_stock':
        return 4;
      case 'critical':
        return 3;
      case 'warning':
        return 2;
      case 'healthy':
      default:
        return 1;
    }
  }
}

class _SalePoint {
  final DateTime date;
  final int quantity;
  _SalePoint({required this.date, required this.quantity});
}
