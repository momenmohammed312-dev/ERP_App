import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/dao/manufacturing_order_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/manufacturing_delivery_dao.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_orders_table.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_scrap_table.dart';
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
  Customer? _customer;
  List<(BomItem, Product)> _bomItems = [];
  List<ManufacturingDelivery> _deliveries = [];
  double _deliveredQty = 0.0;
  List<CustomerStockMovement> _orderMovements = [];
  List<CustomerStockBalance> _customerBalances = [];
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

      Customer? customer;
      List<ManufacturingDelivery> deliveries = [];
      double deliveredQty = 0.0;
      List<CustomerStockMovement> orderMovements = [];
      List<CustomerStockBalance> customerBalances = [];

      if (order.customerId != null && order.customerId!.isNotEmpty) {
        customer = await widget.db.customerDao.getCustomerById(order.customerId!);
        deliveries = await widget.db.manufacturingDeliveryDao.getDeliveriesForOrder(order.id);
        deliveredQty = await widget.db.manufacturingDeliveryDao.getTotalDeliveredQuantity(order.id);
        orderMovements = await (widget.db.select(widget.db.customerStockMovements)
              ..where((m) => m.referenceId.equals(order.orderNumber)))
            .get();
        customerBalances = await widget.db.customerMaterialReceiptDao.getAllBalancesForCustomer(order.customerId!);
      }

      setState(() {
        _order = order;
        _bom = bom;
        _finishedProduct = product;
        _bomItems = items;
        _customer = customer;
        _deliveries = deliveries;
        _deliveredQty = deliveredQty;
        _orderMovements = orderMovements;
        _customerBalances = customerBalances;
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
            const Text('سيتم إلغاء الأمر بدون أي تأثير على المخزون — لا يتم صرف خامات ولا استلام إنتاج.'),
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

  Future<void> _openScrapDialog() async {
    final order = _order;
    if (order == null) return;

    // Candidate items: the recipe's raw materials plus the finished good.
    final options = <({int productId, String label, double available})>[
      for (final p in await widget.db.productDao.searchProducts(''))
        (
          productId: p.id,
          label: '${p.name}${p.unit == null ? '' : ' (${p.unit})'} — متاح ${p.quantity}',
          available: p.quantity.toDouble(),
        ),
    ];

    var productId = options.isEmpty ? 0 : options.first.productId;
    if (!mounted) return;
    var reason = ManufacturingScrapReason.defective;
    var faultParty = 'factory';
    final qtyCtrl = TextEditingController();
    final partyCtrl = TextEditingController();
    final noteCtrl = TextEditingController();

    final saved = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDlg) => AlertDialog(
          title: const Text('تسجيل هالك على الأمر'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  initialValue: productId,
                  isExpanded: true,
                  items: [
                    for (final o in options)
                      DropdownMenuItem(value: o.productId, child: Text(o.label)),
                  ],
                  onChanged: (v) => setDlg(() => productId = v ?? productId),
                ),
                const Gap(12),
                DropdownButtonFormField<String>(
                  initialValue: reason,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'سبب الهالك'),
                  items: [
                    for (final r in ManufacturingScrapReason.all)
                      DropdownMenuItem(
                        value: r,
                        child: Text(ManufacturingScrapReason.label(r)),
                      ),
                  ],
                  onChanged: (v) => setDlg(
                      () => reason = v ?? ManufacturingScrapReason.defective),
                ),
                const Gap(12),
                if (order.orderType != 'internal') ...[
                  DropdownButtonFormField<String>(
                    initialValue: faultParty,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'الطرف المتسبب في الهالك *'),
                    items: const [
                      DropdownMenuItem(value: 'factory', child: Text('المصنع (خطأ تشغيل)')),
                      DropdownMenuItem(value: 'customer', child: Text('العميل (عيب خامة/مواصفة)')),
                    ],
                    onChanged: (v) => setDlg(() => faultParty = v ?? 'factory'),
                  ),
                  const Gap(12),
                ],
                TextField(
                  controller: qtyCtrl,
                  decoration: const InputDecoration(labelText: 'الكمية'),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
                const Gap(12),
                TextField(
                  controller: partyCtrl,
                  decoration: const InputDecoration(
                      labelText: 'المسؤول (إجباري)'),
                ),
                const Gap(12),
                TextField(
                  controller: noteCtrl,
                  decoration: const InputDecoration(
                      labelText: 'ملاحظة / رقم تفويض (اختياري)'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('إلغاء')),
            FilledButton(
              onPressed: () async {
                final qty = double.tryParse(qtyCtrl.text.trim());
                if (qty == null || qty <= 0) {
                  ScaffoldMessenger.of(c).showSnackBar(const SnackBar(
                      content: Text('اكتب كمية أكبر من صفر'),
                      backgroundColor: Colors.red));
                  return;
                }
                if (partyCtrl.text.trim().isEmpty) {
                  ScaffoldMessenger.of(c).showSnackBar(const SnackBar(
                      content: Text('لازم حد يتحمل responsibility — اكتب المسؤول'),
                      backgroundColor: Colors.red));
                  return;
                }
                try {
                  ManufacturingScrap createdScrap;
                  if (order.orderType != 'internal') {
                    createdScrap = await widget.db.manufacturingScrapDao.recordOrderScrapWithPolicy(
                      orderId: order.id,
                      productId: productId,
                      quantity: qty,
                      reason: reason,
                      responsibleParty: partyCtrl.text.trim(),
                      faultParty: faultParty,
                      dispositionNote: noteCtrl.text.trim().isEmpty
                          ? null
                          : noteCtrl.text.trim(),
                      performedBy: 'ui',
                    );
                  } else {
                    createdScrap = await widget.db.manufacturingScrapDao.recordScrap(
                      orderId: order.id,
                      productId: productId,
                      quantity: qty,
                      reason: reason,
                      responsibleParty: partyCtrl.text.trim(),
                      dispositionNote: noteCtrl.text.trim().isEmpty
                          ? null
                          : noteCtrl.text.trim(),
                      performedBy: 'ui',
                    );
                  }
                  if (c.mounted) Navigator.pop(c, true);
                  if (mounted && order.orderType != 'internal') {
                    await _showScrapPolicyResultDialog(createdScrap);
                  }
                } catch (e) {
                  // recordScrap throws ArgumentError/StateError with a message
                  // written for a shop owner; surface it verbatim.
                  if (!c.mounted) return;
                  ScaffoldMessenger.of(c).showSnackBar(SnackBar(
                    content: Text(_readableScrapError(e)),
                    backgroundColor: Colors.red,
                    duration: const Duration(seconds: 5),
                  ));
                }
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );

    qtyCtrl.dispose();
    partyCtrl.dispose();
    noteCtrl.dispose();

    if (saved == true && mounted) {
      _loadData();
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تسجيل الهالك')));
    }
  }

  Future<void> _showScrapPolicyResultDialog(ManufacturingScrap scrap) async {
    String desc = 'سياسة الهالك المنفذة: ';
    if (scrap.compensationAction == 'deducted_from_invoice') {
      desc += 'تم تحديد خصم ${scrap.compensationAmount} ج.م من الفاتورة لصالح العميل.';
    } else if (scrap.compensationAction == 'replaced') {
      desc += 'تم استبدال القطعة وصرفها من مخزن المصنع لحساب العميل.';
    } else if (scrap.compensationAction == 'labour_waived') {
      desc += 'تم التنازل عن أجر التشغيل لهذه القطعة.';
    } else {
      desc += 'العميل يتحمل الهالك بالكامل دون تعويض مالي.';
    }

    await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Row(children: [Icon(Icons.info_outline, color: Colors.blue), Gap(8), Text('نتيجة سياسة الهالك')]),
        content: Text(desc, style: const TextStyle(fontSize: 14)),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(c), child: const Text('حسناً')),
        ],
      ),
    );
  }

  /// Turns a DAO failure into something a shop owner can act on. The DAO
  /// messages are already user-facing; only the generic types need mapping.
  String _readableScrapError(Object e) {
    if (e is ArgumentError) {
      final m = e.message;
      if (m is String && m.trim().isNotEmpty) return m;
      return 'قيمة غير صحيحة: $m';
    }
    if (e is StateError) return e.message;
    if (e is InsufficientStockException) {
      return e.shortages
          .map((s) =>
              '${s.productName}: مطلوب ${s.required} ${s.unit ?? ''}، متاح ${s.available}')
          .join('\n');
    }
    return 'فشل تسجيل الهالك: $e';
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
                if (_order!.orderType == 'for_others' || _order!.orderType == 'mixed') {
                  final result = await widget.db.manufacturingOrderDao.completeForOthersOrder(
                    orderId: _order!.id,
                    actualProducedQuantity: actual,
                  );
                  if (dialogCtx.mounted) Navigator.pop(dialogCtx, true);
                  if (!mounted) return;
                  await _showForOthersCompletionSuccess(result);
                  _loadData();
                } else {
                  final result = await widget.db.manufacturingOrderDao.completeManufacturingOrder(
                    orderId: _order!.id,
                    actualProducedQuantity: actual,
                  );
                  if (dialogCtx.mounted) Navigator.pop(dialogCtx, true);
                  if (!mounted) return;
                  // Success — show cost summary + offer to update product cost
                  await _showCompletionSuccess(result);
                  _loadData();
                }
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
                    Text(
                      _order!.orderType == 'for_others' || _order!.orderType == 'mixed'
                          ? 'سيتم خصم خامات العميل من رصيد العهدة بالمخزن في معاملة واحدة ذريّة (دون زيادة مخزون المصنع لأن البضاعة ملك العميل وتنتظر التسليم).'
                          : 'سيتم خصم المواد الخام وإضافة المنتج النهائي للمخزون في معاملة واحدة (ذريّة).',
                      style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                    ),
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

  Future<void> _showForOthersCompletionSuccess(ForOthersCompletionResult result) async {
    await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Row(children: [Icon(Icons.check_circle, color: Colors.green), Gap(8), Text('تم إكمال أمر التشغيل للغير')]),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('أمر ${result.orderNumber} • المنتج: ${result.finishedProductName}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const Gap(12),
              _costRow('الكمية المنتجة:', '${result.producedQuantity} وحدة'),
              const Divider(),
              const Text('خامات العميل المستهلكة من العهدة:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const Gap(4),
              for (final cons in result.customerConsumptions)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text('• ${cons.productName}: ${cons.quantity} ${cons.unit ?? ''}', style: const TextStyle(fontSize: 12)),
                ),
              if (result.factoryConsumptions.isNotEmpty) ...[
                const Gap(8),
                const Text('خامات المصنع المستهلكة:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const Gap(4),
                for (final f in result.factoryConsumptions)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text('• ${f.productName}: ${f.required} ${f.unit ?? ''}', style: const TextStyle(fontSize: 12)),
                  ),
              ],
              const Gap(12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(6)),
                child: const Text(
                  'تم خصم المواد من عهدة العميل ولم تتم إضافة المنتج النهائي لمخزون المصنع لأن البضاعة ملك للعميل وتنتظر إصدار إذن التسليم.',
                  style: TextStyle(fontSize: 11, color: Colors.blueAccent),
                ),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(c), child: const Text('حسناً')),
        ],
      ),
    );
  }

  Future<void> _openDeliveryDialog() async {
    final order = _order;
    if (order == null) return;
    final alreadyDelivered = await widget.db.manufacturingDeliveryDao.getTotalDeliveredQuantity(order.id);
    if (!mounted) return;
    final remaining = order.producedQuantity - alreadyDelivered;
    if (remaining <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تسليم كامل الكمية المنتجة بالفعل'), backgroundColor: Colors.orange),
        );
      }
      return;
    }

    final qtyCtrl = TextEditingController(text: remaining.toString());
    final deliveredByCtrl = TextEditingController();
    final receiverCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    String? dlgError;
    bool isSubmitting = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text('إذن تسليم منتجات تامة للعميل — أمر ${order.orderNumber}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('المنتج: ${_finishedProduct?.name ?? ''}'),
                const Gap(4),
                Text('المنتج كلياً: ${order.producedQuantity} | المسلم سابقاً: $alreadyDelivered | المتبقي للتسليم: $remaining',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.indigo)),
                const Gap(16),
                TextField(
                  controller: qtyCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'الكمية المراد تسليمها (الحد الأقصى: $remaining) *',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.numbers),
                  ),
                ),
                const Gap(12),
                TextField(
                  controller: deliveredByCtrl,
                  decoration: const InputDecoration(
                    labelText: 'المسؤول عن التسليم / المندوب',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person_pin_outlined),
                  ),
                ),
                const Gap(12),
                TextField(
                  controller: receiverCtrl,
                  decoration: const InputDecoration(
                    labelText: 'اسم المستلم من طرف العميل',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                ),
                const Gap(12),
                TextField(
                  controller: notesCtrl,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظات إذن التسليم',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.notes),
                  ),
                ),
                if (dlgError != null) ...[
                  const Gap(12),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(6)),
                    child: Text(dlgError!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: isSubmitting ? null : () => Navigator.pop(dlgCtx), child: const Text('إلغاء')),
            FilledButton.icon(
              onPressed: isSubmitting
                  ? null
                  : () async {
                      final q = double.tryParse(qtyCtrl.text.trim());
                      if (q == null || q <= 0) {
                        setDlg(() => dlgError = 'أدخل كمية تسليم صحيحة > 0');
                        return;
                      }
                      if (q > remaining + 1e-9) {
                        setDlg(() => dlgError = 'الكمية المطلوبة تتجاوز المتاح للتسليم ($remaining)');
                        return;
                      }
                      setDlg(() {
                        isSubmitting = true;
                        dlgError = null;
                      });
                      try {
                        await widget.db.manufacturingDeliveryDao.createDelivery(
                          orderId: order.id,
                          items: [
                            DeliveryItemInput(
                              productId: order.finishedProductId,
                              quantity: q,
                            ),
                          ],
                          deliveredBy: deliveredByCtrl.text.trim().isEmpty ? null : deliveredByCtrl.text.trim(),
                          receiverName: receiverCtrl.text.trim().isEmpty ? null : receiverCtrl.text.trim(),
                          notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
                        );
                        if (dlgCtx.mounted) Navigator.pop(dlgCtx);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('تم تسجيل إذن التسليم بنجاح'), backgroundColor: Colors.green),
                          );
                          _loadData();
                        }
                      } catch (e) {
                        setDlg(() {
                          isSubmitting = false;
                          dlgError = 'فشل التسليم: $e';
                        });
                      }
                    },
              icon: isSubmitting
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.local_shipping),
              label: const Text('تأكيد التسليم'),
            ),
          ],
        ),
      ),
    );
    qtyCtrl.dispose();
    deliveredByCtrl.dispose();
    receiverCtrl.dispose();
    notesCtrl.dispose();
  }

  Future<void> _generateServiceInvoice() async {
    final order = _order;
    if (order == null) return;
    final deliveredQty = await widget.db.manufacturingDeliveryDao.getTotalDeliveredQuantity(order.id);
    if (!mounted) return;
    if (deliveredQty <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لا يمكن إصدار فاتورة قبل تسليم أي كمية للعميل'), backgroundColor: Colors.orange),
        );
      }
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('إصدار فاتورة خدمات التشغيل للغير'),
        content: Text(
            'سيتم إنشاء فاتورة خدمات للعميل ${_customer?.name ?? ''} عن الكمية المسلمة ($deliveredQty وحدة) وترحيلها مباشرة إلى كشف حساب العميل ورصيد المديونية.\n\nهل تريد المتابعة؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('إصدار الفاتورة')),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final inv = await widget.db.manufacturingDeliveryDao.generateServiceInvoice(order.id);
      if (mounted) {
        await showDialog(
          context: context,
          builder: (c) => AlertDialog(
            title: const Row(children: [Icon(Icons.check_circle, color: Colors.green), Gap(8), Text('تم إصدار الفاتورة')]),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('رقم الفاتورة: ${inv.invoiceNumber}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const Gap(8),
                Text('الإجمالي: ${inv.totalAmount.toStringAsFixed(2)} ج.م'),
                const Gap(8),
                const Text('تم ترحيل الفاتورة إلى سجل حساب العميل بنجاح.', style: TextStyle(color: Colors.green)),
              ],
            ),
            actions: [
              FilledButton(onPressed: () => Navigator.pop(c), child: const Text('حسناً')),
            ],
          ),
        );
        _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل إصدار الفاتورة: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  String _deliveryStatusLabel(String? s) {
    switch (s) {
      case 'delivered':
        return 'تم التسليم بالكامل';
      case 'partially_delivered':
        return 'تسليم جزئي';
      case 'undelivered':
      default:
        return 'لم يتم التسليم';
    }
  }

  String _scrapPolicyLabel(String? s) {
    switch (s) {
      case 'factory_pays_piece_value':
        return 'المصنع يعوض قيمة القطعة';
      case 'factory_bears_labour_only':
        return 'إسقاط أجر التشغيل';
      case 'factory_replaces_piece':
        return 'استبدال القطعة من المصنع';
      case 'customer_bears':
      default:
        return 'العميل يتحمل الهالك';
    }
  }

  Widget _buildDeliveriesSection() {
    final theme = Theme.of(context);
    final undelivered = (_order!.producedQuantity - _deliveredQty);
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.local_shipping, color: theme.colorScheme.primary),
                    const Gap(8),
                    Text('أذونات تسليم المنتج للعميل (${_deliveries.length})',
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  ],
                ),
                if (_order!.status == ManufacturingOrderStatus.completed && undelivered > 0)
                  FilledButton.icon(
                    onPressed: _openDeliveryDialog,
                    icon: const Icon(Icons.add),
                    label: const Text('إذن تسليم جديد'),
                  ),
              ],
            ),
            const Divider(height: 24),
            if (_deliveries.isEmpty)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text('لم يتم تسجيل أي أذونات تسليم بعد', style: TextStyle(color: Colors.grey.shade600)),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _deliveries.length,
                separatorBuilder: (_, i) => const Divider(height: 12),
                itemBuilder: (context, index) {
                  final d = _deliveries[index];
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(child: Icon(Icons.inventory, size: 18)),
                    title: Text('إذن تسليم: ${d.deliveryNumber}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(
                        'التاريخ: ${DateFormat('yyyy/MM/dd HH:mm').format(d.deliveryDate)} | المستلم: ${d.receiverName ?? '—'} | المندوب: ${d.deliveredBy ?? '—'}'),
                    trailing: Chip(
                      label: Text(d.status == 'delivered' ? 'تم التسليم' : d.status),
                      backgroundColor: Colors.green.shade50,
                      labelStyle: const TextStyle(color: Colors.green, fontSize: 12),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildReconciliationCard() {
    final mo = _order!;
    final theme = Theme.of(context);

    double totalConsumed = 0.0;
    for (final m in _orderMovements) {
      if (m.movementType == 'issued_to_order') {
        totalConsumed += m.quantity.abs();
      }
    }

    double totalOnHand = 0.0;
    for (final b in _customerBalances) {
      totalOnHand += b.quantityOnHand;
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.compare_arrows, color: theme.colorScheme.primary),
                const Gap(8),
                Text('بطاقة مطابقة الخامات والتشغيل (Reconciliation)',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const Divider(height: 24),
            Wrap(
              spacing: 20,
              runSpacing: 12,
              children: [
                _stat(context, 'العميل صاحب العهدة', _customer?.name ?? '—', Icons.person),
                _stat(context, 'الكمية المنتجة', '${mo.producedQuantity} وحدة', Icons.check_circle_outline),
                _stat(context, 'المسلم للعميل', '$_deliveredQty وحدة', Icons.local_shipping_outlined),
                _stat(context, 'المتبقي للتسليم', '${mo.producedQuantity - _deliveredQty} وحدة', Icons.hourglass_bottom),
                _stat(context, 'المستهلك من العهدة', '$totalConsumed وحدة', Icons.remove_circle_outline),
                _stat(context, 'رصيد العهدة بالمخزن', '$totalOnHand وحدة', Icons.warehouse_outlined),
              ],
            ),
            if (_customerBalances.isNotEmpty) ...[
              const Gap(16),
              const Text('أرصدة عهدة العميل الحالية بالمخزن:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const Gap(8),
              Table(
                border: TableBorder.all(color: Colors.grey.shade300),
                columnWidths: const {
                  0: FlexColumnWidth(3),
                  1: FlexColumnWidth(2),
                  2: FlexColumnWidth(2),
                  3: FlexColumnWidth(2),
                },
                children: [
                  TableRow(
                    decoration: BoxDecoration(color: Colors.grey.shade100),
                    children: const [
                      Padding(padding: EdgeInsets.all(6), child: Text('كود الصنف', style: TextStyle(fontWeight: FontWeight.bold))),
                      Padding(padding: EdgeInsets.all(6), child: Text('الرصيد المتاح', style: TextStyle(fontWeight: FontWeight.bold))),
                      Padding(padding: EdgeInsets.all(6), child: Text('المحجوز', style: TextStyle(fontWeight: FontWeight.bold))),
                      Padding(padding: EdgeInsets.all(6), child: Text('اللون / المقاس', style: TextStyle(fontWeight: FontWeight.bold))),
                    ],
                  ),
                  for (final b in _customerBalances)
                    TableRow(
                      children: [
                        Padding(padding: const EdgeInsets.all(6), child: Text('#${b.productId}')),
                        Padding(padding: const EdgeInsets.all(6), child: Text('${b.quantityOnHand}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green))),
                        Padding(padding: const EdgeInsets.all(6), child: Text('${b.quantityAllocated}')),
                        Padding(padding: const EdgeInsets.all(6), child: Text('${b.color ?? ''} ${b.size ?? ''}'.trim().isEmpty ? '—' : '${b.color ?? ''} ${b.size ?? ''}'.trim())),
                      ],
                    ),
                ],
              ),
            ],
          ],
        ),
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
                        if (mo.orderType != 'internal') ...[
                          _stat(context, 'نوع التشغيل', mo.orderType == 'for_others' ? 'تشغيل للغير' : 'تشغيل مشترك', Icons.category),
                          _stat(context, 'العميل', _customer?.name ?? '—', Icons.person),
                          _stat(context, 'حالة التسليم', _deliveryStatusLabel(mo.deliveryStatus), Icons.local_shipping),
                          _stat(context, 'أجر التشغيل للوحدة', '${mo.serviceUnitPrice ?? 0} ج.م', Icons.attach_money),
                          _stat(context, 'سياسة الهالك', _scrapPolicyLabel(mo.scrapPolicy), Icons.policy),
                        ],
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
                      runSpacing: 8,
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
                        if (mo.status == ManufacturingOrderStatus.completed && mo.orderType != 'internal') ...[
                          if ((mo.producedQuantity - _deliveredQty) > 0)
                            FilledButton.icon(
                              onPressed: _openDeliveryDialog,
                              icon: const Icon(Icons.local_shipping),
                              label: const Text('تسجيل إذن تسليم'),
                            ),
                          if (mo.invoiceId == null)
                            FilledButton.icon(
                              onPressed: _generateServiceInvoice,
                              icon: const Icon(Icons.receipt_long),
                              label: const Text('إصدار فاتورة خدمات'),
                              style: FilledButton.styleFrom(backgroundColor: Colors.teal),
                            )
                          else
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.teal.shade50,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.teal),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.check_circle, size: 16, color: Colors.teal),
                                  const Gap(6),
                                  Text('فاتورة مسجلة #${mo.invoiceId}',
                                      style: const TextStyle(color: Colors.teal, fontWeight: FontWeight.bold, fontSize: 13)),
                                ],
                              ),
                            ),
                        ],
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
            // Cost components editor (read-only after completion)
            CostComponentEditor(
              db: widget.db,
              orderId: mo.id,
              orderStatus: mo.status,
              onChanged: () => setState(() {}),
            ),
            const Gap(24),
            // Scrap — only meaningful once the order is completed. Waste
            // allowance on the BOM is the plan; these rows are what actually
            // happened, and the variance between the two is the useful number.
            if (mo.status == ManufacturingOrderStatus.completed) ...[
              Text('الهالك',
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const Gap(8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _openScrapDialog,
                        icon: const Icon(Icons.report_problem_outlined),
                        label: const Text('تسجيل هالك'),
                      ),
                      const Gap(8),
                      StreamBuilder<List<ManufacturingScrap>>(
                        stream: widget.db.manufacturingScrapDao
                            .watchForOrder(mo.id),
                        builder: (context, snap) {
                          final rows = snap.data ?? const <ManufacturingScrap>[];
                          if (rows.isEmpty) {
                            return Text('لا يوجد هالك مسجّل على هذا الأمر',
                                style: TextStyle(
                                    color: Colors.grey.shade600, fontSize: 12));
                          }
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final r in rows)
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 2),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        flex: 3,
                                        child: Text(
                                          r.productId == mo.finishedProductId
                                              ? 'منتج نهائي'
                                              : 'خام #${r.productId}',
                                          style:
                                              const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: Text(
                                            '${r.quantity} — ${ManufacturingScrapReason.label(r.reason)}',
                                            style: const TextStyle(
                                                fontSize: 12)),
                                      ),
                                      Expanded(
                                        flex: 3,
                                        child: Text(r.responsibleParty,
                                            style:
                                                const TextStyle(fontSize: 12)),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const Gap(24),
            ],
            if (mo.orderType != 'internal') ...[
              _buildDeliveriesSection(),
              const Gap(24),
              _buildReconciliationCard(),
              const Gap(24),
            ],
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
