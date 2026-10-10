import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/models/user_model.dart';
import 'package:pos_offline_desktop/core/services/invoice_void_service.dart';
import 'package:pos_offline_desktop/ui/widgets/permission_guarded_action.dart';

/// ديالوج تأكيد إلغاء الفاتورة.
///
/// مقصود إنه **متحذّر**: بيعرض الأثر الحقيقي (كام صنف هيرجع للمخزون، كام
/// قيد هيتشال) ويطلب كتابة رقم الفاتورة للتأكيد — عشان ما حدوش يقفل
/// الفاتورة الغلط بضغطة واحدة.
class VoidInvoiceDialog extends ConsumerStatefulWidget {
  final AppDatabase db;
  final int invoiceId;
  final String voidedBy;

  /// بعد نجاح الإلغاء.
  final VoidCallback? onDone;

  const VoidInvoiceDialog({
    super.key,
    required this.db,
    required this.invoiceId,
    required this.voidedBy,
    this.onDone,
  });

  @override
  ConsumerState<VoidInvoiceDialog> createState() => _VoidInvoiceDialogState();
}

class _VoidInvoiceDialogState extends ConsumerState<VoidInvoiceDialog> {
  VoidPreview? _preview;
  String _reason = VoidReasons.inputError;
  final _notesCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _loading = true;
  bool _submitting = false;
  String? _error;

  /// الكلمة/الرقم اللي لازم يتكتب بالظبط للتأكيد.
  String get _expected => _preview?.invoiceNumber ?? '';

  bool get _confirmed =>
      _expected.isNotEmpty && _confirmCtrl.text.trim() == _expected;

  /// لو الفاتورة عليها مرتجعات، الإلغاء **مسموح** — هنعكس المرتجع كمان
  /// (مخزون + قيود + استردادات). بنعرض تنبيه معلوماتي بس.
  bool get _hasReturns => (_preview?.returnCount ?? 0) > 0;

  bool get _canSubmit =>
      _preview != null && _confirmed && !_submitting;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await InvoiceVoidService(widget.db).preview(widget.invoiceId);
      if (!mounted) return;
      setState(() {
        _preview = p;
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

  Future<void> _submit() async {
    if (!_canSubmit) return;

    // فحص الصلاحية هنا جوّه الديالوج مش على مستوى الزرار — عشان الزرار
    // يفضل ظاهر والكاشير يشوف إن الميزة موجودة، ويعرف بالظبط ليه مش قادر
    // يستخدمها بدل ما يفتكر إن البرنامج ناقصه.
    final denied = PermissionGuardedAction.check(
      context,
      ref,
      permission: Permission.deleteSale,
      permissionLabel: 'حذف بيع',
    );
    if (denied != null) {
      _showDenied(denied);
      return;
    }

    setState(() => _submitting = true);
    try {
      await InvoiceVoidService(widget.db).voidInvoice(
        invoiceId: widget.invoiceId,
        reason: _reason,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        voidedBy: widget.voidedBy,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      widget.onDone?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم إلغاء الفاتورة'),
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

  void _showDenied(String message) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.lock_outline, color: Colors.red, size: 32),
        title: const Text('مش مسموح', textAlign: TextAlign.center),
        content: Text(message, textAlign: TextAlign.center),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('فهمت'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
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
          Text('إلغاء الفاتورة', style: TextStyle(color: Colors.red)),
        ],
      ),
      content: SizedBox(
        width: 460,
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
                      _header(),
                      const SizedBox(height: 12),
                      _impactBox(),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _reason,
                        decoration: const InputDecoration(
                          labelText: 'سبب الإلغاء *',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: VoidReasons.all
                            .map((r) => DropdownMenuItem(
                                  value: r,
                                  child: Text(VoidReasons.label(r)),
                                ))
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _reason = v ?? VoidReasons.other),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _notesCtrl,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'ملاحظات (اختياري)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_hasReturns) ...[
                        _returnsNotice(),
                        const SizedBox(height: 12),
                      ],
                      _confirmField(),
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

  Widget _header() {
    final p = _preview!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _row('الفاتورة', p.invoiceNumber),
          _row('العميل', p.customerName ?? 'غير محدد'),
          _row('القيمة', '${p.totalAmount.toStringAsFixed(2)} ج.م'),
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(
              width: 70,
              child: Text(label, style: const TextStyle(fontSize: 13)),
            ),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );

  Widget _impactBox() {
    final p = _preview!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('سيتم:',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        const SizedBox(height: 6),
        _bullet('إرجاع ${p.itemCount} صنف للمخزون'),
        _bullet('إلغاء ${p.paymentCount} دفعة مسجلة'),
        _bullet('حذف ${p.ledgerRowCount} قيد محاسبي'),
        if (p.returnCount > 0)
          _bullet('عكس ${p.returnCount} مرتجع مرتبط بالفاتورة'),
        if (p.refundCount > 0)
          _bullet('عكس ${p.refundCount} استرداد'
              '${p.cashRefundAmount > 0 ? ' (منها ${p.cashRefundAmount.toStringAsFixed(2)} ج.م نقدي)' : ''}'),
        _bullet('إخفاء الفاتورة من كل التقارير والأرصدة'),
        const SizedBox(height: 6),
        const Text(
          'السجل بيتسجل في سجل المراجعة — مش بينمسح نهائي.',
          style: TextStyle(fontSize: 11, color: Colors.grey),
        ),
      ],
    );
  }

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

  Widget _returnsNotice() {
    final p = _preview!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: Colors.orange, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'الفاتورة عليها ${p.returnCount} مرتجع مسجل'
              '${p.refundCount > 0 ? ' و${p.refundCount} استرداد' : ''}.\n'
              'الإلغاء هيعكس المرتجع كمان (المخزون والقيود والاستردادات) '
              'عشان تبقى كأنها مجتش.',
              style: const TextStyle(fontSize: 12.5, color: Colors.orange),
            ),
          ),
        ],
      ),
    );
  }

  Widget _confirmField() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('للتأكيد اكتب: $_expected',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
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
                      _confirmed ? Icons.check_circle : Icons.error_outline,
                      color: _confirmed ? Colors.green : Colors.red,
                      size: 20,
                    ),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      );
}