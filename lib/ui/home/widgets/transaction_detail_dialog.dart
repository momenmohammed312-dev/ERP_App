import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/ui/widgets/invoice_items_table.dart';

const Color _bgDark = Color(0xFF0D1117);
const Color _gold = Color(0xFFC9A84C);
const Color _border = Color(0xFF30363D);
const Color _textMuted = Color(0xFF7D8590);

class TransactionDetailDialog extends StatefulWidget {
  final AppDatabase db;
  final LedgerTransaction transaction;
  final String entityType;

  const TransactionDetailDialog({
    super.key,
    required this.db,
    required this.transaction,
    required this.entityType,
  });

  @override
  State<TransactionDetailDialog> createState() =>
      _TransactionDetailDialogState();
}

class _TransactionDetailDialogState extends State<TransactionDetailDialog> {
  List<InvoiceItemDisplayModel> _items = [];
  bool _isLoading = true;

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
              _infoRow('المبلغ', '${(isDebit ? t.debit : t.credit).toStringAsFixed(2)} ج.م'),
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
        if (invoiceId != null) ...[
          TextButton.icon(
            onPressed: () => _viewInvoice(context, invoiceId),
            icon: const Icon(Icons.visibility, size: 18),
            label: const Text('عرض الفاتورة'),
            style: TextButton.styleFrom(foregroundColor: _gold),
          ),
          TextButton.icon(
            onPressed: () => _editInvoice(context, invoiceId),
            icon: const Icon(Icons.edit, size: 18),
            label: const Text('تعديل'),
            style: TextButton.styleFrom(foregroundColor: Colors.blue),
          ),
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

  void _viewInvoice(BuildContext context, int id) {
    Navigator.pop(context);
    // Navigate to invoice view page
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('عرض الفاتورة رقم $id')),
    );
  }

  void _editInvoice(BuildContext context, int id) {
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تعديل الفاتورة رقم $id')),
    );
  }

  void _refundInvoice(BuildContext context, int id) {
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('استرجاع الفاتورة رقم $id')),
    );
  }
}
