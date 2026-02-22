import 'package:flutter/material.dart';
import '../../core/database/app_database.dart';
import '../../core/database/dao/staff_management_dao.dart';
import '../../core/database/database_singleton.dart';
import '../../core/utils/currency_helper.dart';
import 'package:intl/intl.dart';

class PayrollPage extends StatefulWidget {
  final Staff staff;

  const PayrollPage({super.key, required this.staff});

  @override
  State<PayrollPage> createState() => _PayrollPageState();
}

class _PayrollPageState extends State<PayrollPage> {
  late StaffManagementDao _dao;
  List<Payroll> _payrollHistory = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final db = await DatabaseSingleton.getInstance();
    _dao = StaffManagementDao(db);
    try {
      final history = await _dao.getPayrollByStaff(widget.staff.staffId);
      setState(() {
        _payrollHistory = history.reversed.toList();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ في تحميل سجل المرتبات: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _payrollHistory.isEmpty
          ? _buildEmptyState()
          : _buildPayrollList(),
      floatingActionButton: FloatingActionButton(
        onPressed: _calculatePayroll,
        backgroundColor: Colors.blue[700],
        tooltip: 'احتساب مرتب',
        child: const Icon(Icons.calculate, color: Colors.white),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.payment, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            'لا يوجد كشوف مرتبات لهذا الموظف',
            style: TextStyle(fontSize: 18, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildPayrollList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16.0),
      itemCount: _payrollHistory.length,
      itemBuilder: (context, index) {
        final payroll = _payrollHistory[index];
        return _buildPayrollCard(payroll);
      },
    );
  }

  Widget _buildPayrollCard(Payroll payroll) {
    final statusColor = _getStatusColor(payroll.status);

    return Card(
      margin: const EdgeInsets.only(bottom: 12.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  payroll.payrollPeriod,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Text(
                  CurrencyHelper.formatCurrency(payroll.netSalary),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    color: Colors.green[700],
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            _buildPayrollDetailRow(
              'الراتب الأساسي',
              CurrencyHelper.formatCurrency(payroll.basicSalary),
            ),
            if (payroll.overtimePay > 0)
              _buildPayrollDetailRow(
                'إضافي (${payroll.overtimeHours} ساعة)',
                CurrencyHelper.formatCurrency(payroll.overtimePay),
              ),
            if (payroll.allowances > 0)
              _buildPayrollDetailRow(
                'بدلات ومكافآت',
                CurrencyHelper.formatCurrency(payroll.allowances),
              ),
            if (payroll.deductions > 0)
              _buildPayrollDetailRow(
                'استقطاعات وسلف',
                '- ${CurrencyHelper.formatCurrency(payroll.deductions)}',
                color: Colors.red,
              ),
            const Divider(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'الحالة: ${_getStatusText(payroll.status)}',
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'تاريخ الاحتساب: ${DateFormat('yyyy/MM/dd').format(payroll.createdAt)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPayrollDetailRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[700])),
          Text(
            value,
            style: TextStyle(fontWeight: FontWeight.w500, color: color),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'calculated':
        return Colors.orange;
      case 'approved':
        return Colors.blue;
      case 'paid':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'calculated':
        return 'محسوب';
      case 'approved':
        return 'معتمد';
      case 'paid':
        return 'تم الصرف';
      default:
        return status;
    }
  }

  void _calculatePayroll() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('احتساب المرتب'),
        content: const Text(
          'سيتم احتساب المرتب بناءً على سجل الحضور والسلف لهذه الفترة.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }
}
