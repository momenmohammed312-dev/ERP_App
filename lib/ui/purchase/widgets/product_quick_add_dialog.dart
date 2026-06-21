import 'package:flutter/material.dart';
import 'package:drift/drift.dart' as drift;
import '../../../core/database/app_database.dart';
import '../../../core/database/dao/product_dao.dart';

/// Quick Add Product Dialog
/// نافذة إضافة سريعة للمنتجات أثناء عملية الشراء
class ProductQuickAddDialog extends StatefulWidget {
  final AppDatabase database;
  final Function(Product)? onProductAdded;

  const ProductQuickAddDialog({
    super.key,
    required this.database,
    this.onProductAdded,
  });

  @override
  State<ProductQuickAddDialog> createState() => _ProductQuickAddDialogState();
}

class _ProductQuickAddDialogState extends State<ProductQuickAddDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _priceController = TextEditingController();
  final _barcodeController = TextEditingController();
  final _categoryController = TextEditingController();
  final _cartonQuantityController = TextEditingController();
  final _cartonPriceController = TextEditingController();

  String _selectedUnit = 'قطعة';
  bool _isLoading = false;

  final List<String> _units = [
    'قطعة',
    'كرتونة',
    'كيلو',
    'لتر',
    'متر',
    'علبة',
    'زجاجة',
  ];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF2D2D3D),
      title: Row(
        children: [
          const Icon(Icons.add_shopping_cart, color: Colors.purple),
          const SizedBox(width: 8),
          const Text('إضافة منتج جديد', style: TextStyle(color: Colors.white)),
        ],
      ),
      content: SizedBox(
        width: 500,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Product Name
                TextFormField(
                  controller: _nameController,
                  decoration: _inputDecoration('اسم المنتج *'),
                  style: const TextStyle(color: Colors.white),
                  validator: (v) => v?.isEmpty ?? true ? 'الحقل مطلوب' : null,
                  autofocus: true,
                ),
                const SizedBox(height: 12),

                // Price and Unit
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _priceController,
                        decoration: _inputDecoration('السعر *'),
                        style: const TextStyle(color: Colors.white),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        validator: (v) {
                          final price = double.tryParse(v ?? '0');
                          if (price == null || price <= 0) {
                            return 'سعر غير صحيح';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _selectedUnit,
                        decoration: _inputDecoration('الوحدة'),
                        dropdownColor: const Color(0xFF3D3D4D),
                        style: const TextStyle(color: Colors.white),
                        items: _units.map((unit) {
                          return DropdownMenuItem(
                            value: unit,
                            child: Text(unit),
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => _selectedUnit = value);
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Barcode
                TextFormField(
                  controller: _barcodeController,
                  decoration: _inputDecoration('الباركود (اختياري)'),
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 12),

                // Category
                TextFormField(
                  controller: _categoryController,
                  decoration: _inputDecoration('الفئة (اختياري)'),
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 12),

                // Carton Details
                ExpansionTile(
                  title: const Text(
                    'تفاصيل الكرتونة (اختياري)',
                    style: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                  iconColor: Colors.grey,
                  collapsedIconColor: Colors.grey,
                  children: [
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _cartonQuantityController,
                            decoration: _inputDecoration('عدد القطع'),
                            style: const TextStyle(color: Colors.white),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            controller: _cartonPriceController,
                            decoration: _inputDecoration('سعر الكرتونة'),
                            style: const TextStyle(color: Colors.white),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _saveProduct,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.purple,
            disabledBackgroundColor: Colors.grey,
          ),
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                )
              : const Text('حفظ وإضافة'),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.grey),
      filled: true,
      fillColor: const Color(0xFF3D3D4D),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFF4D4D5D)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Colors.purple, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Colors.red),
      ),
    );
  }

  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final productDao = ProductDao(widget.database);

      // Parse values
      final price = double.tryParse(_priceController.text) ?? 0.0;
      final cartonQty = int.tryParse(_cartonQuantityController.text) ?? 0;
      final cartonPrice = double.tryParse(_cartonPriceController.text) ?? 0.0;

      // Create product
      final productId = await productDao.insertProduct(
        ProductsCompanion.insert(
          name: _nameController.text.trim(),
          price: price,
          unit: drift.Value(_selectedUnit),
          quantity: 0, // Initial quantity is 0
          category: drift.Value(
            _categoryController.text.isEmpty
                ? null
                : _categoryController.text.trim(),
          ),
          barcode: drift.Value(
            _barcodeController.text.isEmpty
                ? null
                : _barcodeController.text.trim(),
          ),
          cartonQuantity: drift.Value(cartonQty > 0 ? cartonQty : null),
          cartonPrice: drift.Value(cartonPrice > 0 ? cartonPrice : null),
        ),
      );

      // Fetch the created product
      final product = await productDao.getProductById(productId);

      if (!mounted) return;

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم إضافة المنتج: ${_nameController.text}'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );

      // Call callback if provided
      if (product != null && widget.onProductAdded != null) {
        widget.onProductAdded!(product);
      }

      // Close dialog
      Navigator.pop(context, product);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ في حفظ المنتج: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _barcodeController.dispose();
    _categoryController.dispose();
    _cartonQuantityController.dispose();
    _cartonPriceController.dispose();
    super.dispose();
  }
}
