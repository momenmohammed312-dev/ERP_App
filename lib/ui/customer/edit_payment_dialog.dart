import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/provider/auth_provider.dart';
import 'package:pos_offline_desktop/core/services/ledger_service.dart';

/// حوار تعديل/حذف دفعة عميل. يعتمد على [LedgerService] لضمان اتساق الرصيد
/// والفاتورة المرتبطة (إن وُجدت) داخل transaction واحد.
class EditPaymentDialog extends ConsumerStatefulWidget {
  final AppDatabase db;
  final LedgerTransaction transaction;
  final VoidCallback? onSaved;

  const EditPaymentDialog({
    super.key,
    required this.db,
    required this.transaction,
    this.onSaved,
  });

  @override
  ConsumerState<EditPaymentDialog> createState() => _EditPaymentDialogState();
}

class _EditPaymentDialogState extends ConsumerState<EditPaymentDialog> {
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  late DateTime _date;
  String _paymentMethod = 'cash';
  bool _isSaving = false;
  String? _error;

  static final _invReceipt = RegExp(r'^INV(\d+)$');

  static const _methods = {
    'cash': 'نقدي',
    'credit': 'آجل',
    'visa': 'بطاقة',
    'bank': 'بنك',
    'instapay': 'انستاباي',
    'wallet': 'محفظة',
  };

  @override
  void initState() {
    super.initState();
    _date = widget.transaction.date;
    final amount = widget.transaction.credit > 0
        ? widget.transaction.credit
        : widget.transaction.debit;
    _amountController.text = amount.toStringAsFixed(2);
    _noteController.text = widget.transaction.description;
    _paymentMethod = widget.transaction.paymentMethod ?? 'cash';
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  bool get _isInvoiceLinked =>
      widget.transaction.receiptNumber != null &&
      _invReceipt.hasMatch(widget.transaction.receiptNumber!);

  Future<void> _save() async {
    final amount = double.tryParse(
      _amountController.text.trim().replaceAll(',', ''),
    );
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
      await LedgerService(widget.db).editCustomerPayment(
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
        const SnackBar(
          content: Text('تم حفظ تعديل الدفعة بنجاح'),
          backgroundColor: Colors.green,
        ),
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
        title: const Text('تأكيد حذف الدفعة'),
        content: const Text('سيتم حذف هذه الدفعة وإرجاع مبلغها لرصيد العميل.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _isSaving = true);
    try {
      final user = ref.read(authProvider);
      await LedgerService(widget.db).deleteStandalonePayment(
        transactionId: widget.transaction.id,
        performedBy: user?.username,
      );
      if (!mounted) return;
      widget.onSaved?.call();
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم حذف الدفعة بنجاح'),
          backgroundColor: Colors.green,
        ),
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
        title: Text(_isInvoiceLinked ? 'تعديل دفعة فاتورة' : 'تعديل دفعة'),
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
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ),
                TextField(
                  controller: _amountController,
                  decoration: const InputDecoration(
                    labelText: 'المبلغ',
                    border: OutlineInputBorder(),
                    prefixText: 'ج.م ',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _paymentMethod,
                  decoration: const InputDecoration(
                    labelText: 'طريقة الدفع',
                    border: OutlineInputBorder(),
                  ),
                  items: _methods.entries
                      .map((e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _paymentMethod = v!),
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
                        _date = DateTime(
                          picked.year,
                          picked.month,
                          picked.day,
                          time.hour,
                          time.minute,
                        );
                      });
                    }
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'التاريخ',
                      border: OutlineInputBorder(),
                    ),
                    child: Text(
                      DateFormat('yyyy/MM/dd HH:mm').format(_date),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _noteController,
                  decoration: const InputDecoration(
                    labelText: 'البيان / السبب',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_isInvoiceLinked)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'هذه الدفعة مرتبطة بفاتورة؛ سيتم تحديث المبلغ المدفوع '
                      'وحالة الفاتورة تلقائياً.',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          if (!_isInvoiceLinked)
            TextButton.icon(
              onPressed: _isSaving ? null : _delete,
              icon: const Icon(Icons.delete, size: 18),
              label: const Text('حذف'),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: _isSaving ? null : _save,
            child: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('حفظ'),
          ),
        ],
      ),
    );
  }
}
