import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/services/audit_log_service.dart';
import 'package:pos_offline_desktop/core/services/document_date_service.dart';
import 'package:pos_offline_desktop/core/services/printer_service.dart';
import 'package:pos_offline_desktop/ui/widgets/document_date_picker.dart';

/// حوار تعديل أو حذف حركة مالية لمورد مع تغيير التاريخ وتحديث دفتر الأستاذ وسجل التدقيق والطباعة
class EditSupplierTransactionDialog extends StatefulWidget {
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
  State<EditSupplierTransactionDialog> createState() =>
      _EditSupplierTransactionDialogState();
}

class _EditSupplierTransactionDialogState
    extends State<EditSupplierTransactionDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  late final TextEditingController _descriptionController;
  late DateTime _selectedDate;
  late String _paymentMethod;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.transaction.date;
    final amount = widget.transaction.debit > 0
        ? widget.transaction.debit
        : widget.transaction.credit;
    _amountController = TextEditingController(text: amount.toStringAsFixed(2));
    _descriptionController =
        TextEditingController(text: widget.transaction.description);
    _paymentMethod = widget.transaction.paymentMethod ?? 'cash';
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
      final isDebit = widget.transaction.debit > 0;
      final oldDate = widget.transaction.date;
      final oldAmount = isDebit ? widget.transaction.debit : widget.transaction.credit;

      await widget.db.transaction(() async {
        // تحديث صف دفتر الأستاذ
        await (widget.db.update(widget.db.ledgerTransactions)
              ..where((t) => t.id.equals(widget.transaction.id)))
            .write(
          LedgerTransactionsCompanion(
            date: Value(_selectedDate),
            description: Value(_descriptionController.text.trim()),
            debit: Value(isDebit ? amount : 0.0),
            credit: Value(isDebit ? 0.0 : amount),
            paymentMethod: Value(_paymentMethod),
          ),
        );

        final isClosed = await DocumentDateService(widget.db)
            .isDateInClosedDay(_selectedDate);

        // توثيق التعديل في سجل التدقيق
        await AuditService.log(
          db: widget.db,
          action: 'UPDATE',
          tableName: 'ledger_transactions',
          details: '[MONEY] تعديل حركة مورد (${widget.transaction.refId}): '
              'التاريخ من ${DateFormat('yyyy/MM/dd HH:mm').format(oldDate)} إلى ${DateFormat('yyyy/MM/dd HH:mm').format(_selectedDate)}'
              ' والمبلغ من $oldAmount إلى $amount ج.م${isClosed ? ' (تحذير: يوم مغلق)' : ''}',
          oldValue: {
            'date': oldDate.toIso8601String(),
            'amount': oldAmount,
            'description': widget.transaction.description,
          },
          newValue: {
            'date': _selectedDate.toIso8601String(),
            'amount': amount,
            'description': _descriptionController.text.trim(),
            'day_closed_warning': isClosed,
          },
        );
      });

      if (mounted) {
        Navigator.pop(context, true);
        widget.onSaved?.call();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم تحديث حركة المورد بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في تحديث الحركة: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد حذف الحركة'),
        content: const Text(
          'هل أنت متأكد من حذف حركة السداد هذه؟\nسيتم استرجاع المبلغ لمديونية المورد.',
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
            child: const Text('تأكيد الحذف'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);

    try {
      await widget.db.transaction(() async {
        await (widget.db.delete(widget.db.ledgerTransactions)
              ..where((t) => t.id.equals(widget.transaction.id)))
            .go();

        await AuditService.log(
          db: widget.db,
          action: 'DELETE',
          tableName: 'ledger_transactions',
          details: '[MONEY] حذف حركة مورد (${widget.transaction.refId}) بمبلغ '
              '${widget.transaction.debit > 0 ? widget.transaction.debit : widget.transaction.credit} ج.م',
          oldValue: {
            'id': widget.transaction.id,
            'refId': widget.transaction.refId,
            'debit': widget.transaction.debit,
            'credit': widget.transaction.credit,
            'date': widget.transaction.date.toIso8601String(),
            'description': widget.transaction.description,
          },
          newValue: null,
        );
      });

      if (mounted) {
        Navigator.pop(context, true);
        widget.onSaved?.call();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حذف الحركة واسترجاع الرصيد بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في حذف الحركة: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _printReceipt() async {
    final amount = double.tryParse(_amountController.text.trim()) ?? 0.0;
    try {
      await PrinterService.printThermalReceipt(
        items: [
          {
            'name': _descriptionController.text.trim().isNotEmpty
                ? _descriptionController.text.trim()
                : (widget.transaction.debit > 0 ? 'سداد دفعة للمورد' : 'حركة مورد'),
            'quantity': 1,
            'unitPrice': amount,
            'totalPrice': amount,
          }
        ],
        totalAmount: amount,
        paidAmount: amount,
        remainingAmount: 0.0,
        paymentMethod: _paymentMethod,
        receiptNumber: widget.transaction.id,
        date: _selectedDate,
        customerName: 'مورد (${widget.transaction.refId})',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر الطباعة: $e'), backgroundColor: Colors.orange),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDebit = widget.transaction.debit > 0;
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.edit_calendar, color: Color(0xFFC9A84C)),
          const Gap(10),
          Text(isDebit ? 'تعديل سداد مورد' : 'تعديل قيد مشتريات مورد'),
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
        TextButton.icon(
          onPressed: _isLoading ? null : _delete,
          icon: const Icon(Icons.delete_outline, color: Colors.red, size: 18),
          label: const Text('حذف', style: TextStyle(color: Colors.red)),
        ),
        TextButton.icon(
          onPressed: _isLoading ? null : _printReceipt,
          icon: const Icon(Icons.print, size: 18),
          label: const Text('طباعة سند'),
        ),
        const Spacer(),
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
              : const Text('حفظ التعديل'),
        ),
      ],
    );
  }
}
