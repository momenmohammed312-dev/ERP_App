import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import '../core/utils/logger.dart';

class AnalyticsService {
  final AppDatabase db;

  AnalyticsService(this.db);

  Future<SalesAnalytics> getSalesAnalytics({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final start =
          startDate ?? DateTime.now().subtract(const Duration(days: 30));
      final end = endDate ?? DateTime.now();

      final salesData = await db
          .customSelect(
            '''
        SELECT 
          date(created_at) as sale_date,
          COUNT(*) as invoice_count,
          SUM(total) as total_sales,
          AVG(total) as average_sale
        FROM invoices 
        WHERE created_at BETWEEN ? AND ?
        AND status = 'completed'
        GROUP BY date(created_at)
        ORDER BY sale_date DESC
        ''',
            variables: [
              Variable.withDateTime(start),
              Variable.withDateTime(end),
            ],
          )
          .get();

      final dailySales = <String, double>{};
      final paymentMethods = <String, double>{};
      double totalSales = 0;
      int totalInvoices = 0;

      for (final row in salesData) {
        final date = row.data['sale_date'].toString();
        final total = (row.data['total_sales'] as double?) ?? 0.0;
        final count = (row.data['invoice_count'] as int?) ?? 0;

        dailySales[date] = total;
        totalSales += total;
        totalInvoices += count;
      }

      // Get payment methods distribution
      final paymentData = await db
          .customSelect(
            '''
        SELECT payment_method, COUNT(*) as count, SUM(total) as total
        FROM invoices 
        WHERE created_at BETWEEN ? AND ?
        AND status = 'completed'
        GROUP BY payment_method
        ''',
            variables: [
              Variable.withDateTime(start),
              Variable.withDateTime(end),
            ],
          )
          .get();

      for (final row in paymentData) {
        final method = row.data['payment_method'].toString();
        final total = (row.data['total'] as double?) ?? 0.0;
        paymentMethods[method] = total;
      }

      return SalesAnalytics(
        period: end,
        totalSales: totalSales,
        totalInvoices: totalInvoices,
        averageSale: totalInvoices > 0 ? totalSales / totalInvoices : 0,
        dailySales: dailySales,
        paymentMethods: paymentMethods,
      );
    } catch (e) {
      AppLogger.e('Error getting sales analytics', e);
      rethrow;
    }
  }

  Future<List<ProductAnalytics>> getProductAnalytics({int? limit = 50}) async {
    try {
      final productData = await db
          .customSelect(
            '''
        SELECT 
          p.id,
          p.name,
          COALESCE(SUM(ii.quantity), 0) as total_sold,
          COALESCE(SUM(ii.total), 0) as revenue,
          p.quantity as current_stock
        FROM products p
        LEFT JOIN invoice_items ii ON p.id = ii.product_id
        LEFT JOIN invoices i ON ii.invoice_id = i.id
        WHERE i.status = 'completed' OR i.id IS NULL
        GROUP BY p.id, p.name, p.quantity
        ORDER BY total_sold DESC
        LIMIT ?
        ''',
            variables: [Variable.withInt(limit ?? 50)],
          )
          .get();

      return productData.map((row) {
        return ProductAnalytics(
          productId: row.data['id'].toString(),
          productName: row.data['name'].toString(),
          totalSold: (row.data['total_sold'] as int?) ?? 0,
          revenue: (row.data['revenue'] as double?) ?? 0.0,
          profit:
              (row.data['revenue'] as double?) ??
              0.0, // Simplified profit calculation
          currentStock: (row.data['current_stock'] as int?) ?? 0,
        );
      }).toList();
    } catch (e) {
      AppLogger.e('Error getting product analytics', e);
      rethrow;
    }
  }

  Future<List<CustomerAnalytics>> getCustomerAnalytics({
    int? limit = 50,
  }) async {
    try {
      final customerData = await db
          .customSelect(
            '''
        SELECT 
          c.id,
          c.name,
          COALESCE(SUM(i.total), 0) as total_purchases,
          COUNT(i.id) as invoice_count,
          MAX(i.created_at) as last_purchase
        FROM customers c
        LEFT JOIN invoices i ON c.id = i.customer_id
        WHERE i.status = 'completed' OR i.id IS NULL
        GROUP BY c.id, c.name
        HAVING total_purchases > 0
        ORDER BY total_purchases DESC
        LIMIT ?
        ''',
            variables: [Variable.withInt(limit ?? 50)],
          )
          .get();

      return customerData.map((row) {
        final totalPurchases = (row.data['total_purchases'] as double?) ?? 0.0;
        final invoiceCount = (row.data['invoice_count'] as int?) ?? 0;

        return CustomerAnalytics(
          customerId: row.data['id'].toString(),
          customerName: row.data['name'].toString(),
          totalPurchases: totalPurchases,
          invoiceCount: invoiceCount,
          averagePurchase: invoiceCount > 0 ? totalPurchases / invoiceCount : 0,
          lastPurchase:
              row.data['last_purchase'] as DateTime? ?? DateTime.now(),
          segment: _getCustomerSegment(totalPurchases),
        );
      }).toList();
    } catch (e) {
      AppLogger.e('Error getting customer analytics', e);
      rethrow;
    }
  }

