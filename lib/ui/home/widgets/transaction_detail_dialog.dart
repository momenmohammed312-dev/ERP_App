import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/services/printer_service.dart';
import 'package:pos_offline_desktop/ui/widgets/invoice_items_table.dart';
import 'package:pos_offline_desktop/ui/customer/edit_payment_dialog.dart';
import 'package:pos_offline_desktop/ui/invoice/edit_invoice_page.dart';
import 'package:pos_offline_desktop/ui/invoice/widgets/invoice_partial_return_dialog.dart';
import 'package:pos_offline_desktop/core/services/invoice_number_formatter.dart';

const Color _bgDark = Color(0xFF0D1117);
const Color _gold = Color(0xFFC9A84C);
const Color _border = Color(0xFF30363D);
const Color _textMuted = Color(0xFF7D8590);

class TransactionDetailDialog extends StatefulWidget {
  final AppDatabase db;
  final LedgerTransaction transaction;
  final String entityType;
  final VoidCallback? onChanged;

  const TransactionDetailDialog({
    super.key,
    required this.db,
    required this.transaction,
    required this.entityType,
    this.onChanged,
  });

  @override
  State<TransactionDetailDialog> createState() =>
      _TransactionDetailDialogState();
}

class _TransactionDetailDialogState extends State<TransactionDetailDialog> {
  List<InvoiceItemDisplayModel> _items = [];
  bool _isLoading = true;

  bool get _isPayment =>
      widget.transaction.origin == 'payment' ||
      widget.transaction.origin == 'reversal';

