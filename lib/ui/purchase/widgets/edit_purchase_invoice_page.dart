import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';

const Color _bgDark = Color(0xFF0D1117);
const Color _cardBg = Color(0xFF161B22);
const Color _gold = Color(0xFFC9A84C);
const Color _border = Color(0xFF30363D);
const Color _textMuted = Color(0xFF8B949E);

class EditPurchaseInvoicePage extends StatefulWidget {
  final AppDatabase db;
  final String purchaseId;
  final VoidCallback? onSaved;

  const EditPurchaseInvoicePage({
    super.key,
    required this.db,
    required this.purchaseId,
    this.onSaved,
  });

  @override
  State<EditPurchaseInvoicePage> createState() => _EditPurchaseInvoicePageState();
}

class _EditPurchaseLine {
  Product? product;
  int quantity;
  double costPrice;
  double sellingPrice;
  String unit;

  _EditPurchaseLine({
    this.product,
    this.quantity = 1,
    this.costPrice = 0.0,
    this.sellingPrice = 0.0,
    this.unit = 'قطعة',
  });

  double get total => quantity * costPrice;
}

class _EditPurchaseInvoicePageState extends State<EditPurchaseInvoicePage> {
  bool _isLoading = true;
  String? _error;
  Purchase? _purchase;
  Supplier? _supplier;
  List<Supplier> _suppliers = [];
  List<Product> _products = [];
  final List<_EditPurchaseLine> _lines = [];

  String? _selectedSupplierId;
  String _paymentMethod = 'cash';
  final _paidAmountController = TextEditingController();
  final _notesController = TextEditingController();
  final _invoiceNumberController = TextEditingController();

  static const _paymentMethods = {
    'cash': 'نقدي',
    'credit': 'آجل',
    'visa': 'بطاقة',
    'bank': 'تحويل بنكي',
  };

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _paidAmountController.dispose();
    _notesController.dispose();
    _invoiceNumberController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      var purchase = await widget.db.purchaseDao.getPurchaseById(widget.purchaseId);
      purchase ??= await widget.db.purchaseDao.getPurchaseByInvoiceNumber(widget.purchaseId);

      if (purchase == null) {
        throw Exception('لم يتم العثور على فاتورة الشراء');
      }

      final itemsWithProducts =
          await widget.db.purchaseDao.getItemsWithProductsByPurchase(purchase.id);
      final suppliers = await (widget.db.select(widget.db.suppliers)
            ..where((s) => s.status.equals('Active')))
          .get();
      final products = await widget.db.productDao.getAllProducts();

      _lines.clear();
      for (final pair in itemsWithProducts) {
        final item = pair.$1;
        final product = pair.$2;
        _lines.add(
          _EditPurchaseLine(
            product: product,
            quantity: item.quantity,
            costPrice: item.unitPrice,
            sellingPrice: product?.price ?? item.unitPrice,
            unit: item.unit ?? product?.unit ?? 'قطعة',
          ),
        );
      }

      if (_lines.isEmpty) {
        _lines.add(_EditPurchaseLine());
      }

      Supplier? supp;
      if (purchase.supplierId != null) {
        supp = suppliers.where((s) => s.id == purchase!.supplierId).firstOrNull;
      }

