import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/provider/auth_provider.dart';
import 'package:pos_offline_desktop/core/services/ledger_service.dart';

class AddSupplierTransactionDialog extends ConsumerStatefulWidget {
  final AppDatabase db;
  final Supplier supplier;
  final VoidCallback? onSaved;

  const AddSupplierTransactionDialog({
    super.key,
    required this.db,
    required this.supplier,
    this.onSaved,
  });

  @override
  ConsumerState<AddSupplierTransactionDialog> createState() => _AddSupplierTransactionDialogState();
}

class _AddSupplierTransactionDialogState extends ConsumerState<AddSupplierTransactionDialog> {
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  DateTime _date = DateTime.now();
  String _origin = 'payment';
  String _paymentMethod = 'cash';
  bool _isSaving = false;
  String? _error;

  static const _origins = {
    'payment': 'دفعة للمورد (تنقص المديونية)',
    'purchase': 'مشتريات/فاتورة (تزيد المديونية)',
    'adjustment': 'تسوية/خصم',
    'reversal': 'مرتجع',
  };
  static const _methods = {
    'cash': 'نقدي',
    'bank': 'بنك',
    'instapay': 'انستاباي',
    'wallet': 'محفظة',
    'credit': 'آجل',
  };

  Future<void> _save() async {
    final amount = double.tryParse(_amountController.text.trim().replaceAll(',', ''));
    if (amount == null || amount <= 0) {
      setState(() => _error = 'أدخل مبلغ صحيح > 0');
      return;
    }
    if (_noteController.text.trim().isEmpty) {
      setState(() => _error = 'أدخل البيان');
      return;
    }
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      final user = ref.read(authProvider);
      await LedgerService(widget.db).addSupplierTransaction(
        supplierId: widget.supplier.id,
        description: _noteController.text.trim(),
        amount: amount,
        origin: _origin,
        paymentMethod: _paymentMethod,
        date: _date,
        performedBy: user?.username,
      );
      if (!mounted) return;
      widget.onSaved?.call();
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تمت إضافة الحركة بنجاح'), backgroundColor: Colors.green),
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
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: AlertDialog(
        title: Text('إضافة حركة للمورد: ${widget.supplier.name}'),
        content: SizedBox(
          width: 440,
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
                  items: _methods.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
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
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ),
        actions: [
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
