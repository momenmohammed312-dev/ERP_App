import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/database/app_database.dart';
import '../../core/provider/app_database_provider.dart';
import '../../core/database/dao/staff_management_dao.dart';
import '../../core/utils/currency_helper.dart';
import '../../core/provider/auth_provider.dart';
import '../../services/staff_management_service.dart';
import 'services/staff_payroll_statement_generator.dart';

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
  bool _isCalculating = false;

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
      floatingActionButton: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (_payrollHistory.isNotEmpty) ...[
            FloatingActionButton.extended(
              heroTag: 'print_payroll',
              onPressed: () {
                final db = ref.read(appDatabaseProvider);
                StaffPayrollStatementGenerator.generateAndPrint(
                  context: context,
                  db: db,
                  staff: widget.staff,
                  payrollRecords: _payrollHistory,
                );
              },
              backgroundColor: Colors.teal,
              icon: const Icon(Icons.print, color: Colors.white),
              label: const Text('طباعة كشف المرتب', style: TextStyle(color: Colors.white)),
            ),
            const SizedBox(width: 12),
          ],
          FloatingActionButton(
            heroTag: 'calc_payroll',
            onPressed: _calculatePayroll,
            backgroundColor: Colors.blue[700],
            tooltip: 'احتساب مرتب',
            child: const Icon(Icons.calculate, color: Colors.white),
          ),
        ],
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
            if (payroll.deductions > 0) ...[
              _buildPayrollDetailRow(
                'استقطاعات وسلف',
                '- ${CurrencyHelper.formatCurrency(payroll.deductions)}',
                color: Colors.red,
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.red.withValues(alpha: 0.2))),
                child: Column(children: [
                  if (payroll.absentDays > 0) _buildPayrollDetailRow('غياب (${payroll.absentDays} يوم)', '- ${CurrencyHelper.formatCurrency(payroll.absentDays * (payroll.basicSalary / 30))}', color: Colors.red),
                  if (payroll.overtimeHours > 0) _buildPayrollDetailRow('تأخير/بدري (${payroll.overtimeHours.toStringAsFixed(1)} س)', '- ${CurrencyHelper.formatCurrency(payroll.deductions - payroll.advances)}', color: Colors.orange),
                  if (payroll.advances > 0) _buildPayrollDetailRow('سلف', '- ${CurrencyHelper.formatCurrency(payroll.advances)}', color: Colors.deepOrange),
                ]),
              ),
            ],
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
            if (payroll.status == 'calculated' || payroll.status == 'approved') ...[
              const Divider(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (payroll.status == 'calculated') ...[
                    OutlinedButton.icon(
                      onPressed: () => _deletePayroll(payroll),
                      icon: const Icon(Icons.delete, size: 18, color: Colors.red),
                      label: const Text('حذف', style: TextStyle(color: Colors.red)),
                      style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red)),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () => _approvePayroll(payroll),
                      icon: const Icon(Icons.verified, size: 18),
                      label: const Text('اعتماد'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                  if (payroll.status == 'approved')
                    ElevatedButton.icon(
                      onPressed: () => _markPaid(payroll),
                      icon: const Icon(Icons.payments, size: 18),
                      label: const Text('صرف'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                ],
              ),
            ],
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

  Future<void> _deletePayroll(Payroll payroll) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف المرتب'),
        content: Text('هل أنت متأكد من حذف مرتب ${payroll.payrollPeriod} قبل الاعتماد؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white), child: const Text('حذف')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final db = ref.read(appDatabaseProvider);
      await (db.delete(db.payrollTable)..where((t) => t.id.equals(payroll.id))).go();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حذف المرتب'), backgroundColor: Colors.green));
      _loadData();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _approvePayroll(Payroll payroll) async {
    final user = ref.read(authProvider);
    if (user == null) return;
    try {
      await _dao.approvePayroll(payroll.id, user.fullName);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم اعتماد المرتب'), backgroundColor: Colors.blue),
        );
      }
      _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _markPaid(Payroll payroll) async {
    final methods = ['cash', 'bank_transfer', 'check'];
    final selectedMethod = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('طريقة الصرف'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: methods.map((m) {
            String label;
            IconData icon;
            switch (m) {
              case 'cash':
                label = 'نقداً';
                icon = Icons.money;
                break;
              case 'bank_transfer':
                label = 'تحويل بنكي';
                icon = Icons.account_balance;
                break;
              case 'check':
                label = 'شيك';
                icon = Icons.receipt;
                break;
              default:
                label = m;
                icon = Icons.payment;
            }
            return ListTile(
              leading: Icon(icon),
              title: Text(label),
              onTap: () => Navigator.pop(ctx, m),
            );
          }).toList(),
        ),
      ),
    );

    if (selectedMethod == null) return;
    try {
      final db = ref.read(appDatabaseProvider);
      final service = StaffManagementService(StaffManagementDao(db), db);
      final user = ref.read(authProvider);
      await service.payPayroll(user, payroll.id, selectedMethod);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم صرف المرتب'), backgroundColor: Colors.green),
        );
      }
      _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _calculatePayroll() async {
    final now = DateTime.now();
    final picked = await showDatePicker(context: context, initialDate: now, firstDate: DateTime(2020), lastDate: DateTime(2030), helpText: 'اختر أي يوم في شهر المرتب');
    if (picked == null) return;
    final selectedPeriod = '${picked.year}-${picked.month.toString().padLeft(2, '0')}';
    final periodStart = DateTime(picked.year, picked.month, 1);
    final periodEnd = DateTime(picked.year, picked.month + 1, 0);
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('احتساب المرتب'),
        content: Text('سيتم احتساب المرتب للموظف ${widget.staff.name}\nللفترة $selectedPeriod\n(${periodStart.year}/${periodStart.month}/${periodStart.day} → ${periodEnd.year}/${periodEnd.month}/${periodEnd.day})'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('احتساب')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _isCalculating = true);
    try {
      final db = ref.read(appDatabaseProvider);
      final service = StaffManagementService(StaffManagementDao(db), db);
      final user = ref.read(authProvider);
      await service.calculatePayroll(user, widget.staff.staffId, selectedPeriod);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم احتساب المرتب بنجاح'), backgroundColor: Colors.green));
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isCalculating = false);
    }
  }
}