      if (!mounted) return;
      setState(() {
        _purchase = purchase;
        _supplier = supp;
        _suppliers = suppliers;
        _products = products;
        _selectedSupplierId = purchase?.supplierId;
        _paymentMethod = purchase?.paymentMethod ?? 'cash';
        _invoiceNumberController.text = purchase?.invoiceNumber ?? '';
        _paidAmountController.text = (purchase?.paidAmount ?? 0.0).toStringAsFixed(2);
        _notesController.text = purchase?.notes ?? '';
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

  double get _subtotal => _lines.fold(0.0, (sum, l) => sum + l.total);

  void _addLine() {
    setState(() {
      _lines.add(_EditPurchaseLine());
    });
  }

  void _removeLine(int index) {
    setState(() {
      _lines.removeAt(index);
    });
  }

  Future<void> _pickProduct(int index) async {
    final picked = await showDialog<Product>(
      context: context,
      builder: (ctx) => _ProductSelectionDialog(products: _products),
    );

    if (picked != null && mounted) {
      setState(() {
        _lines[index].product = picked;
        _lines[index].costPrice = picked.costPrice > 0 ? picked.costPrice : picked.price;
        _lines[index].sellingPrice = picked.price;
        _lines[index].unit = picked.unit ?? 'قطعة';
      });
    }
  }

  Future<void> _save() async {
    if (_lines.isEmpty) {
      setState(() => _error = 'يجب إضافة صنف واحد على الأقل');
      return;
    }

    for (final line in _lines) {
      if (line.product == null) {
        setState(() => _error = 'يرجى اختيار المنتج لجميع الأصناف');
        return;
      }
      if (line.quantity <= 0) {
        setState(() => _error = 'الكمية يجب أن تكون أكبر من الصفر');
        return;
      }
      if (line.costPrice < 0) {
        setState(() => _error = 'سعر الشراء لا يمكن أن يكون سالباً');
        return;
      }
    }

    final total = _subtotal;
    final paid = double.tryParse(_paidAmountController.text.trim().replaceAll(',', '')) ?? 0.0;

    if (paid < 0 || paid > total) {
      setState(() => _error = 'المبلغ المدفوع يجب أن يكون بين 0 وإجمالي الفاتورة');
      return;
    }

    final status = paid >= total ? 'completed' : (paid > 0 ? 'partial' : 'pending');

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final itemsData = _lines.map((l) {
        return {
          'productId': l.product!.id,
          'quantity': l.quantity,
          'unitPrice': l.costPrice,
          'price': l.sellingPrice,
          'sellingPrice': l.sellingPrice,
          'unit': l.unit,
          'discount': 0.0,
          'tax': 0.0,
        };
      }).toList();

      final invoiceNum = _invoiceNumberController.text.trim().isNotEmpty
          ? _invoiceNumberController.text.trim()
          : _purchase!.invoiceNumber;

      final desc = _supplier != null
          ? 'فاتورة مشتريات من ${_supplier!.name}'
          : 'فاتورة مشتريات';

      await widget.db.purchaseDao.updatePurchaseWithItems(
        purchaseId: _purchase!.id,
        supplierId: _selectedSupplierId,
        invoiceNumber: invoiceNum,
        description: desc,
        totalAmount: total,
        paidAmount: paid,
        paymentMethod: _paymentMethod,
        status: status,
        purchaseDate: _purchase!.purchaseDate,
        notes: _notesController.text.trim().isNotEmpty ? _notesController.text.trim() : null,
        items: itemsData,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم تحديث فاتورة المشتريات والمخزون بنجاح'),
          backgroundColor: Colors.green,
        ),
      );

      widget.onSaved?.call();
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'خطأ أثناء الحفظ: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat('#,##0.00');

    return Scaffold(
      backgroundColor: _bgDark,
      appBar: AppBar(
        backgroundColor: _cardBg,
        title: Text(
          _purchase != null
              ? 'تعديل فاتورة مشتريات #${_purchase!.invoiceNumber}'
              : 'تعديل فاتورة مشتريات',
          style: const TextStyle(color: Colors.white, fontSize: 18),
        ),
        actions: [
          ElevatedButton.icon(
            onPressed: _isLoading ? null : _save,
            icon: const Icon(Icons.save, size: 18),
            label: const Text('حفظ التعديلات'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _gold,
              foregroundColor: Colors.black,
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _gold))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_error != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        border: Border.all(color: Colors.redAccent),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline, color: Colors.redAccent),
                          const Gap(8),
                          Expanded(
                            child: Text(
                              _error!,
                              style: const TextStyle(color: Colors.redAccent),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Header Information Card
                  Card(
                    color: _cardBg,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: const BorderSide(color: _border),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'بيانات الفاتورة والمورد',
                            style: TextStyle(
                              color: _gold,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const Gap(16),
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  value: _selectedSupplierId,
                                  dropdownColor: _cardBg,
                                  style: const TextStyle(color: Colors.white),
                                  decoration: const InputDecoration(
                                    labelText: 'المورد',
                                    labelStyle: TextStyle(color: _textMuted),
                                    border: OutlineInputBorder(),
                                    enabledBorder: OutlineInputBorder(
                                      borderSide: BorderSide(color: _border),
                                    ),
                                  ),
                                  items: [
                                    const DropdownMenuItem<String>(
                                      value: null,
                                      child: Text('مورد عام / بدون تحديد'),
                                    ),
                                    ..._suppliers.map(
                                      (s) => DropdownMenuItem<String>(
                                        value: s.id,
                                        child: Text(s.name),
                                      ),
                                    ),
                                  ],
                                  onChanged: (val) {
                                    setState(() {
                                      _selectedSupplierId = val;
                                      _supplier = _suppliers.where((s) => s.id == val).firstOrNull;
                                    });
                                  },
                                ),
                              ),
                              const Gap(16),
                              Expanded(
                                child: TextField(
                                  controller: _invoiceNumberController,
                                  style: const TextStyle(color: Colors.white),
                                  decoration: const InputDecoration(
                                    labelText: 'رقم الفاتورة',
                                    labelStyle: TextStyle(color: _textMuted),
                                    border: OutlineInputBorder(),
                                    enabledBorder: OutlineInputBorder(
                                      borderSide: BorderSide(color: _border),
                                    ),
                                  ),
                                ),
                              ),
                              const Gap(16),
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  value: _paymentMethod,
                                  dropdownColor: _cardBg,
                                  style: const TextStyle(color: Colors.white),
                                  decoration: const InputDecoration(
                                    labelText: 'طريقة الدفع',
                                    labelStyle: TextStyle(color: _textMuted),
                                    border: OutlineInputBorder(),
                                    enabledBorder: OutlineInputBorder(
                                      borderSide: BorderSide(color: _border),
                                    ),
                                  ),
                                  items: _paymentMethods.entries.map((e) {
                                    return DropdownMenuItem<String>(
                                      value: e.key,
                                      child: Text(e.value),
                                    );
                                  }).toList(),
                                  onChanged: (val) {
                                    if (val != null) setState(() => _paymentMethod = val);
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const Gap(20),

                  // Products Table Card
                  Card(
                    color: _cardBg,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: const BorderSide(color: _border),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'بنود الفاتورة (الأصناف والأسعار)',
                                style: TextStyle(
                                  color: _gold,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              ElevatedButton.icon(
                                onPressed: _addLine,
                                icon: const Icon(Icons.add, size: 16),
                                label: const Text('إضافة صنف'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blueAccent,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ],
                          ),
                          const Gap(16),

                          // Table Header
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: _bgDark,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Row(
                              children: [
                                Expanded(flex: 3, child: Text('المنتج', style: TextStyle(color: _textMuted, fontWeight: FontWeight.bold))),
                                Expanded(flex: 2, child: Text('الكمية', style: TextStyle(color: _textMuted, fontWeight: FontWeight.bold))),
                                Expanded(flex: 2, child: Text('سعر الشراء (التكلفة)', style: TextStyle(color: _textMuted, fontWeight: FontWeight.bold))),
                                Expanded(flex: 2, child: Text('سعر البيع المقترح', style: TextStyle(color: _textMuted, fontWeight: FontWeight.bold))),
                                Expanded(flex: 2, child: Text('الإجمالي', style: TextStyle(color: _textMuted, fontWeight: FontWeight.bold))),
                                SizedBox(width: 40),
                              ],
                            ),
                          ),
                          const Gap(8),

                          // Line Items
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _lines.length,
                            separatorBuilder: (_, __) => const Divider(color: _border),
                            itemBuilder: (context, index) {
                              final line = _lines[index];
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  children: [
                                    // Product selection
                                    Expanded(
                                      flex: 3,
                                      child: InkWell(
                                        onTap: () => _pickProduct(index),
                                        borderRadius: BorderRadius.circular(6),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                          decoration: BoxDecoration(
                                            border: Border.all(color: _border),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  line.product?.name ?? 'اختر منتج...',
                                                  style: TextStyle(
                                                    color: line.product != null ? Colors.white : _textMuted,
                                                  ),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              const Icon(Icons.arrow_drop_down, color: _textMuted),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    const Gap(8),

                                    // Quantity
                                    Expanded(
                                      flex: 2,
                                      child: TextFormField(
                                        initialValue: line.quantity.toString(),
                                        style: const TextStyle(color: Colors.white),
                                        keyboardType: TextInputType.number,
                                        decoration: const InputDecoration(
                                          border: OutlineInputBorder(),
                                          isDense: true,
                                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                        ),
                                        onChanged: (val) {
                                          final q = int.tryParse(val) ?? 1;
                                          setState(() => line.quantity = q);
                                        },
                                      ),
                                    ),
                                    const Gap(8),

                                    // Cost Price
                                    Expanded(
                                      flex: 2,
                                      child: TextFormField(
                                        initialValue: line.costPrice.toStringAsFixed(2),
                                        style: const TextStyle(color: Colors.white),
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                        decoration: const InputDecoration(
                                          border: OutlineInputBorder(),
                                          isDense: true,
                                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                        ),
                                        onChanged: (val) {
                                          final p = double.tryParse(val) ?? 0.0;
                                          setState(() => line.costPrice = p);
                                        },
                                      ),
                                    ),
                                    const Gap(8),

                                    // Selling Price
                                    Expanded(
                                      flex: 2,
                                      child: TextFormField(
                                        initialValue: line.sellingPrice.toStringAsFixed(2),
                                        style: const TextStyle(color: Colors.white),
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                        decoration: const InputDecoration(
                                          border: OutlineInputBorder(),
                                          isDense: true,
                                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                        ),
                                        onChanged: (val) {
                                          final p = double.tryParse(val) ?? 0.0;
                                          setState(() => line.sellingPrice = p);
                                        },
                                      ),
                                    ),
                                    const Gap(8),

                                    // Line total
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        '${currencyFormat.format(line.total)} ج.م',
                                        style: const TextStyle(
                                          color: _gold,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),

                                    // Delete button
                                    SizedBox(
                                      width: 40,
                                      child: IconButton(
                                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                        onPressed: _lines.length > 1 ? () => _removeLine(index) : null,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),

                  const Gap(20),

                  // Financial Summary Card
                  Card(
                    color: _cardBg,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: const BorderSide(color: _border),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('إجمالي الفاتورة:', style: TextStyle(color: Colors.white, fontSize: 15)),
                              Text(
                                '${currencyFormat.format(_subtotal)} ج.م',
                                style: const TextStyle(color: _gold, fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          const Divider(color: _border, height: 24),
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _paidAmountController,
                                  style: const TextStyle(color: Colors.white),
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  decoration: const InputDecoration(
                                    labelText: 'المبلغ المدفوع (ج.م)',
                                    labelStyle: TextStyle(color: _textMuted),
                                    border: OutlineInputBorder(),
                                  ),
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                              const Gap(16),
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: _border),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('المبلغ المتبقي (آجل على الحساب)', style: TextStyle(color: _textMuted, fontSize: 12)),
                                      const Gap(4),
                                      Text(
                                        '${currencyFormat.format((_subtotal - (double.tryParse(_paidAmountController.text) ?? 0.0)).clamp(0.0, double.infinity))} ج.م',
                                        style: TextStyle(
                                          color: (_subtotal - (double.tryParse(_paidAmountController.text) ?? 0.0)) > 0
                                              ? Colors.orange
                                              : Colors.green,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _ProductSelectionDialog extends StatefulWidget {
  final List<Product> products;

  const _ProductSelectionDialog({required this.products});

  @override
  State<_ProductSelectionDialog> createState() => _ProductSelectionDialogState();
}

class _ProductSelectionDialogState extends State<_ProductSelectionDialog> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.products.where((p) {
      if (_search.isEmpty) return true;
      final q = _search.toLowerCase();
      return p.name.toLowerCase().contains(q) || (p.barcode?.contains(q) ?? false);
    }).toList();

    return AlertDialog(
      backgroundColor: _cardBg,
      title: const Text('اختر منتج', style: TextStyle(color: Colors.white)),
      content: SizedBox(
        width: 500,
        height: 400,
        child: Column(
          children: [
            TextField(
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'ابحث بالاسم أو الباركود...',
                hintStyle: TextStyle(color: _textMuted),
                prefixIcon: Icon(Icons.search, color: _gold),
                border: OutlineInputBorder(),
              ),
              onChanged: (val) => setState(() => _search = val),
            ),
            const Gap(10),
            Expanded(
              child: ListView.builder(
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final p = filtered[index];
                  return ListTile(
                    title: Text(p.name, style: const TextStyle(color: Colors.white)),
                    subtitle: Text(
                      'سعر الشراء: ${p.costPrice.toStringAsFixed(2)} | المخزون الحالي: ${p.quantity}',
                      style: const TextStyle(color: _textMuted, fontSize: 12),
                    ),
                    trailing: Text(
                      '${p.price.toStringAsFixed(2)} ج.م',
                      style: const TextStyle(color: _gold, fontWeight: FontWeight.bold),
                    ),
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
          child: const Text('إلغاء', style: TextStyle(color: _textMuted)),
        ),
      ],
    );
  }
}
