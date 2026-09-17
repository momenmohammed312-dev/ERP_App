import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';

class ProductSelectionModal extends StatefulWidget {
  final Product product;
  final AppDatabase db;
  final bool forPurchase;

  /// صنف محدد مسبقًا (مثلًا من مسح باركود صنف) — null = يختار المستخدم.
  final ProductVariant? initialVariant;

  final Function(
    int quantity,
    String unit,
    double unitPrice,
    double discount,
    double tax,
    ProductVariant? variant,
  )
  onConfirm;

  const ProductSelectionModal({
    super.key,
    required this.product,
    required this.db,
    required this.onConfirm,
    this.forPurchase = false,
    this.initialVariant,
  });

  @override
  State<ProductSelectionModal> createState() => _ProductSelectionModalState();
}

class _ProductSelectionModalState extends State<ProductSelectionModal> {
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController(text: '1');
  final _priceController = TextEditingController();
  final _discountController = TextEditingController(text: '0');
  final _taxController = TextEditingController(text: '0');

  int _quantity = 1;
  String _selectedUnit = 'piece';
  double _unitPrice = 0.0;
  double _discount = 0.0;
  double _tax = 0.0;

  // أصناف المنتج (ألوان/فئات) — للبيع فقط، المشتريات تستهدف الأب.
  List<ProductVariant> _variants = [];
  ProductVariant? _selectedVariant;

  final List<String> _units = [
    'piece',
    'kg',
    'ton',
    'box',
    'meter',
    'liter',
    'كجم',
    'كيلو',
    'قطعة',
    'علبة',
    'متر',
    'لتر',
  ];

  @override
  void initState() {
    super.initState();
    _selectedVariant = widget.initialVariant;
    if (widget.forPurchase) {
      _unitPrice = widget.product.costPrice ?? widget.product.price;
    } else {
      _unitPrice = widget.initialVariant?.price ?? widget.product.price;
    }
    _priceController.text = _unitPrice.toStringAsFixed(2);
    final productUnit = widget.product.unit ?? 'piece';
    _selectedUnit = _units.contains(productUnit) ? productUnit : 'piece';
    if (!widget.forPurchase) _loadVariants();
  }

  Future<void> _loadVariants() async {
    try {
      final variants = await widget.db.productVariantDao.getVariantsByProduct(
        widget.product.id,
      );
      if (!mounted) return;
      setState(() {
        _variants = variants;
        // لو الصنف المبدئي (من الباركود) مش ضمن القائمة لسبب ما — تجاهله.
        if (_selectedVariant != null &&
            !_variants.any((v) => v.id == _selectedVariant!.id)) {
          _selectedVariant = null;
        }
        _applyVariantPrice();
      });
    } catch (_) {
      // فشل تحميل الأصناف لا يمنع البيع بالمسار القديم.
    }
  }

  /// المخزون المتاح حسب الاختيار الحالي (صنف أو أب).
  int get _availableStock => _selectedVariant?.quantity ?? widget.product.quantity;

  void _applyVariantPrice() {
    final defaultPrice = _selectedVariant?.price ?? widget.product.price;
    _unitPrice = defaultPrice;
    _priceController.text = defaultPrice.toStringAsFixed(2);
    // الكمية المدخلة قد تتجاوز مخزون الصنف الجديد — نعيد ضبطها.
    if (_quantity > _availableStock && _availableStock > 0) {
      _quantity = _availableStock;
      _quantityController.text = '$_quantity';
    }
  }

  void _onVariantChanged(ProductVariant? v) {
    setState(() {
      _selectedVariant = v;
      _applyVariantPrice();
    });
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _priceController.dispose();
    _discountController.dispose();
    _taxController.dispose();
    super.dispose();
  }

