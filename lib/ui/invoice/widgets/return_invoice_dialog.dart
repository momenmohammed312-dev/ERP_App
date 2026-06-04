import 'package:flutter/material.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';

class ReturnInvoiceDialog extends StatefulWidget {
  final AppDatabase db;
  final Function(Invoice) onInvoiceCreated;
  final String? currentUserId;

  const ReturnInvoiceDialog({
    super.key,
    required this.db,
    required this.onInvoiceCreated,
    this.currentUserId,
  });

  @override
  State<ReturnInvoiceDialog> createState() => _ReturnInvoiceDialogState();
}

class _ReturnInvoiceDialogState extends State<ReturnInvoiceDialog> {
  final _formKey = GlobalKey<FormState>();
  final _customerController = TextEditingController();
  final _originalInvoiceController = TextEditingController();
  final _reasonController = TextEditingController();
  final List<Map<String, dynamic>> _items = [];
  double _subtotal = 0.0;
  double _refundAmount = 0.0;
  Invoice? _selectedOriginalInvoice;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('فاتورة مرتجع'),
      content: SizedBox(
        width: 500,
        height: 600,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Original Invoice Selection
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  children: [
                    const Icon(Icons.receipt_long, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: _originalInvoiceController,
                        decoration: const InputDecoration(
                          labelText: 'رقم الفاتورة الأصلية',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.search),
                        ),
                        readOnly: true,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.search),
                      onPressed: _searchOriginalInvoice,
                      tooltip: 'البحث عن الفاتورة',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // Customer Selection
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  children: [
                    const Icon(Icons.person, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: _customerController,
                        decoration: const InputDecoration(
                          labelText: 'العميل',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.search),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: _showCustomerSelection,
                      tooltip: 'إضافة عميل جديد',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // Return Reason
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: TextFormField(
                  controller: _reasonController,
                  decoration: const InputDecoration(
                    labelText: 'سبب المرتجع',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                  validator: (v) => v == null || v.trim().isEmpty ? 'يرجى إدخال سبب المرتجع' : null,
                ),
              ),
              const SizedBox(height: 16),

              // Items Section
              Expanded(
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('المنتجات المرتجعة'),
                        IconButton(
                          icon: const Icon(Icons.add),
                          onPressed: _addItem,
                          tooltip: 'إضافة منتج',
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Expanded(child: _buildItemsList()),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Totals Section
              _buildTotalsSection(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(onPressed: _saveReturnInvoice, child: const Text('حفظ')),
      ],
    );
  }

  Widget _buildItemsList() {
    if (_items.isEmpty) {
      return Center(
        child: Text(
          'لا توجد منتجات. أضف منتجاً باستخدام الزر +',
          style: TextStyle(color: Colors.grey.shade600),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListView.builder(
        itemCount: _items.length,
        itemBuilder: (context, index) {
          return Card(
            margin: const EdgeInsets.all(4),
            child: ListTile(
              leading: const Icon(
                Icons.assignment_return,
                color: Colors.orange,
              ),
              title: TextFormField(
                initialValue: _items[index]['name'] ?? '',
                decoration: const InputDecoration(
                  labelText: 'اسم المنتج',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) {
                  setState(() {
                    _items[index]['name'] = value;
                  });
                },
              ),
              subtitle: Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      initialValue: (_items[index]['price'] ?? 0)
                          .toStringAsFixed(2),
                      decoration: const InputDecoration(
                        labelText: 'السعر (ج.م)',
                        border: OutlineInputBorder(),
                        prefixText: 'ج.م ',
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (value) {
                        setState(() {
                          _items[index]['price'] =
                              double.tryParse(value) ?? 0.0;
                        });
                        _calculateTotals();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 80,
                    child: TextFormField(
                      initialValue: (_items[index]['quantity'] ?? 1).toString(),
                      decoration: const InputDecoration(
                        labelText: 'الكمية',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: (value) => _updateItemQuantity(index, value),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: () => _removeItem(index),
                    tooltip: 'حذف',
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTotalsSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          _buildTotalRow('الإجمالي المرتجع:', _subtotal),
          const Divider(),
          _buildTotalRow('المبلغ المسترد:', _refundAmount),
        ],
      ),
    );
  }

  Widget _buildTotalRow(String label, double amount) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(
            '${amount.toStringAsFixed(2)} ج.م',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  void _addItem() {
    setState(() {
      _items.add({'name': 'منتج مرتجع', 'price': 0.0, 'quantity': 1, 'productId': 1}); // Added dummy productId for testing
    });
    _calculateTotals();
  }

  void _removeItem(int index) {
    setState(() {
      _items.removeAt(index);
    });
    _calculateTotals();
  }

  void _updateItemQuantity(int index, String? value) {
    final quantity = int.tryParse(value ?? '1') ?? 1;
    setState(() {
      _items[index]['quantity'] = quantity;
    });
    _calculateTotals();
  }

  void _calculateTotals() {
    _subtotal = _items.fold(0.0, (sum, item) {
      final price =
          (item['price'] as double? ?? 0.0) * (item['quantity'] as int? ?? 1);
      return sum + price;
    });

    _refundAmount = _subtotal;
  }

  void _searchOriginalInvoice() async {
    final controller = TextEditingController();
    final invoices = await widget.db.invoiceDao.getAllInvoices();
    List<Invoice> filtered = invoices;

    final result = await showDialog<Invoice>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('بحث عن الفاتورة الأصلية'),
          content: SizedBox(
            width: 500,
            height: 400,
            child: Column(
              children: [
                TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    hintText: 'رقم الفاتورة أو اسم العميل',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    setDialogState(() {
                      final q = value.trim().toLowerCase();
                      if (q.isEmpty) {
                        filtered = invoices;
                      } else {
                        filtered = invoices.where((inv) =>
                          (inv.invoiceNumber?.toLowerCase().contains(q) ?? false) ||
                          (inv.customerName?.toLowerCase().contains(q) ?? false)
                        ).toList();
                      }
                    });
                  },
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (ctx, i) {
                      final inv = filtered[i];
                      return ListTile(
                        title: Text('${inv.invoiceNumber ?? inv.id}'),
                        subtitle: Text('${inv.customerName ?? "نقدي"} - ${inv.totalAmount.toStringAsFixed(2)} ج.م'),
                        trailing: Text(inv.status),
                        onTap: () => Navigator.of(ctx).pop(inv),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('إلغاء'),
            ),
          ],
        ),
      ),
    );

    if (result != null) {
      setState(() {
        _selectedOriginalInvoice = result;
        _originalInvoiceController.text = '${result.invoiceNumber ?? result.id} - ${result.customerName ?? "نقدي"}';
        _customerController.text = result.customerName ?? '';
      });
    }
  }

  void _showCustomerSelection() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('اختيار عميل'),
        content: const Text('وظيفة اختيار العميل غير مفعلة حالياً.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  void _saveReturnInvoice() async {
    if (_formKey.currentState?.validate() ?? false) {
      try {
        if (_items.isEmpty) {
           ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('الرجاء إضافة منتجات أولا'), backgroundColor: Colors.red),
          );
          return;
        }

        if (_selectedOriginalInvoice == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('الرجاء البحث عن الفاتورة الأصلية'), backgroundColor: Colors.red),
          );
          return;
        }

        final now = DateTime.now();
        final originalInvoice = _selectedOriginalInvoice!;
        final customerName = _customerController.text.trim().isEmpty ? 'عميل نقدي' : _customerController.text.trim();
        final originalInvoiceId = originalInvoice.id;

        // Build return items companions
        final returnItems = _items.map((item) => SalesReturnItemsCompanion.insert(
          productId: int.tryParse(item['productId']?.toString() ?? '1') ?? 1,
          productName: item['name']?.toString() ?? '',
          quantity: item['quantity'] as int,
          unitPrice: item['price'] as double,
          totalPrice: (item['quantity'] as int) * (item['price'] as double),
        )).toList();

        // Create return companion
        final returnCompanion = SalesReturnsCompanion.insert(
          returnNumber: 'RET-${now.millisecondsSinceEpoch}',
          originalInvoiceId: originalInvoiceId,
          customerName: customerName,
          totalAmount: _refundAmount,
          returnDate: now,
          returnReason: _reasonController.text.trim(),
        );

        // Use processReturn() which restores stock in a transaction
        final insertedId = await widget.db.salesReturnsDao.processReturn(
          returnCompanion: returnCompanion,
          items: returnItems,
        );

        // Create ledger reversal entry (credit for customer — reduces what they owe)
        await widget.db.ledgerDao.insertTransaction(
          LedgerTransactionsCompanion.insert(
            id: 'REV-${now.millisecondsSinceEpoch}-$insertedId',
            entityType: 'Customer',
            refId: originalInvoice.customerId ?? originalInvoiceId.toString(),
            date: now,
            description: 'مرتجع فاتورة رقم ${originalInvoice.invoiceNumber ?? originalInvoiceId.toString()}',
            credit: _refundAmount,
            debit: 0.0,
            origin: 'reversal',
            paymentMethod: const Value(null),
            receiptNumber: Value('RET-$insertedId'),
            lockBatch: const Value(null),
          ),
        );

        // Update original invoice paidAmount and status
        final newPaidAmount = (originalInvoice.paidAmount - _refundAmount).clamp(0.0, originalInvoice.totalAmount);
        String newStatus;
        if (newPaidAmount <= 0) {
          newStatus = 'pending';
        } else if (newPaidAmount < originalInvoice.totalAmount) {
          newStatus = 'partial';
        } else {
          newStatus = 'paid';
        }

        await widget.db.invoiceDao.updateInvoice(
          originalInvoice.copyWith(
            paidAmount: newPaidAmount,
            status: newStatus,
          ),
        );

        final messengerContext = context;
        if (messengerContext.mounted) {
          Navigator.of(messengerContext).pop();
          ScaffoldMessenger.of(messengerContext).showSnackBar(
            const SnackBar(
              content: Text('تم حفظ المرتجع بنجاح'),
              backgroundColor: Colors.green,
            ),
          );
        }

        // Notify parent with a return invoice object
        final returnInvoice = Invoice(
          id: insertedId,
          invoiceNumber: 'RET-$insertedId',
          customerName: customerName,
          totalAmount: _refundAmount,
          paidAmount: _refundAmount,
          date: now,
          status: 'return',
        );
        widget.onInvoiceCreated(returnInvoice);
      } catch (e) {
        final messengerContext = context;
        if (messengerContext.mounted) {
          ScaffoldMessenger.of(messengerContext).showSnackBar(
            SnackBar(
              content: Text('خطأ في حفظ المرتجع: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  void dispose() {
    _customerController.dispose();
    _originalInvoiceController.dispose();
    _reasonController.dispose();
    super.dispose();
  }
}
