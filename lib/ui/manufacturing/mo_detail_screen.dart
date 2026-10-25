import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/dao/manufacturing_order_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/manufacturing_delivery_dao.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_orders_table.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_scrap_table.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_stages_table.dart';
import 'package:pos_offline_desktop/core/services/unified_print_service.dart'
    as ups;
import 'package:pos_offline_desktop/ui/manufacturing/widgets/cost_component_editor.dart';
import 'package:pos_offline_desktop/ui/manufacturing/widgets/mo_form_dialog.dart';
import 'package:printing/printing.dart';

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
  // FEAT-008: balance product ids resolved to displayable names
  final Map<int, String> _balanceProductNames = {};
  // FEAT-009: product ids with movements linked to THIS order
  Set<int> _orderBalanceIds = {};
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
      final order = await widget.db.manufacturingOrderDao.getById(
        widget.orderId,
      );
      if (order == null) {
        setState(() {
          _error = 'أمر التصنيع غير موجود';
          _isLoading = false;
        });
        return;
      }
      final bom = await widget.db.bomDao.getBomById(order.bomId);
      final product = await widget.db.productDao.getProductById(
        order.finishedProductId,
      );
      final items = await widget.db.bomDao.getItemsWithProducts(order.bomId);

      Customer? customer;
      List<ManufacturingDelivery> deliveries = [];
      double deliveredQty = 0.0;
      List<CustomerStockMovement> orderMovements = [];
      List<CustomerStockBalance> customerBalances = [];
      Map<int, String> balanceNames = {};
      Set<int> orderProductIds = {};

      if (order.customerId != null && order.customerId!.isNotEmpty) {
        customer = await widget.db.customerDao.getCustomerById(
          order.customerId!,
        );
        deliveries = await widget.db.manufacturingDeliveryDao
            .getDeliveriesForOrder(order.id);
        deliveredQty = await widget.db.manufacturingDeliveryDao
            .getTotalDeliveredQuantity(order.id);
        orderMovements = await (widget.db.select(
          widget.db.customerStockMovements,
        )..where((m) => m.referenceId.equals(order.orderNumber))).get();
        // FEAT-009: the order-scoped view of custody starts from the
        // product ids this order actually moved in/out of the customer's
        // custody (issue, delivery, scrap, defect return)
        orderProductIds = orderMovements.map((m) => m.productId).toSet();
        customerBalances = await widget.db.customerMaterialReceiptDao
            .getAllBalancesForCustomer(order.customerId!);
        // FEAT-008: resolve material names once so the reconciliation
        // table shows what the customer knows, not raw row ids
        for (final b in customerBalances) {
          if (balanceNames.containsKey(b.productId)) continue;
          final p = await widget.db.productDao.getProductById(b.productId);
          balanceNames[b.productId] = p?.name ?? '#${b.productId}';
        }
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
        _orderBalanceIds = orderProductIds;
        _balanceProductNames
          ..clear()
          ..addAll(balanceNames);
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

  /// FEAT-010: production/consumption documentation card — collects what the
  /// screen already loaded and renders it through the unified print service.
  Future<void> _printProductionCard() async {
    final mo = _order!;
    // BUG-008 evidence: issue/defect rows reference the ORDER number while
    // delivered rows reference each DELIVERY NOTE number, so the ledger for
    // the card must merge both queries or the card shows an empty ledger.
    final deliveryNumbers = _deliveries.map((d) => d.deliveryNumber).toList();
    final deliveredLedger =
        await (widget.db.select(widget.db.customerStockMovements)..where(
              (m) => deliveryNumbers.isNotEmpty
                  ? m.referenceId.isIn(deliveryNumbers)
                  : m.id.isNull(),
            ))
            .get();
    // BUG-008: scope the card to the order — custody balances shown are the
    // ones this order actually moved (or the full customer custody when the
    // order has not moved anything yet).
    final ledger = [..._orderMovements, ...deliveredLedger];
    final linkedIds = ledger.map((m) => m.productId).toSet();
    final scopedBalances = linkedIds.isEmpty
        ? _customerBalances
        : _customerBalances
              .where((b) => linkedIds.contains(b.productId))
              .toList();
    final totalConsumed = _orderMovements
        .where((m) => m.movementType == 'issued_to_order')
        .fold<double>(0, (s, m) => s + m.quantity.abs());
    final totalOnHand = scopedBalances.fold<double>(
      0,
      (s, b) => s + b.quantityOnHand,
    );

    String movementTypeAr(String t) {
      switch (t) {
        case 'receipt':
          return 'استلام عهدة';
        case 'issued_to_order':
          return 'صرف للأمر';
        case 'delivered':
          return 'تسليم للعميل';
        case 'return_defect':
          return 'مرتجع تالف';
        case 'scrapped':
          return 'هالك';
        default:
          return t;
      }
    }

    final movementRows = <Map<String, dynamic>>[
      for (final m in ledger)
        {
          'date': DateFormat('yyyy/MM/dd HH:mm').format(m.createdAt),
          'movementType': movementTypeAr(m.movementType),
          'productName': _balanceProductNames[m.productId] ?? '#${m.productId}',
          'quantity': m.quantity.abs(),
          'reference': m.referenceId,
        },
    ];
    final balanceRows = <Map<String, dynamic>>[
      for (final b in scopedBalances)
        {
          'productName': _balanceProductNames[b.productId] ?? '#${b.productId}',
          'quantityOnHand': b.quantityOnHand,
          'quantityAllocated': b.quantityAllocated,
          'colorSize': '${b.color ?? ''} ${b.size ?? ''}'.trim().isEmpty
              ? null
              : '${b.color ?? ''} ${b.size ?? ''}'.trim(),
        },
    ];

    final orderScraps = await widget.db.manufacturingScrapDao.getForOrder(mo.id);
    final scrapRows = <Map<String, dynamic>>[
      for (final s in orderScraps)
        {
          'date': DateFormat('yyyy/MM/dd').format(s.createdAt),
          'productName': _balanceProductNames[s.productId] ?? '#\${s.productId}',
          'quantity': s.quantity,
          'reason': ManufacturingScrapReason.label(s.reason),
          'faultParty': s.faultParty == 'factory'
              ? 'المصنع'
              : (s.faultParty == 'customer' ? 'العميل' : '—'),
          'responsibleParty': s.responsibleParty,
          'compensationAction': s.compensationAction ?? '—',
          'compensationAmount': s.compensationAmount,
        },
    ];

    try {
      final pdf = await ups.UnifiedPrintService.generateUnifiedDocument(
        documentType: ups.DocumentType.manufacturingCard,
        data: <String, dynamic>{
          'orderNumber': mo.orderNumber,
          'status': _statusLabel(mo.status),
          'orderType': mo.orderType == 'for_others'
              ? 'تصنيع للغير'
              : mo.orderType,
          'customerName': _customer?.name ?? '—',
          'bomName': _bom?.name ?? '—',
          'finishedProductName': _finishedProduct?.name ?? '—',
          'createdDate': DateFormat('yyyy/MM/dd').format(mo.createdAt),
          'startedDate': mo.startedAt == null
              ? '—'
              : DateFormat('yyyy/MM/dd').format(mo.startedAt!),
          'completedDate': mo.completedAt == null
              ? '—'
              : DateFormat('yyyy/MM/dd').format(mo.completedAt!),
          'plannedQuantity': mo.plannedQuantity,
          'producedQuantity': mo.producedQuantity,
          'deliveredQuantity': _deliveredQty,
          'consumedQuantity': totalConsumed,
          'custodyOnHand': totalOnHand,
        },
        additionalData: <String, dynamic>{
          'movements': movementRows,
          'balances': balanceRows,
          'scraps': scrapRows,
        },
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogCtx) => Dialog(
          insetPadding: const EdgeInsets.all(24),
          child: SizedBox(
            width: 900,
            height: 750,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'بطاقة الإنتاج/الصرف — ${mo.orderNumber}',
                          style: Theme.of(dialogCtx).textTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(dialogCtx),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: PdfPreview(
                    build: (format) => pdf.save(),
                    allowPrinting: true,
                    allowSharing: true,
                    initialPageFormat: PdfPageFormat.a4,
                    pdfFileName: 'mo_${mo.orderNumber}.pdf',
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('خطأ في إنشاء البطاقة: $e')));
    }
  }

  Future<void> _printManufacturingReport() async {
    final mo = _order!;
    final stages = await widget.db.manufacturingStageDao.getStagesForOrder(mo.id);
    final scraps = await widget.db.manufacturingScrapDao.getForOrder(mo.id);
    final stagesData = <Map<String, dynamic>>[];
    for (final s in stages) {
      final outputs = await widget.db.manufacturingStageDao.getOutputsForStage(s.id);
      stagesData.add({
        'stageName': s.stageName,
        'status': s.status,
        'inputQuantity': s.inputQuantity,
        'outputQuantity': s.outputQuantity,
        'scrapQuantity': s.scrapQuantity,
        'stageCost': s.stageCost,
        'outputs': outputs.map((o) => {
          'variantName': o.variantName ?? 'قياسي',
          'producedQuantity': o.producedQuantity,
          'scrapQuantity': o.scrapQuantity,
        }).toList(),
      });
    }

    final scrapRows = scraps.map((s) => {
      'date': DateFormat('yyyy/MM/dd').format(s.createdAt),
      'productName': s.variantName != null ? '${_balanceProductNames[s.productId] ?? s.productId} (${s.variantName})' : (_balanceProductNames[s.productId] ?? '#${s.productId}'),
      'quantity': s.quantity,
      'reason': ManufacturingScrapReason.label(s.reason),
      'faultParty': s.faultParty == 'factory' ? 'المصنع' : (s.faultParty == 'customer' ? 'العميل' : '—'),
      'compensationAction': s.compensationAction ?? '—',
      'compensationAmount': s.compensationAmount,
      'isSellable': (s.isSellable == true) ? 'قابل للبيع' : 'تالف',
      'estimatedSellPrice': s.estimatedSellPrice ?? 0.0,
    }).toList();

    try {
      final pdf = await ups.UnifiedPrintService.generateUnifiedDocument(
        documentType: ups.DocumentType.manufacturingReport,
        data: <String, dynamic>{
          'orderNumber': mo.orderNumber,
          'status': _statusLabel(mo.status),
          'orderType': mo.orderType == 'for_others' ? 'تصنيع للغير' : 'تصنيع داخلي',
          'customerName': _customer?.name ?? '—',
          'bomName': _bom?.name ?? '—',
          'finishedProductName': _finishedProduct?.name ?? '—',
          'currentStage': mo.currentStageName ?? '—',
          'createdDate': DateFormat('yyyy/MM/dd').format(mo.createdAt),
          'plannedQuantity': mo.plannedQuantity,
          'producedQuantity': mo.producedQuantity,
          'deliveredQuantity': _deliveredQty,
        },
        additionalData: <String, dynamic>{
          'stages': stagesData,
          'scraps': scrapRows,
        },
      );

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogCtx) => Dialog(
          insetPadding: const EdgeInsets.all(24),
          child: SizedBox(
            width: 900,
            height: 750,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'تقرير مراحل وتكاليف أمر التصنيع — ${mo.orderNumber}',
                          style: Theme.of(dialogCtx).textTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(dialogCtx),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: PdfPreview(
                    build: (format) => pdf.save(),
                    allowPrinting: true,
                    allowSharing: true,
                    initialPageFormat: PdfPageFormat.a4,
                    pdfFileName: 'report_${mo.orderNumber}.pdf',
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في إنشاء التقرير: $e')),
        );
      }
    }
  }

  Future<void> _openAddStageDialog() async {
    final mo = _order;
    if (mo == null) return;
    final nameCtrl = TextEditingController(text: 'الخياطة والتجميع');
    final qtyCtrl = TextEditingController(text: mo.plannedQuantity.toString());
    final noteCtrl = TextEditingController();

    final saved = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.add_task, color: Colors.blue),
            Gap(8),
            Text('إضافة مرحلة تصنيع جديدة'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'اسم المرحلة *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.layers_outlined),
                ),
              ),
              const Gap(8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  'القص والتفصيل',
                  'الخياطة والتجميع',
                  'الكي والتغليف',
                  'التشطيب والجودة',
                  'تطريز وطباعة',
                ].map((s) => ActionChip(
                  label: Text(s, style: const TextStyle(fontSize: 11)),
                  onPressed: () => nameCtrl.text = s,
                )).toList(),
              ),
              const Gap(16),
              TextField(
                controller: qtyCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'الكمية الداخلة للمرحلة *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.numbers),
                ),
              ),
              const Gap(16),
              TextField(
                controller: noteCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'ملاحظات المرحلة (اختياري)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.note_alt_outlined),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              final qty = double.tryParse(qtyCtrl.text.trim()) ?? mo.plannedQuantity;
              try {
                await widget.db.manufacturingStageDao.addStage(
                  orderId: mo.id,
                  stageName: nameCtrl.text.trim(),
                  inputQuantity: qty,
                  notes: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
                );
                await widget.db.manufacturingOrderDao.updateOrder(
                  mo.copyWith(currentStageName: Value(nameCtrl.text.trim())),
                );
                if (c.mounted) Navigator.pop(c, true);
              } catch (e) {
                if (c.mounted) {
                  ScaffoldMessenger.of(c).showSnackBar(
                    SnackBar(content: Text('فشل إضافة المرحلة: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('إضافة المرحلة'),
          ),
        ],
      ),
    );

    nameCtrl.dispose();
    qtyCtrl.dispose();
    noteCtrl.dispose();

    if (saved == true && mounted) {
      _loadData();
    }
  }

  Future<void> _openAddStageOutputDialog(ManufacturingStage stage) async {
    final mo = _order;
    if (mo == null) return;
    final variants = await widget.db.productVariantDao.getVariantsByProduct(mo.finishedProductId);

    int? selectedVariantId = variants.isNotEmpty ? variants.first.id : null;
    String? selectedVariantName = variants.isNotEmpty ? variants.first.name : null;
    final producedCtrl = TextEditingController(text: '0');
    final scrapCtrl = TextEditingController(text: '0');
    final sellableScrapCtrl = TextEditingController(text: '0');
    final sellablePriceCtrl = TextEditingController(text: '0');
    final noteCtrl = TextEditingController();

    if (!mounted) return;

    final saved = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDlg) => AlertDialog(
          title: Text('تسجيل مخرجات لمرحلة: ${stage.stageName}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (variants.isNotEmpty)
                  DropdownButtonFormField<int>(
                    value: selectedVariantId,
                    decoration: const InputDecoration(
                      labelText: 'المقاس / الصنف الفرعي',
                      border: OutlineInputBorder(),
                    ),
                    items: variants.map((v) => DropdownMenuItem(
                      value: v.id,
                      child: Text(v.name),
                    )).toList(),
                    onChanged: (v) {
                      final match = variants.firstWhere((x) => x.id == v);
                      setDlg(() {
                        selectedVariantId = v;
                        selectedVariantName = match.name;
                      });
                    },
                  )
                else
                  const Text('لا توجد مقاسات مسجلة للمنتج. يمكنك استخدام زر "+ مقاس جديد" لإنشاء مقاسات مثل S, M, L.'),
                const Gap(16),
                TextField(
                  controller: producedCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'الكمية السليمة المنتجة *',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.check_circle_outline, color: Colors.green),
                  ),
                ),
                const Gap(12),
                TextField(
                  controller: scrapCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'كمية الهالك التالف (غير صالح)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.delete_outline, color: Colors.red),
                  ),
                ),
                const Gap(12),
                TextField(
                  controller: sellableScrapCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'كمية الهالك القابل للبيع (فرز ثاني)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.recycling, color: Colors.teal),
                  ),
                ),
                const Gap(12),
                TextField(
                  controller: sellablePriceCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'سعر بيع الهالك للوحدة (ج.م)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.attach_money, color: Colors.teal),
                  ),
                ),
                const Gap(12),
                TextField(
                  controller: noteCtrl,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظات (اختياري)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () async {
                final prod = double.tryParse(producedCtrl.text.trim()) ?? 0.0;
                final scr = double.tryParse(scrapCtrl.text.trim()) ?? 0.0;
                final sellScr = double.tryParse(sellableScrapCtrl.text.trim()) ?? 0.0;
                final sellPrice = double.tryParse(sellablePriceCtrl.text.trim()) ?? 0.0;

                try {
                  await widget.db.manufacturingStageDao.upsertStageOutput(
                    stageId: stage.id,
                    orderId: mo.id,
                    productId: mo.finishedProductId,
                    variantId: selectedVariantId,
                    variantName: selectedVariantName,
                    plannedQuantity: prod,
                    producedQuantity: prod,
                    scrapQuantity: scr,
                    sellingPriceOverride: sellPrice > 0 ? sellPrice : null,
                    notes: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
                  );
                  if (c.mounted) Navigator.pop(c, true);
                } catch (e) {
                  if (c.mounted) {
                    ScaffoldMessenger.of(c).showSnackBar(
                      SnackBar(content: Text('فشل تسجيل المخرجات: $e'), backgroundColor: Colors.red),
                    );
                  }
                }
              },
              child: const Text('حفظ المخرجات'),
            ),
          ],
        ),
      ),
    );

    producedCtrl.dispose();
    scrapCtrl.dispose();
    sellableScrapCtrl.dispose();
    sellablePriceCtrl.dispose();
    noteCtrl.dispose();

    if (saved == true && mounted) {
      _loadData();
    }
  }

  Future<void> _openAddNewVariantDialog(ManufacturingStage stage) async {
    final mo = _order;
    if (mo == null) return;

    final nameCtrl = TextEditingController(text: 'مقاس L');
    final producedCtrl = TextEditingController(text: '10');
    final sellableScrapCtrl = TextEditingController(text: '0');
    final sellablePriceCtrl = TextEditingController(text: '0');

    final saved = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.style, color: Colors.blue),
            Gap(8),
            Text('إضافة مقاس / متغير جديد للمنتج'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'اسم المقاس / المتغير *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.straighten),
                ),
              ),
              const Gap(8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: ['S', 'M', 'L', 'XL', '2XL', '3XL', 'حر'].map((sz) => ActionChip(
                  label: Text('مقاس $sz', style: const TextStyle(fontSize: 11)),
                  onPressed: () => nameCtrl.text = 'مقاس $sz',
                )).toList(),
              ),
              const Gap(16),
              TextField(
                controller: producedCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'الكمية المنتجة من هذا المقاس *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.check_circle_outline, color: Colors.green),
                ),
              ),
              const Gap(12),
              TextField(
                controller: sellableScrapCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'هالك قابل للبيع (فرز ثاني)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.recycling, color: Colors.teal),
                ),
              ),
              const Gap(12),
              TextField(
                controller: sellablePriceCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'سعر بيع الهالك للوحدة (ج.م)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.attach_money, color: Colors.teal),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              final prod = double.tryParse(producedCtrl.text.trim()) ?? 0.0;
              final sellScr = double.tryParse(sellableScrapCtrl.text.trim()) ?? 0.0;
              final sellPrice = double.tryParse(sellablePriceCtrl.text.trim()) ?? 0.0;

              try {
                await widget.db.manufacturingStageDao.createVariantAndAddToStage(
                  stageId: stage.id,
                  orderId: mo.id,
                  productId: mo.finishedProductId,
                  variantName: nameCtrl.text.trim(),
                  plannedQuantity: prod,
                  sellingPrice: sellPrice > 0 ? sellPrice : null,
                );
                if (c.mounted) Navigator.pop(c, true);
              } catch (e) {
                if (c.mounted) {
                  ScaffoldMessenger.of(c).showSnackBar(
                    SnackBar(content: Text('فشل إضافة المقاس: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('إنشاء المقاس وحفظه'),
          ),
        ],
      ),
    );

    nameCtrl.dispose();
    producedCtrl.dispose();
    sellableScrapCtrl.dispose();
    sellablePriceCtrl.dispose();

    if (saved == true && mounted) {
      _loadData();
    }
  }

  Future<void> _completeStage(ManufacturingStage stage) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('إكمال مرحلة: ${stage.stageName}'),
        content: Text('هل أنت متأكد من إكمال هذه المرحلة؟ سيتم اعتماد المخرجات وتحديث حالة المرحلة إلى مكتملة.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('تراجع'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('تأكيد الإكمال'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await widget.db.manufacturingStageDao.updateStageStatus(stageId: stage.id, status: ManufacturingStageStatus.completed);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم إكمال مرحلة ${stage.stageName}')),
        );
      }
      _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل إكمال المرحلة: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildStagesSection() {
    final theme = Theme.of(context);
    final mo = _order!;

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
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.layers, color: theme.colorScheme.primary),
                ),
                const Gap(12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'مراحل خط الإنتاج والمقاسات (Routing & Variants)',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (mo.currentStageName != null)
                        Text(
                          'المرحلة الحالية: ${mo.currentStageName}',
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
                if (mo.status != ManufacturingOrderStatus.cancelled &&
                    mo.status != ManufacturingOrderStatus.completed) ...[
                  FilledButton.icon(
                    onPressed: _openAddStageDialog,
                    icon: const Icon(Icons.add_task),
                    label: const Text('إضافة مرحلة جديدة'),
                  ),
                ],
              ],
            ),
            const Divider(height: 24),
            StreamBuilder<List<ManufacturingStage>>(
              stream: widget.db.manufacturingStageDao.watchStagesForOrder(mo.id),
              builder: (context, snap) {
                final stages = snap.data ?? const <ManufacturingStage>[];
                if (stages.isEmpty) {
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.alt_route, size: 36, color: Colors.grey),
                        const Gap(8),
                        const Text(
                          'لم يتم تعريف مراحل لهذا الأمر بعد. يمكنك بدء مرحلة جديدة (قص، خياطة، تغليف...)',
                          style: TextStyle(fontSize: 13),
                        ),
                        const Gap(12),
                        if (mo.status != ManufacturingOrderStatus.cancelled)
                          OutlinedButton.icon(
                            onPressed: _openAddStageDialog,
                            icon: const Icon(Icons.add),
                            label: const Text('إضافة المرحلة الأولى الآن'),
                          ),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: stages.length,
                  separatorBuilder: (_, __) => const Gap(16),
                  itemBuilder: (context, index) {
                    final stage = stages[index];
                    final isCurrent = stage.stageName == mo.currentStageName;
                    final isCompleted = stage.status == ManufacturingStageStatus.completed;

                    return Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: isCurrent
                              ? theme.colorScheme.primary
                              : theme.colorScheme.outlineVariant,
                          width: isCurrent ? 2 : 1,
                        ),
                        borderRadius: BorderRadius.circular(10),
                        color: isCurrent
                            ? theme.colorScheme.primary.withValues(alpha: 0.03)
                            : null,
                      ),
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 14,
                                backgroundColor: isCompleted
                                    ? Colors.green
                                    : (isCurrent
                                        ? theme.colorScheme.primary
                                        : Colors.grey),
                                child: Text(
                                  '${stage.stageOrder}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const Gap(8),
                              Expanded(
                                child: Text(
                                  stage.stageName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                              Chip(
                                label: Text(
                                  isCompleted
                                      ? 'مكتملة'
                                      : (isCurrent ? 'قيد التنفيذ (الحالية)' : 'جارية'),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isCompleted
                                        ? Colors.green
                                        : (isCurrent
                                            ? theme.colorScheme.primary
                                            : Colors.orange),
                                  ),
                                ),
                                backgroundColor: (isCompleted
                                        ? Colors.green
                                        : (isCurrent
                                            ? theme.colorScheme.primary
                                            : Colors.orange))
                                    .withValues(alpha: 0.12),
                                padding: EdgeInsets.zero,
                              ),
                            ],
                          ),
                          const Gap(8),
                          Wrap(
                            spacing: 16,
                            runSpacing: 8,
                            children: [
                              _stageStat('الكمية الداخلة', '${stage.inputQuantity}'),
                              _stageStat('المنجز السليم', '${stage.outputQuantity}', color: Colors.green),
                              _stageStat('هالك تالف', '${stage.scrapQuantity}', color: Colors.red),
                              if (stage.stageCost > 0)
                                _stageStat('تكلفة المرحلة', '${stage.stageCost.toStringAsFixed(2)} ج.م', color: Colors.teal),
                            ],
                          ),
                          const Gap(12),
                          // Outputs Table
                          StreamBuilder<List<ManufacturingStageOutput>>(
                            stream: widget.db.manufacturingStageDao.watchOutputsForStage(stage.id),
                            builder: (context, outSnap) {
                              final outputs = outSnap.data ?? const <ManufacturingStageOutput>[];
                              if (outputs.isEmpty) {
                                return const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 4),
                                  child: Text(
                                    'لا توجد مقاسات مسجلة لهذه المرحلة بعد.',
                                    style: TextStyle(fontSize: 12, color: Colors.grey),
                                  ),
                                );
                              }
                              return Container(
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Table(
                                  border: TableBorder.all(
                                    color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                                  ),
                                  columnWidths: const {
                                    0: FlexColumnWidth(2.5),
                                    1: FlexColumnWidth(1.5),
                                    2: FlexColumnWidth(1.5),
                                    3: FlexColumnWidth(2),
                                  },
                                  children: [
                                    TableRow(
                                      decoration: BoxDecoration(
                                        color: theme.colorScheme.surfaceContainerHighest,
                                      ),
                                      children: const [
                                        Padding(padding: EdgeInsets.all(6), child: Text('المقاس / المتغير', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                                        Padding(padding: EdgeInsets.all(6), child: Text('الكمية المنتجة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                                        Padding(padding: EdgeInsets.all(6), child: Text('الهالك', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                                        Padding(padding: EdgeInsets.all(6), child: Text('سعر البيع المقترح', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                                      ],
                                    ),
                                    for (final out in outputs)
                                      TableRow(
                                        children: [
                                          Padding(padding: const EdgeInsets.all(6), child: Text(out.variantName ?? 'قياسي', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                                          Padding(padding: const EdgeInsets.all(6), child: Text('${out.producedQuantity}', style: const TextStyle(fontSize: 12, color: Colors.green))),
                                          Padding(padding: const EdgeInsets.all(6), child: Text('${out.scrapQuantity}', style: const TextStyle(fontSize: 12, color: Colors.red))),
                                          Padding(padding: const EdgeInsets.all(6), child: Text(out.sellingPriceOverride != null ? '${out.sellingPriceOverride} ج.م' : '—', style: const TextStyle(fontSize: 12, color: Colors.teal))),
                                        ],
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                          if (!isCompleted && mo.status != ManufacturingOrderStatus.cancelled) ...[
                            const Gap(10),
                            Wrap(
                              spacing: 8,
                              children: [
                                FilledButton.tonalIcon(
                                  onPressed: () => _openAddStageOutputDialog(stage),
                                  icon: const Icon(Icons.playlist_add_check, size: 16),
                                  label: const Text('تسجيل مخرجات مقاس', style: TextStyle(fontSize: 12)),
                                ),
                                OutlinedButton.icon(
                                  onPressed: () => _openAddNewVariantDialog(stage),
                                  icon: const Icon(Icons.add, size: 16),
                                  label: const Text('+ مقاس جديد', style: TextStyle(fontSize: 12)),
                                ),
                                if (isCurrent)
                                  OutlinedButton.icon(
                                    onPressed: () async {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('أنت تعمل حالياً على مرحلة: ${stage.stageName}')),
                                      );
                                    },
                                    icon: const Icon(Icons.arrow_forward, size: 16),
                                    label: const Text('المرحلة الحالية النشطة', style: TextStyle(fontSize: 12)),
                                  )
                                else
                                  TextButton.icon(
                                    onPressed: () async {
                                      await widget.db.manufacturingOrderDao.updateOrder(
                                        mo.copyWith(currentStageName: Value(stage.stageName)),
                                      );
                                      _loadData();
                                    },
                                    icon: const Icon(Icons.check, size: 16),
                                    label: const Text('تعيين كمرحلة حالية', style: TextStyle(fontSize: 12)),
                                  ),
                                FilledButton.icon(
                                  style: FilledButton.styleFrom(backgroundColor: Colors.green),
                                  onPressed: () => _completeStage(stage),
                                  icon: const Icon(Icons.done_all, size: 16),
                                  label: const Text('إكمال المرحلة', style: TextStyle(fontSize: 12)),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _stageStat(String label, String value, {Color? color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label: ', style: const TextStyle(fontSize: 12, color: Colors.grey)),
        Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  Future<void> _startOrder() async {
    try {
      await widget.db.manufacturingOrderDao.startOrder(_order!.id);
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم بدء التنفيذ'),
            backgroundColor: Colors.green,
          ),
        );
      _loadData();
    } on InsufficientStockException catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل: $e'), backgroundColor: Colors.red),
        );
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
            const Text(
              'سيتم إلغاء الأمر بدون أي تأثير على المخزون — لا يتم صرف خامات ولا استلام إنتاج.',
            ),
            const Gap(12),
            TextField(
              decoration: const InputDecoration(
                labelText: 'سبب الإلغاء',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => reason = v,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('تراجع'),
          ),
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
      await widget.db.manufacturingOrderDao.cancelOrder(
        _order!.id,
        reason: reason,
      );
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تم إلغاء الأمر')));
      _loadData();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل: $e'), backgroundColor: Colors.red),
        );
    }
  }

  Future<void> _reopenOrder() async {
    try {
      await widget.db.manufacturingOrderDao.reopenCancelledOrder(_order!.id);
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تمت إعادة فتح الأمر'),
            backgroundColor: Colors.green,
          ),
        );
      _loadData();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل: $e'), backgroundColor: Colors.red),
        );
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
          label:
              '${p.name}${p.unit == null ? '' : ' (${p.unit})'} — متاح ${p.quantity}',
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
    final sellPriceCtrl = TextEditingController(text: '0');

    final stages = await widget.db.manufacturingStageDao.getStagesForOrder(order.id);
    final variants = await widget.db.productVariantDao.getVariantsByProduct(order.finishedProductId);

    int? selectedStageId;
    int? selectedVariantId;
    String? selectedVariantName;
    bool isSellable = false;

    final saved = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDlg) => AlertDialog(
          title: const Text('تسجيل هالك على الأمر'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (stages.isNotEmpty) ...[
                  DropdownButtonFormField<int?>(
                    value: selectedStageId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'مرحلة الهالك (اختياري)'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('بدون مرحلة محددة')),
                      for (final st in stages)
                        DropdownMenuItem(value: st.id, child: Text('${st.stageOrder}. ${st.stageName}')),
                    ],
                    onChanged: (v) => setDlg(() => selectedStageId = v),
                  ),
                  const Gap(12),
                ],
                if (variants.isNotEmpty) ...[
                  DropdownButtonFormField<int?>(
                    value: selectedVariantId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'المقاس / الصنف الفرعي (اختياري)'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('المنتج الرئيسي / كل المقاسات')),
                      for (final vr in variants)
                        DropdownMenuItem(value: vr.id, child: Text(vr.name)),
                    ],
                    onChanged: (v) => setDlg(() {
                      selectedVariantId = v;
                      selectedVariantName = v != null ? variants.firstWhere((x) => x.id == v).name : null;
                    }),
                  ),
                  const Gap(12),
                ],
                DropdownButtonFormField<int>(
                  initialValue: productId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'الصنف المصاب بالهالك *'),
                  items: [
                    for (final o in options)
                      DropdownMenuItem(
                        value: o.productId,
                        child: Text(o.label),
                      ),
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
                    () => reason = v ?? ManufacturingScrapReason.defective,
                  ),
                ),
                const Gap(12),
                if (order.orderType != 'internal') ...[
                  DropdownButtonFormField<String>(
                    initialValue: faultParty,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'الطرف المتسبب في الهالك *',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'factory',
                        child: Text('المصنع (خطأ تشغيل)'),
                      ),
                      DropdownMenuItem(
                        value: 'customer',
                        child: Text('العميل (عيب خامة/مواصفة)'),
                      ),
                    ],
                    onChanged: (v) => setDlg(() => faultParty = v ?? 'factory'),
                  ),
                  const Gap(12),
                ],
                TextField(
                  controller: qtyCtrl,
                  decoration: const InputDecoration(labelText: 'الكمية'),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
                const Gap(12),
                TextField(
                  controller: partyCtrl,
                  decoration: const InputDecoration(
                    labelText: 'المسؤول (إجباري)',
                  ),
                ),
                const Gap(12),
                TextField(
                  controller: noteCtrl,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظة / رقم تفويض (اختياري)',
                  ),
                ),
                const Gap(12),
                CheckboxListTile(
                  title: const Text('هالك قابل للبيع (فرز ثاني / عوادم بقيمة)'),
                  subtitle: const Text('سيتم إدخاله في المخزون وتقليل صافي تكلفة الأمر بقيمة البيع'),
                  value: isSellable,
                  onChanged: (v) => setDlg(() => isSellable = v ?? false),
                ),
                if (isSellable) ...[
                  const Gap(8),
                  TextField(
                    controller: sellPriceCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'سعر بيع الهالك المتوقع للوحدة (ج.م) *',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.attach_money, color: Colors.teal),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () async {
                final qty = double.tryParse(qtyCtrl.text.trim());
                if (qty == null || qty <= 0) {
                  ScaffoldMessenger.of(c).showSnackBar(
                    const SnackBar(
                      content: Text('اكتب كمية أكبر من صفر'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                if (partyCtrl.text.trim().isEmpty) {
                  ScaffoldMessenger.of(c).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'لازم حد يتحمل responsibility — اكتب المسؤول',
                      ),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                try {
                  ManufacturingScrap createdScrap;
                  final estPrice = isSellable ? (double.tryParse(sellPriceCtrl.text.trim()) ?? 0.0) : 0.0;
                  if (order.orderType != 'internal') {
                    createdScrap = await widget.db.manufacturingScrapDao
                        .recordOrderScrapWithPolicy(
                          orderId: order.id,
                          productId: productId,
                          quantity: qty,
                          reason: reason,
                          responsibleParty: partyCtrl.text.trim(),
                          faultParty: faultParty,
                          stageId: selectedStageId,
                          variantId: selectedVariantId,
                          variantName: selectedVariantName,
                          isSellable: isSellable,
                          estimatedSellPrice: estPrice,
                          dispositionNote: noteCtrl.text.trim().isEmpty
                              ? null
                              : noteCtrl.text.trim(),
                          performedBy: 'ui',
                        );
                  } else {
                    createdScrap = await widget.db.manufacturingScrapDao
                        .recordScrap(
                          orderId: order.id,
                          productId: productId,
                          quantity: qty,
                          reason: reason,
                          responsibleParty: partyCtrl.text.trim(),
                          stageId: selectedStageId,
                          variantId: selectedVariantId,
                          variantName: selectedVariantName,
                          isSellable: isSellable,
                          estimatedSellPrice: estPrice,
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
                  ScaffoldMessenger.of(c).showSnackBar(
                    SnackBar(
                      content: Text(_readableScrapError(e)),
                      backgroundColor: Colors.red,
                      duration: const Duration(seconds: 5),
                    ),
                  );
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
    sellPriceCtrl.dispose();

    if (saved == true && mounted) {
      _loadData();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم تسجيل الهالك')));
    }
  }

  Future<void> _showScrapPolicyResultDialog(ManufacturingScrap scrap) async {
    String desc = 'سياسة الهالك المنفذة: ';
    if (scrap.compensationAction == 'deducted_from_invoice') {
      desc +=
          'تم تحديد خصم ${scrap.compensationAmount} ج.م من الفاتورة لصالح العميل.';
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
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: Colors.blue),
            Gap(8),
            Text('نتيجة سياسة الهالك'),
          ],
        ),
        content: Text(desc, style: const TextStyle(fontSize: 14)),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('حسناً'),
          ),
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
          .map(
            (s) =>
                '${s.productName}: مطلوب ${s.required} ${s.unit ?? ''}، متاح ${s.available}',
          )
          .join('\n');
    }
    return 'فشل تسجيل الهالك: $e';
  }

  Future<void> _completeOrder() async {
    if (_order == null || _bom == null) return;
    final actualQtyCtrl = TextEditingController(
      text: _order!.plannedQuantity.toString(),
    );
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
                if (_order!.orderType == 'for_others' ||
                    _order!.orderType == 'mixed') {
                  final result = await widget.db.manufacturingOrderDao
                      .completeForOthersOrder(
                        orderId: _order!.id,
                        actualProducedQuantity: actual,
                      );
                  if (dialogCtx.mounted) Navigator.pop(dialogCtx, true);
                  if (!mounted) return;
                  await _showForOthersCompletionSuccess(result);
                  _loadData();
                } else {
                  final result = await widget.db.manufacturingOrderDao
                      .completeManufacturingOrder(
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
                      _order!.orderType == 'for_others' ||
                              _order!.orderType == 'mixed'
                          ? 'سيتم خصم خامات العميل من رصيد العهدة بالمخزن في معاملة واحدة ذريّة (دون زيادة مخزون المصنع لأن البضاعة ملك العميل وتنتظر التسليم).'
                          : 'سيتم خصم المواد الخام وإضافة المنتج النهائي للمخزون في معاملة واحدة (ذريّة).',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                    const Gap(12),
                    TextField(
                      controller: actualQtyCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'الكمية المنتجة فعلياً *',
                        border: OutlineInputBorder(),
                        helperText: 'قد تختلف عن المخططة بسبب الهدر الفعلي',
                      ),
                      onChanged: (_) => setStateDialog(() {}),
                    ),
                    const Gap(12),
                    // Preview of required vs available.
                    // Customer-owned lines are compared against customer
                    // custody balances — never against factory Products.quantity
                    // (same ownership rule as completeForOthersOrder).
                    ..._bomItems.map((entry) {
                      final (item, product) = entry;
                      final waste =
                          item.wastePercentageOverride ?? _bom!.wastePercentage;
                      final actualForPreview =
                          double.tryParse(actualQtyCtrl.text) ??
                          _order!.plannedQuantity;
                      final factor = _bom!.yieldQuantity > 0
                          ? actualForPreview / _bom!.yieldQuantity
                          : actualForPreview;
                      final required =
                          (item.quantityRequired * factor * (1 + waste / 100))
                              .round();
                      final isCustomerOwned = isCustomerOwnedBomLine(
                        orderType: _order!.orderType ?? 'internal',
                        rawMaterialProductId: item.rawMaterialProductId,
                        hasCustodyBalance: _customerBalances.any(
                          (b) => b.productId == item.rawMaterialProductId,
                        ),
                      );
                      final int available;
                      if (isCustomerOwned) {
                        available = _customerBalances
                            .where(
                              (b) => b.productId == item.rawMaterialProductId,
                            )
                            .fold<double>(
                              0,
                              (s, b) =>
                                  s + (b.quantityOnHand - b.quantityAllocated),
                            )
                            .round();
                      } else {
                        available = product.quantity;
                      }
                      final short = required > available;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                isCustomerOwned
                                    ? '${product.name} (عهدة العميل)'
                                    : product.name,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                            Text(
                              '$required / $available ${product.unit ?? ''}',
                              style: TextStyle(
                                fontSize: 12,
                                color: short ? Colors.red : Colors.green,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (short)
                              const Padding(
                                padding: EdgeInsets.only(left: 6),
                                child: Icon(
                                  Icons.warning,
                                  size: 14,
                                  color: Colors.red,
                                ),
                              ),
                          ],
                        ),
                      );
                    }),
                    if (dialogError != null) ...[
                      const Gap(12),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Theme.of(ctx).colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          dialogError!,
                          style: TextStyle(
                            color: Theme.of(ctx).colorScheme.onErrorContainer,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () => Navigator.pop(dialogCtx, false),
                  child: const Text('إلغاء'),
                ),
                FilledButton(
                  onPressed: isSubmitting ? null : doComplete,
                  child: isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
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

  Future<void> _showCompletionSuccess(
    ManufacturingCompletionResult result,
  ) async {
    bool updateCost = false;
    await showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (ctx, setStateDialog) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                Gap(8),
                Text('تم إكمال التصنيع'),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'أمر ${result.orderNumber} • المنتج: ${result.finishedProductName}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const Gap(12),
                  _costRow(
                    'الكمية المنتجة:',
                    '${result.producedInt} وحدة (${result.producedQuantity} فعلي)',
                  ),
                  _costRow(
                    'تكلفة المواد:',
                    '${result.materialCost.toStringAsFixed(2)} ج.م',
                  ),
                  _costRow(
                    'تكاليف إضافية:',
                    '${result.componentsCost.toStringAsFixed(2)} ج.م',
                  ),
                  const Divider(),
                  _costRow(
                    'الإجمالي:',
                    '${result.totalCost.toStringAsFixed(2)} ج.م',
                    isBold: true,
                  ),
                  _costRow(
                    'تكلفة الوحدة:',
                    '${result.unitCost.toStringAsFixed(2)} ج.م / وحدة',
                    isBold: true,
                    color: Theme.of(ctx).colorScheme.primary,
                  ),
                  const Gap(12),
                  Text(
                    'المخزون: ${result.previousFinishedQuantity} → ${result.nextFinishedQuantity} وحدة',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                  const Gap(16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.amber.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Checkbox(
                              value: updateCost,
                              onChanged: (v) =>
                                  setStateDialog(() => updateCost = v ?? false),
                            ),
                            Expanded(
                              child: Text(
                                'تحديث سعر تكلفة المنتج النهائي؟',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.amber.shade800,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          'السعر الحالي: ${result.previousCostPrice?.toStringAsFixed(2) ?? 'غير محدد'} ج.م → الجديد: ${result.unitCost.toStringAsFixed(2)} ج.م',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.amber.shade800,
                          ),
                        ),
                        const Gap(4),
                        Text(
                          'اختياري ويحتاج تأكيدك. لن يتم التحديث بدون موافقتك.',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.amber.shade700,
                          ),
                        ),
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
                      final product = await widget.db.productDao.getProductById(
                        result.finishedProductId,
                      );
                      if (product != null) {
                        await widget.db.productDao.updateProduct(
                          product.copyWith(costPrice: Value(result.unitCost)),
                        );
                        if (mounted)
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('تم تحديث سعر التكلفة'),
                            ),
                          );
                      }
                    } catch (e) {
                      if (mounted)
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('فشل تحديث التكلفة: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
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

  Future<void> _showForOthersCompletionSuccess(
    ForOthersCompletionResult result,
  ) async {
    await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green),
            Gap(8),
            Text('تم إكمال أمر التشغيل للغير'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'أمر ${result.orderNumber} • المنتج: ${result.finishedProductName}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const Gap(12),
              _costRow('الكمية المنتجة:', '${result.producedQuantity} وحدة'),
              const Divider(),
              const Text(
                'خامات العميل المستهلكة من العهدة:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const Gap(4),
              for (final cons in result.customerConsumptions)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    '• ${cons.productName}: ${cons.quantity} ${cons.unit ?? ''}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              if (result.factoryConsumptions.isNotEmpty) ...[
                const Gap(8),
                const Text(
                  'خامات المصنع المستهلكة:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const Gap(4),
                for (final f in result.factoryConsumptions)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      '• ${f.productName}: ${f.required} ${f.unit ?? ''}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
              ],
              const Gap(12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'تم خصم المواد من عهدة العميل ولم تتم إضافة المنتج النهائي لمخزون المصنع لأن البضاعة ملك للعميل وتنتظر إصدار إذن التسليم.',
                  style: TextStyle(fontSize: 11, color: Colors.blueAccent),
                ),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('حسناً'),
          ),
        ],
      ),
    );
  }

  Future<void> _openDeliveryDialog() async {
    final order = _order;
    if (order == null) return;
    final alreadyDelivered = await widget.db.manufacturingDeliveryDao
        .getTotalDeliveredQuantity(order.id);
    if (!mounted) return;
    final remaining = order.producedQuantity - alreadyDelivered;
    if (remaining <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم تسليم كامل الكمية المنتجة بالفعل'),
            backgroundColor: Colors.orange,
          ),
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
          title: Text(
            'إذن تسليم منتجات تامة للعميل — أمر ${order.orderNumber}',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('المنتج: ${_finishedProduct?.name ?? ''}'),
                const Gap(4),
                Text(
                  'المنتج كلياً: ${order.producedQuantity} | المسلم سابقاً: $alreadyDelivered | المتبقي للتسليم: $remaining',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Colors.indigo,
                  ),
                ),
                const Gap(16),
                TextField(
                  controller: qtyCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText:
                        'الكمية المراد تسليمها (الحد الأقصى: $remaining) *',
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
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      dlgError!,
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isSubmitting ? null : () => Navigator.pop(dlgCtx),
              child: const Text('إلغاء'),
            ),
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
                        setDlg(
                          () => dlgError =
                              'الكمية المطلوبة تتجاوز المتاح للتسليم ($remaining)',
                        );
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
                          deliveredBy: deliveredByCtrl.text.trim().isEmpty
                              ? null
                              : deliveredByCtrl.text.trim(),
                          receiverName: receiverCtrl.text.trim().isEmpty
                              ? null
                              : receiverCtrl.text.trim(),
                          notes: notesCtrl.text.trim().isEmpty
                              ? null
                              : notesCtrl.text.trim(),
                        );
                        if (dlgCtx.mounted) Navigator.pop(dlgCtx);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('تم تسجيل إذن التسليم بنجاح'),
                              backgroundColor: Colors.green,
                            ),
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
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
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
    final deliveredQty = await widget.db.manufacturingDeliveryDao
        .getTotalDeliveredQuantity(order.id);
    if (!mounted) return;
    if (deliveredQty <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('لا يمكن إصدار فاتورة قبل تسليم أي كمية للعميل'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('إصدار فاتورة خدمات التشغيل للغير'),
        content: Text(
          'سيتم إنشاء فاتورة خدمات للعميل ${_customer?.name ?? ''} عن الكمية المسلمة ($deliveredQty وحدة) وترحيلها مباشرة إلى كشف حساب العميل ورصيد المديونية.\n\nهل تريد المتابعة؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('إصدار الفاتورة'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final inv = await widget.db.manufacturingDeliveryDao
          .generateServiceInvoice(order.id);
      if (mounted) {
        await showDialog(
          context: context,
          builder: (c) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                Gap(8),
                Text('تم إصدار الفاتورة'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'رقم الفاتورة: ${inv.invoiceNumber}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const Gap(8),
                Text('الإجمالي: ${inv.totalAmount.toStringAsFixed(2)} ج.م'),
                const Gap(8),
                const Text(
                  'تم ترحيل الفاتورة إلى سجل حساب العميل بنجاح.',
                  style: TextStyle(color: Colors.green),
                ),
              ],
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('حسناً'),
              ),
            ],
          ),
        );
        _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل إصدار الفاتورة: $e'),
            backgroundColor: Colors.red,
          ),
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
                    Icon(
                      Icons.local_shipping,
                      color: theme.colorScheme.primary,
                    ),
                    const Gap(8),
                    Text(
                      'أذونات تسليم المنتج للعميل (${_deliveries.length})',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                if (_order!.status == ManufacturingOrderStatus.completed &&
                    undelivered > 0)
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
                child: Text(
                  'لم يتم تسجيل أي أذونات تسليم بعد',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
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
                    leading: const CircleAvatar(
                      child: Icon(Icons.inventory, size: 18),
                    ),
                    title: Text(
                      'إذن تسليم: ${d.deliveryNumber}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      'التاريخ: ${DateFormat('yyyy/MM/dd HH:mm').format(d.deliveryDate)} | المستلم: ${d.receiverName ?? '—'} | المندوب: ${d.deliveredBy ?? '—'}',
                    ),
                    trailing: Chip(
                      label: Text(
                        d.status == 'delivered' ? 'تم التسليم' : d.status,
                      ),
                      backgroundColor: Colors.green.withValues(alpha: 0.12),
                      labelStyle: const TextStyle(
                        color: Colors.green,
                        fontSize: 12,
                      ),
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
    // FEAT-009: prefer the order-scoped balances; only when the order has
    // not moved anything yet show the full customer custody list
    final linkedBalances = _customerBalances
        .where((b) => _orderBalanceIds.contains(b.productId))
        .toList();
    final scoped = linkedBalances.isNotEmpty;

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
                Text(
                  'بطاقة مطابقة الخامات والتشغيل (Reconciliation)',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Wrap(
              spacing: 20,
              runSpacing: 12,
              children: [
                _stat(
                  context,
                  'العميل صاحب العهدة',
                  _customer?.name ?? '—',
                  Icons.person,
                ),
                _stat(
                  context,
                  'الكمية المنتجة',
                  '${mo.producedQuantity} وحدة',
                  Icons.check_circle_outline,
                ),
                _stat(
                  context,
                  'المسلم للعميل',
                  '$_deliveredQty وحدة',
                  Icons.local_shipping_outlined,
                ),
                _stat(
                  context,
                  'المتبقي للتسليم',
                  '${mo.producedQuantity - _deliveredQty} وحدة',
                  Icons.hourglass_bottom,
                ),
                _stat(
                  context,
                  'المستهلك من العهدة',
                  '$totalConsumed وحدة',
                  Icons.remove_circle_outline,
                ),
                _stat(
                  context,
                  'رصيد العهدة بالمخزن',
                  '$totalOnHand وحدة',
                  Icons.warehouse_outlined,
                ),
              ],
            ),
            if (_customerBalances.isNotEmpty) ...[
              const Gap(16),
              Text(
                scoped
                    ? 'أرصدة عهدة العميل المرتبطة بهذا الأمر:'
                    : 'أرصدة عهدة العميل الحالية بالمخزن — دي كامل عهدته، لسه مفيش حركة عهدة على الأمر ده:',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const Gap(8),
              Table(
                border: TableBorder.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                columnWidths: const {
                  0: FlexColumnWidth(3),
                  1: FlexColumnWidth(2),
                  2: FlexColumnWidth(2),
                  3: FlexColumnWidth(2),
                },
                children: [
                  TableRow(
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                    ),
                    children: const [
                      Padding(
                        padding: EdgeInsets.all(6),
                        child: Text(
                          'الصنف',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.all(6),
                        child: Text(
                          'الرصيد المتاح',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.all(6),
                        child: Text(
                          'المحجوز',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.all(6),
                        child: Text(
                          'اللون / المقاس',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  for (final b in (scoped ? linkedBalances : _customerBalances))
                    TableRow(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(6),
                          child: Text(
                            _balanceProductNames[b.productId] ??
                                '#${b.productId}',
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(6),
                          child: Text(
                            '${b.quantityOnHand}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(6),
                          child: Text('${b.quantityAllocated}'),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(6),
                          child: Text(
                            '${b.color ?? ''} ${b.size ?? ''}'.trim().isEmpty
                                ? '—'
                                : '${b.color ?? ''} ${b.size ?? ''}'.trim(),
                          ),
                        ),
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

  Widget _costRow(
    String label,
    String value, {
    bool isBold = false,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: color,
              fontSize: 13,
            ),
          ),
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
      return Scaffold(
        appBar: AppBar(title: const Text('تفاصيل أمر التصنيع')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null || _order == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('تفاصيل أمر التصنيع')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: theme.colorScheme.error,
              ),
              const Gap(16),
              Text(
                _error ?? 'خطأ غير معروف',
                style: theme.textTheme.titleMedium,
              ),
              const Gap(16),
              ElevatedButton(
                onPressed: _loadData,
                child: const Text('إعادة المحاولة'),
              ),
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
    final unitCost = mo.plannedQuantity > 0
        ? totalCost / mo.plannedQuantity
        : 0;

    return Scaffold(
      appBar: AppBar(
        title: Text('أمر ${mo.orderNumber}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.summarize),
            tooltip: 'تقرير مراحل وتكاليف الأمر PDF',
            onPressed: _printManufacturingReport,
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: 'بطاقة الإنتاج/الصرف PDF',
            onPressed: _printProductionCard,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'تحديث',
          ),
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.precision_manufacturing,
                            color: color,
                            size: 32,
                          ),
                        ),
                        const Gap(16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                mo.orderNumber,
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const Gap(4),
                              Text(
                                '${product?.name ?? '#${mo.finishedProductId}'} • وصفة: ${bom?.name ?? '#${mo.bomId}'}',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: color),
                          ),
                          child: Text(
                            _statusLabel(mo.status),
                            style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 32),
                    Wrap(
                      spacing: 24,
                      runSpacing: 16,
                      children: [
                        _stat(
                          context,
                          'الكمية المخططة',
                          '${mo.plannedQuantity} وحدة',
                          Icons.numbers,
                        ),
                        _stat(
                          context,
                          'الكمية المنتجة',
                          '${mo.producedQuantity} وحدة',
                          Icons.inventory,
                        ),
                        _stat(
                          context,
                          'العائد للوصفة',
                          '${bom?.yieldQuantity ?? '-'} وحدة',
                          Icons.scale,
                        ),
                        _stat(
                          context,
                          'تاريخ مخطط',
                          mo.plannedDate != null
                              ? DateFormat('yyyy/MM/dd').format(mo.plannedDate!)
                              : '—',
                          Icons.calendar_today,
                        ),
                        _stat(
                          context,
                          'تكلفة مادية تقديرية',
                          '${totalCost.toStringAsFixed(2)} ج.م',
                          Icons.attach_money,
                        ),
                        _stat(
                          context,
                          'تكلفة الوحدة',
                          '${unitCost.toStringAsFixed(2)} ج.م',
                          Icons.calculate,
                        ),
                        if (mo.orderType != 'internal') ...[
                          _stat(
                            context,
                            'نوع التشغيل',
                            mo.orderType == 'for_others'
                                ? 'تشغيل للغير'
                                : 'تشغيل مشترك',
                            Icons.category,
                          ),
                          _stat(
                            context,
                            'العميل',
                            _customer?.name ?? '—',
                            Icons.person,
                          ),
                          _stat(
                            context,
                            'حالة التسليم',
                            _deliveryStatusLabel(mo.deliveryStatus),
                            Icons.local_shipping,
                          ),
                          _stat(
                            context,
                            'أجر التشغيل للوحدة',
                            '${mo.serviceUnitPrice ?? 0} ج.م',
                            Icons.attach_money,
                          ),
                          _stat(
                            context,
                            'سياسة الهالك',
                            _scrapPolicyLabel(mo.scrapPolicy),
                            Icons.policy,
                          ),
                        ],
                        if (mo.cancelReason != null)
                          _stat(
                            context,
                            'سبب الإلغاء',
                            mo.cancelReason!,
                            Icons.cancel_outlined,
                          ),
                      ],
                    ),
                    if (mo.notes != null && mo.notes!.isNotEmpty) ...[
                      const Gap(16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.amber.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Text(
                          'ملاحظات: ${mo.notes!}',
                          style: TextStyle(color: Colors.amber.shade800),
                        ),
                      ),
                    ],
                    const Gap(16),
                    // Actions
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (mo.status == ManufacturingOrderStatus.planned)
                          FilledButton.icon(
                            onPressed: _startOrder,
                            icon: const Icon(Icons.play_arrow),
                            label: const Text('بدء التنفيذ'),
                          ),
                        if (mo.status == ManufacturingOrderStatus.planned ||
                            mo.status == ManufacturingOrderStatus.inProgress)
                          FilledButton.icon(
                            onPressed: _completeOrder,
                            icon: const Icon(Icons.check_circle),
                            label: const Text('إكمال التصنيع'),
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.green,
                            ),
                          ),
                        if (mo.status == ManufacturingOrderStatus.completed &&
                            mo.orderType != 'internal') ...[
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
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.teal,
                              ),
                            )
                          else
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.teal.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.teal),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.check_circle,
                                    size: 16,
                                    color: Colors.teal,
                                  ),
                                  const Gap(6),
                                  Text(
                                    'فاتورة مسجلة #${mo.invoiceId}',
                                    style: const TextStyle(
                                      color: Colors.teal,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                        if (mo.status == ManufacturingOrderStatus.planned ||
                            mo.status == ManufacturingOrderStatus.inProgress)
                          OutlinedButton.icon(
                            onPressed: _cancelOrder,
                            icon: const Icon(Icons.cancel, color: Colors.red),
                            label: const Text(
                              'إلغاء الأمر',
                              style: TextStyle(color: Colors.red),
                            ),
                          ),
                        if (mo.status == ManufacturingOrderStatus.cancelled)
                          OutlinedButton.icon(
                            onPressed: _reopenOrder,
                            icon: const Icon(Icons.replay),
                            label: const Text('إعادة فتح'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const Gap(24),
            // Stages and Routing section
            _buildStagesSection(),
            const Gap(24),
            // Cost components editor (read-only after completion)
            CostComponentEditor(
              db: widget.db,
              orderId: mo.id,
              orderStatus: mo.status,
              onChanged: () => setState(() {}),
            ),
            const Gap(24),
            // Scrap — meaningful during production (in_progress) for raw materials,
            // or once completed for final reconciliation.
            if (mo.status == ManufacturingOrderStatus.completed ||
                mo.status == ManufacturingOrderStatus.inProgress) ...[
              Text(
                'الهالك',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
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
                        stream: widget.db.manufacturingScrapDao.watchForOrder(
                          mo.id,
                        ),
                        builder: (context, snap) {
                          final rows =
                              snap.data ?? const <ManufacturingScrap>[];
                          if (rows.isEmpty) {
                            return Text(
                              'لا يوجد هالك مسجّل على هذا الأمر',
                              style: TextStyle(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                                fontSize: 12,
                              ),
                            );
                          }
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final r in rows)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 2,
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        flex: 3,
                                        child: Text(
                                          r.productId == mo.finishedProductId
                                              ? 'منتج نهائي'
                                              : 'خام #${r.productId}',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: Text(
                                          '${r.quantity} — ${ManufacturingScrapReason.label(r.reason)}',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 3,
                                        child: Text(
                                          r.responsibleParty,
                                          style: const TextStyle(fontSize: 12),
                                        ),
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
            Text(
              'مكونات الوصفة المطلوبة (للكمية المخططة)',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const Gap(12),
            if (_bomItems.isEmpty)
              Card(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    'لا توجد مكونات لهذه الوصفة',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: Row(
                        children: const [
                          Expanded(
                            flex: 3,
                            child: Text(
                              'المادة الخام',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              'المطلوب',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              'المتاح',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              'الحالة',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    ..._bomItems.map((entry) {
                      final (item, product) = entry;
                      final bomYield = bom?.yieldQuantity ?? 1;
                      final factor = bomYield > 0
                          ? mo.plannedQuantity / bomYield
                          : mo.plannedQuantity;
                      final waste =
                          item.wastePercentageOverride ??
                          bom?.wastePercentage ??
                          0;
                      final required =
                          item.quantityRequired * factor * (1 + waste / 100);
                      final requiredInt = required.round(); // Option A rounding
                      final available = product.quantity;
                      final short = requiredInt > available;
                      final statusColor = short ? Colors.red : Colors.green;
                      final statusText = short
                          ? 'ناقص ${requiredInt - available}'
                          : 'متوفر';
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    product.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                  Text(
                                    '${item.quantityRequired} ${item.unit ?? product.unit ?? ''} × ${factor.toStringAsFixed(2)} + هدر $waste%',
                                    style: TextStyle(
                                      color: theme.colorScheme.onSurfaceVariant,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                '$requiredInt ${product.unit ?? ''}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text('$available ${product.unit ?? ''}'),
                            ),
                            Expanded(
                              flex: 2,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  statusText,
                                  style: TextStyle(
                                    color: statusColor,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
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

  Widget _stat(
    BuildContext context,
    String label,
    String value,
    IconData icon,
  ) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const Gap(8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            Text(
              value,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
