import 'package:flutter/material.dart';
import '../../core/database/app_database.dart';

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
          final openingBalance = (data['current_balance'] as double?) ?? 0.0;
          final totalPurchases = (data['total_purchases'] as double?) ?? 0.0;
          final totalPayments = (data['total_payments'] as double?) ?? 0.0;
          final outstanding = totalPurchases - totalPayments + openingBalance;
          return {
            'id': data['id'],
            'name': data['name'],
            'phone': data['phone'],
            'current_balance': openingBalance,
            'invoice_count': data['invoice_count'] as int? ?? 0,
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
                Text(
                  supplier['phone'] ?? 'لا يوجد رقم هاتف',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 4),
                Text(
                  'المستحق: ${supplier['outstanding'].toStringAsFixed(2)} ج.م',
                  style: TextStyle(
                    fontSize: 12,
                    color: supplier['outstanding'] < 0
                        ? Colors.green
                        : Colors.red,
                  ),
                ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.phone),
                  onPressed: () => _callSupplier(supplier['phone']),
                  tooltip: 'اتصال',
                  color: Colors.blue,
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.receipt_long),
                  onPressed: () => _viewSupplierDetails(supplier),
                  tooltip: 'عرض التفاصيل',
                  color: Colors.green,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _callSupplier(String? phone) {
    if (phone != null && phone.isNotEmpty) {
      debugPrint('Calling supplier: $phone');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('جاري الاتصال بـ $phone'),
          backgroundColor: Colors.blue,
        ),
      );
    }
  }

  void _viewSupplierDetails(Map<String, dynamic> supplier) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('تفاصيل المورد'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailRow('اسم المورد', supplier['name']),
              _buildDetailRow('رقم الهاتف', supplier['phone'] ?? 'غير محدد'),
              _buildDetailRow(
                'الرصيد',
                supplier['current_balance'].toStringAsFixed(2),
              ),
              _buildDetailRow(
                'إجمالي المشتريات',
                '${supplier['total_purchases'].toStringAsFixed(2)} ج.م',
              ),
              _buildDetailRow(
                'إجمالي المدفوعات',
                '${supplier['total_payments'].toStringAsFixed(2)} ج.م',
              ),
              _buildDetailRow(
                'المستحق المتبقي',
                '${supplier['outstanding'].toStringAsFixed(2)} ج.م',
              ),
              _buildDetailRow('عدد الفواتير', '${supplier['invoice_count']}'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('موافق'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade800),
            ),
          ),
        ],
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
