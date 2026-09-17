import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/l10n/l10n.dart';
import 'package:pos_offline_desktop/core/services/audit_log_service.dart';

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
  bool isBarneka = false;
  String? selectedProductType; // null = standard, 'raw_material' | 'semi_finished' | 'finished_product'

  // أصناف المنتج (ألوان/فئات): موجودة (من الـ DB) + مسودات جديدة + محذوفة + معدلة.
  List<ProductVariant> _variants = [];
  final List<_VariantDraft> _drafts = [];
  final Set<int> _removedVariantIds = {};
  final Set<int> _dirtyVariantIds = {};
  bool _loadingVariants = false;

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
      text: widget.product?.minStockLevel.toString() ?? '0',
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
    isBarneka = widget.product?.barneka ?? false;
    selectedProductType = widget.product?.productType;
    if (widget.product != null) _loadVariants();
  }

  Future<void> _loadVariants() async {
    setState(() => _loadingVariants = true);
    try {
      final list = await widget.db.productVariantDao.getVariantsByProduct(
        widget.product!.id,
      );
      if (mounted) {
        setState(() {
          _variants = list;
          _loadingVariants = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingVariants = false);
    }
  }

  List<ProductVariant> get _activeVariants =>
      _variants.where((v) => !_removedVariantIds.contains(v.id)).toList();

  bool get _hasVariants => _activeVariants.isNotEmpty || _drafts.isNotEmpty;

  /// مجموع كميات الأصناف — يصبح كمية الأب تلقائيًا عند الحفظ.
  int get _variantsTotal =>
      _activeVariants.fold<int>(0, (s, v) => s + v.quantity) +
      _drafts.fold<int>(0, (s, d) => s + d.quantity);

  /// فحص تعارض باركود صنف مع المنتجات والأصناف الأخرى.
  Future<String?> _variantBarcodeConflict(
    String barcode, {
    int? excludeVariantId,
  }) async {
    final p = await widget.db.productDao.getProductByBarcode(barcode);
    if (p != null && (widget.product == null || p.id != widget.product!.id)) {
      return 'الباركود مستخدم بالفعل للمنتج «${p.name}»';
    }
    final v = await widget.db.productVariantDao.getVariantByBarcode(barcode);
    if (v != null &&
        v.id != excludeVariantId &&
        !_removedVariantIds.contains(v.id)) {
      return 'الباركود مستخدم بالفعل للصنف «${v.name}»';
    }
    return null;
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

  // ── الأصناف (ألوان/فئات) ──────────────────────────────────────────

  Widget _buildVariantsSection() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.palette_outlined),
                const Gap(8),
                const Expanded(
                  child: Text(
                    'الأصناف (ألوان/فئات)',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
                if (_hasVariants)
                  Chip(
                    label: Text('المجموع: $_variantsTotal'),
                    visualDensity: VisualDensity.compact,
                  ),
                IconButton(
                  icon: const Icon(Icons.add_circle, color: Colors.green),
                  tooltip: 'إضافة صنف',
                  onPressed: () => _showVariantDialog(),
                ),
              ],
            ),
            const Text(
              'كل صنف له كمية وباركود مستقل، وسعر اختياري (الفارغ = سعر المنتج).',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const Gap(8),
            if (_loadingVariants)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (!_hasVariants)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  'لا توجد أصناف — المنتج يُباع كوحدة واحدة.',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
              )
            else ...[
              for (final v in _activeVariants)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.label_outline),
                  title: Text(
                    v.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    'كمية: ${v.quantity}'
                    ' • سعر: ${v.price?.toStringAsFixed(2) ?? 'مثل المنتج'}'
                    '${(v.barcode?.trim().isNotEmpty ?? false) ? ' • ${v.barcode}' : ''}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, size: 20),
                        tooltip: 'تعديل',
                        onPressed: () => _showVariantDialog(existing: v),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          size: 20,
                          color: Colors.red,
                        ),
                        tooltip: 'حذف',
                        onPressed: () => _confirmRemoveVariant(v),
                      ),
                    ],
                  ),
                ),
              for (var i = 0; i < _drafts.length; i++)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.fiber_new_outlined,
                    color: Colors.green.shade700,
                  ),
                  title: Text(
                    '${_drafts[i].name} (جديد)',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    'كمية: ${_drafts[i].quantity}'
                    ' • سعر: ${_drafts[i].price?.toStringAsFixed(2) ?? 'مثل المنتج'}'
                    '${(_drafts[i].barcode?.trim().isNotEmpty ?? false) ? ' • ${_drafts[i].barcode}' : ''}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, size: 20),
                        tooltip: 'تعديل',
                        onPressed: () =>
                            _showVariantDialog(draftIndex: i),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          size: 20,
                          color: Colors.red,
                        ),
                        tooltip: 'حذف',
                        onPressed: () =>
                            setState(() => _drafts.removeAt(i)),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _confirmRemoveVariant(ProductVariant v) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف الصنف'),
        content: Text(
          'حذف الصنف «${v.name}»؟ (حذف آمن: لو عليه حركات بيع سابقة يتحول لمحذوف بدل الحذف النهائي)',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      setState(() {
        _removedVariantIds.add(v.id);
        _dirtyVariantIds.remove(v.id);
      });
    }
  }

  /// حوار إضافة/تعديل صنف. [existing] للتعديل على صنف محفوظ،
  /// [draftIndex] للتعديل على مسودة جديدة، وبدونهما = مسودة جديدة.
  Future<void> _showVariantDialog({
    ProductVariant? existing,
    int? draftIndex,
  }) async {
    final nameCtrl = TextEditingController(
      text: existing?.name ??
          (draftIndex != null ? _drafts[draftIndex].name : ''),
    );
    final qtyCtrl = TextEditingController(
      text: (existing?.quantity ?? (draftIndex != null ? _drafts[draftIndex].quantity : 0))
          .toString(),
    );
    final priceCtrl = TextEditingController(
      text: existing?.price?.toString() ??
          (draftIndex != null ? _drafts[draftIndex].price?.toString() : '') ??
          '',
    );
    final barcodeCtrl = TextEditingController(
      text: existing?.barcode ??
          (draftIndex != null ? _drafts[draftIndex].barcode : '') ??
          '',
    );
    final formKey = GlobalKey<FormState>();

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(existing != null ? 'تعديل الصنف' : 'إضافة صنف جديد'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameCtrl,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'اسم الصنف (اللون/الفئة) *',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.label),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'أدخل اسم الصنف'
                        : null,
                  ),
                  const Gap(12),
                  TextFormField(
                    controller: qtyCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'الكمية *',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.inventory_2),
                    ),
                    validator: (v) {
                      final q = int.tryParse(v ?? '');
                      if (q == null || q < 0) return 'أدخل كمية صحيحة (0 أو أكثر)';
                      return null;
                    },
                  ),
                  const Gap(12),
                  TextFormField(
                    controller: priceCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'السعر (فارغ = سعر المنتج)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.attach_money),
                    ),
                    validator: (v) {
                      if (v != null && v.trim().isNotEmpty) {
                        final p = double.tryParse(v);
                        if (p == null || p < 0) return 'أدخل سعرًا صحيحًا';
                      }
                      return null;
                    },
                  ),
                  const Gap(12),
                  TextFormField(
                    controller: barcodeCtrl,
                    decoration: const InputDecoration(
                      labelText: 'الباركود (فارغ = يتولد تلقائيًا)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.qr_code),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (!(formKey.currentState?.validate() ?? false)) return;
                final bc = barcodeCtrl.text.trim();
                if (bc.isNotEmpty) {
                  final conflict = await _variantBarcodeConflict(
                    bc,
                    excludeVariantId: existing?.id,
                  );
                  if (conflict != null) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(conflict),
                          backgroundColor: Colors.orange,
                        ),
                      );
                    }
                    return;
                  }
                }
                if (context.mounted) Navigator.pop(context, true);
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );

    final name = nameCtrl.text.trim();
    final qty = int.tryParse(qtyCtrl.text) ?? 0;
    final price = priceCtrl.text.trim().isEmpty
        ? null
        : double.tryParse(priceCtrl.text.trim());
    final barcode = barcodeCtrl.text.trim().isEmpty
        ? null
        : barcodeCtrl.text.trim();
    nameCtrl.dispose();
    qtyCtrl.dispose();
    priceCtrl.dispose();
    barcodeCtrl.dispose();

    if (saved != true || !mounted) return;
    setState(() {
      if (existing != null) {
        final i = _variants.indexWhere((v) => v.id == existing.id);
        if (i >= 0) {
          _variants[i] = existing.copyWith(
            name: name,
            quantity: qty,
            price: Value(price),
            barcode: Value(barcode),
          );
          _dirtyVariantIds.add(existing.id);
        }
      } else if (draftIndex != null) {
        _drafts[draftIndex] = _VariantDraft(
          name: name,
          quantity: qty,
          price: price,
          barcode: barcode,
        );
      } else {
        _drafts.add(
          _VariantDraft(
            name: name,
            quantity: qty,
            price: price,
            barcode: barcode,
          ),
        );
      }
    });
  }

  Future<void> _saveProduct() async {
    if (_formKey.currentState!.validate()) {
      try {
        final newPrice = double.tryParse(priceCtrl.text) ?? 0;
        final newQuantity = int.tryParse(quantityCtrl.text) ?? 0;
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
          if (!mounted) return;
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

        // تحقق من باركودات الأصناف (تعارض مع منتج/صنف آخر + تكرار داخلي)
        final seenBarcodes = <String>{};
        for (final d in _drafts) {
          final bc = d.barcode?.trim() ?? '';
          if (bc.isEmpty) continue;
          if (!seenBarcodes.add(bc)) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('الباركود $bc مكرر بين الأصناف'),
                  backgroundColor: Colors.orange,
                ),
              );
            }
            return;
          }
          final conflict = await _variantBarcodeConflict(bc);
          if (conflict != null) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(conflict), backgroundColor: Colors.orange),
              );
            }
            return;
          }
        }
        for (final v in _activeVariants) {
          final bc = v.barcode?.trim() ?? '';
          if (bc.isEmpty) continue;
          if (!seenBarcodes.add(bc)) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('الباركود $bc مكرر بين الأصناف'),
                  backgroundColor: Colors.orange,
                ),
              );
            }
            return;
          }
          final conflict = await _variantBarcodeConflict(
            bc,
            excludeVariantId: v.id,
          );
          if (conflict != null) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(conflict), backgroundColor: Colors.orange),
              );
            }
            return;
          }
        }

        // كمية الأب = مجموع الأصناف لو فيه أصناف، وإلا الكمية المدخلة.
        final effectiveQuantity = _hasVariants ? _variantsTotal : newQuantity;

        if (widget.product == null) {
          // إضافة: المنتج + أصنافه في transaction واحدة
          await widget.db.transaction(() async {
            final newId = await widget.db.productDao.insertProduct(
              ProductsCompanion.insert(
                name: nameCtrl.text,
                price: newPrice,
                quantity: effectiveQuantity,
                minStockLevel: Value(newMinStock),
                costPrice: Value(newCostPrice),
                barcode: Value(newBarcode),
                category: Value(newCategory),
                unit: Value(newUnit),
                cartonQuantity: Value(newCartonQty),
                cartonPrice: Value(newCartonPrice),
                status: Value(selectedStatus),
                barneka: Value(isBarneka),
                productType: Value(selectedProductType),
              ),
            );
            for (final d in _drafts) {
              await widget.db.productVariantDao.insertVariant(
                ProductVariantsCompanion.insert(
                  productId: newId,
                  name: d.name,
                  quantity: Value(d.quantity),
                  price: Value(d.price),
                  barcode: Value(d.barcode),
                ),
              );
            }
          });
        } else {
          // تعديل: المنتج + مزامنة أصنافه (إضافة/تعديل/حذف) في transaction واحدة
          final oldProduct = widget.product!;
          final updatedProduct = widget.product!.copyWith(
            name: nameCtrl.text,
            price: newPrice,
            quantity: effectiveQuantity,
            minStockLevel: newMinStock,
            costPrice: Value(newCostPrice),
            barcode: Value(newBarcode),
            category: Value(newCategory),
            unit: Value(newUnit),
            cartonQuantity: Value(newCartonQty),
            cartonPrice: Value(newCartonPrice),
            status: Value(selectedStatus),
            barneka: isBarneka,
            productType: Value(selectedProductType),
          );

          await widget.db.transaction(() async {
            await widget.db.productDao.updateProduct(updatedProduct);
            for (final v in _variants) {
              if (_removedVariantIds.contains(v.id)) {
                await widget.db.productVariantDao.deleteVariant(v);
              } else if (_dirtyVariantIds.contains(v.id)) {
                await widget.db.productVariantDao.updateVariant(v);
              }
            }
            for (final d in _drafts) {
              await widget.db.productVariantDao.insertVariant(
                ProductVariantsCompanion.insert(
                  productId: oldProduct.id,
                  name: d.name,
                  quantity: Value(d.quantity),
                  price: Value(d.price),
                  barcode: Value(d.barcode),
                ),
              );
            }
          });

          // Audit Log (non-blocking: failure must not break the product save)
          try {
            await AuditService.log(
              db: widget.db,
              action: 'UPDATE',
              tableName: 'products',
              recordId: updatedProduct.id,
              details: 'تعديل منتج: ${updatedProduct.name}',
              oldValue: oldProduct.toJson(),
              newValue: updatedProduct.toJson(),
            );
          } catch (auditErr) {
            debugPrint('Audit log skipped (non-fatal): $auditErr');
          }
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
                        enabled: !_hasVariants,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: context.l10n.quantity,
                          helperText: _hasVariants
                              ? 'تُحسب تلقائيًا = مجموع الأصناف ($_variantsTotal)'
                              : null,
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
                _buildVariantsSection(),
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
                const Gap(16),
                DropdownButtonFormField<String?>(
                  initialValue: selectedProductType,
                  decoration: const InputDecoration(
                    labelText: 'نوع المنتج',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.factory),
                    helperText: 'يحدد هل المنتج مادة خام أم منتج تام للتصنيع',
                  ),
                  items: const [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text('عادي / للبيع المباشر'),
                    ),
                    DropdownMenuItem<String?>(
                      value: 'raw_material',
                      child: Text('مادة خام'),
                    ),
                    DropdownMenuItem<String?>(
                      value: 'semi_finished',
                      child: Text('نصف مصنع'),
                    ),
                    DropdownMenuItem<String?>(
                      value: 'finished_product',
                      child: Text('منتج تام (مُصنع)'),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      selectedProductType = value;
                    });
                  },
                ),
                const Gap(16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.eco),
                  title: const Text('منتج برنيكه (عبوة قابلة للاسترجاع)'),
                  subtitle: const Text('يُتتبَّع للعملاء: كم أخذ وكم رجع من العبوات'),
                  value: isBarneka,
                  onChanged: (value) {
                    setState(() {
                      isBarneka = value;
                    });
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

/// مسودة صنف جديد (قبل حفظ المنتج — لسه مالوش id).
class _VariantDraft {
  String name;
  int quantity;
  double? price;
  String? barcode;

  _VariantDraft({
    required this.name,
    required this.quantity,
    this.price,
    this.barcode,
  });
}
