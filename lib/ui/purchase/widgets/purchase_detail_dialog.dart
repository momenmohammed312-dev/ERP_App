import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';

import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/provider/auth_provider.dart';
import 'package:pos_offline_desktop/core/services/invoice_number_formatter.dart';
import 'package:pos_offline_desktop/core/services/purchase_print_service_simple.dart';
import 'package:pos_offline_desktop/core/services/purchase_return_service.dart';
import 'package:pos_offline_desktop/core/services/document_date_service.dart';
import 'package:pos_offline_desktop/ui/widgets/document_date_picker.dart';
import 'enhanced_purchase_invoice_page.dart';
import 'void_purchase_dialog.dart';

/// Supplier purchase detail (عرض/تعديل/استرجاع/حذف) — mirrors the customer
/// invoice detail dialog. Loads lines with product names on open.
class PurchaseDetailDialog extends ConsumerStatefulWidget {
  final AppDatabase db;
  final String purchaseId;
  final VoidCallback? onChanged;

  const PurchaseDetailDialog({
    super.key,
    required this.db,
    required this.purchaseId,
    this.onChanged,
  });

  @override
  ConsumerState<PurchaseDetailDialog> createState() =>
      _PurchaseDetailDialogState();
}

class _PurchaseDetailDialogState extends ConsumerState<PurchaseDetailDialog> {
  bool _loading = true;
  String? _error;
  Purchase? _purchase;
  String _supplierName = '—';
  List<(PurchaseItem, Product?)> _lines = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final purchase = await (widget.db.select(widget.db.purchases)
            ..where((t) => t.id.equals(widget.purchaseId)))
          .getSingleOrNull();
      if (purchase == null) throw Exception('فاتورة المشتريات غير موجودة');
      String supplierName = '—';
      if (purchase.supplierId != null) {
        final s = await widget.db.supplierDao.getSupplierById(
          purchase.supplierId!,
        );
        if (s != null) supplierName = s.name;
      }
      final lines = await widget.db.purchaseDao
          .getItemsWithProductsByPurchase(purchase.invoiceNumber);
      if (!mounted) return;
      setState(() {
        _purchase = purchase;
        _supplierName = supplierName;
        _lines = lines;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _print() async {
    try {
      await PurchasePrintService(
        widget.db,
      ).printTextPurchase(db: widget.db, purchaseId: widget.purchaseId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ في الطباعة: $e')),
      );
    }
  }

  Future<void> _edit() async {
    Navigator.of(context).pop();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EnhancedPurchaseInvoicePage(
          db: widget.db,
          purchaseId: widget.purchaseId,
        ),
      ),
    );
    widget.onChanged?.call();
    if (mounted) _load();
  }

