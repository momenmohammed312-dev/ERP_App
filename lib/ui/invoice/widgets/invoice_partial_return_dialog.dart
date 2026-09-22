import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/services/sales_return_service.dart';

/// ديالوج المرتجع الجزئي — اختيار صنف أو أكثر بكمية جزئية
class InvoicePartialReturnDialog extends StatefulWidget {
  final AppDatabase db;
  final int invoiceId;
  final VoidCallback? onDone;

  const InvoicePartialReturnDialog({
    super.key,
    required this.db,
    required this.invoiceId,
    this.onDone,
  });

  @override
  State<InvoicePartialReturnDialog> createState() => _InvoicePartialReturnDialogState();
}

class _InvoicePartialReturnDialogState extends State<InvoicePartialReturnDialog> {
  late final SalesReturnService _service;
  List<ReturnableLine> _lines = [];
  final Map<int, int> _picked = {}; // invoiceItemId -> qty
  String _reason = 'customer_request';
  final _notesCtrl = TextEditingController();
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _service = SalesReturnService(widget.db);
    _load();
  }

  Future<void> _load() async {
    try {
      final lines = await _service.getReturnableLines(widget.invoiceId);
      if (!mounted) return;
      setState(() {
        _lines = lines;
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

  double get _total {
    double t = 0;
    for (final l in _lines) {
      final q = _picked[l.invoiceItem.id] ?? 0;
      if (q <= 0) continue;
      final netUnit = l.invoiceItem.price - (l.invoiceItem.discount / l.invoiceItem.quantity);
      t += q * netUnit;
    }
    return t;
  }

  bool get _hasPick => _picked.values.any((q) => q > 0);

  Future<void> _submit() async {
    if (!_hasPick) return;
    setState(() => _submitting = true);
    try {
      await _service.processPartialReturn(
        invoiceId: widget.invoiceId,
        itemReturns: Map<int, int>.from(_picked),
        reason: _reason,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      );
      if (!mounted) return;
      Navigator.pop(context, true);
      widget.onDone?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تسجيل المرتجع الجزئي بنجاح'), backgroundColor: Colors.green),
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
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('مرتجع جزئي — اختر الأصناف'),
      content: SizedBox(
        width: 620,
        child: _loading
            ? const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
            : _error != null
                ? Text(_error!, style: const TextStyle(color: Colors.red))
                : _lines.isEmpty
                    ? const Text('لا توجد أصناف في الفاتورة')
                    : SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // سبب عام
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
                            TextField(
                              controller: _notesCtrl,
                              decoration: const InputDecoration(labelText: 'ملاحظات (اختياري)', border: OutlineInputBorder()),
                              maxLines: 2,
                            ),
                            const SizedBox(height: 12),
                            const Divider(),
                            ..._lines.map((l) {
                              final available = l.available;
                              final picked = _picked[l.invoiceItem.id] ?? 0;
                              final isFullyReturned = available == 0;
                              return Card(
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                child: ListTile(
                                  title: Text(l.product?.name ?? 'صنف ${l.invoiceItem.productId}',
                                      style: TextStyle(
                                          decoration: isFullyReturned ? TextDecoration.lineThrough : null,
                                          color: isFullyReturned ? Colors.grey : null)),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                          'الكمية الأصلية: ${l.invoiceItem.quantity} | تم إرجاع: ${l.alreadyReturned} | متاح: $available'),
                                      Text(
                                          'السعر: ${l.invoiceItem.price.toStringAsFixed(2)}  الخصم: ${l.invoiceItem.discount.toStringAsFixed(2)}  الصافي: ${(l.invoiceItem.price - l.invoiceItem.discount / (l.invoiceItem.quantity == 0 ? 1 : l.invoiceItem.quantity)).toStringAsFixed(2)}'),
                                      if (isFullyReturned)
                                        const Text('تم إرجاع هذا الصنف بالكامل', style: TextStyle(color: Colors.red, fontSize: 12)),
                                    ],
                                  ),
                                  trailing: isFullyReturned
                                      ? const Icon(Icons.block, color: Colors.grey)
                                      : Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              icon: const Icon(Icons.remove_circle_outline),
                                              onPressed: picked <= 0
                                                  ? null
                                                  : () => setState(() {
                                                        final nq = picked - 1;
                                                        if (nq <= 0) {
                                                          _picked.remove(l.invoiceItem.id);
                                                        } else {
                                                          _picked[l.invoiceItem.id] = nq;
                                                        }
                                                      }),
                                            ),
                                            SizedBox(
                                              width: 48,
                                              child: TextField(
                                                textAlign: TextAlign.center,
                                                keyboardType: TextInputType.number,
                                                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                                                controller: TextEditingController(text: picked == 0 ? '' : '$picked'),
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
                                                      _picked.remove(l.invoiceItem.id);
                                                    } else if (n > available) {
                                                      _picked[l.invoiceItem.id] = available;
                                                    } else {
                                                      _picked[l.invoiceItem.id] = n;
                                                    }
                                                  });
                                                },
                                              ),
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.add_circle_outline),
                                              onPressed: picked >= available
                                                  ? null
                                                  : () => setState(() => _picked[l.invoiceItem.id] = picked + 1),
                                            ),
                                          ],
                                        ),
                                ),
                              );
                            }),
                            const Divider(),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('إجمالي المرتجع:', style: TextStyle(fontWeight: FontWeight.bold)),
                                Text('${_total.toStringAsFixed(2)} ج.م',
                                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal, fontSize: 16)),
                              ],
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
}
