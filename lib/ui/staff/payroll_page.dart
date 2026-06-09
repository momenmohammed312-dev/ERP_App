import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/database/app_database.dart';
import '../../core/provider/app_database_provider.dart';
import '../../core/database/dao/staff_management_dao.dart';
import '../../core/utils/currency_helper.dart';
import '../../core/provider/auth_provider.dart';
import '../../services/staff_management_service.dart';

class PayrollPage extends ConsumerStatefulWidget {
  final Staff staff;

  const PayrollPage({super.key, required this.staff});

  @override
  ConsumerState<PayrollPage> createState() => _PayrollPageState();
}

class _PayrollPageState extends ConsumerState<PayrollPage> {
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
    final db = ref.read(appDatabaseProvider);
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('خطأ في تحميل سجل المرتبات: $e')));
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
    final periodOptions = ['2026-01', '2026-02', '2026-03', '2026-04', '2026-05', '2026-06'];
    final selectedPeriod = periodOptions[DateTime.now().month - 1];
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('احتساب المرتب'),
        content: Text('سيتم احتساب المرتب للموظف ${widget.staff.name} للفترة $selectedPeriod'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                final db = ref.read(appDatabaseProvider);
                final service = StaffManagementService(StaffManagementDao(db));
                final user = ref.read(authProvider);
                await service.calculatePayroll(user, widget.staff.staffId, selectedPeriod);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تم احتساب المرتب بنجاح'), backgroundColor: Colors.green),
                );
                _loadData();
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
                );
              }
            },
            child: const Text('احتساب'),
          ),
        ],
      ),
    );
  }
}
