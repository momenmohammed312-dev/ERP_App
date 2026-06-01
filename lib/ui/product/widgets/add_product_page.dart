import 'package:flutter/material.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:pos_offline_desktop/l10n/l10n.dart';
import 'package:pos_offline_desktop/ui/widgets/custom_button.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';

class AddProductDialog extends StatefulHookConsumerWidget {
  final AppDatabase db;
  const AddProductDialog({super.key, required this.db});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() =>
      _AddProductDialogState();
}

class _AddProductDialogState extends ConsumerState<AddProductDialog> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _quantityController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  final TextEditingController _unitController = TextEditingController();
  final TextEditingController _barcodeController = TextEditingController();
  final TextEditingController _categoryController = TextEditingController();
  final TextEditingController _costPriceController = TextEditingController();
  final TextEditingController _minStockController = TextEditingController();

  void _saveProduct() async {
    if (_formKey.currentState!.validate()) {
      try {
        await widget.db.productDao.insertProduct(
          ProductsCompanion.insert(
            name: _nameController.text.trim(),
            quantity: int.tryParse(_quantityController.text.trim()) ?? 0,
            price: double.tryParse(_priceController.text.trim()) ?? 0.0,
            unit: Value(
              _unitController.text.trim().isEmpty
                  ? null
                  : _unitController.text.trim(),
            ),
            barcode: Value(
              _barcodeController.text.trim().isEmpty
                  ? null
                  : _barcodeController.text.trim(),
            ),
            category: Value(
              _categoryController.text.trim().isEmpty
                  ? null
                  : _categoryController.text.trim(),
            ),
            costPrice: Value(
              double.tryParse(_costPriceController.text.trim()),
            ),
            minStockLevel: Value(
              int.tryParse(_minStockController.text.trim()) ?? 0,
            ),
          ),
        );

        if (mounted) {
          final l10n = context.l10n;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.product_saved_successfully),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.of(context).pop();
        }
      } catch (e) {
        if (mounted) {
          final l10n = context.l10n;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${l10n.error}: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _quantityController.dispose();
    _priceController.dispose();
    _unitController.dispose();
    _barcodeController.dispose();
    _categoryController.dispose();
    _costPriceController.dispose();
    _minStockController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: const EdgeInsets.all(16.0),
        width: 500,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Form(
          key: _formKey,
          child: ListView(
            shrinkWrap: true,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: l10n.product_name,
                  border: const OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return l10n.enter_valid_product_name;
                  }
                  return null;
                },
              ),
              const Gap(16),
              TextFormField(
                controller: _barcodeController,
                decoration: const InputDecoration(
                  labelText: 'الباركود (اختياري)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.qr_code),
                ),
              ),
              const Gap(16),
              TextFormField(
                controller: _categoryController,
                decoration: const InputDecoration(
                  labelText: 'التصنيف (اختياري)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.category),
                ),
              ),
              const Gap(16),
              TextFormField(
                controller: _unitController,
                decoration: InputDecoration(
                  labelText: l10n.unit_label,
                  border: const OutlineInputBorder(),
                ),
              ),
              const Gap(16),
              TextFormField(
                controller: _priceController,
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                ],
                decoration: InputDecoration(
                  labelText: l10n.price,
                  border: const OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty || double.tryParse(value.trim()) == null) {
                    return l10n.enter_valid_price;
                  }
                  return null;
                },
              ),
              const Gap(16),
              TextFormField(
                controller: _costPriceController,
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                ],
                decoration: const InputDecoration(
                  labelText: 'سعر التكلفة (اختياري)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.receipt),
                ),
              ),
              const Gap(16),
              TextFormField(
                controller: _quantityController,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: InputDecoration(
                  labelText: l10n.quantity,
                  border: const OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty || int.tryParse(value.trim()) == null) {
                    return l10n.enter_valid_quantity;
                  }
                  return null;
                },
              ),
              const Gap(16),
              TextFormField(
                controller: _minStockController,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: const InputDecoration(
                  labelText: 'الحد الأدنى للمخزون (اختياري)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.warning_amber),
                ),
              ),
              const Gap(24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CustomButton(
                    onPressed: () => Navigator.of(context).pop(),
                    backgroundColor: Colors.red.shade400,
                    title: l10n.cancel,
                  ),
                  CustomButton(
                    title: l10n.save,
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    onPressed: _saveProduct,
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
