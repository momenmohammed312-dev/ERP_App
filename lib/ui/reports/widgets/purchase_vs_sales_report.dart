import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import 'package:pos_offline_desktop/core/provider/app_database_provider.dart';
import 'package:pos_offline_desktop/core/services/purchase_print_service_simple.dart';

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
        final debugResult = await db
            .customSelect('PRAGMA table_info(invoices)')
            .get();
        debugPrint('Invoices table columns:');
        bool hasTotalAmount = false;
        for (final row in debugResult) {
          final columnName = row.read<String>('name');
          debugPrint('  $columnName');
          if (columnName == 'totalAmount') {
            hasTotalAmount = true;
          }
        }

        if (!hasTotalAmount) {
          debugPrint(
            'totalAmount column not found, checking for alternatives...',
          );
          // Check for alternative column names
          for (final row in debugResult) {
            final columnName = row.read<String>('name');
            if (columnName.contains('total') || columnName.contains('amount')) {
              salesTotalColumn = columnName;
              debugPrint('Using alternative column: $columnName');
              break;
            }
          }
        }
      } catch (e) {
        debugPrint('Error checking invoices table: $e');
      }

      // Check purchases table as well
      try {
        final debugResult = await db
            .customSelect('PRAGMA table_info(purchases)')
            .get();
        debugPrint('Purchases table columns:');
        bool hasTotalAmount = false;
        for (final row in debugResult) {
          final columnName = row.read<String>('name');
          debugPrint('  $columnName');
          if (columnName == 'totalAmount') {
            hasTotalAmount = true;
          }
        }

        if (!hasTotalAmount) {
          debugPrint(
            'totalAmount column not found in purchases, checking for alternatives...',
          );
          // Check for alternative column names
          for (final row in debugResult) {
            final columnName = row.read<String>('name');
            if (columnName.contains('total') || columnName.contains('amount')) {
              purchasesTotalColumn = columnName;
              debugPrint('Using alternative purchases column: $columnName');
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
              drift.Variable.withDateTime(_selectedDateRange!.start),
              drift.Variable.withDateTime(_selectedDateRange!.end),
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
              drift.Variable.withDateTime(_selectedDateRange!.start),
              drift.Variable.withDateTime(_selectedDateRange!.end),
            ],
          )
          .get();

      // Combine data by date
      final Map<String, Map<String, dynamic>> combinedData = {};

      // Add sales data
      for (final row in salesResult) {
        final date = row.read<String>('report_date');
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
        final date = row.read<String>('report_date');
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
            'gross_profit': 0.0,
            'profit_margin': 0.0,
          };
        }
      }

      // Calculate profit for each day
      final comparisonData = combinedData.values.map((data) {
        final totalSales = data['total_sales'] as double;
        final totalPurchases = data['total_purchases'] as double;
        final grossProfit = totalSales - totalPurchases;
        final profitMargin = totalSales > 0
            ? (grossProfit / totalSales) * 100
            : 0.0;

        data['gross_profit'] = grossProfit;
        data['profit_margin'] = profitMargin;

        return data;
      }).toList();

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
      final grossProfit = totalSales - totalPurchases;
      final profitMargin = totalSales > 0
          ? (grossProfit / totalSales) * 100
          : 0.0;

      setState(() {
        _comparisonData = comparisonData;
        _totalSales = totalSales;
        _totalPurchases = totalPurchases;
        _grossProfit = grossProfit;
        _profitMargin = profitMargin;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في تحميل التقرير: $e'),
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

  void _exportToExcel() {
    try {
      // Create CSV content for Excel compatibility
      final csvData = <String>[];

      // Add header
      csvData.add(
        'التاريخ,إجمالي المبيعات,إجمالي المشتريات,الربح الصافي,نسبة الربح',
      );

      // Add data rows
      for (final item in _comparisonData) {
        final profitMargin = item['total_sales'] > 0
            ? ((item['gross_profit'] as double) / item['total_sales'] * 100)
            : 0.0;
        csvData.add(
          '${item['date']},${item['total_sales']},${item['total_purchases']},${item['gross_profit']},${profitMargin.toStringAsFixed(2)}%',
        );
      }

      // Add summary
      csvData.add('');
      csvData.add(
        'الإجمالي,$_totalSales,$_totalPurchases,$_grossProfit,$_profitMargin%',
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
                const SizedBox(width: 12),
                Expanded(
                  child: _buildSummaryCard(
                    'إجمالي المشتريات',
                    '${_totalPurchases.toStringAsFixed(2)} ج.م',
                    Colors.orange,
                    Icons.shopping_cart,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildSummaryCard(
                    'الربح الإجمالي',
                    '${_grossProfit.toStringAsFixed(2)} ج.م',
                    _grossProfit >= 0 ? Colors.blue : Colors.red,
                    _grossProfit >= 0 ? Icons.attach_money : Icons.money_off,
                  ),
                ),
                const SizedBox(width: 12),
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
                          DataColumn(label: Text('الربح'), numeric: true),
                          DataColumn(label: Text('نسبة الربح'), numeric: true),
                          DataColumn(label: Text('هامش الربح'), numeric: false),
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
