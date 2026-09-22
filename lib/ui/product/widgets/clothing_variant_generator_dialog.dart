import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:pos_offline_desktop/core/config/clothing_constants.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';

/// Dialog to generate multiple size & color variants for a clothing garment in 1 click.
class ClothingVariantGeneratorDialog extends StatefulWidget {
  final AppDatabase db;

  const ClothingVariantGeneratorDialog({super.key, required this.db});

  @override
  State<ClothingVariantGeneratorDialog> createState() =>
      _ClothingVariantGeneratorDialogState();
}

class _ClothingVariantGeneratorDialogState
    extends State<ClothingVariantGeneratorDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _costPriceCtrl = TextEditingController();
  final _quantityCtrl = TextEditingController(text: '5');
  final _minStockCtrl = TextEditingController(text: '1');

  String? _selectedCategory = ClothingConstants.defaultCategories.first;
  String _activeSizeType = 'alpha'; // alpha, numeric, shoes, kids

  final Set<String> _selectedSizes = {};
  final Set<String> _selectedColors = {};
  bool _isGenerating = false;

  List<String> get _currentSizes {
    switch (_activeSizeType) {
      case 'numeric':
        return ClothingConstants.pantsSizes;
      case 'shoes':
        return ClothingConstants.shoeSizes;
      case 'kids':
        return ClothingConstants.kidsSizes;
      case 'alpha':
      default:
        return ClothingConstants.alphaSizes;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _costPriceCtrl.dispose();
    _quantityCtrl.dispose();
    _minStockCtrl.dispose();
    super.dispose();
  }

  int get _totalVariantsCount {
    final sizesCount = _selectedSizes.isEmpty ? 1 : _selectedSizes.length;
    final colorsCount = _selectedColors.isEmpty ? 1 : _selectedColors.length;
    if (_selectedSizes.isEmpty && _selectedColors.isEmpty) return 0;
    return sizesCount * colorsCount;
  }

  Future<void> _generateVariants() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedSizes.isEmpty && _selectedColors.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى اختيار مقاس أو لون واحد على الأقل'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isGenerating = true);

    try {
      final baseName = _nameCtrl.text.trim();
      final price = double.tryParse(_priceCtrl.text) ?? 0.0;
      final costPrice = double.tryParse(_costPriceCtrl.text);
      final qty = int.tryParse(_quantityCtrl.text) ?? 0;
      final minStock = int.tryParse(_minStockCtrl.text) ?? 0;

      final sizesList = _selectedSizes.isEmpty
          ? [null]
          : _selectedSizes.toList();
      final colorsList = _selectedColors.isEmpty
          ? [null]
          : _selectedColors.toList();

      int createdCount = 0;

      for (final color in colorsList) {
        for (final size in sizesList) {
          // Construct product name
          final parts = [baseName];
          if (color != null) parts.add(color);
          if (size != null) parts.add(size);
          final fullName = parts.join(' - ');

          await widget.db.productDao.insertProduct(
            ProductsCompanion(
              name: Value(fullName),
              price: Value(price),
              costPrice: Value(costPrice),
              quantity: Value(qty),
              minStockLevel: Value(minStock),
              category: Value(_selectedCategory),
              unit: const Value('قطعة'),
              status: const Value('Active'),
              size: Value(size),
              color: Value(color),
            ),
          );
          createdCount++;
        }
      }

      if (mounted) {
        Navigator.of(context).pop(createdCount);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ أثناء إنشاء الأصناف: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 750),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.auto_awesome,
                          color: Colors.purple,
                          size: 28,
                        ),
                        Gap(10),
                        Text(
                          'توليد مقاسات وألوان متعددة للملابس',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const Divider(),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Gap(10),
                        TextFormField(
                          controller: _nameCtrl,
                          decoration: const InputDecoration(
                            labelText:
                                'اسم المنتج الأساسي (مثلاً: تيشيرت بولو قطن)',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.shopping_bag_outlined),
                          ),
                          validator: (v) =>
                              (v == null || v.trim().isEmpty) ? 'مطلوب' : null,
                        ),
                        const Gap(14),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: _selectedCategory,
                                decoration: const InputDecoration(
                                  labelText: 'التصنيف',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.category_outlined),
                                ),
                                items: ClothingConstants.defaultCategories
                                    .map(
                                      (cat) => DropdownMenuItem(
                                        value: cat,
                                        child: Text(cat),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (v) =>
                                    setState(() => _selectedCategory = v),
                              ),
                            ),
                            const Gap(14),
                            Expanded(
                              child: TextFormField(
                                controller: _priceCtrl,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: const InputDecoration(
                                  labelText: 'سعر البيع',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.attach_money),
                                ),
                                validator: (v) =>
                                    (v == null || v.trim().isEmpty)
                                    ? 'مطلوب'
                                    : null,
                              ),
                            ),
                          ],
                        ),
                        const Gap(14),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _costPriceCtrl,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                decoration: const InputDecoration(
                                  labelText: 'سعر التكلفة (اختياري)',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.price_change_outlined),
                                ),
                              ),
                            ),
                            const Gap(14),
                            Expanded(
                              child: TextFormField(
                                controller: _quantityCtrl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'الكمية الابتدائية لكل مقاس/لون',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.inventory_2_outlined),
                                ),
                              ),
                            ),
                            const Gap(14),
                            Expanded(
                              child: TextFormField(
                                controller: _minStockCtrl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'الحد الأدنى للتنبيه',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(
                                    Icons.warning_amber_outlined,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Gap(20),
                        const Text(
                          '1. اختر المقاسات المطلوبة:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const Gap(8),
                        Wrap(
                          spacing: 8,
                          children: [
                            ChoiceChip(
                              label: const Text('أحرف (XS..5XL)'),
                              selected: _activeSizeType == 'alpha',
                              onSelected: (_) =>
                                  setState(() => _activeSizeType = 'alpha'),
                            ),
                            ChoiceChip(
                              label: const Text('بناطيل (28..48)'),
                              selected: _activeSizeType == 'numeric',
                              onSelected: (_) =>
                                  setState(() => _activeSizeType = 'numeric'),
                            ),
                            ChoiceChip(
                              label: const Text('أحذية (36..46)'),
                              selected: _activeSizeType == 'shoes',
                              onSelected: (_) =>
                                  setState(() => _activeSizeType = 'shoes'),
                            ),
                            ChoiceChip(
                              label: const Text('أطفال (أشهر / سنوات)'),
                              selected: _activeSizeType == 'kids',
                              onSelected: (_) =>
                                  setState(() => _activeSizeType = 'kids'),
                            ),
                          ],
                        ),
                        const Gap(8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: _currentSizes.map((size) {
                            final isSel = _selectedSizes.contains(size);
                            return FilterChip(
                              label: Text(size),
                              selected: isSel,
                              onSelected: (sel) {
                                setState(() {
                                  if (sel) {
                                    _selectedSizes.add(size);
                                  } else {
                                    _selectedSizes.remove(size);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                        const Gap(20),
                        const Text(
                          '2. اختر الألوان المطلوبة:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const Gap(8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: ClothingConstants.commonColors.map((entry) {
                            final name = entry['name'] as String;
                            final color = entry['color'] as Color;
                            final isSel = _selectedColors.contains(name);
                            return FilterChip(
                              avatar: CircleAvatar(
                                backgroundColor: color,
                                radius: 8,
                                child: Container(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.grey.shade400,
                                      width: 0.5,
                                    ),
                                  ),
                                ),
                              ),
                              label: Text(name),
                              selected: isSel,
                              onSelected: (sel) {
                                setState(() {
                                  if (sel) {
                                    _selectedColors.add(name);
                                  } else {
                                    _selectedColors.remove(name);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                        const Gap(20),
                        if (_totalVariantsCount > 0)
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.purple.withAlpha(25),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.purple.shade200),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.info_outline,
                                  color: Colors.purple,
                                ),
                                const Gap(10),
                                Text(
                                  'سيتم إنشاء $_totalVariantsCount صنفاً مستقلاً، وتوليد باركود فريد لكل منها.',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.purple,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const Gap(16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('إلغاء'),
                    ),
                    const Gap(10),
                    ElevatedButton.icon(
                      onPressed: _isGenerating ? null : _generateVariants,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                      icon: _isGenerating
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.auto_awesome),
                      label: Text(
                        _isGenerating
                            ? 'جاري الإنشاء...'
                            : 'إنشاء الأصناف ($_totalVariantsCount)',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
