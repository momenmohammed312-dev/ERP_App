import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import '../../core/database/app_database.dart';
import '../../core/provider/app_database_provider.dart';
import '../../core/database/dao/staff_management_dao.dart';
import '../../core/utils/currency_helper.dart';
import '../../core/provider/auth_provider.dart';
import '../../services/staff_management_service.dart';
import 'package:intl/intl.dart';

class AdvancesPage extends ConsumerStatefulWidget {
  final Staff staff;

  const AdvancesPage({super.key, required this.staff});

  @override
  ConsumerState<AdvancesPage> createState() => _AdvancesPageState();
}

class _AdvancesPageState extends ConsumerState<AdvancesPage> {
  static const _arabicMonthNames = [
    'يناير (1)',
    'فبراير (2)',
    'مارس (3)',
    'أبريل (4)',
    'مايو (5)',
    'يونيو (6)',
    'يوليو (7)',
    'أغسطس (8)',
    'سبتمبر (9)',
    'أكتوبر (10)',
    'نوفمبر (11)',
    'ديسمبر (12)',
  ];

  late StaffManagementDao _dao;
  List<StaffAdvance> _advances = [];
  bool _isLoading = true;

  String _formatPeriodLabel(String? period) {
    if (period == null || period.trim().isEmpty) return 'غير محدد';
    final parts = period.trim().split('-');
    if (parts.length >= 2) {
      final y = parts[0];
      final m = int.tryParse(parts[1]);
      if (m != null && m >= 1 && m <= 12) {
        if (parts.length > 2 && parts[2].startsWith('W')) {
          return 'أسبوع ${parts[2].substring(1)} - ${_arabicMonthNames[m - 1]} $y';
        }
        return '${_arabicMonthNames[m - 1]} $y';
      }
    }
    return period;
  }

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
      final advances = await _dao.getAdvancesByStaff(widget.staff.staffId);
      setState(() {
        _advances = advances.reversed.toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(
        // ignore: use_build_context_synchronously
        context,
      ).showSnackBar(SnackBar(content: Text('خطأ في تحميل سجل السلف: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _advances.isEmpty
          ? _buildEmptyState()
          : _buildAdvancesList(),
      floatingActionButton: FloatingActionButton(
        onPressed: _requestAdvance,
        backgroundColor: Colors.teal,
        tooltip: 'طلب سلفة',
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.money_off, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            'لا يوجد سلف لهذا الموظف',
            style: TextStyle(fontSize: 18, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildAdvancesList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16.0),
      itemCount: _advances.length,
      itemBuilder: (context, index) {
        final advance = _advances[index];
        return _buildAdvanceCard(advance);
      },
    );
  }

  Widget _buildAdvanceCard(StaffAdvance advance) {
    final statusColor = _getStatusColor(advance.status);

    return Card(
      margin: const EdgeInsets.only(bottom: 12.0),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          if (advance.status == 'pending') {
            _approveAdvance(advance);
          } else if (advance.status == 'approved') {
            _payAdvance(advance);
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    CurrencyHelper.formatCurrency(advance.amount),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: Colors.teal[700],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: statusColor),
                    ),
                    child: Text(
                      _getStatusText(advance.status),
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(height: 24),
              Row(
                children: [
                  _buildInfoColumn(
                    'تاريخ الطلب',
                    DateFormat('yyyy/MM/dd').format(advance.requestDate),
                  ),
                  const Spacer(),
                  _buildInfoColumn(
                    advance.installmentMonths != null && advance.installmentMonths! > 1
                        ? 'بدء الخصم'
                        : 'شهر الخصم',
                    _formatPeriodLabel(advance.deductOnPeriod ??
                        DateFormat('yyyy-MM').format(advance.paymentDate ?? advance.requestDate)),
                  ),
                  if (advance.installmentMonths != null) ...[
                    const Spacer(),
                    _buildInfoColumn(
                      'الأقساط',
                      '${advance.installmentMonths} شهر',
                    ),
                  ],
                  if (advance.monthlyDeduction != null) ...[
                    const Spacer(),
                    _buildInfoColumn(
                      'القسط الشهري',
                      CurrencyHelper.formatCurrency(advance.monthlyDeduction!),
                    ),
                  ],
                ],
              ),
              if (advance.reason != null && advance.reason!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'السبب: ${advance.reason}',
                    style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  ),
                ),
              ],
              if (advance.paymentDate != null) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'تاريخ الصرف: ${DateFormat('yyyy/MM/dd').format(advance.paymentDate!)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
              const Divider(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _deleteAdvance(advance),
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                    ),
                  ),
                  if (advance.status == 'pending')
                    ElevatedButton.icon(
                      onPressed: () => _approveAdvance(advance),
                      icon: const Icon(Icons.check_circle_outline, size: 18),
                      label: const Text('اعتماد واحتساب'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  if (advance.status == 'approved')
                    ElevatedButton.icon(
                      onPressed: () => _payAdvance(advance),
                      icon: const Icon(Icons.payments, size: 18),
                      label: const Text('صرف السلفة'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _approveAdvance(StaffAdvance advance) async {
    try {
      final user = ref.read(authProvider);
      final approver = user?.fullName ?? user?.username ?? 'الإدارة';
      await _dao.approveAdvance(advance.id, approver);
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم اعتماد السلفة واحتسابها بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في اعتماد السلفة: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteAdvance(StaffAdvance advance) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف السلفة'),
        content: Text(
          'هل أنت متأكد من مسح هذه السلفة بمبلغ ${CurrencyHelper.formatCurrency(advance.amount)}؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('مسح'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      final db = ref.read(appDatabaseProvider);
      await (db.delete(db.staffAdvances)
            ..where((t) => t.id.equals(advance.id)))
          .go();
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم مسح السلفة بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل مسح السلفة: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildInfoColumn(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
      ],
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'approved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      case 'pending':
        return Colors.orange;
      case 'paid':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'approved':
        return 'مقبول';
      case 'rejected':
        return 'مرفوض';
      case 'pending':
        return 'قيد الانتظار';
      case 'paid':
        return 'تم الصرف';
      default:
        return status;
    }
  }

  Future<void> _requestAdvance() async {
    final formKey = GlobalKey<FormState>();
    final amountCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    int? installmentMonths;
    final installmentCtrl = TextEditingController();

    final now = DateTime.now();
    int selectedYear = now.year;
    int selectedMonth = now.month;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) {
        int? instMonths = installmentMonths;

        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('طلب سلفة جديد'),
            content: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: amountCtrl,
                      decoration: const InputDecoration(
                        labelText: 'المبلغ',
                        prefixText: 'ج.م ',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'المبلغ مطلوب';
                        }
                        final amt = double.tryParse(v.trim());
                        if (amt == null || amt <= 0) {
                          return 'أدخل مبلغ صحيح';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: reasonCtrl,
                      decoration: const InputDecoration(
                        labelText: 'السبب',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'السبب مطلوب' : null,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: DropdownButtonFormField<int>(
                            initialValue: selectedMonth,
                            decoration: const InputDecoration(
                              labelText: 'شهر الخصم',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 12,
                              ),
                            ),
                            items: List.generate(12, (i) => i + 1).map((m) {
                              return DropdownMenuItem<int>(
                                value: m,
                                child: Text(
                                  _arabicMonthNames[m - 1],
                                  style: const TextStyle(fontSize: 13),
                                ),
                              );
                            }).toList(),
                            onChanged: (v) {
                              if (v != null) {
                                setDialogState(() => selectedMonth = v);
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: DropdownButtonFormField<int>(
                            initialValue: selectedYear,
                            decoration: const InputDecoration(
                              labelText: 'السنة',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 12,
                              ),
                            ),
                            items: [
                              now.year - 1,
                              now.year,
                              now.year + 1,
                              now.year + 2,
                            ].map((y) {
                              return DropdownMenuItem<int>(
                                value: y,
                                child: Text(
                                  '$y',
                                  style: const TextStyle(fontSize: 13),
                                ),
                              );
                            }).toList(),
                            onChanged: (v) {
                              if (v != null) {
                                setDialogState(() => selectedYear = v);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: installmentCtrl,
                      decoration: const InputDecoration(
                        labelText: 'عدد الأقساط (اختياري)',
                        helperText: 'اتركه فارغاً إذا كان الخصم دفعة واحدة',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (v) {
                        final parsed = int.tryParse(v.trim());
                        setDialogState(() => instMonths = parsed);
                      },
                    ),
                    const SizedBox(height: 8),
                    if (instMonths != null && instMonths! > 1) ...[
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.teal.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.teal.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'القسط الشهري: ${((double.tryParse(amountCtrl.text.trim()) ?? 0) / instMonths!).toStringAsFixed(2)} ج.م',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.teal,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'يبدأ الخصم من مرتب: ${_arabicMonthNames[selectedMonth - 1]} $selectedYear ولمدة $instMonths أشهر',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.teal[800],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          'سيتم خصم السلفة في مرتب: ${_arabicMonthNames[selectedMonth - 1]} $selectedYear',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.teal[700],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                onPressed: () {
                  if (formKey.currentState!.validate()) {
                    final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
                    final inst = int.tryParse(installmentCtrl.text.trim());
                    final deductOnPeriod =
                        '$selectedYear-${selectedMonth.toString().padLeft(2, '0')}';
                    Navigator.pop(ctx, {
                      'amount': amount,
                      'reason': reasonCtrl.text.trim(),
                      'installments': inst,
                      'deductOnPeriod': deductOnPeriod,
                    });
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                ),
                child: const Text('إرسال الطلب'),
              ),
            ],
          ),
        );
      },
    );

    if (result != null) {
      try {
        final amount = result['amount'] as double;
        final reason = result['reason'] as String;
        final inst = result['installments'] as int?;
        final deductOnPeriod = result['deductOnPeriod'] as String?;

        final user = ref.read(authProvider);
        final approver = user?.fullName ?? user?.username ?? 'الإدارة';

        await _dao.addAdvance(
          StaffAdvancesCompanion.insert(
            staffId: widget.staff.staffId,
            amount: amount,
            reason: reason.isNotEmpty
                ? drift.Value(reason)
                : const drift.Value.absent(),
            requestDate: DateTime.now(),
            status: 'approved',
            approvedBy: drift.Value(approver),
            approvedAt: drift.Value(DateTime.now()),
            installmentMonths: inst != null && inst > 0
                ? drift.Value(inst)
                : const drift.Value.absent(),
            monthlyDeduction: inst != null && inst > 0
                ? drift.Value(amount / inst)
                : const drift.Value.absent(),
            deductOnPeriod: deductOnPeriod != null
                ? drift.Value(deductOnPeriod)
                : const drift.Value.absent(),
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );
        await _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم تسجيل السلفة واعتمادها واحتسابها بنجاح'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
    amountCtrl.dispose();
    reasonCtrl.dispose();
    installmentCtrl.dispose();
  }

  Future<void> _payAdvance(StaffAdvance advance) async {
    final methods = ['cash', 'bank_transfer', 'check'];
    final selectedMethod = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('طريقة صرف السلفة'),
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
      await service.payAdvance(user, advance.id, selectedMethod);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم صرف السلفة'), backgroundColor: Colors.green),
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
}