  bool get _isSale => widget.entityType == 'Customer';

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    try {
      int? invoiceId;
      final receiptNum = widget.transaction.receiptNumber;
      if (receiptNum != null && receiptNum.isNotEmpty) {
        final inv = await widget.db.invoiceDao.getInvoiceByNumber(receiptNum);
        if (inv != null) invoiceId = inv.id;
      }

      if (invoiceId == null && widget.transaction.description.contains('#')) {
        final match =
            RegExp(r'#(\d+)').firstMatch(widget.transaction.description);
        if (match != null) {
          final id = int.tryParse(match.group(1) ?? '');
          if (id != null) {
            invoiceId = id;
          }
        }
      }

      if (invoiceId != null) {
        final items = await widget.db.invoiceDao
            .getItemsWithProductsByInvoice(invoiceId);
        setState(() {
          _items = items.map((e) {
            final item = e.$1;
            final product = e.$2;
            return InvoiceItemDisplayModel(
              productName: product?.name ?? 'منتج ${item.productId}',
              quantity: item.quantity.toDouble(),
              unitPrice:
                  item.quantity > 0 ? item.price / item.quantity : item.price,
              total: item.price,
              unit: product?.unit,
            );
          }).toList();
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Error loading transaction items: $e');
      setState(() => _isLoading = false);
    }
  }

  int? _extractInvoiceId() {
    final receiptNum = widget.transaction.receiptNumber;
    if (receiptNum != null && receiptNum.isNotEmpty) {
      final match = RegExp(r'(\d+)').firstMatch(receiptNum);
      if (match != null) return int.tryParse(match.group(0) ?? '');
    }
    final desc = widget.transaction.description;
    final match = RegExp(r'#(\d+)').firstMatch(desc);
    if (match != null) return int.tryParse(match.group(1) ?? '');
    return null;
  }

  void _notifyChanged() {
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.transaction;
    final isDebit = t.debit > 0;
    final isCustomer = widget.entityType == 'Customer';
    final isLiability = isCustomer ? isDebit : t.credit > 0;
    final invoiceId = _extractInvoiceId();

    return AlertDialog(
      backgroundColor: _bgDark,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: _border),
      ),
      title: Row(
        children: [
          Icon(
            isLiability ? Icons.shopping_cart : Icons.payment,
            color: isLiability ? Colors.red : Colors.green,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isLiability ? 'مشتريات' : 'سداد',
              style: const TextStyle(color: Colors.white, fontSize: 18),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _infoRow('التاريخ',
                  DateFormat('yyyy/MM/dd HH:mm').format(t.date)),
              _infoRow('المبلغ',
                  '${(isDebit ? t.debit : t.credit).toStringAsFixed(2)} ج.م'),
              _infoRow('البيان', t.description),
              if (t.receiptNumber != null && t.receiptNumber!.isNotEmpty)
                _infoRow('رقم الفاتورة', t.receiptNumber!),
              if (t.paymentMethod != null && t.paymentMethod!.isNotEmpty)
                _infoRow('طريقة الدفع', t.paymentMethod!),
              const Divider(color: _border),
              const Text(
                'تفاصيل المنتجات',
                style: TextStyle(
                  color: _gold,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 8),
              if (_isLoading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(color: _gold),
                  ),
                )
              else if (_items.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'لا توجد تفاصيل منتجات',
                    style: TextStyle(color: _textMuted),
                  ),
                )
              else
                InvoiceItemsTable(items: _items),
            ],
          ),
        ),
      ),
      actions: [
        if (_isPayment) ...[
          TextButton.icon(
            onPressed: () => _openEditPayment(context),
            icon: const Icon(Icons.edit, size: 18),
            label: const Text('تعديل الدفعة'),
            style: TextButton.styleFrom(foregroundColor: Colors.blue),
          ),
        ] else if (invoiceId != null) ...[
          TextButton.icon(
            onPressed: () => _showInvoiceDetail(context, invoiceId),
            icon: const Icon(Icons.visibility, size: 18),
            label: const Text('عرض الفاتورة'),
            style: TextButton.styleFrom(foregroundColor: _gold),
          ),
          if (_isSale)
            TextButton.icon(
              onPressed: () => _openEditInvoice(context, invoiceId),
              icon: const Icon(Icons.edit_note, size: 18),
              label: const Text('تعديل الفاتورة'),
              style: TextButton.styleFrom(foregroundColor: Colors.blue),
            ),
          if (_isSale)
            TextButton.icon(
              onPressed: () => _refundInvoice(context, invoiceId),
              icon: const Icon(Icons.undo, size: 18),
              label: const Text('استرجاع'),
              style: TextButton.styleFrom(foregroundColor: Colors.orange),
            ),
        ],
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إغلاق', style: TextStyle(color: _textMuted)),
        ),
      ],
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(color: _textMuted, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  void _openEditPayment(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => EditPaymentDialog(
        db: widget.db,
        transaction: widget.transaction,
        onSaved: () {
          _notifyChanged();
        },
      ),
    );
  }

  void _openEditInvoice(BuildContext context, int? invoiceId) {
    if (invoiceId == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditInvoicePage(
          db: widget.db,
          invoiceId: invoiceId,
          onSaved: () {
            _notifyChanged();
            if (context.mounted) Navigator.pop(context);
          },
        ),
      ),
    );
  }

  void _showInvoiceDetail(BuildContext context, int? invoiceId) async {
    if (invoiceId == null) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _InvoiceDetailView(db: widget.db, invoiceId: invoiceId),
    );
  }

  void _refundInvoice(BuildContext context, int? invoiceId) async {
    if (invoiceId == null) return;
    // مرتجع جزئي على مستوى الصنف — اختيار كمية لكل صنف
    final done = await showDialog<bool>(
      context: context,
      builder: (ctx) => InvoicePartialReturnDialog(
        db: widget.db,
        invoiceId: invoiceId,
        onDone: _notifyChanged,
      ),
    );
    if (done == true && context.mounted) {
      // إغلاق ديالوج التفاصيل بعد نجاح المرتجع ليتحدث الـ list
      Navigator.pop(context);
    }
  }
}

class _InvoiceDetailView extends StatefulWidget {
  final AppDatabase db;
  final int invoiceId;

