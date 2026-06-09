import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import 'package:fl_chart/fl_chart.dart';
import 'package:pos_offline_desktop/core/provider/app_database_provider.dart';
import 'package:pos_offline_desktop/core/services/db_schema_cache_service.dart';
import 'package:pos_offline_desktop/core/services/purchase_print_service_simple.dart';
import 'package:pos_offline_desktop/core/utils/logger.dart';

class PurchaseVsSalesReport extends ConsumerStatefulWidget {
  const PurchaseVsSalesReport({super.key});

  @override
  ConsumerState<PurchaseVsSalesReport> createState() =>
      _PurchaseVsSalesReportState();
}

class _PurchaseVsSalesReportState extends ConsumerState<PurchaseVsSalesReport> {
  bool _isLoading = false;
  DateTimeRange? _selectedDateRange;
  List<Map<String, dynamic>> _comparisonData = [];
  double _totalSales = 0.0;
  double _totalPurchases = 0.0;
  double _totalExpenses = 0.0;
  double _grossProfit = 0.0;
  double _profitMargin = 0.0;

  @override
  void initState() {
    super.initState();
    _selectedDateRange = DateTimeRange(
      start: DateTime.now().subtract(const Duration(days: 30)),
      end: DateTime.now(),
    );
    _loadReportData();
  }

