import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/provider/auth_provider.dart';
import 'package:pos_offline_desktop/core/services/audit_log_service.dart';
import 'package:pos_offline_desktop/core/services/invoice_service.dart';

class EditInvoicePage extends ConsumerStatefulWidget {
  final AppDatabase db;
  final int invoiceId;
  final VoidCallback? onSaved;

  const EditInvoicePage({
    super.key,
    required this.db,
    required this.invoiceId,
    this.onSaved,
  });

  @override
  ConsumerState<EditInvoicePage> createState() => _EditInvoicePageState();
}

class _EditLine {
  Product? product;
  int quantity;
  double price;
  double discount;
  int? ctn;
  double commission;
  double? unitCostAtTime;
  int? shipmentId;

  _EditLine({
    this.product,
    this.quantity = 1,
    this.price = 0,
    this.discount = 0,
    this.ctn,
    this.commission = 0,
    this.unitCostAtTime,
    this.shipmentId,
  });
}

class _EditInvoicePageState extends ConsumerState<EditInvoicePage> {
  bool _isLoading = true;
  String? _error;
  Invoice? _invoice;
  List<_EditLine> _lines = [];
  List<Customer> _customers = [];
  List<Product> _products = [];

  String? _selectedCustomerId; // null = نقدي
  String _paymentMethod = 'cash';
  final _paidAmountController = TextEditingController();
  final _numberFormat = NumberFormat('#,##0.00');

  static const _methods = {
    'cash': 'نقدي',
    'credit': 'آجل',
    'visa': 'بطاقة',
    'bank': 'بنك',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _paidAmountController.dispose();
    super.dispose();
  }

