import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/dao/manufacturing_order_dao.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_orders_table.dart';
import 'package:pos_offline_desktop/ui/manufacturing/widgets/cost_component_editor.dart';
import 'package:pos_offline_desktop/ui/manufacturing/widgets/mo_form_dialog.dart';

class MoDetailScreen extends StatefulWidget {
  final AppDatabase db;
  final int orderId;
  const MoDetailScreen({super.key, required this.db, required this.orderId});

  @override
  State<MoDetailScreen> createState() => _MoDetailScreenState();
}

class _MoDetailScreenState extends State<MoDetailScreen> {
  ManufacturingOrder? _order;
  BillOfMaterial? _bom;
  Product? _finishedProduct;
  List<(BomItem, Product)> _bomItems = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final order = await widget.db.manufacturingOrderDao.getById(widget.orderId);
      if (order == null) {
        setState(() {
          _error = 'أمر التصنيع غير موجود';
          _isLoading = false;
        });
        return;
      }
      final bom = await widget.db.bomDao.getBomById(order.bomId);
      final product = await widget.db.productDao.getProductById(order.finishedProductId);
      final items = await widget.db.bomDao.getItemsWithProducts(order.bomId);
      setState(() {
        _order = order;
        _bom = bom;
        _finishedProduct = product;
        _bomItems = items;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'خطأ: $e';
        _isLoading = false;
      });
    }
  }

  Color _statusColor(String s) {
    switch (s) {
      case ManufacturingOrderStatus.planned:
        return Colors.blue;
      case ManufacturingOrderStatus.inProgress:
        return Colors.orange;
      case ManufacturingOrderStatus.completed:
        return Colors.green;
      case ManufacturingOrderStatus.cancelled:
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _statusLabel(String s) {
    switch (s) {
      case ManufacturingOrderStatus.planned:
        return 'مخطط';
      case ManufacturingOrderStatus.inProgress:
        return 'قيد التنفيذ';
      case ManufacturingOrderStatus.completed:
        return 'مكتمل';
      case ManufacturingOrderStatus.cancelled:
        return 'ملغي';
      default:
        return s;
    }
  }

  Future<void> _startOrder() async {
    try {
      await widget.db.manufacturingOrderDao.startOrder(_order!.id);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم بدء التنفيذ'), backgroundColor: Colors.green));
      _loadData();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _cancelOrder() async {
    String? reason;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('إلغاء الأمر ${_order!.orderNumber}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('سيتم إلغاء الأمر بدون أي تأثير على المخزون (Phase 3).'),
            const Gap(12),
            TextField(
              decoration: const InputDecoration(labelText: 'سبب الإلغاء', border: OutlineInputBorder()),
              onChanged: (v) => reason = v,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('تراجع')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('تأكيد الإلغاء'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await widget.db.manufacturingOrderDao.cancelOrder(_order!.id, reason: reason);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إلغاء الأمر')));
      _loadData();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _reopenOrder() async {
    try {
      await widget.db.manufacturingOrderDao.reopenCancelledOrder(_order!.id);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تمت إعادة فتح الأمر'), backgroundColor: Colors.green));
      _loadData();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _completeOrder() async {
    if (_order == null || _bom == null) return;
    final actualQtyCtrl = TextEditingController(text: _order!.plannedQuantity.toString());
    String? dialogError;
    bool isSubmitting = false;

    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            Future<void> doComplete() async {
              final actual = double.tryParse(actualQtyCtrl.text.trim());
              if (actual == null || actual <= 0) {
                setStateDialog(() => dialogError = 'أدخل كمية منتجة صحيحة > 0');
                return;
              }
              setStateDialog(() {
                isSubmitting = true;
                dialogError = null;
              });
              try {
                final result = await widget.db.manufacturingOrderDao.completeManufacturingOrder(
                  orderId: _order!.id,
                  actualProducedQuantity: actual,
                );
                if (dialogCtx.mounted) Navigator.pop(dialogCtx, true);
                if (!mounted) return;
                // Success — show cost summary + offer to update product cost
                await _showCompletionSuccess(result);
                _loadData();
              } on InsufficientStockException catch (e) {
                setStateDialog(() {
                  isSubmitting = false;
                  dialogError = e.toString();
                });
              } catch (e) {
                setStateDialog(() {
                  isSubmitting = false;
                  dialogError = 'فشل: $e';
                });
              }
            }

            return AlertDialog(
              title: Text('إكمال أمر ${_order!.orderNumber}'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('سيتم خصم المواد الخام وإضافة المنتج النهائي للمخزون في معاملة واحدة (ذريّة).',
                        style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
                    const Gap(12),
                    TextField(
                      controller: actualQtyCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'الكمية المنتجة فعلياً *',
                        border: OutlineInputBorder(),
                        helperText: 'قد تختلف عن المخططة بسبب الهدر الفعلي',
                      ),
                      onChanged: (_) => setStateDialog(() {}),
                    ),
                    const Gap(12),
                    // Preview of required vs available
                    ..._bomItems.map((entry) {
                      final (item, product) = entry;
                      final waste = item.wastePercentageOverride ?? _bom!.wastePercentage;
                      final actualForPreview = double.tryParse(actualQtyCtrl.text) ?? _order!.plannedQuantity;
                      final factor = _bom!.yieldQuantity > 0 ? actualForPreview / _bom!.yieldQuantity : actualForPreview;
                      final required = (item.quantityRequired * factor * (1 + waste / 100)).round();
                      final short = required > product.quantity;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Expanded(child: Text(product.name, style: const TextStyle(fontSize: 12))),
                            Text('$required / ${product.quantity} ${product.unit ?? ''}',
                                style: TextStyle(fontSize: 12, color: short ? Colors.red : Colors.green, fontWeight: FontWeight.bold)),
                            if (short) const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.warning, size: 14, color: Colors.red)),
                          ],
                        ),
                      );
                    }),
                    if (dialogError != null) ...[
                      const Gap(12),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: Theme.of(ctx).colorScheme.errorContainer, borderRadius: BorderRadius.circular(6)),
                        child: Text(dialogError!, style: TextStyle(color: Theme.of(ctx).colorScheme.onErrorContainer, fontSize: 12)),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: isSubmitting ? null : () => Navigator.pop(dialogCtx, false), child: const Text('إلغاء')),
                FilledButton(
                  onPressed: isSubmitting ? null : doComplete,
                  child: isSubmitting
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('تأكيد الإكمال'),
                ),
              ],
            );
          },
        );
      },
    );
    if (confirm == true && mounted) {
      // already handled in doComplete success
    }
  }

  Future<void> _showCompletionSuccess(ManufacturingCompletionResult result) async {
    bool updateCost = false;
    await showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (ctx, setStateDialog) {
          return AlertDialog(
            title: const Row(children: [Icon(Icons.check_circle, color: Colors.green), Gap(8), Text('تم إكمال التصنيع')]),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('أمر ${result.orderNumber} • المنتج: ${result.finishedProductName}', style: const TextStyle(fontWeight: FontWeight.bold)),
                  const Gap(12),
                  _costRow('الكمية المنتجة:', '${result.producedInt} وحدة (${result.producedQuantity} فعلي)'),
                  _costRow('تكلفة المواد:', '${result.materialCost.toStringAsFixed(2)} ج.م'),
                  _costRow('تكاليف إضافية:', '${result.componentsCost.toStringAsFixed(2)} ج.م'),
                  const Divider(),
                  _costRow('الإجمالي:', '${result.totalCost.toStringAsFixed(2)} ج.م', isBold: true),
                  _costRow('تكلفة الوحدة:', '${result.unitCost.toStringAsFixed(2)} ج.م / وحدة', isBold: true, color: Theme.of(ctx).colorScheme.primary),
                  const Gap(12),
                  Text('المخزون: ${result.previousFinishedQuantity} → ${result.nextFinishedQuantity} وحدة', style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
                  const Gap(16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.amber.shade200)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Checkbox(
                              value: updateCost,
                              onChanged: (v) => setStateDialog(() => updateCost = v ?? false),
                            ),
                            const Expanded(child: Text('تحديث سعر تكلفة المنتج النهائي؟', style: TextStyle(fontWeight: FontWeight.bold))),
                          ],
                        ),
                        Text(
                            'السعر الحالي: ${result.previousCostPrice?.toStringAsFixed(2) ?? 'غير محدد'} ج.م → الجديد: ${result.unitCost.toStringAsFixed(2)} ج.م',
                            style: TextStyle(fontSize: 12, color: Colors.amber.shade900)),
                        const Gap(4),
                        Text('اختياري ويحتاج تأكيدك. لن يتم التحديث بدون موافقتك.',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              FilledButton(
                onPressed: () async {
                  if (updateCost) {
                    try {
                      final product = await widget.db.productDao.getProductById(result.finishedProductId);
                      if (product != null) {
                        await widget.db.productDao.updateProduct(product.copyWith(costPrice: Value(result.unitCost)));
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تحديث سعر التكلفة')));
                      }
                    } catch (e) {
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل تحديث التكلفة: $e'), backgroundColor: Colors.red));
                    }
                  }
                  if (c.mounted) Navigator.pop(c);
                },
                child: const Text('حسناً'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _costRow(String label, String value, {bool isBold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
          Text(value, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal, color: color, fontSize: 13)),
        ],
      ),
    );
  }

  double _totalMaterialCostForOrder() {
    double total = 0;
    final planned = _order?.plannedQuantity ?? 0;
    final bomYield = _bom?.yieldQuantity ?? 1;
    final factor = bomYield > 0 ? planned / bomYield : planned;
    for (final (item, product) in _bomItems) {
      final unitCost = product.costPrice ?? product.price;
      final waste = item.wastePercentageOverride ?? _bom?.wastePercentage ?? 0;
      final required = item.quantityRequired * factor * (1 + waste / 100);
      total += required * unitCost;
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_isLoading) {
      return Scaffold(appBar: AppBar(title: const Text('تفاصيل أمر التصنيع')), body: const Center(child: CircularProgressIndicator()));
    }
    if (_error != null || _order == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('تفاصيل أمر التصنيع')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: theme.colorScheme.error),
              const Gap(16),
              Text(_error ?? 'خطأ غير معروف', style: theme.textTheme.titleMedium),
              const Gap(16),
              ElevatedButton(onPressed: _loadData, child: const Text('إعادة المحاولة')),
            ],
          ),
        ),
      );
    }
    final mo = _order!;
    final bom = _bom;
    final product = _finishedProduct;
    final color = _statusColor(mo.status);
    final totalCost = _totalMaterialCostForOrder();
    final unitCost = mo.plannedQuantity > 0 ? totalCost / mo.plannedQuantity : 0;

    return Scaffold(
      appBar: AppBar(
        title: Text('أمر ${mo.orderNumber}'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadData, tooltip: 'تحديث'),
          if (mo.status == ManufacturingOrderStatus.planned)
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: 'تعديل',
              onPressed: () async {
                final res = await showDialog<bool>(
                  context: context,
                  builder: (_) => MoFormDialog(db: widget.db, order: mo),
                );
                if (res == true) _loadData();
              },
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header card
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                          child: Icon(Icons.precision_manufacturing, color: color, size: 32),
                        ),
                        const Gap(16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(mo.orderNumber, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                              const Gap(4),
                              Text(
                                '${product?.name ?? '#${mo.finishedProductId}'} • وصفة: ${bom?.name ?? '#${mo.bomId}'}',
                                style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey.shade700),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: color)),
                          child: Text(_statusLabel(mo.status), style: TextStyle(color: color, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    const Divider(height: 32),
                    Wrap(
                      spacing: 24,
                      runSpacing: 16,
                      children: [
                        _stat(context, 'الكمية المخططة', '${mo.plannedQuantity} وحدة', Icons.numbers),
                        _stat(context, 'الكمية المنتجة', '${mo.producedQuantity} وحدة', Icons.inventory),
                        _stat(context, 'العائد للوصفة', '${bom?.yieldQuantity ?? '-'} وحدة', Icons.scale),
                        _stat(context, 'تاريخ مخطط', mo.plannedDate != null ? DateFormat('yyyy/MM/dd').format(mo.plannedDate!) : '—', Icons.calendar_today),
                        _stat(context, 'تكلفة مادية تقديرية', '${totalCost.toStringAsFixed(2)} ج.م', Icons.attach_money),
                        _stat(context, 'تكلفة الوحدة', '${unitCost.toStringAsFixed(2)} ج.م', Icons.calculate),
                        if (mo.cancelReason != null) _stat(context, 'سبب الإلغاء', mo.cancelReason!, Icons.cancel_outlined),
                      ],
                    ),
                    if (mo.notes != null && mo.notes!.isNotEmpty) ...[
                      const Gap(16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.amber.shade200)),
                        child: Text('ملاحظات: ${mo.notes!}', style: TextStyle(color: Colors.amber.shade900)),
                      ),
                    ],
                    const Gap(16),
                    // Actions
                    Wrap(
                      spacing: 8,
                      children: [
                        if (mo.status == ManufacturingOrderStatus.planned)
                          FilledButton.icon(onPressed: _startOrder, icon: const Icon(Icons.play_arrow), label: const Text('بدء التنفيذ')),
                        if (mo.status == ManufacturingOrderStatus.planned || mo.status == ManufacturingOrderStatus.inProgress)
                          FilledButton.icon(
                            onPressed: _completeOrder,
                            icon: const Icon(Icons.check_circle),
                            label: const Text('إكمال التصنيع'),
                            style: FilledButton.styleFrom(backgroundColor: Colors.green),
                          ),
                        if (mo.status == ManufacturingOrderStatus.planned || mo.status == ManufacturingOrderStatus.inProgress)
                          OutlinedButton.icon(
                              onPressed: _cancelOrder,
                              icon: const Icon(Icons.cancel, color: Colors.red),
                              label: const Text('إلغاء الأمر', style: TextStyle(color: Colors.red))),
                        if (mo.status == ManufacturingOrderStatus.cancelled)
                          OutlinedButton.icon(onPressed: _reopenOrder, icon: const Icon(Icons.replay), label: const Text('إعادة فتح')),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const Gap(24),
            // Phase 4: Cost components editor (read-only after completion)
            CostComponentEditor(
              db: widget.db,
              orderId: mo.id,
              orderStatus: mo.status,
              onChanged: () => setState(() {}),
            ),
            const Gap(24),
            Text('مكونات الوصفة المطلوبة (للكمية المخططة)',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const Gap(12),
            if (_bomItems.isEmpty)
              Card(child: Container(width: double.infinity, padding: const EdgeInsets.all(32), child: Text('لا توجد مكونات لهذه الوصفة', style: TextStyle(color: Colors.grey.shade600), textAlign: TextAlign.center)))
            else
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      color: Colors.grey.shade100,
                      child: Row(
                        children: const [
                          Expanded(flex: 3, child: Text('المادة الخام', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                          Expanded(flex: 2, child: Text('المطلوب', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                          Expanded(flex: 2, child: Text('المتاح', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                          Expanded(flex: 2, child: Text('الحالة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                        ],
                      ),
                    ),
                    ..._bomItems.map((entry) {
                      final (item, product) = entry;
                      final bomYield = bom?.yieldQuantity ?? 1;
                      final factor = bomYield > 0 ? mo.plannedQuantity / bomYield : mo.plannedQuantity;
                      final waste = item.wastePercentageOverride ?? bom?.wastePercentage ?? 0;
                      final required = item.quantityRequired * factor * (1 + waste / 100);
                      final requiredInt = required.round(); // Option A rounding
                      final available = product.quantity;
                      final short = requiredInt > available;
                      final statusColor = short ? Colors.red : Colors.green;
                      final statusText = short ? 'ناقص ${requiredInt - available}' : 'متوفر';
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Row(
                          children: [
                            Expanded(
                                flex: 3,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(product.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                    Text('${item.quantityRequired} ${item.unit ?? product.unit ?? ''} × ${factor.toStringAsFixed(2)} + هدر $waste%', style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
                                  ],
                                )),
                            Expanded(flex: 2, child: Text('$requiredInt ${product.unit ?? ''}', style: const TextStyle(fontWeight: FontWeight.bold))),
                            Expanded(flex: 2, child: Text('$available ${product.unit ?? ''}')),
                            Expanded(
                                flex: 2,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                                  child: Text(statusText, style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.bold)),
                                )),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _stat(BuildContext context, String label, String value, IconData icon) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const Gap(8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600)),
            Text(value, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
          ],
        ),
      ],
    );
  }
}