  Future<void> _return() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _PurchaseReturnDialog(
        db: widget.db,
        purchaseId: widget.purchaseId,
        lines: _lines,
      ),
    );
    if (result == true) {
      widget.onChanged?.call();
      if (mounted) _load();
    }
  }

  Future<void> _voidPurchase() async {
    final username = ref.read(authProvider)?.username ?? 'admin';
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => VoidPurchaseDialog(
        db: widget.db,
        purchaseId: widget.purchaseId,
        voidedBy: username,
        onDone: () {
          widget.onChanged?.call();
        },
      ),
    );
    if (result == true && mounted) {
      Navigator.of(context).pop(true);
      widget.onChanged?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isVoided =
        _purchase?.isDeleted == true || _purchase?.status == 'Voided';

    return AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('تفاصيل فاتورة المشتريات'),
          if (isVoided)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.redAccent),
              ),
              child: const Text(
                'ملغاة',
                style: TextStyle(
                  color: Colors.red,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: _loading
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              )
            : _error != null
                ? Text(_error!)
                : SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _row(
                          'رقم الفاتورة',
                          displayInvoiceNumber(
                                _purchase!.invoiceNumber,
                                null,
                              ) ??
                              '',
                        ),
                        _row('المورد', _supplierName),
                        _row(
                          'التاريخ',
                          DateFormat(
                            'yyyy/MM/dd HH:mm',
                          ).format(_purchase!.purchaseDate),
                        ),
                        _row(
                          'الإجمالي',
                          '${_purchase!.totalAmount.toStringAsFixed(2)} ج.م',
                        ),
                        _row(
                          'المدفوع',
                          '${_purchase!.paidAmount.toStringAsFixed(2)} ج.م',
                        ),
                        _row(
                          'المتبقي',
                          '${(_purchase!.totalAmount - _purchase!.paidAmount).toStringAsFixed(2)} ج.م',
                        ),
                        _row('الحالة', _purchase!.status),
                        const Divider(),
                        const Text(
                          'الأصناف',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const Gap(8),
                        if (_lines.isEmpty)
                          const Text('لا توجد أصناف'),
                        for (final pair in _lines)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    pair.$2?.name ?? 'منتج ${pair.$1.productId}',
                                  ),
                                ),
                                Text(
                                  '${pair.$1.quantity} × ${pair.$1.unitPrice.toStringAsFixed(2)} = ${pair.$1.totalPrice.toStringAsFixed(2)}',
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إغلاق'),
        ),
        if (_purchase != null && !isVoided)
          TextButton.icon(
            onPressed: () async {
              final newDate = await pickDocumentDate(
                context: context,
                db: widget.db,
                initialDate: _purchase!.purchaseDate,
              );
              if (newDate != null) {
                await DocumentDateService(widget.db).updatePurchaseDate(
                  purchaseId: _purchase!.id,
                  newDate: newDate,
                );
                if (mounted) {
                  _load();
                  widget.onChanged?.call();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('تم تعديل تاريخ فاتورة المشتريات بنجاح'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                }
              }
            },
            icon: const Icon(Icons.edit_calendar, size: 18),
            label: const Text('تعديل التاريخ'),
            style: TextButton.styleFrom(foregroundColor: Colors.blue),
          ),
        TextButton.icon(
          onPressed: _loading || _error != null ? null : _print,
          icon: const Icon(Icons.print, size: 18),
          label: const Text('عرض'),
        ),
        TextButton.icon(
          onPressed: _loading || _error != null || isVoided ? null : _edit,
          icon: const Icon(Icons.edit, size: 18),
          label: const Text('تعديل'),
        ),
        TextButton.icon(
          onPressed: _loading || _error != null || isVoided ? null : _return,
          icon: const Icon(Icons.undo, size: 18),
          label: const Text('استرجاع'),
          style: TextButton.styleFrom(foregroundColor: Colors.orange),
        ),
        TextButton.icon(
          onPressed: _loading || _error != null || isVoided ? null : _voidPurchase,
          icon: const Icon(Icons.delete_outline, size: 18),
          label: const Text('حذف الفاتورة'),
          style: TextButton.styleFrom(foregroundColor: Colors.red),
        ),
      ],
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

/// Per-line return quantities, capped at each line's current quantity.
class _PurchaseReturnDialog extends StatefulWidget {
  final AppDatabase db;
  final String purchaseId;
  final List<(PurchaseItem, Product?)> lines;

  const _PurchaseReturnDialog({
    required this.db,
    required this.purchaseId,
    required this.lines,
  });

  @override
  State<_PurchaseReturnDialog> createState() => _PurchaseReturnDialogState();
}

class _PurchaseReturnDialogState extends State<_PurchaseReturnDialog> {
  late Map<String, int> _qty;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _qty = {for (final p in widget.lines) p.$1.id: 0};
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('استرجاع مشتريات'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final pair in widget.lines)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${pair.$2?.name ?? 'منتج ${pair.$1.productId}'} (المتاح: ${pair.$1.quantity})',
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.remove),
                        onPressed: _busy
                            ? null
                            : () => setState(() {
                                  final cur = _qty[pair.$1.id] ?? 0;
                                  if (cur > 0) _qty[pair.$1.id] = cur - 1;
                                }),
                      ),
                      Text('${_qty[pair.$1.id] ?? 0}'),
                      IconButton(
                        icon: const Icon(Icons.add),
                        onPressed: _busy
                            ? null
                            : () => setState(() {
                                  final cur = _qty[pair.$1.id] ?? 0;
                                  if (cur < pair.$1.quantity) {
                                    _qty[pair.$1.id] = cur + 1;
                                  }
                                }),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          onPressed: _busy
              ? null
              : () async {
                  setState(() => _busy = true);
                  try {
                    final value = await PurchaseReturnService(
                      widget.db,
                    ).processReturn(
                      purchaseId: widget.purchaseId,
                      itemReturns: _qty,
                    );
                    if (!context.mounted) return;
                    Navigator.of(context).pop(true);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          value > 0
                              ? 'تم الاسترجاع: ${value.toStringAsFixed(2)} ج.م'
                              : 'لا توجد كميات مرتجعة',
                        ),
                        backgroundColor:
                            value > 0 ? Colors.green : Colors.orange,
                      ),
                    );
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('خطأ: $e')),
                    );
                    setState(() => _busy = false);
                  }
                },
          child: const Text('تأكيد الاسترجاع'),
        ),
      ],
    );
  }
}
