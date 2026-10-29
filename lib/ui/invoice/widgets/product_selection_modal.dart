import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/platform/platform_utils.dart';
import 'package:pos_offline_desktop/core/platform/responsive.dart';

class ProductSelectionModal extends StatefulWidget {
  static const Color _accentColor = Color(0xFF10B981); // Emerald Green
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
    'box',
    'carton',
    'meter',
    'liter',
    'ton',
  ];

  String _formatUnitName(String unit) {
    final u = unit.trim().toLowerCase();
    switch (u) {
      case 'piece':
      case 'قطعة':
        return 'قطعة';
      case 'kg':
      case 'كيلو':
      case 'كجم':
        return 'كيلو';
      case 'box':
      case 'علبة':
        return 'علبة';
      case 'carton':
      case 'كرتون':
        return 'كرتون';
      case 'meter':
      case 'متر':
        return 'متر';
      case 'liter':
      case 'لتر':
        return 'لتر';
      case 'ton':
      case 'طن':
        return 'طن';
      default:
        return unit;
    }
  }

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
    final isMobile = PlatformUtils.isMobile;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        backgroundColor: const Color(0xFF1E222B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(isMobile ? 18 : 16),
        ),
        insetPadding: EdgeInsets.symmetric(
          horizontal: isMobile ? 16 : 40,
          vertical: 24,
        ),
        child: Container(
          width: dialogWidth(context, 460),
          padding: EdgeInsets.all(isMobile ? 18 : 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: dialogMaxHeight(context)),
            child: SingleChildScrollView(
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
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: ProductSelectionModal._accentColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.inventory_2_rounded,
                            color: ProductSelectionModal._accentColor,
                            size: 24,
                          ),
                        ),
                        const Gap(12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.product.name,
                                style: const TextStyle(
                                  fontFamily: 'NotoSansArabic',
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const Gap(2),
                              Text(
                                'المخزون المتوفر: $_availableStock ${_formatUnitName(widget.product.unit ?? 'piece')}',
                                style: TextStyle(
                                  fontFamily: 'NotoSansArabic',
                                  color: Colors.white.withValues(alpha: 0.6),
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Gap(22),

                    // اختيار الصنف (لون/فئة) — إجباري لو المنتج له أصناف.
                    if (_variants.isNotEmpty) ...[
                      DropdownButtonFormField<ProductVariant>(
                        initialValue: _selectedVariant,
                        decoration: InputDecoration(
                          labelText: 'الصنف (اللون/الفئة) *',
                          labelStyle: const TextStyle(fontFamily: 'NotoSansArabic'),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          prefixIcon: const Icon(Icons.palette_outlined),
                        ),
                        items: _variants.map((v) {
                          final price = v.price ?? widget.product.price;
                          return DropdownMenuItem(
                            value: v,
                            child: Text(
                              '${v.name} — متاح: ${v.quantity} — ${price.toStringAsFixed(2)} ج.م',
                              style: const TextStyle(fontFamily: 'NotoSansArabic'),
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        validator: (v) =>
                            v == null ? 'اختر الصنف (اللون/الفئة) أولاً' : null,
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
                            decoration: InputDecoration(
                              labelText: 'الكمية',
                              labelStyle: const TextStyle(fontFamily: 'NotoSansArabic'),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              prefixIcon: const Icon(Icons.format_list_numbered, size: 20),
                            ),
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            validator: (value) {
                              final qty = int.tryParse(value ?? '');
                              if (qty == null || qty <= 0) {
                                return 'يرجى إدخال كمية صحيحة';
                              }
                              if (!widget.forPurchase && qty > _availableStock) {
                                return 'الكمية تتجاوز المخزون ($_availableStock)';
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
                            decoration: InputDecoration(
                              labelText: 'الوحدة',
                              labelStyle: const TextStyle(fontFamily: 'NotoSansArabic'),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              prefixIcon: const Icon(Icons.scale_rounded, size: 20),
                            ),
                            items: _units.map((unit) {
                              return DropdownMenuItem(
                                value: unit,
                                child: Text(
                                  _formatUnitName(unit),
                                  style: const TextStyle(fontFamily: 'NotoSansArabic'),
                                ),
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
                        labelText: 'سعر الوحدة',
                        labelStyle: const TextStyle(fontFamily: 'NotoSansArabic'),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        prefixIcon: const Icon(Icons.payments_outlined, size: 20),
                        suffixText:
                            'الافتراضي: ${(_selectedVariant?.price ?? widget.product.price).toStringAsFixed(2)}',
                        suffixStyle: TextStyle(
                          fontFamily: 'NotoSansArabic',
                          color: Colors.white.withValues(alpha: 0.5),
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
                          return 'يرجى إدخال سعر صحيح';
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
                            decoration: InputDecoration(
                              labelText: 'الخصم',
                              labelStyle: const TextStyle(fontFamily: 'NotoSansArabic'),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              prefixIcon: const Icon(Icons.discount_outlined, size: 20),
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
                            decoration: InputDecoration(
                              labelText: 'الضريبة',
                              labelStyle: const TextStyle(fontFamily: 'NotoSansArabic'),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              prefixIcon: const Icon(Icons.receipt_long_outlined, size: 20),
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
                    const Gap(18),

                    // Line Total Preview (Modern Dark Box)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF161B22),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: ProductSelectionModal._accentColor.withValues(alpha: 0.35),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: ProductSelectionModal._accentColor.withValues(alpha: 0.08),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: ProductSelectionModal._accentColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  Icons.calculate_rounded,
                                  color: ProductSelectionModal._accentColor,
                                  size: 20,
                                ),
                              ),
                              const Gap(10),
                              const Text(
                                'إجمالي البند:',
                                style: TextStyle(
                                  fontFamily: 'NotoSansArabic',
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            '${((_unitPrice * _quantity) - _discount + _tax).toStringAsFixed(2)} ج.م',
                            style: TextStyle(
                              fontFamily: 'NotoSansArabic',
                              fontWeight: FontWeight.w800,
                              fontSize: 20,
                              color: ProductSelectionModal._accentColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Gap(22),

                    // Action Buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close_rounded, size: 18),
                            label: const Text(
                              'إلغاء',
                              style: TextStyle(
                                fontFamily: 'NotoSansArabic',
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white70,
                              side: BorderSide(
                                color: Colors.white.withValues(alpha: 0.2),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                        const Gap(12),
                        Expanded(
                          child: ElevatedButton.icon(
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
                            icon: const Icon(
                              Icons.add_shopping_cart_rounded,
                              size: 18,
                            ),
                            label: const Text(
                              'إضافة إلى الفاتورة',
                              style: TextStyle(
                                fontFamily: 'NotoSansArabic',
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: ProductSelectionModal._accentColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              elevation: 2,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