  Future<InventoryAnalytics> getInventoryAnalytics() async {
    try {
      final inventoryData = await db.customSelect('''
        SELECT 
          COUNT(*) as total_products,
          SUM(quantity * price) as total_value,
          SUM(CASE WHEN quantity = 0 THEN 1 ELSE 0 END) as dead_stock_count
        FROM products
        ''').get();

      final row = inventoryData.first;
      final totalProducts = (row.data['total_products'] as int?) ?? 0;
      final totalValue = (row.data['total_value'] as double?) ?? 0.0;
      final deadStockCount = (row.data['dead_stock_count'] as int?) ?? 0;

      // Calculate turnover ratio (simplified)
      final turnoverRatio = totalValue > 0 ? 4.2 : 0.0; // Placeholder
      final healthScore = totalProducts > 0
          ? ((totalProducts - deadStockCount) / totalProducts) * 100
          : 0.0;

      return InventoryAnalytics(
        totalValue: totalValue,
        totalProducts: totalProducts,
        turnoverRatio: turnoverRatio,
        deadStockCount: deadStockCount,
        healthScore: healthScore,
      );
    } catch (e) {
      AppLogger.e('Error getting inventory analytics', e);
      rethrow;
    }
  }

  Future<FinancialAnalytics> getFinancialAnalytics({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final start =
          startDate ?? DateTime.now().subtract(const Duration(days: 30));
      final end = endDate ?? DateTime.now();

      final financialData = await db
          .customSelect(
            '''
        SELECT 
          SUM(total) as revenue,
          SUM(CASE WHEN total < 0 THEN ABS(total) ELSE 0 END) as expenses
        FROM invoices 
        WHERE created_at BETWEEN ? AND ?
        AND status = 'completed'
        ''',
            variables: [
              Variable.withDateTime(start),
              Variable.withDateTime(end),
            ],
          )
          .get();

      final row = financialData.first;
      final revenue = (row.data['revenue'] as double?) ?? 0.0;
      final expenses = (row.data['expenses'] as double?) ?? 0.0;
      final profit = revenue - expenses;
      final cashFlow = revenue - expenses;

      final margins = <String, double>{};
      if (revenue > 0) {
        margins['gross'] = (profit / revenue) * 100;
        margins['net'] = (profit / revenue) * 100;
      }

      return FinancialAnalytics(
        revenue: revenue,
        profit: profit,
        expenses: expenses,
        cashFlow: cashFlow,
        margins: margins,
      );
    } catch (e) {
      AppLogger.e('Error getting financial analytics', e);
      rethrow;
    }
  }

  Future<void> exportAnalytics(
    Map<String, dynamic> data,
    String format,
    String filePath,
  ) async {
    try {
      switch (format.toLowerCase()) {
        case 'json':
          await _exportAsJson(data, filePath);
          break;
        case 'csv':
          await _exportAsCsv(data, filePath);
          break;
        case 'excel':
          await _exportAsExcel(data, filePath);
          break;
        case 'pdf':
          await _exportAsPdf(data, filePath);
          break;
        default:
          throw ArgumentError('Unsupported export format: $format');
      }
    } catch (e) {
      AppLogger.e('Error exporting analytics data', e);
      rethrow;
    }
  }

  String _getCustomerSegment(double totalPurchases) {
    if (totalPurchases > 10000) return 'vip';
    if (totalPurchases > 5000) return 'premium';
    if (totalPurchases > 1000) return 'regular';
    return 'occasional';
  }

  Future<void> _exportAsJson(Map<String, dynamic> data, String filePath) async {
    final file = File(filePath);
    await file.writeAsString(jsonEncode(data));
  }

  Future<void> _exportAsCsv(Map<String, dynamic> data, String filePath) async {
    // Implement CSV export
    final file = File(filePath);
    // CSV generation logic here
    await file.writeAsString('CSV export not implemented');
  }

  Future<void> _exportAsExcel(
    Map<String, dynamic> data,
    String filePath,
  ) async {
    // Implement Excel export
    final file = File(filePath);
    await file.writeAsString('Excel export not implemented');
  }

  Future<void> _exportAsPdf(Map<String, dynamic> data, String filePath) async {
    // Implement PDF export
    final file = File(filePath);
    await file.writeAsString('PDF export not implemented');
  }
}

// Analytics Data Models
class SalesAnalytics {
  final DateTime period;
  final double totalSales;
  final int totalInvoices;
  final double averageSale;
  final Map<String, double> dailySales;
  final Map<String, double> paymentMethods;

  SalesAnalytics({
    required this.period,
    required this.totalSales,
    required this.totalInvoices,
    required this.averageSale,
    required this.dailySales,
    required this.paymentMethods,
  });
}

class ProductAnalytics {
  final String productId;
  final String productName;
  final int totalSold;
  final double revenue;
  final double profit;
  final int currentStock;

  ProductAnalytics({
    required this.productId,
    required this.productName,
    required this.totalSold,
    required this.revenue,
    required this.profit,
    required this.currentStock,
  });
}

class CustomerAnalytics {
  final String customerId;
  final String customerName;
  final double totalPurchases;
  final int invoiceCount;
  final double averagePurchase;
  final DateTime lastPurchase;
  final String segment;

  CustomerAnalytics({
    required this.customerId,
    required this.customerName,
    required this.totalPurchases,
    required this.invoiceCount,
    required this.averagePurchase,
    required this.lastPurchase,
    required this.segment,
  });
}

class InventoryAnalytics {
  final double totalValue;
  final int totalProducts;
  final double turnoverRatio;
  final int deadStockCount;
  final double healthScore;

  InventoryAnalytics({
    required this.totalValue,
    required this.totalProducts,
    required this.turnoverRatio,
    required this.deadStockCount,
    required this.healthScore,
  });
}

class FinancialAnalytics {
  final double revenue;
  final double profit;
  final double expenses;
  final double cashFlow;
  final Map<String, double> margins;

  FinancialAnalytics({
    required this.revenue,
    required this.profit,
    required this.expenses,
    required this.cashFlow,
    required this.margins,
  });
}
