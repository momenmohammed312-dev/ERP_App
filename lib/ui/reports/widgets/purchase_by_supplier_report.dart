import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import 'package:pos_offline_desktop/core/provider/app_database_provider.dart';
import 'package:pos_offline_desktop/core/services/purchase_print_service_simple.dart';

class PurchaseBySupplierReport extends ConsumerStatefulWidget {
  const PurchaseBySupplierReport({super.key});

  @override
  ConsumerState<PurchaseBySupplierReport> createState() =>
      _PurchaseBySupplierReportState();
}

class _PurchaseBySupplierReportState
    extends ConsumerState<PurchaseBySupplierReport> {
  bool _isLoading = false;
  DateTimeRange? _selectedDateRange;
  List<Map<String, dynamic>> _supplierData = [];
  double _totalPurchases = 0.0;
  double _totalPaid = 0.0;
  double _totalRemaining = 0.0;
  int _totalInvoices = 0;

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

      // Get purchase data grouped by supplier
      final result = await db
          .customSelect(
            '''
        SELECT 
          s.id as supplier_id,
          s.name as supplier_name,
          s.phone as supplier_phone,
          COUNT(p.id) as invoice_count,
          COALESCE(SUM(p.total_amount), 0) as total_purchases,
          COALESCE(SUM(p.paid_amount), 0) as total_paid,
          COALESCE(SUM(p.total_amount - p.paid_amount), 0) as total_remaining
        FROM suppliers s
        LEFT JOIN purchases p ON s.id = p.supplier_id 
          AND p.purchase_date >= ? 
          AND p.purchase_date <= ?
          AND p.is_deleted = 0
        WHERE s.status = 'Active'
        GROUP BY s.id, s.name, s.phone
        HAVING COUNT(p.id) > 0 OR COALESCE(SUM(p.total_amount), 0) > 0
        ORDER BY total_purchases DESC
      ''',
            variables: [
              if (_selectedDateRange != null)
                drift.Variable.withDateTime(_selectedDateRange!.start)
              else
                drift.Variable.withDateTime(
                  DateTime.now().subtract(const Duration(days: 30)),
                ),
              if (_selectedDateRange != null)
                drift.Variable.withDateTime(_selectedDateRange!.end)
              else
                drift.Variable.withDateTime(DateTime.now()),
            ],
          )
          .get();

      final supplierData = result
          .map(
            (row) => {
              'supplier_id': row.read<String>('supplier_id'),
              'supplier_name': row.read<String>('supplier_name'),
              'supplier_phone': row.read<String?>('supplier_phone') ?? '-',
              'invoice_count': row.read<int>('invoice_count'),
              'total_purchases': row.read<double>('total_purchases'),
              'total_paid': row.read<double>('total_paid'),
              'total_remaining': row.read<double>('total_remaining'),
            },
          )
          .toList();

      // Calculate totals
      final totalPurchases = supplierData.fold<double>(
        0.0,
        (sum, item) => sum + (item['total_purchases'] as double),
      );
      final totalPaid = supplierData.fold<double>(
        0.0,
        (sum, item) => sum + (item['total_paid'] as double),
      );
      final totalRemaining = supplierData.fold<double>(
        0.0,
        (sum, item) => sum + (item['total_remaining'] as double),
      );
      final totalInvoices = supplierData.fold<int>(
        0,
        (sum, item) => sum + (item['invoice_count'] as int),
      );

      setState(() {
        _supplierData = supplierData;
        _totalPurchases = totalPurchases;
        _totalPaid = totalPaid;
        _totalRemaining = totalRemaining;
        _totalInvoices = totalInvoices;
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
        'المورد,إجمالي المشتريات,عدد الفواتير,المبلغ المدفوع,المبلغ المتبقي',
      );

      // Add data rows
      for (final item in _supplierData) {
        csvData.add(
          '${item['supplier_name']},${item['total_purchases']},${item['invoice_count']},${item['total_paid']},${item['total_remaining']}',
        );
      }

      // Add summary
      csvData.add('');
      csvData.add(
        'الإجمالي,$_totalPurchases,$_totalInvoices,$_totalPaid,$_totalRemaining',
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
        title: const Text('تقرير المشتريات حسب المورد'),
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
                    'إجمالي المشتريات',
                    '${_totalPurchases.toStringAsFixed(2)} ج.م',
                    Colors.blue,
                    Icons.shopping_cart,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildSummaryCard(
                    'المدفوع',
                    '${_totalPaid.toStringAsFixed(2)} ج.م',
                    Colors.green,
                    Icons.payment,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildSummaryCard(
                    'المتبقي',
                    '${_totalRemaining.toStringAsFixed(2)} ج.م',
                    Colors.orange,
                    Icons.account_balance,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildSummaryCard(
                    'عدد الفواتير',
                    '$_totalInvoices',
                    Colors.purple,
                    Icons.receipt_long,
                  ),
                ),
              ],
            ),
          ),

          // Data Table
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _supplierData.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inbox, size: 64, color: Colors.grey),
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
                          DataColumn(label: Text('المورد'), numeric: false),
                          DataColumn(label: Text('رقم الهاتف'), numeric: false),
                          DataColumn(
                            label: Text('عدد الفواتير'),
                            numeric: true,
                          ),
                          DataColumn(
                            label: Text('إجمالي المشتريات'),
                            numeric: true,
                          ),
                          DataColumn(label: Text('المدفوع'), numeric: true),
                          DataColumn(label: Text('المتبقي'), numeric: true),
                        ],
                        rows: _supplierData.map((supplier) {
                          return DataRow(
                            cells: [
                              DataCell(
                                Text(
                                  supplier['supplier_name'] as String,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              DataCell(
                                Text(supplier['supplier_phone'] as String),
                              ),
                              DataCell(Text('${supplier['invoice_count']}')),
                              DataCell(
                                Text(
                                  '${(supplier['total_purchases'] as double).toStringAsFixed(2)} ج.م',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              DataCell(
                                Text(
                                  '${(supplier['total_paid'] as double).toStringAsFixed(2)} ج.م',
                                  style: TextStyle(
                                    color: Colors.green,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              DataCell(
                                Text(
                                  '${(supplier['total_remaining'] as double).toStringAsFixed(2)} ج.م',
                                  style: TextStyle(
                                    color:
                                        (supplier['total_remaining']
                                                as double) >
                                            0
                                        ? Colors.red
                                        : Colors.green,
                                    fontWeight: FontWeight.bold,
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
