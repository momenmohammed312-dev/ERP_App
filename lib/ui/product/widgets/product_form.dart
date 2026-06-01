import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/l10n/l10n.dart';
import 'package:pos_offline_desktop/core/services/audit_service.dart';

class ProductForm extends StatefulWidget {
  final Product? product; // لو null → إضافة، لو مش null → تعديل
  final AppDatabase db;

  const ProductForm({super.key, this.product, required this.db});

  @override
  State<ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends State<ProductForm> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController nameCtrl;
  late TextEditingController priceCtrl;
  late TextEditingController costPriceCtrl;
  late TextEditingController quantityCtrl;
  late TextEditingController minStockCtrl;
  late TextEditingController barcodeCtrl;
  late TextEditingController categoryCtrl;
  late TextEditingController unitCtrl;
  late TextEditingController cartonQtyCtrl;
  late TextEditingController cartonPriceCtrl;
  String selectedStatus = 'Active';

  @override
  void initState() {
    super.initState();
    nameCtrl = TextEditingController(text: widget.product?.name ?? '');
    priceCtrl = TextEditingController(
      text: widget.product?.price.toString() ?? '',
    );
    costPriceCtrl = TextEditingController(
      text: widget.product?.costPrice?.toString() ?? '',
    );
    quantityCtrl = TextEditingController(
      text: widget.product?.quantity.toString() ?? '',
    );
    minStockCtrl = TextEditingController(
      text: widget.product?.minStockLevel?.toString() ?? '0',
    );
    barcodeCtrl = TextEditingController(text: widget.product?.barcode ?? '');
    categoryCtrl = TextEditingController(text: widget.product?.category ?? '');
    unitCtrl = TextEditingController(text: widget.product?.unit ?? 'قطعة');
    cartonQtyCtrl = TextEditingController(
      text: widget.product?.cartonQuantity?.toString() ?? '',
    );
    cartonPriceCtrl = TextEditingController(
      text: widget.product?.cartonPrice?.toString() ?? '',
    );
    selectedStatus = widget.product?.status ?? 'Active';
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    priceCtrl.dispose();
    costPriceCtrl.dispose();
    quantityCtrl.dispose();
    minStockCtrl.dispose();
    barcodeCtrl.dispose();
    categoryCtrl.dispose();
    unitCtrl.dispose();
    cartonQtyCtrl.dispose();
    cartonPriceCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveProduct() async {
    if (_formKey.currentState!.validate()) {
      try {
        final newPrice = double.parse(priceCtrl.text);
        final newQuantity = int.parse(quantityCtrl.text);
        final newMinStock = int.tryParse(minStockCtrl.text) ?? 0;
        final newCostPrice = double.tryParse(costPriceCtrl.text);
        final newBarcode = barcodeCtrl.text.trim().isEmpty ? null : barcodeCtrl.text.trim();
        final newCategory = categoryCtrl.text.trim().isEmpty ? null : categoryCtrl.text.trim();
        final newUnit = unitCtrl.text.trim().isEmpty ? null : unitCtrl.text.trim();
        final newCartonQty = int.tryParse(cartonQtyCtrl.text);
        final newCartonPrice = double.tryParse(cartonPriceCtrl.text);

        // Check barcode uniqueness
        if (newBarcode != null) {
          final existing = await widget.db.productDao.getProductByBarcode(newBarcode);
          if (existing != null && (widget.product == null || existing.id != widget.product!.id)) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('الباركود مستخدم بالفعل لمنتج آخر'), backgroundColor: Colors.orange),
              );
            }
            return;
          }
        }

