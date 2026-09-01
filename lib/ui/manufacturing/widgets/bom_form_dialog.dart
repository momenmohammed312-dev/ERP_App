import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';

class BomFormDialog extends StatefulWidget {
  final AppDatabase db;
  final BillOfMaterial? bom;

  const BomFormDialog({super.key, required this.db, this.bom});

  @override
  State<BomFormDialog> createState() => _BomFormDialogState();
}

class _BomItemRow {
  int? id; // existing BomItem id, null for new
  int? rawMaterialProductId;
  String? rawMaterialName;
  String quantityRequired;
  String unit;
  String wasteOverride;
  String notes;
  _BomItemRow({
    this.id,
    this.rawMaterialProductId,
    this.rawMaterialName,
    this.quantityRequired = '',
    this.unit = '',
    this.wasteOverride = '',
    this.notes = '',
  });
}

class _BomFormDialogState extends State<BomFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _codeCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _yieldCtrl = TextEditingController();
  final _wasteCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  String _status = 'Active';
  int? _selectedFinishedProductId;

  List<Product> _allProducts = [];
  List<Product> _finishedCandidates = [];
  List<Product> _rawCandidates = [];
  List<_BomItemRow> _items = [];
  bool _loadingProducts = true;
  bool _loadingBomItems = false;
  bool _isSubmitting = false;
  String? _errorMessage;
  double _simulatedCost = 0;

  @override
  void initState() {
    super.initState();
    _codeCtrl.text = widget.bom?.code ?? '';
    _nameCtrl.text = widget.bom?.name ?? '';
    _yieldCtrl.text = (widget.bom?.yieldQuantity ?? 1).toString();
    _wasteCtrl.text = (widget.bom?.wastePercentage ?? 0).toString();
    _notesCtrl.text = widget.bom?.notes ?? '';
    _status = widget.bom?.status ?? 'Active';
    _selectedFinishedProductId = widget.bom?.finishedProductId;
    _loadProducts();
    if (widget.bom != null) {
      _loadBomItems();
    } else {
      // Start with one empty row for convenience
      _items = [_BomItemRow()];
    }
  }

  Future<void> _loadProducts() async {
    try {
      final products = await widget.db.productDao.getAllProducts();
      setState(() {
        _allProducts = products;
        // Finished candidates: finished_product + standard (null) + semi_finished
        _finishedCandidates = products.where((p) => p.status != 'Deleted').toList();
        // Raw candidates: raw_material + standard + all, so user can pick any
        _rawCandidates = products.where((p) => p.status != 'Deleted').toList();
        _loadingProducts = false;
      });
      _recalcCost();
    } catch (e) {
      setState(() {
        _loadingProducts = false;
        _errorMessage = 'فشل تحميل المنتجات: $e';
      });
    }
  }

  Future<void> _loadBomItems() async {
    setState(() => _loadingBomItems = true);
    try {
      final bomItems = await widget.db.bomDao.getItemsForBom(widget.bom!.id);
      // Map product names
      final productMap = {for (var p in _allProducts) p.id: p};
      // If products not yet loaded, fetch again
      if (_allProducts.isEmpty) {
        final products = await widget.db.productDao.getAllProducts();
        productMap.addAll({for (var p in products) p.id: p});
      }
      setState(() {
        _items = bomItems
            .map((it) => _BomItemRow(
                  id: it.id,
                  rawMaterialProductId: it.rawMaterialProductId,
                  rawMaterialName: productMap[it.rawMaterialProductId]?.name ?? '#${it.rawMaterialProductId}',
                  quantityRequired: it.quantityRequired.toString(),
                  unit: it.unit ?? '',
                  wasteOverride: it.wastePercentageOverride?.toString() ?? '',
                  notes: it.notes ?? '',
                ))
            .toList();
        if (_items.isEmpty) _items = [_BomItemRow()];
        _loadingBomItems = false;
      });
      _recalcCost();
    } catch (e) {
      setState(() {
        _loadingBomItems = false;
        _errorMessage = 'فشل تحميل مكونات الوصفة: $e';
      });
    }
  }

  void _recalcCost() {
    double total = 0;
    for (final row in _items) {
      if (row.rawMaterialProductId == null) continue;
      final qty = double.tryParse(row.quantityRequired) ?? 0;
      if (qty <= 0) continue;
      final product = _allProducts.where((p) => p.id == row.rawMaterialProductId).firstOrNull;
      if (product == null) continue;
      final unitCost = product.costPrice ?? product.price;
      final waste = double.tryParse(row.wasteOverride) ?? double.tryParse(_wasteCtrl.text) ?? 0;
      final effective = qty * (1 + waste / 100);
      total += effective * unitCost;
    }
    setState(() => _simulatedCost = total);
  }

  void _addRow() {
    setState(() => _items.add(_BomItemRow()));
  }

  void _removeRow(int index) {
    if (_items.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('يجب أن تحتوي الوصفة على مكون واحد على الأقل')));
      return;
    }
    setState(() => _items.removeAt(index));
    _recalcCost();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedFinishedProductId == null) {
      setState(() => _errorMessage = 'يرجى اختيار المنتج النهائي');
      return;
    }
    // Validate items
    for (var i = 0; i < _items.length; i++) {
      final r = _items[i];
      if (r.rawMaterialProductId == null) {
        setState(() => _errorMessage = 'يرجى اختيار المادة الخام في السطر ${i + 1}');
        return;
      }
      final q = double.tryParse(r.quantityRequired);
      if (q == null || q <= 0) {
        setState(() => _errorMessage = 'الكمية غير صحيحة في السطر ${i + 1}');
        return;
      }
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final code = _codeCtrl.text.trim().isEmpty ? null : _codeCtrl.text.trim();
    final name = _nameCtrl.text.trim();
    final yieldQty = double.tryParse(_yieldCtrl.text.trim()) ?? 1;
    final waste = double.tryParse(_wasteCtrl.text.trim()) ?? 0;

    try {
      if (widget.bom == null) {
        // Create
        final bomCompanion = BillOfMaterialsCompanion(
          finishedProductId: Value(_selectedFinishedProductId!),
          code: Value(code),
          name: Value(name),
          yieldQuantity: Value(yieldQty),
          wastePercentage: Value(waste),
          status: Value(_status),
          notes: Value(_notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim()),
        );
        final itemCompanions = _items
            .map((r) => BomItemsCompanion(
                  bomId: const Value.absent(), // filled by DAO
                  rawMaterialProductId: Value(r.rawMaterialProductId!),
                  quantityRequired: Value(double.parse(r.quantityRequired)),
                  unit: Value(r.unit.trim().isEmpty ? null : r.unit.trim()),
                  wastePercentageOverride: Value(
                      r.wasteOverride.trim().isEmpty ? null : double.tryParse(r.wasteOverride)),
                  notes: Value(r.notes.trim().isEmpty ? null : r.notes.trim()),
                ))
            .toList();
        await widget.db.bomDao.insertBomWithItems(bom: bomCompanion, items: itemCompanions);
      } else {
        // Update header + replace items
        final headerUpdate = BillOfMaterialsCompanion(
          finishedProductId: Value(_selectedFinishedProductId!),
          code: Value(code),
          name: Value(name),
          yieldQuantity: Value(yieldQty),
          wastePercentage: Value(waste),
          status: Value(_status),
          notes: Value(_notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim()),
          updatedAt: Value(DateTime.now()),
        );
        final itemCompanions = _items
            .map((r) => BomItemsCompanion(
                  bomId: Value(widget.bom!.id),
                  rawMaterialProductId: Value(r.rawMaterialProductId!),
                  quantityRequired: Value(double.parse(r.quantityRequired)),
                  unit: Value(r.unit.trim().isEmpty ? null : r.unit.trim()),
                  wastePercentageOverride: Value(
                      r.wasteOverride.trim().isEmpty ? null : double.tryParse(r.wasteOverride)),
                  notes: Value(r.notes.trim().isEmpty ? null : r.notes.trim()),
                ))
            .toList();
        await widget.db.bomDao.replaceBomItems(
          bomId: widget.bom!.id,
          items: itemCompanions,
          bomUpdate: headerUpdate,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _isSubmitting = false;
        _errorMessage = 'فشل الحفظ: $e';
      });
    }
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _nameCtrl.dispose();
    _yieldCtrl.dispose();
    _wasteCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEdit = widget.bom != null;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 820,
        constraints: const BoxConstraints(maxHeight: 700),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(isEdit ? Icons.edit : Icons.add, color: theme.colorScheme.primary, size: 28),
                const Gap(12),
                Text(isEdit ? 'تعديل الوصفة' : 'وصفة تصنيع جديدة',
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const Divider(height: 24),
            if (_errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer, borderRadius: BorderRadius.circular(8)),
                child: Text(_errorMessage!, style: TextStyle(color: theme.colorScheme.onErrorContainer)),
              ),
              const Gap(16),
            ],
            Expanded(
              child: SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_loadingProducts)
                        const Center(child: CircularProgressIndicator())
                      else ...[
                        // Finished product picker
                        DropdownButtonFormField<int>(
                          initialValue: _selectedFinishedProductId,
                          decoration: const InputDecoration(
                            labelText: 'المنتج النهائي *',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.factory),
                            helperText: 'المنتج الذي ستنتجه هذه الوصفة',
                          ),
                          items: _finishedCandidates
                              .map((p) => DropdownMenuItem(
                                    value: p.id,
                                    child: Text(
                                        '${p.name} — ${p.quantity} ${p.unit ?? ''} ${p.productType != null ? '(${p.productType})' : ''}'),
                                  ))
                              .toList(),
                          onChanged: (v) {
                            setState(() => _selectedFinishedProductId = v);
                          },
                          validator: (v) => v == null ? 'اختر المنتج النهائي' : null,
                        ),
                        const Gap(16),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _codeCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'كود الوصفة (اختياري)',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.tag),
                                  hintText: 'BOM-CHAIR-01',
                                ),
                              ),
                            ),
                            const Gap(12),
                            Expanded(
                              child: TextFormField(
                                controller: _nameCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'اسم الوصفة *',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.receipt_long),
                                ),
                                validator: (v) =>
                                    v == null || v.trim().isEmpty ? 'الاسم مطلوب' : null,
                              ),
                            ),
                          ],
                        ),
                        const Gap(16),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _yieldCtrl,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(
                                  labelText: 'العائد (Yield) *',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.numbers),
                                  helperText: 'كم وحدة ينتجها التنفيذ الواحد',
                                ),
                                validator: (v) {
                                  final n = double.tryParse(v ?? '');
                                  if (n == null || n <= 0) return 'أدخل عائد صحيح > 0';
                                  return null;
                                },
                                onChanged: (_) => _recalcCost(),
                              ),
                            ),
                            const Gap(12),
                            Expanded(
                              child: TextFormField(
                                controller: _wasteCtrl,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(
                                  labelText: 'نسبة الهدر العامة %',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.percent),
                                  suffixText: '%',
                                ),
                                onChanged: (_) => _recalcCost(),
                              ),
                            ),
                            const Gap(12),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: _status,
                                decoration: const InputDecoration(
                                  labelText: 'الحالة',
                                  border: OutlineInputBorder(),
                                ),
                                items: const [
                                  DropdownMenuItem(value: 'Active', child: Text('مفعلة')),
                                  DropdownMenuItem(value: 'Inactive', child: Text('غير مفعلة')),
                                ],
                                onChanged: (v) => setState(() => _status = v ?? 'Active'),
                              ),
                            ),
                          ],
                        ),
                        const Gap(16),
                        TextFormField(
                          controller: _notesCtrl,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            labelText: 'ملاحظات',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.note_alt_outlined),
                          ),
                        ),
                      ],
                      const Gap(20),
                      Row(
                        children: [
                          Text('مكونات الوصفة', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                          const Spacer(),
                          FilledButton.icon(
                            onPressed: _addRow,
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('إضافة مكون'),
                          ),
                        ],
                      ),
                      const Gap(8),
                      if (_loadingBomItems)
                        const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
                      else
                        Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: theme.dividerColor.withValues(alpha: 0.3)),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            children: [
                              // Header — theme-aware, not white-on-white
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surfaceContainerHighest,
                                  borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(flex: 3, child: Text('المادة الخام *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: theme.colorScheme.onSurface))),
                                    const Gap(6),
                                    Expanded(flex: 2, child: Text('الكمية *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: theme.colorScheme.onSurface))),
                                    const Gap(6),
                                    Expanded(flex: 1, child: Text('الوحدة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: theme.colorScheme.onSurface))),
                                    const Gap(6),
                                    Expanded(flex: 1, child: Text('هدر %', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: theme.colorScheme.onSurface))),
                                    const SizedBox(width: 40),
                                  ],
                                ),
                              ),
                              ..._items.asMap().entries.map((entry) {
                                final idx = entry.key;
                                final row = entry.value;
                                // Per-row label + cost hint
                                final productForRow = row.rawMaterialProductId != null
                                    ? _allProducts.where((p) => p.id == row.rawMaterialProductId).firstOrNull
                                    : null;
                                final lineCost = (() {
                                  final q = double.tryParse(row.quantityRequired) ?? 0;
                                  if (q <= 0 || productForRow == null) return null;
                                  final waste = double.tryParse(row.wasteOverride) ?? double.tryParse(_wasteCtrl.text) ?? 0;
                                  final eff = q * (1 + waste / 100);
                                  return eff * (productForRow.costPrice ?? productForRow.price);
                                })();
                                return Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            flex: 3,
                                            child: DropdownButtonFormField<int>(
                                              initialValue: row.rawMaterialProductId,
                                              isExpanded: true,
                                              decoration: InputDecoration(
                                                labelText: 'المادة الخام *',
                                                hintText: 'اختر مادة',
                                                border: const OutlineInputBorder(),
                                                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                                                filled: true,
                                                fillColor: theme.colorScheme.surface,
                                              ),
                                              items: _rawCandidates
                                                  .map((p) => DropdownMenuItem(
                                                        value: p.id,
                                                        child: Text(
                                                          '${p.name} (${p.quantity} ${p.unit ?? ''})',
                                                          overflow: TextOverflow.ellipsis,
                                                          style: const TextStyle(fontSize: 12),
                                                        ),
                                                      ))
                                                  .toList(),
                                              onChanged: (v) {
                                                setState(() {
                                                  row.rawMaterialProductId = v;
                                                  final m = _allProducts.where((pp) => pp.id == v);
                                                  row.rawMaterialName = m.isNotEmpty ? m.first.name : null;
                                                  if (m.isNotEmpty && (row.unit.isEmpty)) {
                                                    row.unit = m.first.unit ?? '';
                                                  }
                                                });
                                                _recalcCost();
                                              },
                                            ),
                                          ),
                                          const Gap(6),
                                          Expanded(
                                            flex: 2,
                                            child: TextFormField(
                                              initialValue: row.quantityRequired,
                                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                              decoration: InputDecoration(
                                                labelText: 'الكمية *',
                                                hintText: '0.0',
                                                border: const OutlineInputBorder(),
                                                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                                                filled: true,
                                                fillColor: theme.colorScheme.surface,
                                              ),
                                              onChanged: (v) {
                                                row.quantityRequired = v;
                                                _recalcCost();
                                              },
                                            ),
                                          ),
                                          const Gap(6),
                                          Expanded(
                                            flex: 1,
                                            child: TextFormField(
                                              initialValue: row.unit,
                                              decoration: InputDecoration(
                                                labelText: 'الوحدة',
                                                hintText: 'قطعة',
                                                border: const OutlineInputBorder(),
                                                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                                                filled: true,
                                                fillColor: theme.colorScheme.surface,
                                              ),
                                              onChanged: (v) => row.unit = v,
                                            ),
                                          ),
                                          const Gap(6),
                                          Expanded(
                                            flex: 1,
                                            child: TextFormField(
                                              initialValue: row.wasteOverride,
                                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                              decoration: InputDecoration(
                                                labelText: 'هدر %',
                                                hintText: '0',
                                                border: const OutlineInputBorder(),
                                                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                                                filled: true,
                                                fillColor: theme.colorScheme.surface,
                                              ),
                                              onChanged: (v) {
                                                row.wasteOverride = v;
                                                _recalcCost();
                                              },
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                                            tooltip: 'حذف السطر',
                                            onPressed: () => _removeRow(idx),
                                          ),
                                        ],
                                      ),
                                      if (lineCost != null) ...[
                                        const Gap(4),
                                        Align(
                                          alignment: Alignment.centerLeft,
                                          child: Text(
                                            'تكلفة السطر: ${lineCost.toStringAsFixed(2)} ج.م',
                                            style: TextStyle(fontSize: 11, color: theme.colorScheme.primary, fontWeight: FontWeight.w600),
                                          ),
                                        ),
                                      ] else if (row.rawMaterialProductId != null) ...[
                                        const Gap(4),
                                        Text(
                                          'سعر التكلفة غير محدد للخامة — ادخل سعر التكلفة في بطاقة المنتج',
                                          style: TextStyle(fontSize: 11, color: Colors.orange.shade700),
                                        ),
                                      ],
                                    ],
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                      const Gap(12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calculate, size: 18),
                            const Gap(8),
                            Text('التكلفة المادية التقديرية:',
                                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
                            const Spacer(),
                            Text('${_simulatedCost.toStringAsFixed(2)} ج.م',
                                style: theme.textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
                          ],
                        ),
                      ),
                      if (_selectedFinishedProductId != null && _yieldCtrl.text.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'تكلفة الوحدة ≈ ${(double.tryParse(_yieldCtrl.text) != null && double.parse(_yieldCtrl.text) > 0 ? (_simulatedCost / double.parse(_yieldCtrl.text)).toStringAsFixed(2) : '-')} ج.م / وحدة',
                            style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade700),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const Gap(16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                    onPressed: _isSubmitting ? null : () => Navigator.pop(context),
                    child: const Text('إلغاء')),
                const Gap(12),
                ElevatedButton.icon(
                  onPressed: _isSubmitting ? null : _submit,
                  icon: _isSubmitting
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(isEdit ? Icons.save : Icons.check),
                  label: Text(isEdit ? 'حفظ التعديلات' : 'إنشاء الوصفة'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
