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
  late StaffManagementDao _dao;
  List<StaffAdvance> _advances = [];
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
                if (advance.installmentMonths != null)
                  _buildInfoColumn(
                    'الأقساط',
                    '${advance.installmentMonths} شهر',
                  ),
                const Spacer(),
                if (advance.monthlyDeduction != null)
                  _buildInfoColumn(
                    'القسط الشهري',
                    CurrencyHelper.formatCurrency(advance.monthlyDeduction!),
                  ),
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
            if (advance.status == 'approved') ...[
              const Divider(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
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
          ],
        ),
      ),
    );
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
                    TextFormField(
                      controller: installmentCtrl,
                      decoration: const InputDecoration(
                        labelText: 'عدد الأقساط (اختياري)',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (v) {
                        final parsed = int.tryParse(v.trim());
                        setDialogState(() => instMonths = parsed);
                      },
                    ),
                    if (instMonths != null && instMonths! > 0) ...[
                      const SizedBox(height: 8),
                      Text(
                        'القسط الشهري: ${((double.tryParse(amountCtrl.text.trim()) ?? 0) / instMonths!).toStringAsFixed(2)} ج.م',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.teal,
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
                    Navigator.pop(ctx, {
                      'amount': amount,
                      'reason': reasonCtrl.text.trim(),
                      'installments': inst,
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

        await _dao.addAdvance(
          StaffAdvancesCompanion.insert(
            staffId: widget.staff.staffId,
            amount: amount,
            reason: reason.isNotEmpty
                ? drift.Value(reason)
                : const drift.Value.absent(),
            requestDate: DateTime.now(),
            status: 'pending',
            installmentMonths: inst != null && inst > 0
                ? drift.Value(inst)
                : const drift.Value.absent(),
            monthlyDeduction: inst != null && inst > 0
                ? drift.Value(amount / inst)
                : const drift.Value.absent(),
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );
        await _loadData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم إرسال طلب السلفة'),
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
      final service = StaffManagementService(StaffManagementDao(db));
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
