import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/provider/auth_provider.dart';
import 'package:pos_offline_desktop/core/services/ledger_service.dart';

/// حوار تعديل/حذف حركة مورد (شراء/دفعة/تسوية).
/// يستخدم LedgerService لضمان اتساق الرصيد داخل transaction.
class EditSupplierTransactionDialog extends ConsumerStatefulWidget {
  final AppDatabase db;
  final LedgerTransaction transaction;
  final VoidCallback? onSaved;

  const EditSupplierTransactionDialog({
    super.key,
    required this.db,
    required this.transaction,
    this.onSaved,
  });

  @override
  ConsumerState<EditSupplierTransactionDialog> createState() => _EditSupplierTransactionDialogState();
}

class _EditSupplierTransactionDialogState extends ConsumerState<EditSupplierTransactionDialog> {
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  late DateTime _date;
  String? _paymentMethod;
  String _origin = 'payment';
  bool _isSaving = false;
  String? _error;

  static const _methods = {
    'cash': 'نقدي',
    'bank': 'بنك',
    'instapay': 'انستاباي',
    'wallet': 'محفظة',
    'credit': 'آجل',
  };

  static const _origins = {
    'purchase': 'مشتريات',
    'payment': 'دفعة',
    'adjustment': 'تسوية',
    'opening': 'افتتاحي',
    'reversal': 'مرتجع',
  };

  @override
  void initState() {
    super.initState();
    _date = widget.transaction.date;
    final amount = widget.transaction.credit > 0 ? widget.transaction.credit : widget.transaction.debit;
    _amountController.text = amount.toStringAsFixed(2);
    _noteController.text = widget.transaction.description;
    _paymentMethod = widget.transaction.paymentMethod;
    _origin = widget.transaction.origin;
    if (!_origins.containsKey(_origin)) _origin = 'payment';
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amountController.text.trim().replaceAll(',', ''));
    if (amount == null || amount <= 0) {
      setState(() => _error = 'الرجاء إدخال مبلغ صحيح أكبر من صفر');
      return;
    }
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      final user = ref.read(authProvider);
      await LedgerService(widget.db).editSupplierTransaction(
        transactionId: widget.transaction.id,
        newAmount: amount,
        date: _date,
        paymentMethod: _paymentMethod,
        note: _noteController.text.trim(),
        performedBy: user?.username,
      );
      if (!mounted) return;
      widget.onSaved?.call();
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ تعديل حركة المورد بنجاح'), backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isSaving = false;
      });
    }
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد حذف الحركة'),
        content: const Text('سيتم حذف هذه الحركة وسيتأثر رصيد المورد.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _isSaving = true);
    try {
      final user = ref.read(authProvider);
      await LedgerService(widget.db).deleteSupplierTransaction(
        transactionId: widget.transaction.id,
        performedBy: user?.username,
      );
      if (!mounted) return;
      widget.onSaved?.call();
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حذف حركة المورد بنجاح'), backgroundColor: Colors.green),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: AlertDialog(
        title: const Text('تعديل حركة مورد'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_error != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                    child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                  ),
                DropdownButtonFormField<String>(
                  initialValue: _origin,
                  decoration: const InputDecoration(labelText: 'نوع الحركة', border: OutlineInputBorder()),
                  items: _origins.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                  onChanged: (v) => setState(() => _origin = v!),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _amountController,
                  decoration: const InputDecoration(labelText: 'المبلغ', border: OutlineInputBorder(), prefixText: 'ج.م '),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _paymentMethod,
                  decoration: const InputDecoration(labelText: 'طريقة الدفع', border: OutlineInputBorder()),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('غير محدد')),
                    ..._methods.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))),
                  ],
                  onChanged: (v) => setState(() => _paymentMethod = v),
                ),
                const SizedBox(height: 16),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _date,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) {
                      final time = TimeOfDay.fromDateTime(_date);
                      setState(() {
                        _date = DateTime(picked.year, picked.month, picked.day, time.hour, time.minute);
                      });
                    }
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'التاريخ', border: OutlineInputBorder()),
                    child: Text(DateFormat('yyyy/MM/dd HH:mm').format(_date)),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _noteController,
                  decoration: const InputDecoration(labelText: 'البيان', border: OutlineInputBorder()),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: _isSaving ? null : _delete,
            icon: const Icon(Icons.delete, size: 18),
            label: const Text('حذف'),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
          ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: _isSaving ? null : _save,
            child: _isSaving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('حفظ'),
          ),
        ],
      ),
    );
  }
}
