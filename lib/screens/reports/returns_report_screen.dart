import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/models/user_model.dart';
import 'package:pos_offline_desktop/core/services/export_service.dart';
import 'package:pos_offline_desktop/widgets/permission_guard.dart';

class ReturnsReportScreen extends StatefulWidget {
  final AppDatabase database;

  const ReturnsReportScreen({super.key, required this.database});

  @override
  State<ReturnsReportScreen> createState() => _ReturnsReportScreenState();
}

class _ReturnsReportScreenState extends State<ReturnsReportScreen> {
  List<SalesReturn> _returns = [];
  Map<int, List<SalesReturnItem>> _returnItems = {};
  bool _isLoading = true;
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();
  final ExportService _exportService = ExportService();

  @override
  void initState() {
    super.initState();
    _loadReturns();
  }

  Future<void> _loadReturns() async {
    setState(() => _isLoading = true);
    try {
      final returns = await widget.database.salesReturnsDao.getReturnsByDateRange(
        _startDate,
        _endDate,
      );
      final items = <int, List<SalesReturnItem>>{};
      for (final ret in returns) {
        items[ret.id] = await widget.database.salesReturnsDao.getItemsForReturn(ret.id);
      }
      setState(() {
        _returns = returns;
        _returnItems = items;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Colors.teal,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      _loadReturns();
    }
  }

  double get _totalReturns =>
      _returns.fold<double>(0.0, (sum, r) => sum + r.totalAmount);

  int get _totalItems =>
      _returnItems.values.fold<int>(0, (sum, items) => sum + items.length);

  Future<void> _exportToPDF() async {
    if (_returns.isEmpty) return;
    await _exportService.exportToPDF(
      title: 'تقرير مرتجعات المبيعات',
      data: _returns.map((r) => {
        'رقم المرتجع': r.returnNumber,
        'العميل': r.customerName,
        'التاريخ': DateFormat('yyyy/MM/dd').format(r.returnDate),
        'المبلغ': r.totalAmount.toStringAsFixed(2),
        'السبب': _getReasonText(r.returnReason),
        'الحالة': r.status,
      }).toList(),
      headers: ['رقم المرتجع', 'العميل', 'التاريخ', 'المبلغ', 'السبب', 'الحالة'],
      columns: ['رقم المرتجع', 'العميل', 'التاريخ', 'المبلغ', 'السبب', 'الحالة'],
      fileName: 'returns_report_${DateFormat('yyyyMMdd').format(DateTime.now())}',
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تصدير التقرير بنجاح')),
      );
    }
  }

  String _getReasonText(String reason) {
    switch (reason) {
      case 'defective': return 'تالف';
      case 'wrong_item': return 'صنف خطأ';
      case 'customer_request': return 'طلب عميل';
      case 'other': return 'أخرى';
      default: return reason;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('تقرير مرتجعات المبيعات'),
        actions: [
          IconButton(
            icon: const Icon(Icons.date_range),
            onPressed: _pickDateRange,
            tooltip: 'اختيار فترة',
          ),
          PermissionGuard(
            permission: Permission.exportReports,
            showUpgradePrompt: false,
            child: IconButton(
              icon: const Icon(Icons.picture_as_pdf),
              onPressed: _exportToPDF,
              tooltip: 'تصدير PDF',
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadReturns,
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
            child: Row(
              children: [
                Expanded(child: _buildStatCard('إجمالي المرتجعات', '${_totalReturns.toStringAsFixed(2)} ج.م', Colors.teal)),
                const SizedBox(width: 12),
                Expanded(child: _buildStatCard('عدد المرتجعات', '${_returns.length}', Colors.blue)),
                const SizedBox(width: 12),
                Expanded(child: _buildStatCard('إجمالي الأصناف', '$_totalItems', Colors.orange)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${DateFormat('yyyy/MM/dd').format(_startDate)} - ${DateFormat('yyyy/MM/dd').format(_endDate)}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _returns.isEmpty
                    ? const Center(child: Text('لا توجد مرتجعات في هذه الفترة'))
                    : ListView.builder(
                        itemCount: _returns.length,
                        itemBuilder: (context, index) {
                          final ret = _returns[index];
                          final items = _returnItems[ret.id] ?? [];
                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                            child: ExpansionTile(
                              leading: CircleAvatar(
                                backgroundColor: Colors.teal.withValues(alpha: 0.2),
                                child: const Icon(Icons.replay, color: Colors.teal),
                              ),
                              title: Text(ret.returnNumber, style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text('${ret.customerName} • ${DateFormat('yyyy/MM/dd').format(ret.returnDate)}'),
                              trailing: Text('${ret.totalAmount.toStringAsFixed(2)} ج.م',
                                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal)),
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (ret.notes != null && ret.notes!.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(bottom: 8),
                                          child: Text('ملاحظات: ${ret.notes}', style: const TextStyle(color: Colors.grey)),
                                        ),
                                      ...items.map((item) => ListTile(
                                        dense: true,
                                        title: Text(item.productName),
                                        trailing: Text('${item.quantity} × ${item.unitPrice.toStringAsFixed(2)} = ${item.totalPrice.toStringAsFixed(2)} ج.م'),
                                      )),
                                      const Divider(),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(title, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}
