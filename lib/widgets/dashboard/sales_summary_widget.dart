import 'package:flutter/material.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/services/db_schema_cache_service.dart';

// Sales statistics data class
class SalesStats {
  final double totalSales;
  final double creditSales;
  final double cashSales;
  final int totalInvoices;
  final int creditInvoices;
  final int cashInvoices;

  SalesStats({
    required this.totalSales,
    required this.creditSales,
    required this.cashSales,
    required this.totalInvoices,
    required this.creditInvoices,
    required this.cashInvoices,
  });
}

class SalesSummaryWidget extends StatefulWidget {
  final AppDatabase db;

  const SalesSummaryWidget({super.key, required this.db});

  @override
  State<SalesSummaryWidget> createState() => _SalesSummaryWidgetState();
}

class _SalesSummaryWidgetState extends State<SalesSummaryWidget> {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'ملخص المبيعات',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                IconButton(
                  onPressed: () {
                    // Refresh sales data
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('تم تحديث بيانات المبيعات'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  },
                  icon: const Icon(Icons.refresh),
                  tooltip: 'تحديث بيانات المبيعات',
                ),
              ],
            ),
            const SizedBox(height: 16),
            FutureBuilder<SalesStats>(
              future: _getSalesStats(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final stats = snapshot.data!;

                return Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _buildMetricCard(
                            'إجمالي المبيعات',
                            '${stats.totalSales.toStringAsFixed(2)} ج.م',
                            Icons.attach_money,
                            Colors.green,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildMetricCard(
                            'مبيعات آجلة',
                            '${stats.creditSales.toStringAsFixed(2)} ج.م',
                            Icons.credit_card,
                            Colors.orange,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildMetricCard(
                            'مبيعات نقدية',
                            '${stats.cashSales.toStringAsFixed(2)} ج.م',
                            Icons.money,
                            Colors.blue,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _buildMetricCard(
                            'إجمالي الفواتير',
                            '${stats.totalInvoices}',
                            Icons.receipt,
                            Colors.purple,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildMetricCard(
                            'فواتير آجلة',
                            '${stats.creditInvoices}',
                            Icons.pending,
                            Colors.orange,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildMetricCard(
                            'فواتير نقدية',
                            '${stats.cashInvoices}',
                            Icons.check_circle,
                            Colors.green,
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.7),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<SalesStats> _getSalesStats() async {
    try {
      // Check if totalAmount column exists
      String totalColumn = 'totalAmount';
      try {
        final columnNames =
            await DbSchemaCacheService.getColumns(widget.db, 'invoices');
        if (!columnNames.contains('totalAmount')) {
          for (final columnName in columnNames) {
            if (columnName.contains('total') || columnName.contains('amount')) {
              totalColumn = columnName;
              break;
            }
          }
        }
      } catch (e) {
        debugPrint('Error checking invoices table: $e');
      }

      final now = DateTime.now();
      final startOfMonth = DateTime(now.year, now.month, 1);

      // Get sales data with defensive column checking
      final salesResult = await widget.db
          .customSelect(
            '''
        SELECT 
          paymentMethod,
          COUNT(*) as invoice_count,
          COALESCE(SUM($totalColumn), 0) as total_amount
        FROM invoices 
        WHERE date >= ? AND status != 'deleted'
        GROUP BY paymentMethod
      ''',
            variables: [Variable.withDateTime(startOfMonth)],
          )
          .get();

      double totalSales = 0.0;
      double creditSales = 0.0;
      double cashSales = 0.0;
      int totalInvoices = 0;
      int creditInvoices = 0;
      int cashInvoices = 0;

      for (final row in salesResult) {
        final paymentMethod = row.readNullable<String>('paymentMethod') ?? '';
        final amount = row.readNullable<double>('total_amount') ?? 0.0;
        final count = row.readNullable<int>('invoice_count') ?? 0;

        totalSales += amount;
        totalInvoices += count;

        if (paymentMethod.toLowerCase() == 'credit') {
          creditSales += amount;
          creditInvoices += count;
        } else {
          cashSales += amount;
          cashInvoices += count;
        }
      }

      return SalesStats(
        totalSales: totalSales,
        creditSales: creditSales,
        cashSales: cashSales,
        totalInvoices: totalInvoices,
        creditInvoices: creditInvoices,
        cashInvoices: cashInvoices,
      );
    } catch (e) {
      debugPrint('Error getting sales stats: $e');
      // Return default values if there's an error
      return SalesStats(
        totalSales: 0.0,
        creditSales: 0.0,
        cashSales: 0.0,
        totalInvoices: 0,
        creditInvoices: 0,
        cashInvoices: 0,
      );
    }
  }
}
