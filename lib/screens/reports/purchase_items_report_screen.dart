import 'package:flutter/material.dart';
import '../../core/database/app_database.dart';

class PurchaseItemsReportScreen extends StatefulWidget {
  final AppDatabase database;

  const PurchaseItemsReportScreen({super.key, required this.database});

  @override
  State<PurchaseItemsReportScreen> createState() =>
      _PurchaseItemsReportScreenState();
}

class _PurchaseItemsReportScreenState extends State<PurchaseItemsReportScreen> {
  List<Map<String, dynamic>> _purchaseData = [];
  bool _isLoading = true;
  String _selectedPeriod = 'all';

  @override
  void initState() {
    super.initState();
    _loadPurchaseData();
  }

  Future<void> _loadPurchaseData() async {
    setState(() => _isLoading = true);

    try {
      // Get purchase items summary
      final purchaseItems = await (widget.database.customSelect('''
        SELECT 
          p.product_name,
          SUM(pi.quantity) as total_quantity,
          SUM(pi.total_cost) as total_cost,
          COUNT(DISTINCT p.id) as distinct_products
        FROM supply_invoice_items pi
        LEFT JOIN supply_invoices si ON pi.supply_invoice_id = si.id
        LEFT JOIN products p ON pi.product_id = p.id
        WHERE si.status = "completed"
        GROUP BY p.product_name
        ORDER BY total_cost DESC
        ''')).get();

      setState(() {
        _purchaseData = purchaseItems.map((row) => row.data).toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      debugPrint('Error loading purchase items data: $e');
    }
  }

  double _totalCost() {
    return _purchaseData.fold(
      0.0,
      (sum, item) => sum + (item['total_cost'] as double? ?? 0.0),
    );
  }

  int _totalQuantity() {
    return _purchaseData.fold(
      0,
      (sum, item) => sum + (item['total_quantity'] as int? ?? 0),
    );
  }

  int _distinctProducts() {
    return _purchaseData.fold(
      0,
      (sum, item) => sum + (item['distinct_products'] as int? ?? 0),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('تقرير المشتريات'),
        backgroundColor: Colors.blue.shade800,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadPurchaseData,
            tooltip: 'تحديث',
          ),
          IconButton(
            icon: const Icon(Icons.download),
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
                            _loadPurchaseData();
                          },
                        ),
                      ],
                    ),
                  ),
                ),

                // Summary Cards
                Row(
                  children: [
                    _buildSummaryCard(
                      'إجمالي التكلفة',
                      '${_totalCost().toStringAsFixed(2)} ج.م',
                      Icons.attach_money,
                      Colors.red,
                    ),
                    const SizedBox(width: 16),
                    _buildSummaryCard(
                      'إجمالي الكمية',
                      '$_totalQuantity() وحدة',
                      Icons.inventory,
                      Colors.blue,
                    ),
                    const SizedBox(width: 16),
                    _buildSummaryCard(
                      'عدد المنتجات',
                      '$_distinctProducts() منتج',
                      Icons.category,
                      Colors.green,
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Items List
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
                                Icons.shopping_cart,
                                color: Colors.blue.shade800,
                                size: 24,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'قائمة المشتريات',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey.shade800,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '${_purchaseData.length} منتج',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Divider(),
                        Expanded(
                          child: _purchaseData.isEmpty
                              ? _buildEmptyState()
                              : _buildPurchaseItemsList(),
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
                    color: color.withValues(alpha: 0.8),
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
                color: color.withValues(alpha: 0.9),
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
            Icons.shopping_cart_outlined,
            size: 80,
            color: Colors.grey.shade600,
          ),
          const SizedBox(height: 24),
          Text(
            'لا توجد مشتريات',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'اضغط "إنشاء فاتورة شراء" لبدء تسجيل المشتريات',
            style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildPurchaseItemsList() {
    return ListView.builder(
      itemCount: _purchaseData.length,
      itemBuilder: (context, index) {
        final item = _purchaseData[index];
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.blue.shade100,
              child: Icon(
                Icons.inventory_2,
                color: Colors.blue.shade700,
                size: 20,
              ),
            ),
            title: Text(
              item['product_name'],
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'الوحدة: ${item['unit'] ?? 'غير محدد'}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 4),
                Text(
                  'الكمية: ${item['total_quantity']}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 4),
                Text(
                  'سعر الوحدة: ${item['unit_price'].toStringAsFixed(2)} ج.م',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 4),
                Text(
                  'التكلفة الإجمالية: ${item['total_cost'].toStringAsFixed(2)} ج.م',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'أول شراء: ${item['first_purchase']}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
            trailing: Text(
              '${item['total_cost'].toStringAsFixed(2)} ج.م',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.red,
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _exportReport() async {
    // In a real app, this would generate and export a CSV/PDF report
    debugPrint('Exporting purchase items report...');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('سيتم تصدير التقرير'),
        backgroundColor: Colors.green,
      ),
    );
  }
}