  void _calculateTotals() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.inventory_2, color: Colors.blue.shade600),
                  ),
                  const Gap(12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.product.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Stock: $_availableStock ${widget.product.unit ?? 'pieces'}',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Gap(24),

              // اختيار الصنف (لون/فئة) — إجباري لو المنتج له أصناف.
              if (_variants.isNotEmpty) ...[
                DropdownButtonFormField<ProductVariant>(
                  initialValue: _selectedVariant,
                  decoration: const InputDecoration(
                    labelText: 'الصنف (اللون/الفئة) *',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.palette),
                  ),
                  items: _variants.map((v) {
                    final price = v.price ?? widget.product.price;
                    return DropdownMenuItem(
                      value: v,
                      child: Text(
                        '${v.name} — متاح: ${v.quantity} — ${price.toStringAsFixed(2)}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  validator: (v) =>
                      v == null ? 'اختر الصنف (اللون/الفئة) أولًا' : null,
                  onChanged: _onVariantChanged,
                ),
                const Gap(16),
              ],

              // Quantity and Unit
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _quantityController,
                      decoration: const InputDecoration(
                        labelText: 'Quantity',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.format_list_numbered),
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: (value) {
                        final qty = int.tryParse(value ?? '');
                        if (qty == null || qty <= 0) {
                          return 'Invalid quantity';
                        }
                        if (!widget.forPurchase && qty > _availableStock) {
                          return 'Exceeds available stock ($_availableStock)';
                        }
                        return null;
                      },
                      onChanged: (value) {
                        _quantity = int.tryParse(value) ?? 1;
                        _calculateTotals();
                      },
                    ),
                  ),
                  const Gap(12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedUnit,
                      decoration: const InputDecoration(
                        labelText: 'Unit',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.scale),
                      ),
                      items: _units.map((unit) {
                        return DropdownMenuItem(
                          value: unit,
                          child: Text(unit.toUpperCase()),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedUnit = value!;
                        });
                      },
                    ),
                  ),
                ],
              ),
              const Gap(16),

              // Unit Price
              TextFormField(
                controller: _priceController,
                decoration: InputDecoration(
                  labelText: 'Unit Price',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.attach_money),
                  suffixText:
                      'Default: ${(_selectedVariant?.price ?? widget.product.price).toStringAsFixed(2)}',
                  suffixStyle: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 12,
                  ),
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                ],
                validator: (value) {
                  final price = double.tryParse(value ?? '');
                  if (price == null || price <= 0) {
                    return 'Invalid price';
                  }
                  return null;
                },
                onChanged: (value) {
                  _unitPrice = double.tryParse(value) ?? 0.0;
                  _calculateTotals();
                },
              ),
              const Gap(16),

              // Discount and Tax
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _discountController,
                      decoration: const InputDecoration(
                        labelText: 'Discount',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.discount),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'^\d+\.?\d{0,2}'),
                        ),
                      ],
                      onChanged: (value) {
                        _discount = double.tryParse(value) ?? 0.0;
                        _calculateTotals();
                      },
                    ),
                  ),
                  const Gap(12),
                  Expanded(
                    child: TextFormField(
                      controller: _taxController,
                      decoration: const InputDecoration(
                        labelText: 'Tax',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.receipt_long),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'^\d+\.?\d{0,2}'),
                        ),
                      ],
                      onChanged: (value) {
                        _tax = double.tryParse(value) ?? 0.0;
                        _calculateTotals();
                      },
                    ),
                  ),
                ],
              ),
              const Gap(16),

              // Line Total Preview
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Line Total:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      ((_unitPrice * _quantity) - _discount + _tax)
                          .toStringAsFixed(2),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: Colors.blue,
                      ),
                    ),
                  ],
                ),
              ),
              const Gap(24),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const Gap(12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        if (_formKey.currentState!.validate()) {
                          widget.onConfirm(
                            _quantity,
                            _selectedUnit,
                            _unitPrice,
                            _discount,
                            _tax,
                            _selectedVariant,
                          );
                          Navigator.of(context).pop();
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Add to Invoice'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