  Customer? _findCustomer(String? id) {
    if (id == null) return null;
    for (final c in _customers) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<void> _load() async {
    try {
      final invoice = await widget.db.invoiceDao.getInvoiceById(widget.invoiceId);
      if (invoice == null) throw Exception('الفاتورة غير موجودة');

      final items = await widget.db.invoiceDao.getItemsByInvoiceId(widget.invoiceId);
      final customers = await widget.db.customerDao.getAllActiveCustomers();
      final products = await widget.db.productDao.getAllProducts();

      final lines = <_EditLine>[];
      for (final item in items) {
        final product = products.firstWhere(
          (p) => p.id == item.productId,
          orElse: () => Product(
            id: item.productId,
            name: 'منتج #${item.productId}',
            quantity: 0,
            price: item.price,
            minStockLevel: 0,
            barneka: false,
          ),
        );
        lines.add(
          _EditLine(
            product: product,
            quantity: item.quantity,
            price: item.price,
            discount: item.discount,
            ctn: item.ctn,
            commission: item.commission,
            unitCostAtTime: item.unitCostAtTime,
            shipmentId: item.shipmentId,
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _invoice = invoice;
        _lines = lines;
        _customers = customers;
        _products = products;
        _selectedCustomerId = invoice.customerId;
        _paymentMethod = invoice.paymentMethod ?? 'cash';
        _paidAmountController.text = invoice.paidAmount.toStringAsFixed(2);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  double get _subtotal => _lines.fold(
        0.0,
        (sum, l) => sum + (l.price * l.quantity - l.discount),
      );

  Future<void> _pickProduct(int index) async {
    final picked = await showDialog<Product>(
      context: context,
      builder: (ctx) => _ProductPicker(products: _products),
    );
    if (picked != null && mounted) {
      setState(() {
        _lines[index].product = picked;
        _lines[index].price = picked.price;
      });
    }
  }

  void _addLine() {
    setState(() => _lines.add(_EditLine(quantity: 1, price: 0)));
  }

  void _removeLine(int index) {
    setState(() => _lines.removeAt(index));
  }

  Future<void> _save() async {
    setState(() => _error = null);
    final subtotal = _subtotal;
    final paid = double.tryParse(
          _paidAmountController.text.trim().replaceAll(',', ''),
        ) ??
        0.0;

    if (_lines.isEmpty) {
      setState(() => _error = 'يجب إضافة صنف واحد على الأقل');
      return;
    }
    for (final l in _lines) {
      if (l.product == null) {
        setState(() => _error = 'بعض الأصناف غير محددة');
        return;
      }
      if (l.quantity <= 0) {
        setState(() => _error = 'الكمية يجب أن تكون أكبر من صفر');
        return;
      }
      if (l.price < 0) {
        setState(() => _error = 'السعر غير صحيح');
        return;
      }
    }
    if (subtotal <= 0) {
      setState(() => _error = 'إجمالي الفاتورة يجب أن يكون أكبر من صفر');
      return;
    }
    if (paid < 0 || paid > subtotal) {
      setState(() => _error = 'المبلغ المدفوع يجب أن يكون بين 0 والإجمالي');
      return;
    }

    final status = paid >= subtotal
        ? 'paid'
        : (paid > 0 ? 'partial' : 'pending');

    final cashAmount = _paymentMethod == 'cash' ? paid : 0.0;
    final cardAmount = (_paymentMethod == 'visa' ||
            _paymentMethod == 'bank' ||
            _paymentMethod == 'card')
        ? paid
        : 0.0;
    final creditAmount = _paymentMethod == 'credit' ? paid : 0.0;

    final customer = _findCustomer(_selectedCustomerId);

    final items = _lines
        .map(
          (l) => InvoiceItemParams(
            productId: l.product!.id,
            quantity: l.quantity,
            price: l.price,
            ctn: l.ctn,
            discount: l.discount,
            commission: l.commission,
            unitCostAtTime: l.unitCostAtTime,
            shipmentId: l.shipmentId,
          ),
        )
        .toList();

    final oldValues = {
      'invoiceNumber': _invoice!.invoiceNumber,
      'customerId': _invoice!.customerId,
      'totalAmount': _invoice!.totalAmount,
      'paidAmount': _invoice!.paidAmount,
      'paymentMethod': _invoice!.paymentMethod,
      'status': _invoice!.status,
    };

    try {
      final updated = await InvoiceService(widget.db).editInvoice(
        invoiceId: widget.invoiceId,
        customerId: customer?.id,
        customerName: customer?.name ?? 'نقدي',
        customerContact: customer?.phone,
        customerAddress: customer?.address,
        paymentMethod: _paymentMethod,
        totalAmount: subtotal,
        paidAmount: paid,
        cashAmount: cashAmount,
        cardAmount: cardAmount,
        creditAmount: creditAmount,
        status: status,
        items: items,
        primaryShipmentId: _invoice!.shipmentId,
      );

      final user = ref.read(authProvider);
      await AuditService.log(
        db: widget.db,
        action: 'UPDATE',
        tableName: 'invoices',
        recordId: updated.id,
        details: 'تعديل فاتورة ${updated.invoiceNumber}',
        oldValue: oldValues,
        newValue: {
          'invoiceNumber': updated.invoiceNumber,
          'customerId': updated.customerId,
          'totalAmount': updated.totalAmount,
          'paidAmount': updated.paidAmount,
          'paymentMethod': updated.paymentMethod,
          'status': updated.status,
          'performedBy': user?.username,
        },
      );

      if (!mounted) return;
      widget.onSaved?.call();
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم حفظ تعديل الفاتورة بنجاح'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('تعديل فاتورة')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final customerName = _findCustomer(_selectedCustomerId)?.name ?? 'نقدي';

    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text('تعديل فاتورة ${_invoice?.invoiceNumber ?? widget.invoiceId}'),
          actions: [
            TextButton.icon(
              onPressed: _isLoading ? null : _save,
              icon: const Icon(Icons.save),
              label: const Text('حفظ'),
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_error != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red),
                    ),
                    child: Text(_error!, style: const TextStyle(color: Colors.red)),
                  ),
                // Customer + payment
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      crossAxisAlignment: WrapCrossAlignment.end,
                      children: [
                        SizedBox(
                          width: 260,
                          child: DropdownButtonFormField<String?>(
                            initialValue: _selectedCustomerId,
                            decoration: const InputDecoration(
                              labelText: 'العميل',
                              border: OutlineInputBorder(),
                            ),
                            items: [
                              const DropdownMenuItem(
                                value: null,
                                child: Text('نقدي'),
                              ),
                              ..._customers.map(
                                (c) => DropdownMenuItem(
                                  value: c.id,
                                  child: Text(c.name),
                                ),
                              ),
                            ],
                            onChanged: (v) =>
                                setState(() => _selectedCustomerId = v),
                          ),
                        ),
                        SizedBox(
                          width: 180,
                          child: DropdownButtonFormField<String>(
                            initialValue: _paymentMethod,
                            decoration: const InputDecoration(
                              labelText: 'طريقة الدفع',
                              border: OutlineInputBorder(),
                            ),
                            items: _methods.entries
                                .map(
                                  (e) => DropdownMenuItem(
                                    value: e.key,
                                    child: Text(e.value),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) =>
                                setState(() => _paymentMethod = v!),
                          ),
                        ),
                        SizedBox(
                          width: 180,
                          child: TextField(
                            controller: _paidAmountController,
                            decoration: const InputDecoration(
                              labelText: 'المبلغ المدفوع',
                              border: OutlineInputBorder(),
                              prefixText: 'ج.م ',
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Line items
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'الأصناف (${_lines.length})',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: _addLine,
                      icon: const Icon(Icons.add),
                      label: const Text('إضافة صنف'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ..._lines.asMap().entries.map((entry) {
                  final i = entry.key;
                  final line = entry.value;
                  return _LineCard(
                    index: i,
                    line: line,
                    numberFormat: _numberFormat,
                    onPickProduct: () => _pickProduct(i),
                    onQuantityChanged: (v) {
                      final q = int.tryParse(v);
                      if (q != null) setState(() => line.quantity = q);
                    },
                    onPriceChanged: (v) {
                      final p = double.tryParse(v.replaceAll(',', ''));
                      if (p != null) setState(() => line.price = p);
                    },
                    onDiscountChanged: (v) {
                      final d = double.tryParse(v.replaceAll(',', ''));
                      setState(() => line.discount = d ?? 0);
                    },
                    onRemove: () => _removeLine(i),
                  );
                }),
                const SizedBox(height: 16),
                // Totals
                Card(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _totalRow('إجمالي الفاتورة', _subtotal),
                        _totalRow(
                          'المدفوع',
                          double.tryParse(_paidAmountController.text
                                  .trim()
                                  .replaceAll(',', '')) ??
                              0.0,
                        ),
                        _totalRow(
                          'المتبقي',
                          (_subtotal -
                              (double.tryParse(_paidAmountController.text
                                      .trim()
                                      .replaceAll(',', '')) ??
                                  0.0)),
                          bold: true,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.save),
                    label: const Text('حفظ التعديلات'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('إلغاء'),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _totalRow(String label, double value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontWeight: bold ? FontWeight.bold : null)),
          Text(
            '${_numberFormat.format(value)} ج.م',
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : null,
              fontSize: bold ? 16 : 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _LineCard extends StatelessWidget {
  final int index;
  final _EditLine line;
  final NumberFormat numberFormat;
  final VoidCallback onPickProduct;
  final ValueChanged<String> onQuantityChanged;
  final ValueChanged<String> onPriceChanged;
  final ValueChanged<String> onDiscountChanged;
  final VoidCallback onRemove;

  const _LineCard({
    required this.index,
    required this.line,
    required this.numberFormat,
    required this.onPickProduct,
    required this.onQuantityChanged,
    required this.onPriceChanged,
    required this.onDiscountChanged,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final lineTotal = line.price * line.quantity - line.discount;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: onPickProduct,
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'الصنف',
                        border: OutlineInputBorder(),
                      ),
                      child: Text(line.product?.name ?? 'اختر صنفاً'),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: onRemove,
                  icon: const Icon(Icons.delete, color: Colors.red),
                  tooltip: 'حذف الصنف',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: 120,
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: 'الكمية',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    controller: TextEditingController(text: line.quantity.toString()),
                    onChanged: onQuantityChanged,
                  ),
                ),
                SizedBox(
                  width: 140,
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: 'السعر',
                      border: OutlineInputBorder(),
                      prefixText: 'ج.م ',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    controller: TextEditingController(
                      text: line.price.toStringAsFixed(2),
                    ),
                    onChanged: onPriceChanged,
                  ),
                ),
                SizedBox(
                  width: 140,
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: 'خصم',
                      border: OutlineInputBorder(),
                      prefixText: 'ج.م ',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    controller: TextEditingController(
                      text: line.discount.toStringAsFixed(2),
                    ),
                    onChanged: onDiscountChanged,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${numberFormat.format(lineTotal)} ج.م',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductPicker extends StatefulWidget {
  final List<Product> products;

  const _ProductPicker({required this.products});

  @override
  State<_ProductPicker> createState() => _ProductPickerState();
}

class _ProductPickerState extends State<_ProductPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.products
        .where((p) => p.name.toLowerCase().contains(_query.toLowerCase()))
        .toList();
    return AlertDialog(
      title: const Text('اختر صنفاً'),
      content: SizedBox(
        width: 400,
        height: 420,
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(
                labelText: 'بحث',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (ctx, i) {
                  final p = filtered[i];
                  return ListTile(
                    title: Text(p.name),
                    subtitle: Text('${p.price.toStringAsFixed(2)} ج.م — مخزون: ${p.quantity}'),
                    onTap: () => Navigator.pop(context, p),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
      ],
    );
  }
}
