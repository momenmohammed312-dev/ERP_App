import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:drift/drift.dart' as drift;
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/services/db_schema_cache_service.dart';

class DailySalesPerformanceWidget extends StatefulWidget {
  final AppDatabase db;

  const DailySalesPerformanceWidget({super.key, required this.db});

  @override
  State<DailySalesPerformanceWidget> createState() =>
      _DailySalesPerformanceWidgetState();
}

class _DailySalesPerformanceWidgetState
    extends State<DailySalesPerformanceWidget> {
  DateTimeRange? _selectedDateRange;
  List<DailySalesData> _dailySalesData = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _selectedDateRange = DateTimeRange(
      start: DateTime.now().subtract(const Duration(days: 7)),
      end: DateTime.now(),
    );
    _loadDailySalesData();
  }

  Future<void> _loadDailySalesData() async {
    if (_selectedDateRange == null) return;

    setState(() => _isLoading = true);

    try {
      final data = await _getDailySalesData(
        _selectedDateRange!.start,
        _selectedDateRange!.end,
      );
      setState(() {
        _dailySalesData = data;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      debugPrint('Error loading daily sales data: $e');
    }
  }

  Future<List<DailySalesData>> _getDailySalesData(
    DateTime startDate,
    DateTime endDate,
  ) async {
    try {
      // Check if totalAmount column exists in invoices
      String salesTotalColumn = 'totalAmount';
      try {
        final invoicesColumns =
            await DbSchemaCacheService.getColumns(widget.db, 'invoices');
        if (!invoicesColumns.contains('totalAmount')) {
          for (final columnName in invoicesColumns) {
            if (columnName.contains('total') || columnName.contains('amount')) {
              salesTotalColumn = columnName;
              break;
            }
          }
        }
      } catch (e) {
        debugPrint('Error checking invoices table: $e');
      }

      String purchasesTotalColumn = 'totalAmount';
      try {
        final purchasesColumns =
            await DbSchemaCacheService.getColumns(widget.db, 'purchases');
        if (!purchasesColumns.contains('totalAmount')) {
          for (final columnName in purchasesColumns) {
            if (columnName.contains('total') || columnName.contains('amount')) {
              purchasesTotalColumn = columnName;
              break;
            }
          }
        }
      } catch (e) {
        debugPrint('Error checking purchases table: $e');
      }

      // Get daily sales data
      final salesResult = await widget.db
          .customSelect(
            '''
        SELECT 
          DATE(date) as report_date,
          COALESCE(SUM($salesTotalColumn), 0) as total_sales,
          COUNT(*) as invoice_count
        FROM invoices 
        WHERE date >= ? AND date <= ? AND status != 'deleted'
        GROUP BY DATE(date)
        ORDER BY report_date DESC
      ''',
            variables: [
              drift.Variable.withDateTime(startDate),
              drift.Variable.withDateTime(endDate),
            ],
          )
          .get();

      // Get daily purchases data
      final purchasesResult = await widget.db
          .customSelect(
            '''
        SELECT 
          DATE(purchaseDate) as report_date,
          COALESCE(SUM($purchasesTotalColumn), 0) as total_purchases,
          COUNT(*) as purchase_count
        FROM purchases 
        WHERE purchaseDate >= ? AND purchaseDate <= ? AND isDeleted = 0
        GROUP BY DATE(purchaseDate)
        ORDER BY report_date DESC
      ''',
            variables: [
              drift.Variable.withDateTime(startDate),
              drift.Variable.withDateTime(endDate),
            ],
          )
          .get();

      // Get day opening/closing data
      final daysResult = await widget.db
          .customSelect(
            '''
        SELECT 
          DATE(date) as report_date,
          openingBalance,
          closingBalance,
          isOpen
        FROM days 
        WHERE date >= ? AND date <= ?
        ORDER BY report_date DESC
      ''',
            variables: [
              drift.Variable.withDateTime(startDate),
              drift.Variable.withDateTime(endDate),
            ],
          )
          .get();

      // Combine data by date
      Map<String, DailySalesData> dailyData = {};

      // Add sales data
      for (final row in salesResult) {
        final date = row.readNullable<String>('report_date') ?? '';
        dailyData[date] = DailySalesData(
          date: DateTime.parse(date),
          totalSales: row.readNullable<double>('total_sales') ?? 0.0,
          totalPurchases: 0.0,
          invoiceCount: row.readNullable<int>('invoice_count') ?? 0,
          purchaseCount: 0,
          openingBalance: 0.0,
          closingBalance: 0.0,
          isOpen: false,
        );
      }

      // Add purchases data
      for (final row in purchasesResult) {
        final date = row.readNullable<String>('report_date') ?? '';
        if (dailyData.containsKey(date)) {
          dailyData[date] = dailyData[date]!.copyWith(
            totalPurchases: row.readNullable<double>('total_purchases') ?? 0.0,
            purchaseCount: row.readNullable<int>('purchase_count') ?? 0,
          );
        } else {
          dailyData[date] = DailySalesData(
            date: DateTime.parse(date),
            totalSales: 0.0,
            totalPurchases: row.readNullable<double>('total_purchases') ?? 0.0,
            invoiceCount: 0,
            purchaseCount: row.readNullable<int>('purchase_count') ?? 0,
            openingBalance: 0.0,
            closingBalance: 0.0,
            isOpen: false,
          );
        }
      }

      // Add days data
      for (final row in daysResult) {
        final date = row.readNullable<String>('report_date') ?? '';
        if (dailyData.containsKey(date)) {
          dailyData[date] = dailyData[date]!.copyWith(
            openingBalance: row.readNullable<double>('openingBalance') ?? 0.0,
            closingBalance: row.readNullable<double>('closingBalance') ?? 0.0,
            isOpen: (row.readNullable<int>('isOpen') ?? 0) == 1,
          );
        } else {
          dailyData[date] = DailySalesData(
            date: DateTime.parse(date),
            totalSales: 0.0,
            totalPurchases: 0.0,
            invoiceCount: 0,
            purchaseCount: 0,
            openingBalance: row.readNullable<double>('openingBalance') ?? 0.0,
            closingBalance: row.readNullable<double>('closingBalance') ?? 0.0,
            isOpen: (row.readNullable<int>('isOpen') ?? 0) == 1,
          );
        }
      }

      return dailyData.values.toList()
        ..sort((a, b) => b.date.compareTo(a.date));
    } catch (e) {
      debugPrint('Error getting daily sales data: $e');
      return [];
    }
  }

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
            // Header with date range selector
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'أداء المبيعات اليومي',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                Row(
                  children: [
                    // Date range selector
                    InkWell(
                      onTap: _selectDateRange,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.date_range,
                              size: 16,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _selectedDateRange != null
                                  ? '${DateFormat('dd/MM').format(_selectedDateRange!.start)} - ${DateFormat('dd/MM').format(_selectedDateRange!.end)}'
                                  : 'اختر الفترة',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      onPressed: _loadDailySalesData,
                      icon: const Icon(Icons.refresh),
                      tooltip: 'تحديث البيانات',
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Daily sales data
            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _dailySalesData.isEmpty
                ? Container(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 48,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'لا توجد بيانات في الفترة المحددة',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.7),
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  )
                : Column(
                    children: [
                      // Summary cards
                      Row(
                        children: [
                          Expanded(
                            child: _buildSummaryCard(
                              'إجمالي المبيعات',
                              '${_dailySalesData.fold<double>(0, (sum, day) => sum + day.totalSales).toStringAsFixed(2)} ج.م',
                              Icons.trending_up,
                              Colors.green,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildSummaryCard(
                              'إجمالي المشتريات',
                              '${_dailySalesData.fold<double>(0, (sum, day) => sum + day.totalPurchases).toStringAsFixed(2)} ج.م',
                              Icons.shopping_cart,
                              Colors.orange,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildSummaryCard(
                              'صافي الربح',
                              '${(_dailySalesData.fold<double>(0, (sum, day) => sum + (day.totalSales - day.totalPurchases))).toStringAsFixed(2)} ج.م',
                              Icons.account_balance,
                              _dailySalesData.fold<double>(
                                        0,
                                        (sum, day) =>
                                            sum +
                                            (day.totalSales -
                                                day.totalPurchases),
                                      ) >=
                                      0
                                  ? Colors.blue
                                  : Colors.red,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Daily list
                      Container(
                        height: 300,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ListView.builder(
                          padding: const EdgeInsets.all(8),
                          itemCount: _dailySalesData.length,
                          itemBuilder: (context, index) {
                            final dayData = _dailySalesData[index];
                            return _buildDayCard(dayData);
                          },
                        ),
                      ),
                    ],
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(
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
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDayCard(DailySalesData dayData) {
    final profit = dayData.totalSales - dayData.totalPurchases;
    final isProfit = profit >= 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isProfit
              ? Colors.green.withValues(alpha: 0.3)
              : Colors.red.withValues(alpha: 0.3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date and status
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  DateFormat('EEEE, dd MMMM yyyy', 'ar').format(dayData.date),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                Row(
                  children: [
                    Icon(
                      dayData.isOpen ? Icons.lock_open : Icons.lock,
                      size: 16,
                      color: dayData.isOpen ? Colors.green : Colors.grey,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      dayData.isOpen ? 'مفتوح' : 'مغلق',
                      style: TextStyle(
                        fontSize: 12,
                        color: dayData.isOpen ? Colors.green : Colors.grey,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Financial summary
            Row(
              children: [
                Expanded(
                  child: _buildDayMetric(
                    'المبيعات',
                    '${dayData.totalSales.toStringAsFixed(2)} ج.م',
                    Icons.trending_up,
                    Colors.green,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildDayMetric(
                    'المشتريات',
                    '${dayData.totalPurchases.toStringAsFixed(2)} ج.م',
                    Icons.shopping_cart,
                    Colors.orange,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildDayMetric(
                    'الصافي',
                    '${profit.toStringAsFixed(2)} ج.م',
                    isProfit ? Icons.trending_up : Icons.trending_down,
                    isProfit ? Colors.blue : Colors.red,
                  ),
                ),
              ],
            ),

            // Additional info
            if (dayData.openingBalance > 0 || dayData.closingBalance > 0)
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    if (dayData.openingBalance > 0)
                      Text(
                        'رصيد افتتاح: ${dayData.openingBalance.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                    if (dayData.closingBalance > 0)
                      Text(
                        'رصيد إغلاق: ${dayData.closingBalance.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDayMetric(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Future<void> _selectDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _selectedDateRange,
      builder: (context, child) {
        return Theme(
          data: Theme.of(
            context,
          ).copyWith(colorScheme: Theme.of(context).colorScheme),
          child: child!,
        );
      },
    );

    if (picked != null && picked != _selectedDateRange) {
      setState(() {
        _selectedDateRange = picked;
      });
      _loadDailySalesData();
    }
  }
}

class DailySalesData {
  final DateTime date;
  final double totalSales;
  final double totalPurchases;
  final int invoiceCount;
  final int purchaseCount;
  final double openingBalance;
  final double closingBalance;
  final bool isOpen;

  DailySalesData({
    required this.date,
    required this.totalSales,
    required this.totalPurchases,
    required this.invoiceCount,
    required this.purchaseCount,
    required this.openingBalance,
    required this.closingBalance,
    required this.isOpen,
  });

  DailySalesData copyWith({
    DateTime? date,
    double? totalSales,
    double? totalPurchases,
    int? invoiceCount,
    int? purchaseCount,
    double? openingBalance,
    double? closingBalance,
    bool? isOpen,
  }) {
    return DailySalesData(
      date: date ?? this.date,
      totalSales: totalSales ?? this.totalSales,
      totalPurchases: totalPurchases ?? this.totalPurchases,
      invoiceCount: invoiceCount ?? this.invoiceCount,
      purchaseCount: purchaseCount ?? this.purchaseCount,
      openingBalance: openingBalance ?? this.openingBalance,
      closingBalance: closingBalance ?? this.closingBalance,
      isOpen: isOpen ?? this.isOpen,
    );
  }
}