  const _InvoiceDetailView({required this.db, required this.invoiceId});

  @override
  State<_InvoiceDetailView> createState() => _InvoiceDetailViewState();
}

class _InvoiceDetailViewState extends State<_InvoiceDetailView> {
  Invoice? _invoice;
  List<InvoiceItemDisplayModel> _items = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final invoice = await widget.db.invoiceDao.getInvoiceById(widget.invoiceId);
      final itemsWithProducts = await widget.db.invoiceDao
          .getItemsWithProductsByInvoice(widget.invoiceId);
      setState(() {
        _invoice = invoice;
        _items = itemsWithProducts.map((e) {
          final item = e.$1;
          final product = e.$2;
          return InvoiceItemDisplayModel(
            productName: product?.name ?? 'منتج ${item.productId}',
            quantity: item.quantity.toDouble(),
            unitPrice: item.quantity > 0 ? item.price / item.quantity : item.price,
            total: item.price,
            unit: product?.unit,
          );
        }).toList();
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading invoice: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _print() async {
    if (_invoice == null) return;
    try {
      final itemsMaps = _items.map((item) {
        return {
          'productName': item.productName,
          'name': item.productName,
          'quantity': item.quantity,
          'price': item.unitPrice,
          'total': item.total,
        };
      }).toList();

      await PrinterService.autoPrintInvoice(
        invoice: {
          'id': _invoice!.id,
          'customerName': _invoice!.customerName,
          'date': _invoice!.date,
          'totalAmount': _invoice!.totalAmount,
          'paymentMethod': _invoice!.paymentMethod,
        },
        items: itemsMaps,
        paymentMethod: _invoice!.paymentMethod ?? 'cash',
        ledgerDao: widget.db.ledgerDao,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في الطباعة: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: _bgDark,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: _border),
      ),
      title: const Text('تفاصيل الفاتورة', style: TextStyle(color: Colors.white)),
      content: SizedBox(
        width: 520,
        child: _isLoading
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(color: _gold),
                ),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_invoice != null) ...[
                      _row('رقم الفاتورة',
                          displayInvoiceNumber(_invoice!.invoiceNumber, _invoice!.id) ?? '...'),
                      _row('العميل', _invoice!.customerName ?? '—'),
                      _row('التاريخ',
                          DateFormat('yyyy/MM/dd HH:mm').format(_invoice!.date)),
                      _row('طريقة الدفع', _invoice!.paymentMethod ?? '—'),
                      _row('الإجمالي',
                          '${_invoice!.totalAmount.toStringAsFixed(2)} ج.م'),
                      const Divider(color: _border),
                    ],
                    if (_items.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('لا توجد أصناف',
                            style: TextStyle(color: _textMuted)),
                      )
                    else
                      InvoiceItemsTable(items: _items),
                  ],
                ),
              ),
      ),
      actions: [
        if (_invoice != null)
          TextButton.icon(
            onPressed: _print,
            icon: const Icon(Icons.print, size: 18),
            label: const Text('طباعة'),
            style: TextButton.styleFrom(foregroundColor: _gold),
          ),
        if (_invoice != null && _invoice!.status != 'voided' && _invoice!.status != 'draft')
          TextButton.icon(
            onPressed: () async {
              final done = await showDialog<bool>(
                context: context,
                builder: (ctx) => InvoicePartialReturnDialog(
                  db: widget.db,
                  invoiceId: widget.invoiceId,
                ),
              );
              if (done == true && context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تم تسجيل المرتجع'), backgroundColor: Colors.green),
                );
              }
            },
            icon: const Icon(Icons.undo, size: 18),
            label: const Text('مرتجع جزئي'),
            style: TextButton.styleFrom(foregroundColor: Colors.orange),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إغلاق', style: TextStyle(color: _textMuted)),
        ),
      ],
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(label,
                style: const TextStyle(color: _textMuted, fontSize: 13)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(color: Colors.white, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
