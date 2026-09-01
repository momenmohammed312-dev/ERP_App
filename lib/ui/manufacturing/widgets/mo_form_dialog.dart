import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_orders_table.dart';

class MoFormDialog extends StatefulWidget {
  final AppDatabase db;
  final ManufacturingOrder? order;
  const MoFormDialog({super.key, required this.db, this.order});

  @override
  State<MoFormDialog> createState() => _MoFormDialogState();
}

class _MoFormDialogState extends State<MoFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _orderNumberCtrl = TextEditingController();
  final _plannedQtyCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  int? _selectedBomId;
  BillOfMaterial? _selectedBom;
  Product? _finishedProduct;
  List<BillOfMaterial> _activeBoms = [];
  Map<int, Product> _productMap = {};
  bool _loadingBoms = true;
  bool _isSubmitting = false;
  String? _errorMessage;
  DateTime? _plannedDate;

  @override
  void initState() {
    super.initState();
    if (widget.order != null) {
      final o = widget.order!;
      _orderNumberCtrl.text = o.orderNumber;
      _plannedQtyCtrl.text = o.plannedQuantity.toString();
      _notesCtrl.text = o.notes ?? '';
      _selectedBomId = o.bomId;
      _plannedDate = o.plannedDate;
    } else {
      _orderNumberCtrl.text = 'MO-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}';
      _plannedQtyCtrl.text = '1';
      _plannedDate = DateTime.now();
    }
    _loadBoms();
  }

  Future<void> _loadBoms() async {
    try {
      final boms = await widget.db.bomDao.getActiveBoms();
      final products = await widget.db.productDao.getAllProducts();
      final map = {for (var p in products) p.id: p};
      setState(() {
        _activeBoms = boms;
        _productMap = map;
        _loadingBoms = false;
        if (_selectedBomId != null) {
          final match = boms.where((b) => b.id == _selectedBomId);
          if (match.isNotEmpty) {
            _selectedBom = match.first;
            _finishedProduct = map[_selectedBom!.finishedProductId];
          } else {
            // Try to load the BOM even if inactive (for edit)
            widget.db.bomDao.getBomById(_selectedBomId!).then((b) {
              if (b != null && mounted) {
                setState(() {
                  _selectedBom = b;
                  _finishedProduct = map[b.finishedProductId];
                });
              }
            });
          }
        }
      });
    } catch (e) {
      setState(() {
        _loadingBoms = false;
        _errorMessage = 'فشل تحميل الوصفات: $e';
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedBomId == null) {
      setState(() => _errorMessage = 'يرجى اختيار الوصفة (BOM)');
      return;
    }
    final qty = double.tryParse(_plannedQtyCtrl.text.trim());
    if (qty == null || qty <= 0) {
      setState(() => _errorMessage = 'الكمية المخططة غير صحيحة');
      return;
    }
    // Check orderNumber uniqueness on create
    final orderNumber = _orderNumberCtrl.text.trim();
    if (widget.order == null) {
      final existing = await widget.db.manufacturingOrderDao.getByOrderNumber(orderNumber);
      if (existing != null) {
        setState(() => _errorMessage = 'رقم الأمر موجود بالفعل');
        return;
      }
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      // Resolve finishedProductId from BOM if not already
      BillOfMaterial? bom = _selectedBom;
      bom ??= await widget.db.bomDao.getBomById(_selectedBomId!);
      if (bom == null) throw Exception('الوصفة غير موجودة');
      final finishedId = bom.finishedProductId;

      if (widget.order == null) {
        final companion = ManufacturingOrdersCompanion(
          orderNumber: Value(orderNumber),
          bomId: Value(_selectedBomId!),
          finishedProductId: Value(finishedId),
          plannedQuantity: Value(qty),
          plannedDate: Value(_plannedDate),
          notes: Value(_notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim()),
          status: const Value(ManufacturingOrderStatus.planned),
        );
        await widget.db.manufacturingOrderDao.createOrder(companion);
      } else {
        // Update allowed only for planned orders in Phase 3 (no stock effect)
        if (widget.order!.status != ManufacturingOrderStatus.planned) {
          throw StateError('لا يمكن تعديل أمر غير مخطط (الحالة الحالية: ${widget.order!.status})');
        }
        final updated = widget.order!.copyWith(
          orderNumber: orderNumber,
          bomId: _selectedBomId!,
          finishedProductId: finishedId,
          plannedQuantity: qty,
          plannedDate: Value(_plannedDate),
          notes: Value(_notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim()),
          updatedAt: DateTime.now(),
        );
        await widget.db.manufacturingOrderDao.updateOrder(updated);
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
    _orderNumberCtrl.dispose();
    _plannedQtyCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEdit = widget.order != null;
    final canEdit = !isEdit || widget.order!.status == ManufacturingOrderStatus.planned;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 560,
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(isEdit ? Icons.edit : Icons.add, color: theme.colorScheme.primary, size: 28),
                    const Gap(12),
                    Text(isEdit ? 'تعديل أمر التصنيع' : 'أمر تصنيع جديد',
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
                if (!canEdit)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.amber.shade200)),
                    child: Text('هذا الأمر في حالة "${widget.order!.status}" ولا يمكن تعديل بياناته الأساسية في هذه المرحلة.',
                        style: TextStyle(color: Colors.amber.shade900)),
                  ),
                if (!canEdit) const Gap(16),
                if (_loadingBoms)
                  const Center(child: CircularProgressIndicator())
                else ...[
                  DropdownButtonFormField<int>(
                    initialValue: _selectedBomId,
                    decoration: const InputDecoration(
                      labelText: 'الوصفة (BOM) *',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.receipt_long),
                    ),
                    items: _activeBoms
                        .map((b) {
                          final product = _productMap[b.finishedProductId];
                          return DropdownMenuItem(
                            value: b.id,
                            child: Text('${b.name} — ${product?.name ?? '#${b.finishedProductId}'} ${b.code != null ? '(${b.code})' : ''}'),
                          );
                        })
                        .toList(),
                    onChanged: canEdit
                        ? (v) {
                            setState(() {
                              _selectedBomId = v;
                              final m = _activeBoms.where((bb) => bb.id == v);
                              _selectedBom = m.isNotEmpty ? m.first : null;
                              _finishedProduct = _selectedBom != null ? _productMap[_selectedBom!.finishedProductId] : null;
                            });
                          }
                        : null,
                    validator: (v) => v == null ? 'اختر الوصفة' : null,
                  ),
                  const Gap(16),
                  if (_finishedProduct != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
                      child: Row(
                        children: [
                          const Icon(Icons.factory, size: 18, color: Colors.green),
                          const Gap(8),
                          Text('المنتج النهائي: ${_finishedProduct!.name} — مخزون حالي: ${_finishedProduct!.quantity} ${_finishedProduct!.unit ?? ''}',
                              style: TextStyle(color: Colors.green.shade800, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  if (_finishedProduct != null) const Gap(16),
                  TextFormField(
                    controller: _orderNumberCtrl,
                    enabled: canEdit,
                    decoration: const InputDecoration(
                      labelText: 'رقم الأمر *',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.tag),
                    ),
                    validator: (v) => v == null || v.trim().isEmpty ? 'رقم الأمر مطلوب' : null,
                  ),
                  const Gap(16),
                  TextFormField(
                    controller: _plannedQtyCtrl,
                    enabled: canEdit,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'الكمية المخططة *',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.numbers),
                      helperText: 'عدد وحدات المنتج النهائي المطلوب إنتاجها',
                    ),
                    validator: (v) {
                      final n = double.tryParse(v ?? '');
                      if (n == null || n <= 0) return 'أدخل كمية صحيحة > 0';
                      return null;
                    },
                  ),
                  const Gap(16),
                  InkWell(
                    onTap: canEdit
                        ? () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: _plannedDate ?? DateTime.now(),
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2100),
                            );
                            if (picked != null) setState(() => _plannedDate = picked);
                          }
                        : null,
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'تاريخ التنفيذ المخطط',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.calendar_today),
                      ),
                      child: Text(_plannedDate != null ? DateFormat('yyyy/MM/dd').format(_plannedDate!) : 'بدون تاريخ'),
                    ),
                  ),
                  const Gap(16),
                  TextFormField(
                    controller: _notesCtrl,
                    enabled: canEdit,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'ملاحظات',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.note_alt_outlined),
                    ),
                  ),
                ],
                const Gap(24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: _isSubmitting ? null : () => Navigator.pop(context), child: const Text('إلغاء')),
                    const Gap(12),
                    if (canEdit)
                      ElevatedButton.icon(
                        onPressed: _isSubmitting ? null : _submit,
                        icon: _isSubmitting
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : Icon(isEdit ? Icons.save : Icons.check),
                        label: Text(isEdit ? 'حفظ التعديلات' : 'إنشاء الأمر'),
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
