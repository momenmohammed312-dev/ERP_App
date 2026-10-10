import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/services/sales_return_service.dart';
import 'package:pos_offline_desktop/core/services/return_refund_service.dart';

/// ديالوج المرتجع الجزئي — اختيار صنف أو أكثر بكمية جزئية + طريقة الاسترداد.
class InvoicePartialReturnDialog extends StatefulWidget {
  final AppDatabase db;
  final int invoiceId;
  final VoidCallback? onDone;

  /// اسم المستخدم — بيتسجل في سجل المراجعة مع كل استرداد.
  final String? processedBy;

  const InvoicePartialReturnDialog({
    super.key,
    required this.db,
    required this.invoiceId,
    this.onDone,
    this.processedBy,
  });

  @override
  State<InvoicePartialReturnDialog> createState() => _InvoicePartialReturnDialogState();
}

class _InvoicePartialReturnDialogState extends State<InvoicePartialReturnDialog> {
  late final SalesReturnService _service;
  List<ReturnableLine> _lines = [];
  final Map<int, int> _picked = {}; // invoiceItemId -> qty
  final Map<int, String> _conditions = {}; // invoiceItemId -> restockCondition
  String _reason = 'customer_request';
  final _notesCtrl = TextEditingController();

  // --- الاسترداد ---
  String _refundMethod = RefundMethod.cash;
  bool _refundEnabled = true;
  final _refundAmountCtrl = TextEditingController();
  bool _isLoading = true;
  bool _submitting = false;
  String? _error;

  /// الفاتورة آجلة ولها عميل مسجّل؟ بيحدد لو الرصيد مسموح ولا لأ.
  bool _hasCreditCustomer = false;

  @override
  void initState() {
    super.initState();
    _service = SalesReturnService(widget.db);
    _load();
  }