  Future<void> _loadReportData() async {
    if (_selectedDateRange == null) return;

    setState(() => _isLoading = true);

    try {
      final db = ref.read(appDatabaseProvider);

      // Debug: Check actual column names in invoices table
      String salesTotalColumn = 'totalAmount';
      String purchasesTotalColumn = 'totalAmount';

      try {
        final invoiceColumns =
            await DbSchemaCacheService.getColumns(db, 'invoices');
        if (!invoiceColumns.contains('totalAmount')) {
          for (final columnName in invoiceColumns) {
            if (columnName.contains('total') || columnName.contains('amount')) {
              salesTotalColumn = columnName;
              break;
            }
          }
        }
      } catch (e) {
        debugPrint('Error checking invoices table: $e');
      }

      try {
        final purchaseColumns =
            await DbSchemaCacheService.getColumns(db, 'purchases');
        if (!purchaseColumns.contains('totalAmount')) {
          for (final columnName in purchaseColumns) {
            if (columnName.contains('total') || columnName.contains('amount')) {
              purchasesTotalColumn = columnName;
              break;
            }
          }
        }
      } catch (e) {
        debugPrint('Error checking purchases table: $e');
      }

      // Get sales data
      final salesResult = await db
          .customSelect(
            '''
        SELECT 
          DATE(date) as report_date,
          COUNT(*) as invoice_count,
          SUM(total_amount) as total_sales,
          SUM(CASE WHEN LOWER(TRIM(COALESCE(payment_method, 'cash'))) = 'cash' THEN total_amount ELSE 0 END) as cash_sales,
          SUM(CASE WHEN LOWER(TRIM(COALESCE(payment_method, 'cash'))) = 'credit' OR LOWER(TRIM(payment_method)) LIKE '%آجل%' THEN total_amount ELSE 0 END) as credit_sales
        FROM invoices 
        WHERE date >= ? AND date <= ? AND status != 'deleted'
        GROUP BY DATE(date)
        ORDER BY report_date
      ''',
            variables: [
              drift.Variable.withString(
                _selectedDateRange!.start.toIso8601String(),
              ),
              drift.Variable.withString(
                _selectedDateRange!.end.toIso8601String(),
              ),
            ],
          )
          .get();

      // Get purchases data
      final purchasesResult = await db
          .customSelect(
            '''
        SELECT 
          DATE(purchase_date) as report_date,
          COUNT(*) as purchase_count,
          SUM(total_amount) as total_purchases,
          SUM(CASE WHEN LOWER(TRIM(COALESCE(payment_method, 'cash'))) = 'cash' THEN total_amount ELSE 0 END) as cash_purchases,
          SUM(CASE WHEN LOWER(TRIM(COALESCE(payment_method, 'cash'))) = 'credit' OR LOWER(TRIM(payment_method)) LIKE '%آجل%' THEN total_amount ELSE 0 END) as credit_purchases
        FROM purchases 
        WHERE purchase_date >= ? AND purchase_date <= ? AND is_deleted = 0
        GROUP BY DATE(purchase_date)
        ORDER BY report_date
      ''',
            variables: [
              drift.Variable.withString(
                _selectedDateRange!.start.toIso8601String(),
              ),
              drift.Variable.withString(
                _selectedDateRange!.end.toIso8601String(),
              ),
            ],
          )
          .get();

      // Get expenses data
      final expensesResult = await db
          .customSelect(
            '''
        SELECT 
          DATE(date) as report_date,
          COUNT(*) as expense_count,
          SUM(amount) as total_expenses
        FROM expenses 
        WHERE date >= ? AND date <= ?
        GROUP BY DATE(date)
        ORDER BY report_date
      ''',
            variables: [
              drift.Variable.withString(
                _selectedDateRange!.start.toIso8601String(),
              ),
              drift.Variable.withString(
                _selectedDateRange!.end.toIso8601String(),
              ),
            ],
          )
          .get();

      // Combine data by date
      final Map<String, Map<String, dynamic>> combinedData = {};

      // Add sales data
      for (final row in salesResult) {
        final date = row.readNullable<String>('report_date') ?? 'unknown';
        combinedData[date] = {
          'date': date,
          'sales_count': row.readNullable<num>('invoice_count')?.toInt() ?? 0,
          'total_sales':
              row.readNullable<num>('total_sales')?.toDouble() ?? 0.0,
          'cash_sales': row.readNullable<num>('cash_sales')?.toDouble() ?? 0.0,
          'credit_sales':
              row.readNullable<num>('credit_sales')?.toDouble() ?? 0.0,
          'purchase_count': 0,
          'total_purchases': 0.0,
          'cash_purchases': 0.0,
          'credit_purchases': 0.0,
          'gross_profit': 0.0,
          'profit_margin': 0.0,
        };
      }

      // Add purchases data
      for (final row in purchasesResult) {
        final date = row.readNullable<String>('report_date') ?? 'unknown';
        if (combinedData.containsKey(date)) {
          final data = combinedData[date]!;
          data['purchase_count'] =
              row.readNullable<num>('purchase_count')?.toInt() ?? 0;
          data['total_purchases'] =
              row.readNullable<num>('total_purchases')?.toDouble() ?? 0.0;
          data['cash_purchases'] =
              row.readNullable<num>('cash_purchases')?.toDouble() ?? 0.0;
          data['credit_purchases'] =
              row.readNullable<num>('credit_purchases')?.toDouble() ?? 0.0;
        } else {
          combinedData[date] = {
            'date': date,
            'sales_count': 0,
            'total_sales': 0.0,
            'cash_sales': 0.0,
            'credit_sales': 0.0,
            'purchase_count':
                row.readNullable<num>('purchase_count')?.toInt() ?? 0,
            'total_purchases':
                row.readNullable<num>('total_purchases')?.toDouble() ?? 0.0,
            'cash_purchases':
                row.readNullable<num>('cash_purchases')?.toDouble() ?? 0.0,
            'credit_purchases':
                row.readNullable<num>('credit_purchases')?.toDouble() ?? 0.0,
            'expense_count': 0,
            'total_expenses': 0.0,
            'gross_profit': 0.0,
            'profit_margin': 0.0,
          };
        }
      }

      // Add expenses data
      for (final row in expensesResult) {
        final date = row.readNullable<String>('report_date') ?? 'unknown';
        if (combinedData.containsKey(date)) {
          final data = combinedData[date]!;
          data['expense_count'] =
              row.readNullable<num>('expense_count')?.toInt() ?? 0;
          data['total_expenses'] =
              row.readNullable<num>('total_expenses')?.toDouble() ?? 0.0;
        } else {
          combinedData[date] = {
            'date': date,
            'sales_count': 0,
            'total_sales': 0.0,
            'cash_sales': 0.0,
            'credit_sales': 0.0,
            'purchase_count': 0,
            'total_purchases': 0.0,
            'cash_purchases': 0.0,
            'credit_purchases': 0.0,
            'expense_count':
                row.readNullable<num>('expense_count')?.toInt() ?? 0,
            'total_expenses':
                row.readNullable<num>('total_expenses')?.toDouble() ?? 0.0,
            'gross_profit': 0.0,
            'profit_margin': 0.0,
          };
        }
      }

      // Calculate profit for each day
      final comparisonData = combinedData.values.map((data) {
        final totalSales = data['total_sales'] as double;
        final totalPurchases = data['total_purchases'] as double;
        final totalExpenses = data['total_expenses'] as double;
        final grossProfit = totalSales - totalPurchases - totalExpenses;
        final profitMargin = totalSales > 0
            ? (grossProfit / totalSales) * 100
            : 0.0;

        data['gross_profit'] = grossProfit;
        data['profit_margin'] = profitMargin;

        return data;
      }).toList();

      comparisonData.removeWhere((item) => item['date'] == 'unknown');

      // Sort by date
      comparisonData.sort(
        (a, b) => (a['date'] as String).compareTo(b['date'] as String),
      );

      // Calculate totals
      final totalSales = comparisonData.fold<double>(
        0.0,
        (sum, item) => sum + (item['total_sales'] as double),
      );
      final totalPurchases = comparisonData.fold<double>(
        0.0,
        (sum, item) => sum + (item['total_purchases'] as double),
      );
      final totalExpenses = comparisonData.fold<double>(
        0.0,
        (sum, item) => sum + (item['total_expenses'] as double),
      );
      final grossProfit = totalSales - totalPurchases - totalExpenses;
      final profitMargin = totalSales > 0
          ? (grossProfit / totalSales) * 100
          : 0.0;

      setState(() {
        _comparisonData = comparisonData;
        _totalSales = totalSales;
        _totalPurchases = totalPurchases;
        _totalExpenses = totalExpenses;
        _grossProfit = grossProfit;
        _profitMargin = profitMargin;
        _isLoading = false;
      });
    } catch (e, stack) {
      AppLogger.e('Failed to load purchase vs sales report', e, stack);
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('حدث خطأ أثناء تحميل البيانات'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _selectedDateRange,
      builder: (context, child) {
        return child!;
      },
    );

    if (picked != null) {
      setState(() {
        _selectedDateRange = picked;
      });
      _loadReportData();
    }
  }

  Widget _buildBarChart() {
    if (_comparisonData.isEmpty) return const SizedBox.shrink();

    final maxValue = _comparisonData.fold<double>(0.0, (max, item) {
      final s = (item['total_sales'] as double);
      final p = (item['total_purchases'] as double);
      final e = (item['total_expenses'] as double);
      return [max, s, p, e].reduce((a, b) => a > b ? a : b);
    });

    final barGroups = _comparisonData.asMap().entries.map((entry) {
      final i = entry.key;
      final data = entry.value;
      return BarChartGroupData(
        x: i,
        barRods: [
          BarChartRodData(
            toY: (data['total_sales'] as double),
            color: Colors.green,
            width: 8,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(3),
              topRight: Radius.circular(3),
            ),
          ),
          BarChartRodData(
            toY: (data['total_purchases'] as double),
            color: Colors.orange,
            width: 8,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(3),
              topRight: Radius.circular(3),
            ),
          ),
          BarChartRodData(
            toY: (data['total_expenses'] as double),
            color: Colors.redAccent,
            width: 8,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(3),
              topRight: Radius.circular(3),
            ),
          ),
        ],
      );
    }).toList();

    return SizedBox(
      height: 220,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 16, 24, 8),
        child: BarChart(
          BarChartData(
            alignment: BarChartAlignment.spaceAround,
            maxY: maxValue * 1.2,
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipItem: (group, groupIndex, rod, rodIndex) {
                  final date = _comparisonData[group.x]['date'] as String;
                  final labels = ['المبيعات', 'المشتريات', 'المصروفات'];
                  return BarTooltipItem(
                    '$date\n${labels[rodIndex]}: ${rod.toY.toStringAsFixed(0)} ج.م',
                    const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  );
                },
              ),
            ),
            titlesData: FlTitlesData(
              show: true,
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 28,
                  getTitlesWidget: (value, meta) {
                    final i = value.toInt();
                    if (i < 0 || i >= _comparisonData.length) {
                      return const SizedBox.shrink();
                    }
                    final parts = (_comparisonData[i]['date'] as String).split('-');
                    final label = parts.length >= 3 ? '${parts[2]}/${parts[1]}' : '';
                    return SideTitleWidget(
                      axisSide: meta.axisSide,
                      child: Text(
                        label,
                        style: const TextStyle(fontSize: 9),
                      ),
                    );
                  },
                ),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 48,
                  getTitlesWidget: (value, meta) {
                    return Text(
                      '${value.toInt()}',
                      style: const TextStyle(fontSize: 9),
                    );
                  },
                ),
              ),
              topTitles: AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              rightTitles: AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
            ),
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: maxValue * 0.2 > 1 ? maxValue * 0.2 : 1,
            ),
            borderData: FlBorderData(show: false),
            barGroups: barGroups,
          ),
        ),
      ),
    );
  }

  void _exportToExcel() {
    try {
      // Create CSV content for Excel compatibility
      final csvData = <String>[];

      // Add header
      csvData.add(
        'التاريخ,إجمالي المبيعات,إجمالي المشتريات,إجمالي المصروفات,صافي الربح,نسبة الربح',
      );

      // Add data rows
      for (final item in _comparisonData) {
        final profitMargin = item['total_sales'] > 0
            ? ((item['gross_profit'] as double) / item['total_sales'] * 100)
            : 0.0;
        csvData.add(
          '${item['date']},${item['total_sales']},${item['total_purchases']},${item['total_expenses']},${item['gross_profit']},${profitMargin.toStringAsFixed(2)}%',
        );
      }

      // Add summary
      csvData.add('');
      csvData.add(
        'الإجمالي,$_totalSales,$_totalPurchases,$_totalExpenses,$_grossProfit,$_profitMargin%',
      );

      // Create download
      final csvString = csvData.join('\n');

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم تصدير البيانات بنجاح (نسخة للمعاينة)'),
          backgroundColor: Colors.green,
        ),
      );

      // For now, just show the data in a dialog
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('بيانات التصدير'),
          content: SingleChildScrollView(child: Text(csvString)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ في التصدير: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _printReport() async {
    try {
      final db = ref.read(appDatabaseProvider);
      final printService = PurchasePrintService(db);

      await printService.printPurchaseReport(
        startDate: _selectedDateRange?.start,
        endDate: _selectedDateRange?.end,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم طباعة التقرير بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في الطباعة: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('تقرير مقارنة المشتريات بالمبيعات'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            onPressed: _selectDateRange,
            icon: const Icon(Icons.date_range),
            tooltip: 'اختر الفترة',
          ),
          IconButton(
            onPressed: _exportToExcel,
            icon: const Icon(Icons.file_download),
            tooltip: 'تصدير Excel',
          ),
          IconButton(
            onPressed: _printReport,
            icon: const Icon(Icons.print),
            tooltip: 'طباعة',
          ),
          IconButton(
            onPressed: _loadReportData,
            icon: const Icon(Icons.refresh),
            tooltip: 'تحديث',
          ),
        ],
      ),
      body: Column(
        children: [
          // Date Range Selector
          Container(
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).colorScheme.surface,
            child: Row(
              children: [
                Icon(
                  Icons.date_range,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _selectedDateRange != null
                        ? 'الفترة: ${DateFormat('yyyy-MM-dd').format(_selectedDateRange!.start)} إلى ${DateFormat('yyyy-MM-dd').format(_selectedDateRange!.end)}'
                        : 'اختر الفترة',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _selectDateRange,
                  child: const Text('تغيير الفترة'),
                ),
              ],
            ),
          ),

          // Summary Cards
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: _buildSummaryCard(
                    'إجمالي المبيعات',
                    '${_totalSales.toStringAsFixed(2)} ج.م',
                    Colors.green,
                    Icons.trending_up,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildSummaryCard(
                    'إجمالي المشتريات',
                    '${_totalPurchases.toStringAsFixed(2)} ج.م',
                    Colors.orange,
                    Icons.shopping_cart,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildSummaryCard(
                    'إجمالي المصروفات',
                    '${_totalExpenses.toStringAsFixed(2)} ج.م',
                    Colors.redAccent,
                    Icons.receipt_long,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildSummaryCard(
                    'صافي الربح',
                    '${_grossProfit.toStringAsFixed(2)} ج.م',
                    _grossProfit >= 0 ? Colors.blue : Colors.red,
                    _grossProfit >= 0 ? Icons.attach_money : Icons.money_off,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildSummaryCard(
                    'نسبة الربح',
                    '${_profitMargin.toStringAsFixed(1)}%',
                    _profitMargin >= 0 ? Colors.purple : Colors.red,
                    Icons.percent,
                  ),
                ),
              ],
            ),
          ),

          // Bar Chart
          if (_comparisonData.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.bar_chart, size: 20),
                          const SizedBox(width: 8),
                          const Text(
                            'مخطط المقارنة اليومي',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          _buildLegend(Colors.green, 'مبيعات'),
                          const SizedBox(width: 12),
                          _buildLegend(Colors.orange, 'مشتريات'),
                          const SizedBox(width: 12),
                          _buildLegend(Colors.redAccent, 'مصروفات'),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildBarChart(),
                    ],
                  ),
                ),
              ),
            ),

          // Data Table
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _comparisonData.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.analytics, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text(
                          'لا توجد بيانات في الفترة المحددة',
                          style: TextStyle(fontSize: 18, color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : SingleChildScrollView(
                    child: Card(
                      margin: const EdgeInsets.all(16),
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('التاريخ'), numeric: false),
                          DataColumn(label: Text('المبيعات'), numeric: true),
                          DataColumn(label: Text('المشتريات'), numeric: true),
                          DataColumn(label: Text('المصروفات'), numeric: true),
                          DataColumn(label: Text('صافي الربح'), numeric: true),
                          DataColumn(label: Text('نسبة الربح'), numeric: true),
                          DataColumn(label: Text('الهامش'), numeric: false),
                        ],
                        rows: _comparisonData.map((data) {
                          final grossProfit = data['gross_profit'] as double;
                          final profitMargin = data['profit_margin'] as double;

                          return DataRow(
                            cells: [
                              DataCell(
                                Text(
                                  data['date'] as String,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              DataCell(
                                Text(
                                  '${(data['total_sales'] as double).toStringAsFixed(2)} ج.م',
                                  style: const TextStyle(
                                    color: Colors.green,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              DataCell(
                                Text(
                                  '${(data['total_purchases'] as double).toStringAsFixed(2)} ج.م',
                                  style: const TextStyle(
                                    color: Colors.orange,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              DataCell(
                                Text(
                                  '${(data['total_expenses'] as double).toStringAsFixed(2)} ج.م',
                                  style: const TextStyle(
                                    color: Colors.redAccent,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              DataCell(
                                Text(
                                  '${grossProfit.toStringAsFixed(2)} ج.م',
                                  style: TextStyle(
                                    color: grossProfit >= 0
                                        ? Colors.blue
                                        : Colors.red,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              DataCell(
                                Text(
                                  '${profitMargin.toStringAsFixed(1)}%',
                                  style: TextStyle(
                                    color: profitMargin >= 0
                                        ? Colors.purple
                                        : Colors.red,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              DataCell(
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: profitMargin >= 0
                                        ? Colors.green.withValues(alpha: 0.3)
                                        : Colors.red.withValues(alpha: 0.3),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: profitMargin >= 0
                                          ? Colors.green
                                          : Colors.red,
                                    ),
                                  ),
                                  child: Text(
                                    profitMargin >= 0 ? 'ربح' : 'خسارة',
                                    style: TextStyle(
                                      color: profitMargin >= 0
                                          ? Colors.green
                                          : Colors.red,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegend(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }

  Widget _buildSummaryCard(
    String title,
    String value,
    Color color,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(title, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
