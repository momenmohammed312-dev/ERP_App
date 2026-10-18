import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/services/audit_log_service.dart';
import 'package:pos_offline_desktop/ui/widgets/document_date_picker.dart';

/// حوار إضافة حركة مالية لمورد (سداد أو دين/فاتورة) مع اختيار التاريخ والتحقق من اليوم المغلق
class AddSupplierTransactionDialog extends StatefulWidget {
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
  State<AddSupplierTransactionDialog> createState() =>
      _AddSupplierTransactionDialogState();
}

class _AddSupplierTransactionDialogState
    extends State<AddSupplierTransactionDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  late DateTime _selectedDate;
  String _transactionType = 'payment'; // 'payment' (سداد للمورد) أو 'purchase' (دين/فاتورة)
  String _paymentMethod = 'cash';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await pickDocumentDate(
      context: context,
      db: widget.db,
      initialDate: _selectedDate,
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final amount = double.tryParse(_amountController.text.trim()) ?? 0.0;
    if (amount <= 0) return;

    setState(() => _isLoading = true);

    try {
      final isPayment = _transactionType == 'payment';
      final desc = _descriptionController.text.trim().isNotEmpty
          ? _descriptionController.text.trim()
          : (isPayment ? 'سداد دفعة للمورد' : 'قيد فاتورة/شراء للمورد');

      final txId = '${DateTime.now().millisecondsSinceEpoch}_supplier_${widget.supplier.id}';

      await widget.db.transaction(() async {
        await widget.db.ledgerDao.insertTransaction(
          LedgerTransactionsCompanion.insert(
            id: txId,
            entityType: 'Supplier',
            refId: widget.supplier.id,
            date: _selectedDate,
            description: desc,
            // سداد للمورد = مدين debit (يقلل الدين المستحق علينا للمورد)
            // شراء/دين = دائن credit (يزيد الدين المستحق للمورد)
            debit: Value(isPayment ? amount : 0.0),
            credit: Value(isPayment ? 0.0 : amount),
            origin: isPayment ? 'payment' : 'purchase',
            paymentMethod: Value(_paymentMethod),
            createdAt: Value(DateTime.now()),
          ),
        );

        await AuditService.log(
          db: widget.db,
          action: 'INSERT',
          tableName: 'ledger_transactions',
          details: '[MONEY] إضافة حركة مورد (${widget.supplier.name}): $desc بمبلغ $amount ج.م بتاريخ ${DateFormat('yyyy/MM/dd HH:mm').format(_selectedDate)}',
          newValue: {
            'supplierId': widget.supplier.id,
            'amount': amount,
            'type': _transactionType,
            'date': _selectedDate.toIso8601String(),
          },
        );
      });

      if (mounted) {
        Navigator.pop(context, true);
        widget.onSaved?.call();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم تسجيل الحركة بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في حفظ الحركة: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.receipt_long, color: Color(0xFFC9A84C)),
          const Gap(10),
          Text('إضافة حركة للمورد: ${widget.supplier.name}'),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // نوع الحركة
                DropdownButtonFormField<String>(
                  initialValue: _transactionType,
                  decoration: const InputDecoration(
                    labelText: 'نوع الحركة',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.swap_horiz),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'payment',
                      child: Text('سداد دفعة للمورد (يقلل رصيده المستحق)'),
                    ),
                    DropdownMenuItem(
                      value: 'purchase',
                      child: Text('شراء / فاتورة (يزيد رصيد المورد المستحق)'),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _transactionType = val);
                  },
                ),
                const Gap(14),

                // المبلغ
                TextFormField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'المبلغ (ج.م) *',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.attach_money),
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) return 'يرجى إدخال المبلغ';
                    final n = double.tryParse(val.trim());
                    if (n == null || n <= 0) return 'أدخل مبلغاً صحيحاً أكبر من صفر';
                    return null;
                  },
                ),
                const Gap(14),

                // التاريخ
                InkWell(
                  onTap: _pickDate,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'تاريخ الحركة',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.calendar_today),
                      suffixIcon: Icon(Icons.edit_calendar, size: 18),
                    ),
                    child: Text(
                      DateFormat('yyyy/MM/dd - hh:mm a').format(_selectedDate),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const Gap(14),

                // طريقة الدفع
                DropdownButtonFormField<String>(
                  initialValue: _paymentMethod,
                  decoration: const InputDecoration(
                    labelText: 'طريقة الدفع',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.payment),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'cash', child: Text('نقدي')),
                    DropdownMenuItem(value: 'bank', child: Text('تحويل بنكي')),
                    DropdownMenuItem(value: 'visa', child: Text('بطاقة')),
                    DropdownMenuItem(value: 'credit', child: Text('آجل')),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _paymentMethod = val);
                  },
                ),
                const Gap(14),

                // البيان / الوصف
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'البيان / ملاحظات',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.notes),
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFC9A84C),
            foregroundColor: Colors.black,
            textStyle: const TextStyle(fontWeight: FontWeight.bold),
          ),
          child: _isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('حفظ الحركة'),
        ),
      ],
    );
  }
}
