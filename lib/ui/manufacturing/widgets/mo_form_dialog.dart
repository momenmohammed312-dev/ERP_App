import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_orders_table.dart';
import 'package:pos_offline_desktop/ui/manufacturing/widgets/receipt_picker_field.dart';
import 'package:pos_offline_desktop/ui/manufacturing/widgets/searchable_product_picker.dart';

class MoFormDialog extends StatefulWidget {
  final AppDatabase db;
  final ManufacturingOrder? order;

  /// Secondary entry: prefill the form from a customer material receipt.
  final int? initialReceiptId;
  const MoFormDialog({super.key, required this.db, this.order, this.initialReceiptId});

  @override
  State<MoFormDialog> createState() => _MoFormDialogState();
}

class _MoFormDialogState extends State<MoFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _orderNumberCtrl = TextEditingController();
  final _plannedQtyCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _pieceUnitValueCtrl = TextEditingController(text: '0');
  final _serviceUnitPriceCtrl = TextEditingController(text: '0');

  String _orderType = 'internal';
  String? _customerId;
  String _pricingMode = 'inclusive';
  String _scrapPolicy = 'customer_bears';

  int? _selectedBomId;
  BillOfMaterial? _selectedBom;
  Product? _finishedProduct;
  List<BillOfMaterial> _activeBoms = [];
  Map<int, Product> _productMap = {};
  // Receipt → recipe flow (for_others primary entry)
  CustomerMaterialReceipt? _selectedReceipt;
  List<BillOfMaterial> _compatibleBoms = [];
  Map<int, Set<int>> _bomRawProductIds = {};
  bool _showAllBoms = false;
  List<CustomerStockBalance> _customerBalances = [];
  CustomerStockBalance? _selectedBalance;
  List<Customer> _customers = [];
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
      _orderType = o.orderType ?? 'internal';
      _customerId = o.customerId;
      _pricingMode = o.pricingMode ?? 'inclusive';
      if (_orderType != 'internal') _loadCustomerBalances(_customerId);
      _scrapPolicy = o.scrapPolicy ?? 'customer_bears';
      _pieceUnitValueCtrl.text = (o.pieceUnitValue ?? 0.0).toString();
      _serviceUnitPriceCtrl.text = (o.serviceUnitPrice ?? 0.0).toString();
    } else {
      _orderNumberCtrl.text = 'MO-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}';
      _plannedQtyCtrl.text = '1';
      _plannedDate = DateTime.now();
      _orderType = 'internal';
      _pricingMode = 'inclusive';
      _scrapPolicy = 'customer_bears';
      _pieceUnitValueCtrl.text = '0';
      _serviceUnitPriceCtrl.text = '0';
    }
    _loadBoms();
    // Secondary entry: a receipt was chosen first (receipt → recipe flow).
    if (widget.initialReceiptId != null && widget.order == null) {
      _orderType = 'for_others';
      _selectReceiptById(widget.initialReceiptId!);
    }
  }

  Future<void> _loadBoms() async {
    try {
      final boms = await widget.db.bomDao.getActiveBoms();
      final products = await widget.db.productDao.getAllProducts();
      final customers = await widget.db.customerDao.getCustomersForManufacturing();
      final map = {for (var p in products) p.id: p};
      setState(() {
        _activeBoms = boms;
        _productMap = map;
        _customers = customers;
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

  Future<void> _loadCustomerBalances(String? customerId) async {
    if (customerId == null) {
      setState(() { _customerBalances = []; _selectedBalance = null; });
      return;
    }
    try {
      final bals = await widget.db.customerMaterialReceiptDao.getAllBalancesForCustomer(customerId);
      setState(() {
        _customerBalances = bals;
        _selectedBalance = null;
      });
    } catch (e) {
      // ignore
    }
  }

  /// Secondary entry helper: load a receipt by id, then run the same
  /// receipt → recipe flow as the picker.
  Future<void> _selectReceiptById(int receiptId) async {
    try {
      final receipt = await widget.db.customerMaterialReceiptDao
          .getReceiptById(receiptId);
      if (receipt != null && mounted) {
        await _onReceiptPicked(receipt);
      }
    } catch (_) {
      // leave the form empty on error; user can pick manually
    }
  }

  /// Raw-material product ids per BOM, computed lazily for the
  /// compatible-recipe filter.
  Future<void> _ensureBomProductMap() async {
    if (_bomRawProductIds.isNotEmpty || _activeBoms.isEmpty) return;
    for (final b in _activeBoms) {
      try {
        final items = await widget.db.bomDao.getItemsForBom(b.id);
        _bomRawProductIds[b.id] =
            items.map((i) => i.rawMaterialProductId).toSet();
      } catch (_) {
        // ignore unloadable BOMs for the filter
      }
    }
  }

  /// Receipt picked (primary entry) or prefilled (secondary entry):
  /// fix the customer, reload custody balances + receipt items, recompute
  /// compatible recipes, and preselect the matching custody balance.
  Future<void> _onReceiptPicked(CustomerMaterialReceipt? receipt) async {
    setState(() {
      _selectedReceipt = receipt;
      _compatibleBoms = [];
      _showAllBoms = false;
      _selectedBomId = null;
      _selectedBom = null;
      _finishedProduct = null;
      _selectedBalance = null;
    });
    if (receipt == null) return;
    setState(() => _customerId = receipt.customerId);
    await _loadCustomerBalances(receipt.customerId);
    try {
      final items = await widget.db.customerMaterialReceiptDao
          .getItemsForReceipt(receipt.id);
      await _ensureBomProductMap();
      final productIds = items.map((i) => i.productId).toSet();
      final compat = _activeBoms
          .where((b) => (_bomRawProductIds[b.id] ?? const <int>{})
              .any(productIds.contains))
          .toList();
      if (!mounted) return;
      setState(() {
        _compatibleBoms = compat;
        // Preselect the custody balance of the first receipt item.
        for (final it in items) {
          final m =
              _customerBalances.where((b) => b.productId == it.productId);
          if (m.isNotEmpty) {
            _selectedBalance = m.first;
            _plannedQtyCtrl.text =
                (m.first.quantityOnHand - m.first.quantityAllocated)
                    .toString();
            break;
          }
        }
      });
    } catch (_) {
      // balances already loaded; recipe filter stays empty
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
        if (_orderType == 'internal' && _selectedBomId == null) {
      setState(() => _errorMessage = 'يرجى اختيار الوصفة (BOM)');
      return;
    }
    if (_orderType != 'internal' && _selectedReceipt == null) {
      setState(() => _errorMessage = 'يرجى اختيار إذن الاستلام من العميل');
      return;
    }
    if (_orderType != 'internal' && _selectedBomId == null) {
      setState(() => _errorMessage = 'يرجى اختيار الوصفة (BOM)');
      return;
    }
    if (_orderType != 'internal' && _selectedBalance == null) {
      setState(() => _errorMessage = 'يرجى اختيار الخامة من العهدة');
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

    if (_orderType != 'internal' && (_customerId == null || _customerId!.isEmpty)) {
      setState(() => _errorMessage = 'يرجى اختيار العميل لأمر تشغيل للغير');
      return;
    }
    final pieceVal = double.tryParse(_pieceUnitValueCtrl.text.trim()) ?? 0.0;
    final servicePrice = double.tryParse(_serviceUnitPriceCtrl.text.trim()) ?? 0.0;

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
        if (_orderType == 'internal') {
          final companion = ManufacturingOrdersCompanion(
            orderNumber: Value(orderNumber),
            bomId: Value(_selectedBomId!),
            finishedProductId: Value(finishedId),
            plannedQuantity: Value(qty),
            plannedDate: Value(_plannedDate),
            orderType: Value(_orderType),
            customerId: Value(_orderType == 'internal' ? null : _customerId),
            pricingMode: Value(_orderType == 'internal' ? null : _pricingMode),
            scrapPolicy: Value(_orderType == 'internal' ? null : _scrapPolicy),
            pieceUnitValue: Value(_orderType == 'internal' ? 0.0 : pieceVal),
            serviceUnitPrice: Value(_orderType == 'internal' ? 0.0 : servicePrice),
            notes: Value(_notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim()),
            status: const Value(ManufacturingOrderStatus.planned),
          );
          await widget.db.manufacturingOrderDao.createOrder(companion);
        } else {
          // Recipe-based for-others order: real BOM + finished product from
          // the recipe. Direct-input fields stay null so completion goes
          // through the BOM path (customer custody per BOM line, factory
          // finished stock never touched).
          await widget.db.manufacturingOrderDao.createJobWorkOrder(
            orderNumber: orderNumber,
            orderType: _orderType,
            customerId: _customerId!,
            bomId: _selectedBomId!,
            finishedProductId: finishedId,
            plannedQuantity: qty,
            plannedDate: _plannedDate,
            pricingMode: _pricingMode,
            scrapPolicy: _scrapPolicy,
            pieceUnitValue: pieceVal,
            serviceUnitPrice: servicePrice,
            notes: _notesCtrl.text.trim().isEmpty
                ? null
                : _notesCtrl.text.trim(),
          );
        }
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
          orderType: Value(_orderType),
          customerId: Value(_orderType == 'internal' ? null : _customerId),
          pricingMode: Value(_orderType == 'internal' ? null : _pricingMode),
          scrapPolicy: Value(_orderType == 'internal' ? null : _scrapPolicy),
          pieceUnitValue: Value(_orderType == 'internal' ? 0.0 : pieceVal),
          serviceUnitPrice: Value(_orderType == 'internal' ? 0.0 : servicePrice),
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
    _pieceUnitValueCtrl.dispose();
    _serviceUnitPriceCtrl.dispose();
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
                    decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber.withValues(alpha: 0.4))),
                    child: Text('هذا الأمر في حالة "${widget.order!.status}" ولا يمكن تعديل بياناته الأساسية في هذه المرحلة.',
                        style: TextStyle(color: Colors.amber.shade800)),
                  ),
                if (!canEdit) const Gap(16),
                if (_loadingBoms)
                  const Center(child: CircularProgressIndicator())
                else ...[
                  // With no recipes there is nothing to order against. Say so
                  // and offer a way out, instead of showing an empty dropdown
                  // that fails validation with no explanation.
                  if (_activeBoms.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'لا توجد وصفات. أنشئ وصفة أولاً',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color:
                                      theme.colorScheme.onSurfaceVariant),
                            ),
                          ),
                          const Gap(8),
                          FilledButton.icon(
                            onPressed: () {
                              Navigator.of(context).pop(true);
                              context.push('/manufacturing/bom');
                            },
                            icon: const Icon(Icons.add),
                            label: const Text('إنشاء وصفة'),
                          ),
                        ],
                      ),
                    ),
                  DropdownButtonFormField<String>(
                    value: _orderType,
                    decoration: const InputDecoration(labelText: 'نوع الأمر *', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'internal', child: Text('تصنيع داخلي (مخزون المصنع)')),
                      DropdownMenuItem(value: 'for_others', child: Text('تشغيل للغير (خامات العميل)')),
                    ],
                    onChanged: canEdit ? (v) => setState(() {
                       _orderType = v ?? 'internal';
                       _selectedBomId = null;
                       _selectedBom = null;
                       _customerId = null;
                       _customerBalances = [];
                       _selectedBalance = null;
                       _selectedReceipt = null;
                       _compatibleBoms = [];
                       _showAllBoms = false;
                       _finishedProduct = null;
                    }) : null,
                  ),
                  const Gap(16),
                  if (_orderType == 'internal')
                    DropdownButtonFormField<int>(
                      value: _selectedBomId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'الوصفة (BOM) *',
                        border: OutlineInputBorder(),
                      ),
                      items: _activeBoms
                          .map((b) => DropdownMenuItem(
                                value: b.id,
                                child: Text('${b.name} (${_productMap[b.finishedProductId]?.name ?? b.finishedProductId})'),
                              ))
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
                    )
                  else ...[
                    // Step 1 — pick the customer receipt first.
                    ReceiptPickerField(
                      db: widget.db,
                      label: 'إذن الاستلام من العميل *',
                      initialReceiptId: _selectedReceipt?.id,
                      enabled: canEdit,
                      validator: (r) =>
                          r == null ? 'يرجى اختيار إذن الاستلام' : null,
                      onChanged: (r) => _onReceiptPicked(r),
                    ),
                    const Gap(16),
                    // Step 2 — pick a recipe; compatible BOMs first.
                    DropdownButtonFormField<int>(
                      value: _selectedBomId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'الوصفة (BOM) *',
                        border: OutlineInputBorder(),
                      ),
                      items: (_showAllBoms
                              ? _activeBoms
                              : _compatibleBoms)
                          .map((b) => DropdownMenuItem(
                                value: b.id,
                                child: Text(
                                  '${b.name} (${_productMap[b.finishedProductId]?.name ?? b.finishedProductId})',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ))
                          .toList(),
                      onChanged: canEdit
                          ? (v) {
                              setState(() {
                                _selectedBomId = v;
                                final m =
                                    _activeBoms.where((bb) => bb.id == v);
                                _selectedBom =
                                    m.isNotEmpty ? m.first : null;
                                _finishedProduct = _selectedBom != null
                                    ? _productMap[
                                        _selectedBom!.finishedProductId]
                                    : null;
                              });
                            }
                          : null,
                    ),
                    if (_selectedReceipt != null &&
                        _compatibleBoms.isEmpty &&
                        !_showAllBoms)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                          'لا توجد وصفات متوافقة مع أصناف هذا الإذن — فعّل عرض الكل',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    Row(
                      children: [
                        Checkbox(
                          value: _showAllBoms,
                          onChanged: canEdit
                              ? (v) => setState(
                                  () => _showAllBoms = v ?? false)
                              : null,
                        ),
                        const Text('عرض كل الوصفات',
                            style: TextStyle(fontSize: 13)),
                      ],
                    ),
                    const Gap(8),
                    DropdownButtonFormField<String>(
                      value: _customerId,
                      decoration: const InputDecoration(labelText: 'العميل *', border: OutlineInputBorder()),
                      items: _customers.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
                      // The customer is fixed by the chosen receipt.
                      onChanged: (canEdit && _selectedReceipt == null) ? (v) {
                        setState(() => _customerId = v);
                        _loadCustomerBalances(v);
                      } : null,
                    ),
                    const Gap(16),
                    DropdownButtonFormField<int>(
                      value: _selectedBalance?.id,
                      decoration: const InputDecoration(labelText: 'الخامة من عهدة العميل *', border: OutlineInputBorder()),
                      items: _customerBalances.map((b) {
                        final p = _productMap[b.productId];
                        final avail = b.quantityOnHand - b.quantityAllocated;
                        final color = b.color != null ? ' - ' + b.color! : '';
                        final size = b.size != null ? ' - ' + b.size! : '';
                        return DropdownMenuItem(
                          value: b.id,
                          child: Text('${p?.name ?? b.productId}' + color + size + ' (متاح: ${avail})'),
                        );
                      }).toList(),
                      onChanged: canEdit ? (v) {
                        final match = _customerBalances.firstWhere((b) => b.id == v);
                        setState(() {
                          _selectedBalance = match;
                          _plannedQtyCtrl.text = (match.quantityOnHand - match.quantityAllocated).toString();
                        });
                      } : null,
                    ),
                    const Gap(16),
                    SearchableProductPicker(
                      db: widget.db,
                      label: 'المنتج النهائي الموجه للعميل *',
                      initialProductId: _finishedProduct?.id,
                      // Fixed by the chosen recipe.
                      enabled: canEdit && _selectedBomId == null,
                      onChanged: (p) =>
                          setState(() => _finishedProduct = p),
                    ),
                  ],
                  const Gap(16),
                  DropdownButtonFormField<String>(
                    initialValue: _pricingMode,

                      decoration: const InputDecoration(
                        labelText: 'نظام التسعير *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.request_quote_outlined),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'inclusive', child: Text('شامل (سعر مصنعية للوحدة التامة)')),
                        DropdownMenuItem(value: 'separate', child: Text('منفصل (أجر تشغيل + تكلفة خامات المصنع)')),
                      ],
                      onChanged: canEdit ? (v) => setState(() => _pricingMode = v ?? 'inclusive') : null,
                    ),
                    const Gap(16),
                    TextFormField(
                      controller: _serviceUnitPriceCtrl,
                      enabled: canEdit,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'سعر أجر التشغيل للوحدة (ج.م) *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.attach_money),
                        helperText: 'أجر تصنيع الوحدة الواحدة لصالح العميل',
                      ),
                      validator: (v) {
                        if (_orderType != 'internal') {
                          final p = double.tryParse(v ?? '');
                          if (p == null || p < 0) return 'أدخل سعر تشغيل صحيح >= 0';
                        }
                        return null;
                      },
                    ),
                    const Gap(16),
                    DropdownButtonFormField<String>(
                      initialValue: _scrapPolicy,
                      decoration: const InputDecoration(
                        labelText: 'سياسة الهالك المتفق عليها *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.policy_outlined),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'customer_bears', child: Text('العميل يتحمل الهالك (بدون تعويض)')),
                        DropdownMenuItem(value: 'factory_pays_piece_value', child: Text('المصنع يعوض قيمة القطعة (يخصم من الفاتورة)')),
                        DropdownMenuItem(value: 'factory_bears_labour_only', child: Text('المصنع يتنازل عن أجر التشغيل فقط')),
                        DropdownMenuItem(value: 'factory_replaces_piece', child: Text('المصنع يستبدل القطعة التالفة من مخزونه')),
                      ],
                      onChanged: canEdit ? (v) => setState(() => _scrapPolicy = v ?? 'customer_bears') : null,
                    ),
                    const Gap(16),
                    TextFormField(
                      controller: _pieceUnitValueCtrl,
                      enabled: canEdit,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'القيمة التقديرية للقطعة (للتعويض) ج.م',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.price_check),
                        helperText: 'تستخدم لحساب قيمة التعويض عند خطأ المصنع',
                      ),
                      validator: (v) {
                        if (_orderType != 'internal' && _scrapPolicy == 'factory_pays_piece_value') {
                          final val = double.tryParse(v ?? '');
                          if (val == null || val < 0) return 'أدخل قيمة قطعة صحيحة';
                        }
                        return null;
                      },
                    ),
                    const Gap(16),
                  ],
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
