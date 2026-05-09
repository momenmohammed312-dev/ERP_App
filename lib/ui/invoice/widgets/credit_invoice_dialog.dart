import 'package:flutter/material.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';

class CreditInvoiceDialog extends StatefulWidget {
  final AppDatabase db;
  final Function(Invoice) onInvoiceCreated;

  const CreditInvoiceDialog({
    super.key,
    required this.db,
    required this.onInvoiceCreated,
  });

  @override
  State<CreditInvoiceDialog> createState() => _CreditInvoiceDialogState();
}

class _CreditInvoiceDialogState extends State<CreditInvoiceDialog> {
  final _formKey = GlobalKey<FormState>();
  final _customerController = TextEditingController();
  final List<Map<String, dynamic>> _items = [];
  double _subtotal = 0.0;
  double _tax = 0.0;
  double _total = 0.0;
  final double _paidAmount = 0.0;
  double _remainingAmount = 0.0;
  DateTime? _dueDate;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('فاتورة آجل'),
      content: SizedBox(
        width: 500,
        height: 650,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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

              // Due Date Selection
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        readOnly: true,
                        controller: TextEditingController(
                          text: _dueDate != null
                              ? '${_dueDate!.day}/${_dueDate!.month}/${_dueDate!.year}'
                              : '',
                        ),
                        decoration: const InputDecoration(
                          labelText: 'تاريخ الاستحقاق',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.calendar_month),
                      label: const Text('اختيار'),
                      onPressed: _selectDueDate,
                    ),
                  ],
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
                        const Text('المنتجات'),
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
        ElevatedButton(onPressed: _saveInvoice, child: const Text('حفظ')),
      ],
    );
  }

  Widget _buildItemsList() {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListView.builder(
        itemCount: _items.length,
        itemBuilder: (context, index) {
          return ListTile(
            leading: const Icon(Icons.shopping_cart),
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
                    initialValue: (_items[index]['price'] ?? 0).toStringAsFixed(
                      2,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'السعر (ج.م)',
                      border: OutlineInputBorder(),
                      prefixText: 'ج.م ',
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (value) {
                      setState(() {
                        _items[index]['price'] = double.tryParse(value) ?? 0.0;
                      });
                      _calculateTotals();
                    },
                  ),
                ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
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
          _buildTotalRow('الإجمالي:', _subtotal),
          _buildTotalRow('الضريبة:', _tax),
          _buildTotalRow('الإجمالي:', _total),
          _buildTotalRow('المدفوع:', _paidAmount),
          _buildTotalRow('المتبقي:', _remainingAmount),
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
      _items.add({'name': 'منتج جديد', 'price': 0.0, 'quantity': 1});
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

    _tax = _subtotal * 0.14; // 14% tax
    _total = _subtotal + _tax;

    // Calculate remaining amount
    _remainingAmount = _total - _paidAmount;
  }

  void _selectDueDate() async {
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (selectedDate != null) {
      setState(() {
        _dueDate = selectedDate;
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

  void _saveInvoice() {
    if (_formKey.currentState?.validate() ?? false) {
      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم حفظ الفاتورة'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.of(context).pop();
    }
  }
}