  Future<void> _load() async {
    try {
      final lines = await _service.getReturnableLines(widget.invoiceId);
      final invoice = await widget.db.invoiceDao.getInvoiceById(widget.invoiceId);
      final cid = invoice?.customerId;
      final hasCredit = cid != null && cid.isNotEmpty && cid != 'cash';
      if (!mounted) return;
      setState(() {
        _lines = lines;
        _hasCreditCustomer = hasCredit;
        _isLoading = false;
      });
      _syncRefundAmount();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  double get _total {
    double t = 0;
    for (final l in _lines) {
      final q = _picked[l.invoiceItem.id] ?? 0;
      if (q <= 0) continue;
      t += q * _netUnit(l);
    }
    return t;
  }

  /// سعر السطر بعد توزيع الخصم — quantity ممكن يكون 0 فبنقسم على 1.
  double _netUnit(ReturnableLine l) {
    final divisor = l.invoiceItem.quantity == 0 ? 1 : l.invoiceItem.quantity;
    return l.invoiceItem.price - (l.invoiceItem.discount / divisor);
  }

  String _conditionOf(int invoiceItemId) =>
      _conditions[invoiceItemId] ?? SalesReturnService.restockSellable;

  bool get _hasPick => _picked.values.any((q) => q > 0);

  /// يملأ خانة المبلغ بالمتبقي تلقائياً — ما نكتبش فوق رقم الكاشير.
  void _syncRefundAmount() {
    if (!_refundEnabled) return;
    final t = _total;
    if (t <= 0) {
      _refundAmountCtrl.clear();
      return;
    }
    final typed = double.tryParse(_refundAmountCtrl.text);
    if (typed == null || typed > t + 0.01) {
      _refundAmountCtrl.text = t.toStringAsFixed(2);
    }
  }

  double get _refundAmount {
    if (!_refundEnabled) return 0.0;
    return double.tryParse(_refundAmountCtrl.text) ?? 0.0;
  }

  Future<void> _submit() async {
    if (!_hasPick) return;

    if (_refundEnabled && _refundAmount > 0) {
      if (_refundAmount > _total + 0.01) {
        _toast('مبلغ الاسترداد أكبر من قيمة المرتجع', Colors.red);
        return;
      }
      if (_refundMethod != RefundMethod.cash && !_hasCreditCustomer) {
        _toast('الاسترداد كرصيد يحتاج عميل مسجّل على الفاتورة', Colors.red);
        return;
      }
    }

    setState(() => _submitting = true);
    try {
      final returnId = await _service.processPartialReturn(
        invoiceId: widget.invoiceId,
        itemReturns: Map<int, int>.from(_picked),
        reason: _reason,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        processedBy: widget.processedBy,
        restockConditions: Map<int, String>.from(_conditions),
      );

      var refunded = 0.0;
      if (_refundEnabled && _refundAmount > 0.01) {
        await ReturnRefundService(widget.db).refund(
          returnId: returnId,
          amount: _refundAmount,
          method: _refundMethod,
          notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
          processedBy: widget.processedBy ?? 'unknown',
        );
        refunded = _refundAmount;
      }

      if (!mounted) return;
      Navigator.pop(context, true);
      widget.onDone?.call();
      _toast(
        refunded > 0
            ? 'تم المرتجع واسترداد ${refunded.toStringAsFixed(2)} ج.م'
            : 'تم تسجيل المرتجع الجزئي بنجاح',
        Colors.green,
      );
    } catch (e) {
      if (!mounted) return;
      _toast('خطأ: $e', Colors.red);
      setState(() => _submitting = false);
    }
  }

  void _toast(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    _refundAmountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('مرتجع جزئي — اختر الأصناف'),
      content: SizedBox(
        width: 620,
        child: _isLoading
            ? const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
            : _error != null
                ? Text(_error!, style: const TextStyle(color: Colors.red))
                : _lines.isEmpty
                    ? const Text('لا توجد أصناف في الفاتورة')
                    : SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            DropdownButtonFormField<String>(
                              initialValue: _reason,
                              decoration: const InputDecoration(labelText: 'سبب المرتجع', border: OutlineInputBorder()),
                              items: const [
                                DropdownMenuItem(value: 'customer_request', child: Text('طلب عميل')),
                                DropdownMenuItem(value: 'defective', child: Text('تالف')),
                                DropdownMenuItem(value: 'wrong_item', child: Text('صنف خطأ')),
                                DropdownMenuItem(value: 'other', child: Text('أخرى')),
                              ],
                              onChanged: (v) => setState(() => _reason = v ?? 'customer_request'),
                            ),
                            const SizedBox(height: 12),
                            const Divider(),
                            ..._lines.map(_buildLine),
                            const Divider(),
                            _buildTotals(),
                            const SizedBox(height: 8),
                            _buildRefundSection(),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _notesCtrl,
                              decoration: const InputDecoration(labelText: 'ملاحظات (اختياري)', border: OutlineInputBorder()),
                              maxLines: 2,
                            ),
                          ],
                        ),
                      ),
      ),
      actions: [
        TextButton(onPressed: _submitting ? null : () => Navigator.pop(context), child: const Text('إلغاء')),
        ElevatedButton(
          onPressed: _submitting || !_hasPick ? null : _submit,
          child: _submitting
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('تأكيد المرتجع'),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- السطر

  Widget _buildLine(ReturnableLine l) {
    final available = l.available;
    final id = l.invoiceItem.id;
    final picked = _picked[id] ?? 0;
    final isFullyReturned = available == 0;
    final condition = _conditionOf(id);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l.product?.name ?? 'صنف ${l.invoiceItem.productId}',
                    style: TextStyle(
                      decoration: isFullyReturned ? TextDecoration.lineThrough : null,
                      color: isFullyReturned ? Colors.grey : null,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (isFullyReturned)
                  const Icon(Icons.block, color: Colors.grey)
                else
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: picked <= 0
                            ? null
                            : () => setState(() {
                                  final nq = picked - 1;
                                  if (nq <= 0) {
                                    _picked.remove(id);
                                  } else {
                                    _picked[id] = nq;
                                  }
                                  _syncRefundAmount();
                                }),
                      ),
                      SizedBox(
                        width: 48,
                        child: TextField(
                          textAlign: TextAlign.center,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: InputDecoration(
                            hintText: '0',
                            isDense: true,
                            border: const OutlineInputBorder(),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                          ),
                          onChanged: (v) {
                            final n = int.tryParse(v) ?? 0;
                            setState(() {
                              if (n <= 0) {
                                _picked.remove(id);
                              } else if (n > available) {
                                _picked[id] = available;
                              } else {
                                _picked[id] = n;
                              }
                              _syncRefundAmount();
                            });
                          },
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: picked >= available
                            ? null
                            : () => setState(() {
                                  _picked[id] = picked + 1;
                                  _syncRefundAmount();
                                }),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'الكمية الأصلية: ${l.invoiceItem.quantity} | تم إرجاع: ${l.alreadyReturned} | متاح: $available',
              style: const TextStyle(fontSize: 12),
            ),
            Text(
              'السعر: ${l.invoiceItem.price.toStringAsFixed(2)}'
              '  الخصم: ${l.invoiceItem.discount.toStringAsFixed(2)}'
              '  الصافي للوحدة: ${_netUnit(l).toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 12),
            ),
            if (isFullyReturned)
              const Text(
                'تم إرجاع هذا الصنف بالكامل',
                style: TextStyle(color: Colors.red, fontSize: 12),
              ),
            // حالة الصنف — بتظهر بس لما الكاشير يختار كمية
            if (picked > 0 && !isFullyReturned) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Text('حالة الصنف: ', style: TextStyle(fontSize: 12)),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: condition,
                      isDense: true,
                      style: const TextStyle(fontSize: 12),
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: SalesReturnService.restockSellable,
                          child: Text('قابل للبيع — يرجع للمخزون'),
                        ),
                        DropdownMenuItem(
                          value: SalesReturnService.restockDamaged,
                          child: Text('تالف — لا يرجع للمخزون'),
                        ),
                        DropdownMenuItem(
                          value: SalesReturnService.restockSupplier,
                          child: Text('يُرسل للمورد'),
                        ),
                      ],
                      onChanged: (v) => setState(
                        () => _conditions[id] = v ?? SalesReturnService.restockSellable,
                      ),
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

  // ------------------------------------------------------------- الإجماليات

  Widget _buildTotals() {
    final t = _total;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('إجمالي المرتجع:', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('${t.toStringAsFixed(2)} ج.م',
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal, fontSize: 16)),
          ],
        ),
        if (_lines.any((l) => (_picked[l.invoiceItem.id] ?? 0) > 0))
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('منهم يرجع للمخزون:', style: TextStyle(fontSize: 12)),
              Text('${_sellableRestockedValue.toStringAsFixed(2)} ج.م',
                  style: const TextStyle(fontSize: 12, color: Colors.green)),
            ],
          ),
      ],
    );
  }

  double get _sellableRestockedValue {
    double t = 0;
    for (final l in _lines) {
      final q = _picked[l.invoiceItem.id] ?? 0;
      if (q <= 0) continue;
      if (_conditionOf(l.invoiceItem.id) != SalesReturnService.restockSellable) continue;
      t += q * _netUnit(l);
    }
    return t;
  }

  // ------------------------------------------------------- قسم الاسترداد

  Widget _buildRefundSection() {
    final remaining = _total - _refundAmount;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.payments_outlined, size: 18),
                const SizedBox(width: 6),
                const Text('الاسترداد', style: TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                Switch(
                  value: _refundEnabled,
                  onChanged: (v) => setState(() {
                    _refundEnabled = v;
                    _syncRefundAmount();
                  }),
                ),
              ],
            ),
            if (_refundEnabled) ...[
              const Text(
                'سيبه زي ما هو لو العميل هيرجع البضاعة بس من غير فلوس دلوقتي.',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _refundAmountCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'المبلغ المسترد',
                  suffixText: 'ج.م',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  helperText: 'قيمة المرتجع ${_total.toStringAsFixed(2)} ج.م',
                  helperStyle: const TextStyle(fontSize: 11),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              RadioGroup<String>(
                groupValue: _refundMethod,
                onChanged: (v) => setState(() => _refundMethod = v ?? RefundMethod.cash),
                child: Column(
                  children: [
                    RadioListTile(
                      value: RefundMethod.cash,
                      title: const Text('نقدي — من الصندوق'),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                    RadioListTile(
                      value: RefundMethod.creditBalance,
                      title: const Text('رصيد للعميل — يصرفه وقت ما يحب'),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      // الفاتورة النقدية مالهاش عميل، فالرصيد مش منطقي.
                      enabled: _hasCreditCustomer,
                    ),
                    RadioListTile(
                      value: RefundMethod.original,
                      title: const Text('نفس طريقة الدفع الأصلية'),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      enabled: _hasCreditCustomer,
                    ),
                  ],
                ),
              ),
              if (_refundAmount > _total + 0.01)
                const Text(
                  'المبلغ أكبر من قيمة المرتجع',
                  style: TextStyle(color: Colors.red, fontSize: 12),
                )
              else if (remaining > 0.01)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('متبقّي للعميل:', style: TextStyle(fontSize: 12)),
                    Text(
                      '${remaining.toStringAsFixed(2)} ج.م',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange),
                    ),
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }
}