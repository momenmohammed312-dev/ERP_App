import 'package:flutter/material.dart';
import 'package:drift/drift.dart' as drift;
import '../../core/database/app_database.dart';
import '../../core/services/db_schema_cache_service.dart';

class SalesPurchaseComparisonCard extends StatefulWidget {
  final AppDatabase database;

  const SalesPurchaseComparisonCard({super.key, required this.database});

  @override
  State<SalesPurchaseComparisonCard> createState() =>
      _SalesPurchaseComparisonCardState();
}

class _SalesPurchaseComparisonCardState
    extends State<SalesPurchaseComparisonCard> {
  double _todaySales = 0.0;
  double _todayPurchases = 0.0;
  bool _isLoading = true;
  DateTime? _lastRefresh;

  @override
  void initState() {
    super.initState();
    _loadTodayData();
  }

  Future<void> _loadTodayData() async {
    setState(() => _isLoading = true);

    try {
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      double salesTotal = 0.0;
      double purchasesTotal = 0.0;

      // Get today's sales with defensive column checking
      try {
        String salesTotalColumn = 'totalAmount';

        final invoicesColumns =
            await DbSchemaCacheService.getColumns(widget.database, 'invoices');
        if (!invoicesColumns.contains('totalAmount')) {
          for (final columnName in invoicesColumns) {
            if (columnName.contains('total') || columnName.contains('amount')) {
              salesTotalColumn = columnName;
              break;
            }
          }
        }

        final salesResult = await widget.database
            .customSelect(
              '''
          SELECT COALESCE(SUM($salesTotalColumn), 0) as total_sales
          FROM invoices 
          WHERE date >= ? AND date < ? AND status != 'deleted'
        ''',
              variables: [
                drift.Variable.withDateTime(startOfDay),
                drift.Variable.withDateTime(endOfDay),
              ],
            )
            .get();

        salesTotal =
            salesResult.first.readNullable<double>('total_sales') ?? 0.0;
      } catch (e) {
        debugPrint('Error getting sales data: $e');
        salesTotal = 0.0;
      }

      // Get today's purchases with defensive column checking
      try {
        String purchasesTotalColumn = 'totalAmount';

        final purchasesColumns =
            await DbSchemaCacheService.getColumns(widget.database, 'purchases');
        if (!purchasesColumns.contains('totalAmount')) {
          for (final columnName in purchasesColumns) {
            if (columnName.contains('total') || columnName.contains('amount')) {
              purchasesTotalColumn = columnName;
              break;
            }
          }
        }

        final purchasesResult = await widget.database
            .customSelect(
              '''
          SELECT COALESCE(SUM($purchasesTotalColumn), 0) as total_purchases
          FROM purchases 
          WHERE purchaseDate >= ? AND purchaseDate < ? AND isDeleted = 0
        ''',
              variables: [
                drift.Variable.withDateTime(startOfDay),
                drift.Variable.withDateTime(endOfDay),
              ],
            )
            .get();

        purchasesTotal =
            purchasesResult.first.readNullable<double>('total_purchases') ??
            0.0;
      } catch (e) {
        debugPrint('Error getting purchases data: $e');
        purchasesTotal = 0.0;
      }

      setState(() {
        _todaySales = salesTotal;
        _todayPurchases = purchasesTotal;
        _isLoading = false;
        _lastRefresh = DateTime.now();
      });
    } catch (e) {
      setState(() => _isLoading = false);
      debugPrint('Error loading today\'s data: $e');
    }
  }

  double get _profitLoss => _todaySales - _todayPurchases;
  bool get _isProfit => _profitLoss >= 0;
  String get _profitLossText {
    final amount = _profitLoss.abs().toStringAsFixed(2);
    return _isProfit ? 'ربح: $amount ج.م' : 'خسارة: $amount ج.م';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with refresh button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.compare_arrows,
                      color: Colors.blue.shade700,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'مقارنة المبيعات والمشتريات',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade800,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadTodayData,
                  tooltip: 'تحديث',
                  color: Colors.blue.shade700,
                ),
              ],
            ),

            const SizedBox(height: 20),

            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    children: [
                      // Sales and Purchases Row
                      Row(
                        children: [
                          Expanded(
                            child: _buildMetricCard(
                              'المبيعات اليوم',
                              _todaySales.toStringAsFixed(2),
                              Icons.trending_up,
                              Colors.green,
                              'ج.م',
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildMetricCard(
                              'المشتريات اليوم',
                              _todayPurchases.toStringAsFixed(2),
                              Icons.trending_down,
                              Colors.orange,
                              'ج.م',
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // Profit/Loss Card
                      _buildProfitLossCard(),

                      const SizedBox(height: 12),

                      // Last refresh info
                      if (_lastRefresh != null)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.schedule,
                              size: 14,
                              color: Colors.grey.shade600,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'آخر تحديث: ${_formatTime(_lastRefresh!)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                    ],
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
    String unit,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
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
                    fontSize: 14,
                    color: color.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: color.withValues(alpha: 0.8),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                unit,
                style: TextStyle(
                  fontSize: 14,
                  color: color.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProfitLossCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _isProfit
            ? Color.fromRGBO(76, 175, 80, 0.1)
            : Color.fromRGBO(244, 67, 54, 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _isProfit
              ? Color.fromRGBO(76, 175, 80, 0.8)
              : Color.fromRGBO(244, 67, 54, 0.8),
        ),
      ),
      child: Row(
        children: [
          Icon(
            _isProfit ? Icons.trending_up : Icons.trending_down,
            color: _isProfit
                ? Color.fromRGBO(76, 175, 80, 0.8)
                : Color.fromRGBO(244, 67, 54, 0.8),
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isProfit ? 'الربح الصافي اليوم' : 'الخسارة الصافية اليوم',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _isProfit
                        ? Colors.green.shade800
                        : Colors.red.shade800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _profitLossText,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _isProfit
                        ? Colors.green.shade700
                        : Colors.red.shade700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dateTime) {
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
