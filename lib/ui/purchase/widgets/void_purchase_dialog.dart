import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/models/user_model.dart';
import 'package:pos_offline_desktop/core/services/invoice_number_formatter.dart';
import 'package:pos_offline_desktop/core/services/purchase_void_service.dart';
import 'package:pos_offline_desktop/ui/widgets/permission_guarded_action.dart';

/// ديالوج تأكيد إلغاء فاتورة مشتريات.
///
/// نفس فلسفة ديالوج البيع: بيعرض الأثر الحقيقي، وبيطلب كتابة رقم الفاتورة
/// للتأكيد عشان ما حدوش يقفل الفاتورة الغلط بضغطة.
class VoidPurchaseDialog extends ConsumerStatefulWidget {
  final AppDatabase db;
  final String purchaseId;
  final String voidedBy;
  final VoidCallback? onDone;

  const VoidPurchaseDialog({
    super.key,
    required this.db,
    required this.purchaseId,
    required this.voidedBy,
    this.onDone,
  });

  @override
  ConsumerState<VoidPurchaseDialog> createState() =>
      _VoidPurchaseDialogState();
}

class _VoidPurchaseDialogState extends ConsumerState<VoidPurchaseDialog> {
  Purchase? _purchase;
  List<PurchaseItem> _lines = const [];
  final _reasonCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _loading = true;
  bool _submitting = false;
  String? _error;

  String get _expected => _purchase == null
      ? ''
      : (displayInvoiceNumber(_purchase!.invoiceNumber, null) ??
          _purchase!.invoiceNumber);

  bool get _confirmed =>
      _expected.isNotEmpty && _confirmCtrl.text.trim() == _expected;

  bool get _canSubmit =>
      _purchase != null && _confirmed && !_submitting;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await (_dbSelectPurchase());
      final l = await widget.db.purchaseDao
          .getPurchaseItems(p.invoiceNumber);
      if (!mounted) return;
      setState(() {
        _purchase = p;
        _lines = l;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<Purchase> _dbSelectPurchase() async {
    final p = await (widget.db.select(widget.db.purchases)
          ..where((t) => t.id.equals(widget.purchaseId)))
        .getSingleOrNull();
    if (p == null) throw Exception('فاتورة المشتريات غير موجودة');
    return p;
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;

    final denied = PermissionGuardedAction.check(
      context,
      ref,
      permission: Permission.deletePurchase,
      permissionLabel: 'حذف مشتريات',
    );
    if (denied != null) {
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.lock_outline, color: Colors.red, size: 32),
          title: const Text('مش مسموح', textAlign: TextAlign.center),
          content: Text(denied, textAlign: TextAlign.center),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('فهمت'),
            ),
          ],
        ),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      await PurchaseVoidService(widget.db).voidPurchase(
        purchaseId: widget.purchaseId,
        reason: _reasonCtrl.text.trim().isEmpty
            ? 'إلغاء يدوي'
            : _reasonCtrl.text.trim(),
        voidedBy: widget.voidedBy,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      widget.onDone?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم إلغاء فاتورة المشتريات'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
      );
      setState(() => _submitting = false);
    }
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.red),
          SizedBox(width: 8),
          Text('إلغاء فاتورة مشتريات',
              style: TextStyle(color: Colors.red)),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: _loading
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              )
            : _error != null
                ? Text(_error!, style: const TextStyle(color: Colors.red))
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _row('الفاتورة', _expected),
                      _row(
                          'المورد',
                          _purchase?.supplierId ?? 'غير محدد'),
                      _row(
                        'القيمة',
                        '${_purchase?.totalAmount.toStringAsFixed(2) ?? '0.00'} ج.م',
                      ),
                      const SizedBox(height: 12),
                      const Text('سيتم:',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 6),
                      _bullet(
                          'خصم ${_lines.length} صنف من المخزون (كانوا اتزادوا)'),
                      _bullet('حذف سطور فاتورة المشتريات'),
                      _bullet('حذف قيود المورد'),
                      _bullet('إخفاء الفاتورة من كل التقارير'),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _reasonCtrl,
                        decoration: const InputDecoration(
                          labelText: 'سبب الإلغاء *',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text('للتأكيد اكتب: $_expected',
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _confirmCtrl,
                        decoration: InputDecoration(
                          hintText: _expected,
                          border: const OutlineInputBorder(),
                          isDense: true,
                          suffixIcon: _confirmCtrl.text.isEmpty
                              ? null
                              : Icon(
                                  _confirmed
                                      ? Icons.check_circle
                                      : Icons.error_outline,
                                  color: _confirmed ? Colors.green : Colors.red,
                                  size: 20,
                                ),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ],
                  ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('رجوع'),
        ),
        ElevatedButton(
          onPressed: _canSubmit ? _submit : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
          ),
          child: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text('تأكيد الإلغاء'),
        ),
      ],
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(width: 60, child: Text(label, style: const TextStyle(fontSize: 13))),
            Expanded(
              child: Text(value,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );

  Widget _bullet(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('•  ', style: TextStyle(color: Colors.red)),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
          ],
        ),
      );
}