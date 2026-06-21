import 'package:flutter/material.dart';
import 'package:drift/drift.dart' as drift;
import 'package:intl/intl.dart';
import '../../core/database/app_database.dart';
import '../../core/utils/app_utils.dart';

class SupplierReportScreen extends StatefulWidget {
  final AppDatabase database;

  const SupplierReportScreen({super.key, required this.database});

  @override
  State<SupplierReportScreen> createState() => _SupplierReportScreenState();
}

class _SupplierReportScreenState extends State<SupplierReportScreen> {
  List<Map<String, dynamic>> _supplierData = [];
  bool _isLoading = true;
  String _selectedPeriod = 'all'; // 'all', 'today', 'week', 'month'

  @override
  void initState() {
    super.initState();
    _loadSupplierData();
  }

  Future<void> _loadSupplierData() async {
    setState(() => _isLoading = true);
    try {
      // Get supplier summary data. This is a simplified query for demonstration.
      final suppliers = widget.database.customSelect('''
        SELECT 
          s.id, s.name, s.phone,
          COALESCE(s.opening_balance, 0) as current_balance,
          COUNT(CASE WHEN p.is_deleted = 0 OR p.is_deleted IS NULL THEN p.id END) as invoice_count,
          COALESCE(SUM(CASE WHEN p.is_deleted = 0 OR p.is_deleted IS NULL THEN p.total_amount ELSE 0 END), 0) as total_purchases,
          COALESCE(SUM(CASE WHEN p.is_deleted = 0 OR p.is_deleted IS NULL THEN p.paid_amount ELSE 0 END), 0) as total_payments
        FROM suppliers s
        LEFT JOIN purchases p ON s.id = p.supplier_id
        GROUP BY s.id
        ORDER BY s.name
        ''');

      final supplierList = await suppliers.get();
      setState(() {
        _supplierData = supplierList.map((row) {
          final data = row.data;
          final openingBalance =
              (data['current_balance'] as num?)?.toDouble() ?? 0.0;
          final totalPurchases =
              (data['total_purchases'] as num?)?.toDouble() ?? 0.0;
          final totalPayments =
              (data['total_payments'] as num?)?.toDouble() ?? 0.0;
          final outstanding = totalPurchases - totalPayments + openingBalance;
          return {
            'id': data['id'],
            'name': data['name'],
            'phone': data['phone'],
            'current_balance': openingBalance,
            'invoice_count': (data['invoice_count'] as num?)?.toInt() ?? 0,
            'total_purchases': totalPurchases,
            'total_payments': totalPayments,
            'outstanding': outstanding,
          };
        }).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      debugPrint('Error loading supplier data: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في تحميل بيانات الموردين: ${e.toString().contains('no such column') ? 'يرجى تحديث قاعدة البيانات' : e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  double get _totalOutstanding =>
      _supplierData.fold(0.0, (sum, s) => sum + (s['outstanding'] as double));
  double get _totalPurchases => _supplierData.fold(
    0.0,
    (sum, s) => sum + (s['total_purchases'] as double),
  );
  double get _totalPayments => _supplierData.fold(
    0.0,
    (sum, s) => sum + (s['total_payments'] as double),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('تقرير الموردين'),
        backgroundColor: Colors.blue.shade800,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadSupplierData,
            tooltip: 'تحديث',
          ),
          IconButton(
            icon: Icon(Icons.download),
            onPressed: _exportReport,
            tooltip: 'تصدير',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Period Selector
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        const Text(
                          'الفترة:',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 16),
                        DropdownButton<String>(
                          value: _selectedPeriod,
                          items: const [
                            DropdownMenuItem(
                              value: 'all',
                              child: Text('الكل الوقت'),
                            ),
                            DropdownMenuItem(
                              value: 'today',
                              child: Text('اليوم فقط'),
                            ),
                            DropdownMenuItem(
                              value: 'week',
                              child: Text('هذا الأسبوع'),
                            ),
                            DropdownMenuItem(
                              value: 'month',
                              child: Text('هذا الشهر'),
                            ),
                          ],
                          onChanged: (value) {
                            setState(() => _selectedPeriod = value!);
                            _loadSupplierData();
                          },
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Summary Cards
                Row(
                  children: [
                    _buildSummaryCard(
                      'إجمالي المستحقات',
                      '${_totalOutstanding.toStringAsFixed(2)} ج.م',
                      Icons.account_balance,
                      Colors.red,
                    ),
                    const SizedBox(width: 16),
                    _buildSummaryCard(
                      'إجمالي المشتريات',
                      '${_totalPurchases.toStringAsFixed(2)} ج.م',
                      Icons.shopping_cart,
                      Colors.blue,
                    ),
                    const SizedBox(width: 16),
                    _buildSummaryCard(
                      'إجمالي المدفوعات',
                      '${_totalPayments.toStringAsFixed(2)} ج.م',
                      Icons.payment,
                      Colors.green,
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Suppliers List
                Expanded(
                  child: Card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Row(
                            children: [
                              Icon(
                                Icons.business,
                                color: Colors.blue.shade700,
                                size: 24,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'قائمة الموردين',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey.shade800,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '${_supplierData.length} مورد',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Divider(),
                        Expanded(
                          child: _supplierData.isEmpty
                              ? _buildEmptyState()
                              : _buildSuppliersList(),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _exportReport,
        tooltip: 'تصدير',
        child: const Icon(Icons.download),
      ),
    );
  }

  Widget _buildSummaryCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Expanded(
      child: Container(
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
                Icon(icon, color: color, size: 24),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    color: color.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.business,
            size: 80,
            color: Colors.grey.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 24),
          Text(
            'لا يوجد موردين',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'اضغط "إضافة مورد" لبدء إدارة الموردين',
            style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildSuppliersList() {
    return ListView.builder(
      itemCount: _supplierData.length,
      itemBuilder: (context, index) {
        final supplier = _supplierData[index];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
          child: InkWell(
            // FIX: tap anywhere on row to open transactions table
            onTap: () => _viewSupplierTransactions(supplier),
            borderRadius: BorderRadius.circular(8),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.blue.shade100,
                child: Icon(
                  Icons.business,
                  color: Colors.blue.shade700,
                  size: 20,
                ),
              ),
              title: Text(
                supplier['name'],
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (supplier['phone'] != null &&
                      (supplier['phone'] as String).isNotEmpty)
                    Text(
                      supplier['phone'],
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    'المستحق: ${(supplier['outstanding'] as double).toStringAsFixed(2)} ج.م',
                    style: TextStyle(
                      fontSize: 12,
                      color: (supplier['outstanding'] as double) <= 0
                          ? Colors.green
                          : Colors.red,
                    ),
                  ),
                ],
              ),
              // FIX: single icon to view transactions — removed phone/call button
              trailing: Icon(Icons.chevron_left, color: Colors.grey.shade400),
            ),
          ),
        );
      },
    );
  }

  /// FIX: replaced _callSupplier + simple AlertDialog with full transaction table
  Future<void> _viewSupplierTransactions(Map<String, dynamic> supplier) async {
    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final rows = await widget.database
          .customSelect(
            '''
        SELECT 
          p.id,
          p.created_at,
          p.invoice_number,
          p.total_amount,
          p.paid_amount,
          p.payment_method,
          p.notes
        FROM purchases p
        WHERE p.supplier_id = ?
          AND (p.is_deleted = 0 OR p.is_deleted IS NULL)
        ORDER BY p.created_at DESC
      ''',
            variables: [drift.Variable.withString(supplier['id'].toString())],
          )
          .get();

      if (!mounted) return;
      Navigator.of(context).pop(); // close loading

      final purchases = rows.map((r) => r.data).toList();

      showDialog(
        context: context,
        builder: (context) => Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade800,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(8),
                    topRight: Radius.circular(8),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.business, color: Colors.white),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'معاملات المورد: ${supplier['name']}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              // Summary row
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    _summaryChip(
                      'إجمالي المشتريات',
                      '${(supplier['total_purchases'] as double).toStringAsFixed(2)} ج.م',
                      Colors.blue,
                    ),
                    const SizedBox(width: 8),
                    _summaryChip(
                      'المدفوع',
                      '${(supplier['total_payments'] as double).toStringAsFixed(2)} ج.م',
                      Colors.green,
                    ),
                    const SizedBox(width: 8),
                    _summaryChip(
                      'المستحق',
                      '${(supplier['outstanding'] as double).toStringAsFixed(2)} ج.م',
                      (supplier['outstanding'] as double) > 0
                          ? Colors.red
                          : Colors.green,
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Transactions table
              purchases.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(32),
                      child: Column(
                        children: [
                          Icon(
                            Icons.inbox_outlined,
                            size: 48,
                            color: Colors.grey,
                          ),
                          SizedBox(height: 12),
                          Text(
                            'لا توجد معاملات لهذا المورد',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                  : Flexible(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.vertical,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            columnSpacing: 16,
                            headingRowColor: WidgetStateProperty.all(
                              Colors.blue.withValues(alpha: 0.08),
                            ),
                            columns: const [
                              DataColumn(label: Text('التاريخ')),
                              DataColumn(label: Text('رقم الفاتورة')),
                              DataColumn(label: Text('المبلغ')),
                              DataColumn(label: Text('المدفوع')),
                              DataColumn(label: Text('المتبقي')),
                              DataColumn(label: Text('النوع')),
                            ],
                            rows: purchases.map((p) {
                              final total =
                                  (p['total_amount'] as num?)?.toDouble() ??
                                  0.0;
                              final paid =
                                  (p['paid_amount'] as num?)?.toDouble() ?? 0.0;
                              final remaining = total - paid;
              final isCredit =
                  (p['payment_method'] as String?)?.toLowerCase() == 'credit';
                              DateTime? date;
                              try {
                                date = parseDate(p['created_at']);
                              } catch (e) {
                                print('Error parsing date: $e');
                              }
                              return DataRow(
                                cells: [
                                  DataCell(
                                    Text(
                                      date != null
                                          ? DateFormat(
                                              'yyyy-MM-dd',
                                            ).format(date)
                                          : '-',
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      p['invoice_number']?.toString() ?? '-',
                                    ),
                                  ),
                                  DataCell(
                                    Text('${total.toStringAsFixed(2)} ج.م'),
                                  ),
                                  DataCell(
                                    Text(
                                      '${paid.toStringAsFixed(2)} ج.م',
                                      style: const TextStyle(
                                        color: Colors.green,
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Text(
                                      '${remaining.toStringAsFixed(2)} ج.م',
                                      style: TextStyle(
                                        color: remaining > 0
                                            ? Colors.red
                                            : Colors.green,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  DataCell(
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isCredit
                                            ? Colors.orange.withValues(
                                                alpha: 0.15,
                                              )
                                            : Colors.green.withValues(
                                                alpha: 0.15,
                                              ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        isCredit ? 'آجل' : 'كاش',
                                        style: TextStyle(
                                          color: isCredit
                                              ? Colors.orange.shade700
                                              : Colors.green.shade700,
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
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop(); // close loading
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ في تحميل المعاملات: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _summaryChip(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }



  Future<void> _exportReport() async {
    debugPrint('Exporting supplier report...');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('سيتم تصدير التقرير'),
        backgroundColor: Colors.green,
      ),
    );
  }
}
