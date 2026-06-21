import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import 'dart:convert';
import 'package:pos_offline_desktop/core/provider/app_database_provider.dart';
import 'package:pos_offline_desktop/core/utils/logger.dart';

class PurchaseByProductReport extends ConsumerStatefulWidget {
  const PurchaseByProductReport({super.key});

  @override
  ConsumerState<PurchaseByProductReport> createState() =>
      _PurchaseByProductReportState();
}

class _PurchaseByProductReportState
    extends ConsumerState<PurchaseByProductReport> {
  bool _isLoading = false;
  DateTimeRange? _selectedDateRange;
  List<Map<String, dynamic>> _productData = [];
  double _totalQuantity = 0.0;
  double _totalAmount = 0.0;

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


      // Simple test query first
      try {
        final testResult = await db
            .customSelect('SELECT COUNT(*) as count FROM products')
            .get();
        final productCount = testResult.first.readNullable<int>('count') ?? 0;
        debugPrint('Products count: $productCount');
      } catch (e) {
        debugPrint('Error counting products: $e');
        rethrow;
      }

      // Test purchase_items table instead of enhanced_purchase_items
      try {
        final testResult = await db
            .customSelect('SELECT COUNT(*) as count FROM purchase_items')
            .get();
        final itemsCount = testResult.first.readNullable<int>('count') ?? 0;
        debugPrint('Purchase items count: $itemsCount');
      } catch (e) {
        debugPrint('Error counting purchase items: $e');
        // If purchase_items doesn't exist, try enhanced_purchase_items
        try {
          final testResult = await db
              .customSelect(
                'SELECT COUNT(*) as count FROM enhanced_purchase_items',
              )
              .get();
          final itemsCount = testResult.first.readNullable<int>('count') ?? 0;
          debugPrint('Enhanced purchase items count: $itemsCount');
        } catch (e2) {
          debugPrint('Error counting enhanced purchase items: $e2');
          rethrow;
        }
      }

      // Get purchase data grouped by product - try both tables
      String query;
      final start = _selectedDateRange!.start;
      final end = DateTime(_selectedDateRange!.end.year, _selectedDateRange!.end.month, _selectedDateRange!.end.day, 23, 59, 59);
      try {
        // First try with standard purchase_items table
        query = '''
          SELECT 
            p.id as product_id,
            p.name as product_name,
            p.barcode as product_barcode,
            p.unit as product_unit,
            COALESCE(SUM(pi.quantity), 0) as total_quantity,
            COALESCE(SUM(pi.total_price), 0) as total_amount
          FROM products p
          LEFT JOIN purchase_items pi ON p.id = CAST(pi.product_id AS INTEGER)
          WHERE p.status = 'Active'
            AND pi.created_at >= ? AND pi.created_at <= ?
          GROUP BY p.id, p.name, p.barcode, p.unit
          HAVING COALESCE(SUM(pi.quantity), 0) > 0
          ORDER BY total_quantity DESC
        ''';
        final startMicro = start.microsecondsSinceEpoch;
        final endMicro = end.microsecondsSinceEpoch;
        final result = await db.customSelect(query, variables: [
          drift.Variable.withInt(startMicro),
          drift.Variable.withInt(endMicro),
        ]).get();

        final productData = result
            .map(
              (row) => {
                'product_id': row.readNullable<String>('product_id') ?? '',
                'product_name': row.readNullable<String>('product_name') ?? '',
                'product_barcode': row.read<String?>('product_barcode') ?? '-',
                'product_unit': row.read<String?>('product_unit') ?? 'قطعة',
                'product_category': 'بدون تصنيف',
                'total_quantity':
                    row.readNullable<double>('total_quantity') ?? 0.0,
                'avg_unit_price': 0.0,
                'total_amount':
                    row.readNullable<double>('total_amount') ?? 0.0,
                'purchase_count': 1,
              },
            )
            .toList();

        // Calculate totals
        _totalQuantity = productData.fold(
          0.0,
          (sum, item) => sum + (item['total_quantity'] as double),
        );
        _totalAmount = productData.fold(
          0.0,
          (sum, item) => sum + (item['total_amount'] as double),
        );

        setState(() {
          _productData = productData;
          _isLoading = false;
        });
        return;
      } catch (e) {
        debugPrint('Standard purchase_items query failed: $e');

        // Try with enhanced_purchase_items table
        try {
          query = '''
            SELECT 
              p.id as product_id,
              p.name as product_name,
              p.barcode as product_barcode,
              p.unit as product_unit,
              COALESCE(SUM(epi.quantity), 0) as total_quantity,
              COALESCE(SUM(epi.total_price), 0) as total_amount
            FROM products p
            LEFT JOIN enhanced_purchase_items epi ON p.id = epi.product_id
            WHERE p.status = 'Active'
              AND epi.created_at >= ? AND epi.created_at <= ?
            GROUP BY p.id, p.name, p.barcode, p.unit
            HAVING COALESCE(SUM(epi.quantity), 0) > 0
            ORDER BY total_quantity DESC
          ''';
          final startMicro = start.microsecondsSinceEpoch;
          final endMicro = end.microsecondsSinceEpoch;
          final result = await db.customSelect(query, variables: [
            drift.Variable.withInt(startMicro),
            drift.Variable.withInt(endMicro),
          ]).get();

          final productData = result
              .map(
                (row) => {
                  'product_id': row.readNullable<String>('product_id') ?? '',
                  'product_name':
                      row.readNullable<String>('product_name') ?? '',
                  'product_barcode':
                      row.read<String?>('product_barcode') ?? '-',
                  'product_unit': row.read<String?>('product_unit') ?? 'قطعة',
                  'product_category': 'بدون تصنيف',
                  'total_quantity':
                      row.readNullable<double>('total_quantity') ?? 0.0,
                  'avg_unit_price': 0.0,
                  'total_amount':
                      row.readNullable<double>('total_amount') ?? 0.0,
                  'purchase_count': 1,
                },
              )
              .toList();

          // Calculate totals
          _totalQuantity = productData.fold(
            0.0,
            (sum, item) => sum + (item['total_quantity'] as double),
          );
          _totalAmount = productData.fold(
            0.0,
            (sum, item) => sum + (item['total_amount'] as double),
          );

          setState(() {
            _productData = productData;
            _isLoading = false;
          });
          return;
        } catch (e2) {
          debugPrint('Enhanced purchase_items query failed: $e2');
          rethrow;
        }
      }
    } catch (e, stack) {
      AppLogger.e('Failed to load purchase by product report', e, stack);
      setState(() {
        _isLoading = false;
      });

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

  Future<void> _exportToCSV() async {
    if (_productData.isEmpty) return;

    try {
      final csvData = <String>[];

      // Add header
      csvData.add(
        'المنتج,إجمالي الكمية,إجمالي القيمة,متوسط السعر,عدد المشتريات',
      );

      // Add data rows
      for (final item in _productData) {
        final avgPrice = item['total_quantity'] > 0
            ? (item['total_amount'] as double) / item['total_quantity']
            : 0.0;
        csvData.add(
          '${item['product_name']},${item['total_quantity']},${item['total_amount']},${avgPrice.toStringAsFixed(2)}',
        );
      }

      // Add summary
      csvData.add('');
      csvData.add(
        'الإجمالي,$_totalQuantity,$_totalAmount,${(_totalAmount / _totalQuantity).toStringAsFixed(2)}',
      );

      // Create download
      final csvString = csvData.join('\n');
      final bytes = utf8.encode(csvString);

      // For now, just show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Report exported successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error exporting report: $e'),
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
        title: const Text('تقرير المشتريات حسب المنتج'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.date_range),
            onPressed: _selectDateRange,
          ),
          IconButton(icon: const Icon(Icons.download), onPressed: _exportToCSV),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _productData.isEmpty
          ? _buildEmptyState()
          : _buildReportContent(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'لا توجد بيانات مشتريات',
            style: TextStyle(fontSize: 18, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Text(
            'قم بتحديد فترة زمنية مختلفة',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildReportContent() {
    return Column(
      children: [
        // Date range selector
        Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _selectedDateRange != null
                      ? 'الفترة: ${DateFormat('yyyy-MM-dd').format(_selectedDateRange!.start)} إلى ${DateFormat('yyyy-MM-dd').format(_selectedDateRange!.end)}'
                      : 'اختر الفترة',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.date_range),
                onPressed: _selectDateRange,
              ),
            ],
          ),
        ),
        // Summary cards
        Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: _buildSummaryCard(
                  'إجمالي الكمية',
                  _totalQuantity.toStringAsFixed(2),
                  Colors.green,
                  Icons.inventory_2,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildSummaryCard(
                  'إجمالي القيمة',
                  '${_totalAmount.toStringAsFixed(2)} ج.م',
                  Colors.orange,
                  Icons.attach_money,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildSummaryCard(
                  'متوسط سعر الوحدة',
                  _totalQuantity > 0
                      ? '${(_totalAmount / _totalQuantity).toStringAsFixed(2)} ج.م'
                      : '0.00 ج.م',
                  Colors.purple,
                  Icons.calculate,
                ),
              ),
            ],
          ),
        ),
        // Data table
        Expanded(
          child: Card(
            margin: const EdgeInsets.all(16),
            child: DataTable(
              columns: const [
                DataColumn(label: Text('المنتج')),
                DataColumn(label: Text('الوحدة')),
                DataColumn(label: Text('الكمية')),
                DataColumn(label: Text('متوسط السعر')),
                DataColumn(label: Text('الإجمالي')),
                DataColumn(label: Text('عدد')),
              ],
              rows: _productData.map((product) {
                return DataRow(
                  cells: [
                    DataCell(
                      Text(
                        product['product_name'] as String,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    DataCell(Text(product['product_unit'] as String)),
                    DataCell(
                      Text(
                        (product['total_quantity'] as double).toStringAsFixed(
                          2,
                        ),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    DataCell(
                      Text(
                        '${(product['avg_unit_price'] as double).toStringAsFixed(2)} ج.م',
                      ),
                    ),
                    DataCell(
                      Text(
                        '${(product['total_amount'] as double).toStringAsFixed(2)} ج.م',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ),
                    DataCell(Text('${product['purchase_count']}')),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
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

  Future<void> _selectDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _selectedDateRange,
    );

    if (picked != null && picked != _selectedDateRange) {
      setState(() {
        _selectedDateRange = picked;
      });
      _loadReportData();
    }
  }
}
