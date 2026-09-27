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
                  _formatPeriod(payroll.payrollPeriod),
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
                'بدلات',
                CurrencyHelper.formatCurrency(payroll.allowances),
              ),
            if (payroll.rewardsTotal > 0)
              _buildPayrollDetailRow(
                'مكافآت',
                CurrencyHelper.formatCurrency(payroll.rewardsTotal),
              ),
            // Breakdown only — these three rows are ALREADY inside
            // payroll.deductions, so they must never be summed again on top
            // of the total row below.
            if (payroll.lateDeduction > 0)
              _buildPayrollDetailRow(
                'منها: غرامة تأخير (${payroll.lateDays} يوم)',
                '- ${CurrencyHelper.formatCurrency(payroll.lateDeduction)}',
                color: Colors.red,
                subtitle: true,
              ),
            if (_absencePart(payroll) > 0)
              _buildPayrollDetailRow(
                'منها: خصم الغياب (${payroll.absentDays} يوم)',
                '- ${CurrencyHelper.formatCurrency(_absencePart(payroll))}',
                color: Colors.red,
                subtitle: true,
              ),
            if (_permissionPart(payroll) > 0)
              _buildPayrollDetailRow(
                _permissionHours(payroll) > 0
                    ? 'منها: خصم إذن / انصراف مبكر (${_permissionHours(payroll).toStringAsFixed(1)} ساعة)'
                    : 'منها: خصم إذن / انصراف مبكر',
                '- ${CurrencyHelper.formatCurrency(_permissionPart(payroll))}',
                color: Colors.red,
                subtitle: true,
              ),
            if (payroll.penaltiesTotal > 0)
              _buildPayrollDetailRow(
                'منها: جزاءات',
                '- ${CurrencyHelper.formatCurrency(payroll.penaltiesTotal)}',
                color: Colors.red,
                subtitle: true,
              ),
            if (payroll.advances > 0)
              _buildPayrollDetailRow(
                'منها: سلف',
                '- ${CurrencyHelper.formatCurrency(payroll.advances)}',
                color: Colors.red,
                subtitle: true,
              ),
            if (payroll.deductions > 0)
              _buildPayrollDetailRow(
                'إجمالي الخصومات',
                '- ${CurrencyHelper.formatCurrency(payroll.deductions)}',
                color: Colors.red,
                bold: true,
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
            if (payroll.status == 'calculated' || payroll.status == 'approved') ...[
              const Divider(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (payroll.status == 'calculated')
                    ElevatedButton.icon(
                      onPressed: () => _approvePayroll(payroll),
                      icon: const Icon(Icons.verified, size: 18),
                      label: const Text('اعتماد'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                    ),
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
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () => _deletePayroll(payroll),
                    icon: const Icon(
                      Icons.delete_outline,
                      size: 18,
                      color: Colors.red,
                    ),
                    label: const Text(
                      'مسح',
                      style: TextStyle(color: Colors.red),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.red),
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

  /// Permission / early-leave deduction, read from the FIRST-CLASS payroll
  /// column written by `StaffManagementService.calculatePayroll`.
  ///
  /// v72: this used to be reverse-engineered from `Payroll.otherDeductions`,
  /// which was a legacy catch-all that never had a column of its own. The
  /// service no longer writes permission into it, so the old read returned 0
  /// and [Payroll.otherDeductions] went stale for every slip.
  ///
  /// Falls back to `otherDeductions` ONLY for slips calculated before the v72
  /// migration, where the first-class columns are still 0. A current slip has
  /// `permissionDeduction` populated, so the fallback cannot mask a real value.
  double _permissionPart(Payroll payroll) {
    if (payroll.permissionDeduction > 0) return payroll.permissionDeduction;
    return payroll.otherDeductions > 0 ? payroll.otherDeductions : 0.0;
  }

  /// Permission hours, read from the first-class column.
  double _permissionHours(Payroll payroll) =>
      payroll.permissionHours > 0 ? payroll.permissionHours : 0.0;

  /// Absence share of the aggregate deductions.
  ///
  /// v72: the permission share is now subtracted from its own first-class
  /// column instead of being left to fall into this residual. Without that,
  /// `_absencePart` returned absence + permission and the slip showed the
  /// permission money on the absence line.
  double _absencePart(Payroll payroll) {
    final part = payroll.deductions -
        payroll.advances -
        payroll.penaltiesTotal -
        payroll.lateDeduction -
        _permissionPart(payroll);
    return part > 0 ? part : 0.0;
  }

  /// [subtitle] = صف تفصيل محتسب ضمن [total] — بيتعرض بشكل باهت مع مسافة
  /// بادئة عشان ما يتجمعش مع الصف الإجمالي مرتين. [bold] = صف الإجمالي.
  Widget _buildPayrollDetailRow(
    String label,
    String value, {
    Color? color,
    bool subtitle = false,
    bool bold = false,
  }) {
    final weight = bold ? FontWeight.bold : FontWeight.w500;
    return Padding(
      padding: EdgeInsets.fromLTRB(subtitle ? 16 : 0, 4.0, 0, 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: subtitle ? Colors.grey[500] : Colors.grey[700],
              fontSize: subtitle ? 13 : null,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: weight,
              color: color,
              fontSize: subtitle ? 13 : null,
            ),
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

  Future<void> _deletePayroll(Payroll payroll) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('مسح المرتب؟'),
        content: Text(
          'سيتم مسح مرتب ${_formatPeriod(payroll.payrollPeriod)} نهائياً '
          'ويمكنك إعادة احتسابه من جديد.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text(
              'مسح',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final db = ref.read(appDatabaseProvider);
      final service = StaffManagementService(StaffManagementDao(db), db);
      final user = ref.read(authProvider);
      await service.deletePayroll(user, payroll.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم مسح المرتب'),
          backgroundColor: Colors.green,
        ),
      );
      _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  String _formatPeriod(String period) {
    final parts = period.split('-');
    if (parts.length >= 3 && parts[2].startsWith('W')) {
      final weekNum = parts[2].substring(1);
      return 'أسبوع $weekNum (شهر ${parts[1]} / ${parts[0]})';
    }
    if (parts.length >= 2) {
      return 'شهر ${parts[1]} / ${parts[0]}';
    }
    return period;
  }

  void _calculatePayroll() {
    final now = DateTime.now();
    final currentWeek = ref
        .read(staffManagementServiceProvider)
        .weekPeriodForDate(now);
    String payrollType = 'monthly';
    int selectedYear = currentWeek.year;
    int selectedMonth = currentWeek.month;
    int selectedWeek = currentWeek.week;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final periodCode = payrollType == 'monthly'
              ? '$selectedYear-${selectedMonth.toString().padLeft(2, '0')}'
              : '$selectedYear-${selectedMonth.toString().padLeft(2, '0')}-W$selectedWeek';

          // Valid weeks of the chosen month (Thursday must fall in it).
          // A week runs Saturday → Thursday and may start in the previous
          // month — the range below always shows the real dates.
          List<int> validWeeks() {
            final svc = ref.read(staffManagementServiceProvider);
            final out = <int>[];
            for (var w = 1; w <= 5; w++) {
              try {
                svc.weekBounds(selectedYear, selectedMonth, w);
                out.add(w);
              } catch (_) {}
            }
            return out;
          }

          String rangeText() {
            final fmt = DateFormat('yyyy/MM/dd');
            if (payrollType == 'monthly') {
              final start = DateTime(selectedYear, selectedMonth, 1);
              final end = DateTime(selectedYear, selectedMonth + 1, 0);
              return '${fmt.format(start)} → ${fmt.format(end)}';
            }
            try {
              final svc = ref.read(staffManagementServiceProvider);
              final b = svc.weekBounds(
                selectedYear,
                selectedMonth,
                selectedWeek,
              );
              return '${fmt.format(b.$1)} → ${fmt.format(b.$2)} (سبت → خميس)';
            } catch (_) {
              return 'أسبوع غير موجود في هذا الشهر';
            }
          }

          void clampWeek() {
            final valid = validWeeks();
            if (valid.isNotEmpty && !valid.contains(selectedWeek)) {
              selectedWeek = valid.last;
            }
          }

          return AlertDialog(
            title: const Text('احتساب المرتب'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'الموظف: ${widget.staff.name}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  const Text('دورة المرتب:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: const Center(child: Text('شهري')),
                          selected: payrollType == 'monthly',
                          onSelected: (val) {
                            if (val) setDialogState(() => payrollType = 'monthly');
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ChoiceChip(
                          label: const Center(child: Text('أسبوعي')),
                          selected: payrollType == 'weekly',
                          onSelected: (val) {
                            if (val) setDialogState(() => payrollType = 'weekly');
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: selectedYear,
                          decoration: const InputDecoration(
                            labelText: 'السنة',
                            border: OutlineInputBorder(),
                          ),
                          items: [now.year - 1, now.year, now.year + 1]
                              .map((y) => DropdownMenuItem(value: y, child: Text('$y')))
                              .toList(),
                          onChanged: (v) {
                            if (v == null) return;
                            setDialogState(() {
                              selectedYear = v;
                              clampWeek();
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: selectedMonth,
                          decoration: const InputDecoration(
                            labelText: 'الشهر',
                            border: OutlineInputBorder(),
                          ),
                          items: List.generate(12, (i) => i + 1)
                              .map((m) => DropdownMenuItem(value: m, child: Text('شهر $m')))
                              .toList(),
                          onChanged: (v) {
                            if (v == null) return;
                            setDialogState(() {
                              selectedMonth = v;
                              clampWeek();
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  if (payrollType == 'weekly') ...[
                    const SizedBox(height: 12),
                    Builder(builder: (context) {
                      final valid = validWeeks();
                      if (!valid.contains(selectedWeek) && valid.isNotEmpty) {
                        selectedWeek = valid.last;
                      }
                      final svc = ref.read(staffManagementServiceProvider);
                      final fmt = DateFormat('dd/MM');
                      return DropdownButtonFormField<int>(
                        value: valid.contains(selectedWeek)
                            ? selectedWeek
                            : (valid.isEmpty ? null : valid.last),
                        decoration: const InputDecoration(
                          labelText: 'الأسبوع (سبت → خميس)',
                          border: OutlineInputBorder(),
                        ),
                        items: valid.map((w) {
                          String range = '';
                          try {
                            final b = svc.weekBounds(
                              selectedYear,
                              selectedMonth,
                              w,
                            );
                            range =
                                ' (${fmt.format(b.$1)} → ${fmt.format(b.$2)})';
                          } catch (_) {}
                          return DropdownMenuItem(
                            value: w,
                            child: Text('الأسبوع $w$range (W$w)'),
                          );
                        }).toList(),
                        onChanged: (v) {
                          if (v != null) {
                            setDialogState(() => selectedWeek = v);
                          }
                        },
                      );
                    }),
                  ],
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, color: Colors.blue, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'الفترة المحددة: ${_formatPeriod(periodCode)}',
                                style:
                                    const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                rangeText(),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.blue[800],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  try {
                    final db = ref.read(appDatabaseProvider);
                    final service = StaffManagementService(StaffManagementDao(db), db);
                    final user = ref.read(authProvider);
                    await service.calculatePayroll(user, widget.staff.staffId, periodCode);
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('تم احتساب المرتب للفترة ${_formatPeriod(periodCode)} بنجاح'),
                        backgroundColor: Colors.green,
                      ),
                    );
                    _loadData();
                  } catch (e) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[700],
                  foregroundColor: Colors.white,
                ),
                child: const Text('احتساب'),
              ),
            ],
          );
        },
      ),
    );
  }
}