        // Warning for cost price
        if (newCostPrice != null && newCostPrice > newPrice) {
          final confirm = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('تحذير'),
              content: const Text('سعر التكلفة أكبر من سعر البيع. هل تريد الاستمرار؟'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
                TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('استمرار')),
              ],
            ),
          );
          if (confirm != true) return;
        }

        if (widget.product == null) {
          // إضافة
          await widget.db.productDao.insertProduct(
            ProductsCompanion.insert(
              name: nameCtrl.text,
              price: newPrice,
              quantity: newQuantity,
              minStockLevel: Value(newMinStock),
              costPrice: Value(newCostPrice),
              barcode: Value(newBarcode),
              category: Value(newCategory),
              unit: Value(newUnit),
              cartonQuantity: Value(newCartonQty),
              cartonPrice: Value(newCartonPrice),
              status: Value(selectedStatus),
            ),
          );
        } else {
          // تعديل
          final oldProduct = widget.product!;
          final updatedProduct = widget.product!.copyWith(
            name: nameCtrl.text,
            price: newPrice,
            quantity: newQuantity,
            minStockLevel: Value(newMinStock),
            costPrice: Value(newCostPrice),
            barcode: Value(newBarcode),
            category: Value(newCategory),
            unit: Value(newUnit),
            cartonQuantity: Value(newCartonQty),
            cartonPrice: Value(newCartonPrice),
            status: Value(selectedStatus),
          );
          
          await widget.db.productDao.updateProduct(updatedProduct);

          // Audit Log
          await AuditService.log(
            db: widget.db,
            action: 'UPDATE',
            tableName: 'products',
            recordId: updatedProduct.id,
            details: 'تعديل منتج: ${updatedProduct.name}',
            oldValue: oldProduct.toJson(),
            newValue: updatedProduct.toJson(),
          );
        }

        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                widget.product == null
                    ? context.l10n.save_product
                    : context.l10n.product_updated_successfully,
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${context.l10n.error}: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.product == null
              ? context.l10n.add_product
              : context.l10n.edit_product,
        ),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    labelText: context.l10n.product_name,
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.inventory),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return context.l10n.enter_valid_product_name;
                    }
                    return null;
                  },
                ),
                const Gap(16),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: priceCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: context.l10n.price,
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.attach_money),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return context.l10n.enter_valid_price;
                          }
                          if (double.tryParse(value) == null ||
                              double.parse(value) < 0) {
                            return context.l10n.enter_valid_price;
                          }
                          return null;
                        },
                      ),
                    ),
                    const Gap(16),
                    Expanded(
                      child: TextFormField(
                        controller: costPriceCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          labelText: 'سعر التكلفة',
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.money_off),
                        ),
                        validator: (value) {
                          if (value != null && value.trim().isNotEmpty) {
                            if (double.tryParse(value) == null ||
                                double.parse(value) < 0) {
                              return context.l10n.enter_valid_price;
                            }
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const Gap(16),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: quantityCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: context.l10n.quantity,
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.inventory_2),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return context.l10n.enter_valid_quantity;
                          }
                          if (int.tryParse(value) == null || int.parse(value) < 0) {
                            return context.l10n.enter_valid_quantity;
                          }
                          return null;
                        },
                      ),
                    ),
                    const Gap(16),
                    Expanded(
                      child: TextFormField(
                        controller: unitCtrl,
                        decoration: const InputDecoration(
                          labelText: 'الوحدة (مثال: قطعة)',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.ad_units),
                        ),
                      ),
                    ),
                    const Gap(16),
                    Expanded(
                      child: TextFormField(
                        controller: minStockCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'الحد الأدنى للمخزون',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.warning_amber),
                        ),
                      ),
                    ),
                  ],
                ),
                const Gap(16),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: barcodeCtrl,
                        decoration: const InputDecoration(
                          labelText: 'الباركود',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.qr_code),
                        ),
                      ),
                    ),
                    const Gap(16),
                    Expanded(
                      child: TextFormField(
                        controller: categoryCtrl,
                        decoration: const InputDecoration(
                          labelText: 'الفئة',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.category),
                        ),
                      ),
                    ),
                  ],
                ),
                const Gap(16),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: cartonQtyCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'الكمية بالكرتونة',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.inventory),
                        ),
                      ),
                    ),
                    const Gap(16),
                    Expanded(
                      child: TextFormField(
                        controller: cartonPriceCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'سعر الكرتونة',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.money),
                        ),
                      ),
                    ),
                  ],
                ),
                const Gap(16),
                DropdownButtonFormField<String>(
                  initialValue: selectedStatus,
                  decoration: InputDecoration(
                    labelText: context.l10n.status,
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.toggle_on),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'Active',
                      child: Text(context.l10n.active),
                    ),
                    DropdownMenuItem(
                      value: 'Inactive',
                      child: Text(context.l10n.inactive),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        selectedStatus = value;
                      });
                    }
                  },
                ),
                const Gap(24),
                ElevatedButton(
                  onPressed: _saveProduct,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Colors.white,
                  ),
                  child: Text(
                    widget.product == null
                        ? context.l10n.save_product
                        : context.l10n.update_product,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
