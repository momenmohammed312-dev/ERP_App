import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:printing/printing.dart';
import 'package:pos_offline_desktop/core/services/unified_print_service.dart' as ups;
import 'package:gap/gap.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/dao/customer_material_receipt_dao.dart';
import 'package:pos_offline_desktop/ui/manufacturing/widgets/mo_form_dialog.dart';
import 'package:pos_offline_desktop/ui/manufacturing/widgets/searchable_product_picker.dart';

class CustomerMaterialReceiptListScreen extends StatefulWidget {
  final AppDatabase db;
  const CustomerMaterialReceiptListScreen({super.key, required this.db});

  @override
  State<CustomerMaterialReceiptListScreen> createState() =>
      _CustomerMaterialReceiptListScreenState();
}

class _CustomerMaterialReceiptListScreenState
    extends State<CustomerMaterialReceiptListScreen> {
  Map<String, Customer> _customerMap = {};
  Map<int, Product> _productMap = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  Future<void> _loadCustomers() async {
    try {
      final customers = await widget.db.customerDao
          .getCustomersForManufacturing();
      setState(() {
        _customerMap = {for (var c in customers) c.id: c};
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _openReceiptDialog() async {
    final res = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CustomerMaterialReceiptDialog(db: widget.db),
    );
    if (res == true && mounted) {
      _loadCustomers();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم تسجيل إذن استلام الخامات بنجاح'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  /// Secondary entry to the for-others flow: opens the same manufacturing
  /// order form prefilled with this receipt (receipt → recipe → order).
  Future<void> _printReceipt(CustomerMaterialReceipt r) async {
    final customer = _customerMap[r.customerId];
    final items = await widget.db.customerMaterialReceiptDao.getItemsForReceipt(r.id);
    final products = await widget.db.productDao.getAllProducts();
    final pMap = {for (var p in products) p.id: p};

    final itemsData = items.map((it) {
      final p = pMap[it.productId];
      return {
        'productName': p?.name ?? '#${it.productId}',
        'received': it.quantityReceived,
        'defective': it.quantityDefectiveAtReceipt,
        'accepted': it.quantityAccepted,
        'unit': p?.unit ?? 'وحدة',
        'notes': it.rejectionReason ?? it.notes ?? '',
      };
    }).toList();

    try {
      final pdf = await ups.UnifiedPrintService.generateUnifiedDocument(
        documentType: ups.DocumentType.customerMaterialReceiptCard,
        data: {
          'receiptNumber': r.receiptNumber,
          'date': DateFormat('yyyy/MM/dd HH:mm').format(r.receivedDate),
          'customerName': customer?.name ?? r.customerId,
          'receivedBy': r.receivedBy ?? '—',
          'notes': r.notes ?? '',
        },
        additionalData: {'items': itemsData},
      );

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => Dialog(
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
                          'إذن استلام خامات العميل — ${r.receiptNumber}',
                          style: Theme.of(ctx).textTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx),
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
                    pdfFileName: 'receipt_${r.receiptNumber}.pdf',
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
          SnackBar(content: Text('فشل إنشاء إذن الاستلام PDF: $e')),
        );
      }
    }
  }

  Future<void> _openForOthersOrder(int receiptId) async {
    final res = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => MoFormDialog(db: widget.db, initialReceiptId: receiptId),
    );
    if (res == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم إنشاء أمر التشغيل للغير'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('أذونات استلام خامات العملاء (تشغيل للغير)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() {}),
            tooltip: 'تحديث',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openReceiptDialog,
        icon: const Icon(Icons.add),
        label: const Text('إذن استلام جديد'),
      ),
      body: Column(
        children: [
          // Quick Navigation Strip
          Container(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: () => context.push('/manufacturing/orders'),
                    icon: const Icon(Icons.precision_manufacturing, size: 18),
                    label: const Text('أوامر التصنيع'),
                  ),
                  const Gap(8),
                  OutlinedButton.icon(
                    onPressed: () => context.push('/manufacturing/bom'),
                    icon: const Icon(Icons.playlist_add_check, size: 18),
                    label: const Text('الوصفات (BOM)'),
                  ),
                  const Gap(8),
                  FilledButton.tonalIcon(
                    onPressed: () {},
                    icon: const Icon(Icons.inventory_2_outlined, size: 18),
                    label: const Text('خامات العملاء'),
                  ),
                  const Gap(8),
                  OutlinedButton.icon(
                    onPressed: () => context.push('/manufacturing/reports'),
                    icon: const Icon(Icons.analytics_outlined, size: 18),
                    label: const Text('تقارير التصنيع PDF'),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : StreamBuilder<List<CustomerMaterialReceipt>>(
              stream: widget.db.customerMaterialReceiptDao.watchAllReceipts(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final receipts = snapshot.data ?? [];
                if (receipts.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.inventory_2_outlined,
                          size: 64,
                          color: Colors.grey.shade400,
                        ),
                        const Gap(16),
                        Text(
                          'لا توجد أذونات استلام خامات مسجلة',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const Gap(8),
                        FilledButton.icon(
                          onPressed: _openReceiptDialog,
                          icon: const Icon(Icons.add),
                          label: const Text('تسجيل أول إذن استلام'),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: receipts.length,
                  separatorBuilder: (_, i) => const Gap(12),
                  itemBuilder: (context, index) {
                    final r = receipts[index];
                    final customer = _customerMap[r.customerId];
                    return Card(
                      elevation: 1.5,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: ExpansionTile(
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.teal.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.input, color: Colors.teal),
                        ),
                        title: Text(
                          r.receiptNumber,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          'العميل: ${customer?.name ?? r.customerId} • التاريخ: ${r.receivedDate.toString().substring(0, 16)}',
                        ),
                        children: [
                          FutureBuilder<List<CustomerMaterialReceiptItem>>(
                            future: widget.db.customerMaterialReceiptDao
                                .getItemsForReceipt(r.id),
                            builder: (context, itemSnap) {
                              final items = itemSnap.data ?? [];
                              if (itemSnap.connectionState ==
                                      ConnectionState.waiting &&
                                  items.isEmpty) {
                                return const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Center(
                                    child: CircularProgressIndicator(),
                                  ),
                                );
                              }
                              return Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'الأصناف المستلمة:',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const Gap(8),
                                    Table(
                                      border: TableBorder.all(
                                        color: theme.colorScheme.outlineVariant,
                                      ),
                                      columnWidths: const {
                                        0: FlexColumnWidth(3),
                                        1: FlexColumnWidth(2),
                                        2: FlexColumnWidth(2),
                                        3: FlexColumnWidth(2),
                                        4: FlexColumnWidth(3),
                                      },
                                      children: [
                                        TableRow(
                                          decoration: BoxDecoration(
                                            color: theme
                                                .colorScheme
                                                .surfaceContainerHighest,
                                          ),
                                          children: const [
                                            Padding(
                                              padding: EdgeInsets.all(6),
                                              child: Text(
                                                'المنتج',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                            Padding(
                                              padding: EdgeInsets.all(6),
                                              child: Text(
                                                'المستلم',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                            Padding(
                                              padding: EdgeInsets.all(6),
                                              child: Text(
                                                'معيب/تالف',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                            Padding(
                                              padding: EdgeInsets.all(6),
                                              child: Text(
                                                'المقبول للعهدة',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                            Padding(
                                              padding: EdgeInsets.all(6),
                                              child: Text(
                                                'ملاحظات / سبب الرفض',
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        for (final it in items)
                                          TableRow(
                                            children: [
                                              Padding(
                                                padding: const EdgeInsets.all(
                                                  6,
                                                ),
                                                child: Text(
                                                  _productMap[it.productId]
                                                          ?.name ??
                                                      it.productId.toString(),
                                                ),
                                              ),
                                              Padding(
                                                padding: const EdgeInsets.all(
                                                  6,
                                                ),
                                                child: Text(
                                                  '${it.quantityReceived}',
                                                ),
                                              ),
                                              Padding(
                                                padding: const EdgeInsets.all(
                                                  6,
                                                ),
                                                child: Text(
                                                  '${it.quantityDefectiveAtReceipt}',
                                                  style: TextStyle(
                                                    color:
                                                        it.quantityDefectiveAtReceipt >
                                                            0
                                                        ? Colors.red
                                                        : Colors.black,
                                                  ),
                                                ),
                                              ),
                                              Padding(
                                                padding: const EdgeInsets.all(
                                                  6,
                                                ),
                                                child: Text(
                                                  '${it.quantityAccepted}',
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.green,
                                                  ),
                                                ),
                                              ),
                                              Padding(
                                                padding: const EdgeInsets.all(
                                                  6,
                                                ),
                                                child: Text(
                                                  it.rejectionReason ??
                                                      it.notes ??
                                                      '-',
                                                ),
                                              ),
                                            ],
                                          ),
                                      ],
                                    ),
                                    if (r.notes != null &&
                                        r.notes!.isNotEmpty) ...[
                                      const Gap(8),
                                      Text('ملاحظات الإذن: ${r.notes}'),
                                    ],
                                    const Gap(12),
                                    Row(
                                       children: [
                                         FilledButton.tonalIcon(
                                           onPressed: () => _openForOthersOrder(r.id),
                                           icon: const Icon(Icons.precision_manufacturing),
                                           label: const Text('إنشاء أمر تشغيل للغير'),
                                         ),
                                         const Gap(12),
                                         OutlinedButton.icon(
                                           onPressed: () => _printReceipt(r),
                                           icon: const Icon(Icons.picture_as_pdf),
                                           label: const Text('طباعة إذن الاستلام PDF'),
                                         ),
                                       ],
                                     ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Dialog to record customer material receipt with defective-at-receipt inspection
class CustomerMaterialReceiptDialog extends StatefulWidget {
  final AppDatabase db;
  const CustomerMaterialReceiptDialog({super.key, required this.db});

  @override
  State<CustomerMaterialReceiptDialog> createState() =>
      _CustomerMaterialReceiptDialogState();
}

class _CustomerMaterialReceiptDialogState
    extends State<CustomerMaterialReceiptDialog> {
  final _formKey = GlobalKey<FormState>();
  final _notesCtrl = TextEditingController();
  final _receivedByCtrl = TextEditingController();

  String? _selectedCustomerId;
  List<Customer> _customers = [];
  List<Product> _products = [];
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  final List<_ReceiptItemRow> _itemRows = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final custs = await widget.db.customerDao.getCustomersForManufacturing();
      final prods = await widget.db.productDao.getAllProducts();
      setState(() {
        _customers = custs;
        _products = prods;
        _loading = false;
        if (prods.isNotEmpty) {
          _itemRows.add(_ReceiptItemRow(selectedProductId: prods.first.id));
        }
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'فشل التحميل: $e';
      });
    }
  }

  void _addItemRow() {
    if (_products.isEmpty) return;
    setState(() {
      _itemRows.add(_ReceiptItemRow(selectedProductId: _products.first.id));
    });
  }

  void _removeItemRow(int idx) {
    if (_itemRows.length <= 1) return;
    setState(() {
      _itemRows.removeAt(idx);
    });
  }

  /// FEAT-006: receive material the workshop does not stock. Custody is
  /// keyed by product, so create the product row on the fly: factory
  /// quantity stays 0 and consumption happens only in custody flows.
  Future<void> _createCustodyProduct([_ReceiptItemRow? row]) async {
    final nameCtrl = TextEditingController();
    final unitCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    String? localError;
    final created = await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('إضافة صنف عهدة (غير مخزني)'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'اسم الصنف',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'أدخل اسم الصنف' : null,
                ),
                const Gap(12),
                TextFormField(
                  controller: unitCtrl,
                  decoration: const InputDecoration(
                    labelText: 'الوحدة (اختياري)',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (localError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      localError!,
                      style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                try {
                  final id = await widget.db.productDao.insertProduct(
                    ProductsCompanion.insert(
                      name: nameCtrl.text.trim(),
                      quantity: 0,
                      price: 0,
                      unit: Value(
                        unitCtrl.text.trim().isEmpty
                            ? null
                            : unitCtrl.text.trim(),
                      ),
                      productType: const Value('raw_material'),
                    ),
                  );
                  if (ctx.mounted) Navigator.pop(ctx, id);
                } catch (e) {
                  setDialogState(() => localError = 'فشل الحفظ: $e');
                }
              },
              child: const Text('إضافة'),
            ),
          ],
        ),
      ),
    );
    if (created == null || !mounted) return;
    final prods = await widget.db.productDao.getAllProducts();
    if (!mounted) return;
    setState(() {
      _products = prods;
      if (row == null) {
        _itemRows.add(_ReceiptItemRow(selectedProductId: created));
      } else {
        row.selectedProductId = created;
      }
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCustomerId == null) {
      setState(() => _error = 'اختر العميل المورد للخامات');
      return;
    }
    if (_itemRows.isEmpty) {
      setState(() => _error = 'أضف صنفاً واحداً على الأقل');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    // BUG-006 guard: validate the product id explicitly (the form
    // validator already blocks it; this keeps the money path safe).
    for (final r in _itemRows) {
      if (r.selectedProductId == null) {
        setState(
          () => _error =
              '\u0627\u062E\u062A\u0631 \u0627\u0644\u0645\u0646\u062A\u062C / \u0627\u0644\u062E\u0627\u0645\u0629 \u0641\u064A \u0643\u0644 \u0633\u0637\u0631',
        );
        return;
      }
    }

    try {
      final inputs = _itemRows.map((r) {
        final rec = double.tryParse(r.qtyReceivedCtrl.text.trim()) ?? 0.0;
        final def = double.tryParse(r.qtyDefectiveCtrl.text.trim()) ?? 0.0;
        return ReceiptItemInput(
          productId: r.selectedProductId!,
          quantityReceived: rec,
          quantityDefectiveAtReceipt: def,
          rejectionReason: r.reasonCtrl.text.trim().isEmpty
              ? null
              : r.reasonCtrl.text.trim(),
          notes: r.notesCtrl.text.trim().isEmpty
              ? null
              : r.notesCtrl.text.trim(),
        );
      }).toList();

      await widget.db.customerMaterialReceiptDao.receiveCustomerMaterial(
        customerId: _selectedCustomerId!,
        items: inputs,
        receivedBy: _receivedByCtrl.text.trim().isEmpty
            ? null
            : _receivedByCtrl.text.trim(),
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      );

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _submitting = false;
        _error = 'خطأ: $e';
      });
    }
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    _receivedByCtrl.dispose();
    for (final r in _itemRows) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800, maxHeight: 750),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : Form(
                  key: _formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.input, color: Colors.teal),
                            const Gap(8),
                            Text(
                              'إذن استلام خامات من العميل (عهدة تشغيل للغير)',
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 24),
                        if (_error != null) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.errorContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _error!,
                              style: TextStyle(
                                color: theme.colorScheme.onErrorContainer,
                              ),
                            ),
                          ),
                          const Gap(16),
                        ],
                        DropdownButtonFormField<String>(
                          initialValue: _selectedCustomerId,
                          decoration: const InputDecoration(
                            labelText: 'العميل المورد للخامات *',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.person),
                          ),
                          items: _customers
                              .map(
                                (c) => DropdownMenuItem(
                                  value: c.id,
                                  child: Text('${c.name} (${c.id})'),
                                ),
                              )
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _selectedCustomerId = v),
                          validator: (v) => v == null ? 'اختر العميل' : null,
                        ),
                        const Gap(16),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _receivedByCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'المستلم / الفاحص',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.badge),
                                ),
                              ),
                            ),
                            const Gap(16),
                            Expanded(
                              child: TextFormField(
                                controller: _notesCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'ملاحظات الإذن',
                                  border: OutlineInputBorder(),
                                  prefixIcon: Icon(Icons.notes),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Gap(24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: const Text(
                                'الأصناف وفحص الاستلام (المعيب لا يدخل العهدة)',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            TextButton.icon(
                              key: const Key('fe006-add-custody-product'),
                              onPressed: () => _createCustodyProduct(
                                _itemRows.isEmpty ||
                                        _itemRows.first.selectedProductId !=
                                            null
                                    ? null
                                    : _itemRows.first,
                              ),
                              icon: const Icon(Icons.new_label),
                              label: const Text(
                                '\u0625\u0636\u0627\u0641\u0629 \u0635\u0646\u0641 \u0639\u0647\u062F\u0629',
                              ),
                            ),
                            const Gap(8),
                            FilledButton.tonalIcon(
                              onPressed: _addItemRow,
                              icon: const Icon(Icons.add),
                              label: const Text('إضافة صنف'),
                            ),
                          ],
                        ),
                        const Gap(12),
                        for (int i = 0; i < _itemRows.length; i++) ...[
                          _buildItemRowWidget(i),
                          const Gap(8),
                        ],
                        const Gap(24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: _submitting
                                  ? null
                                  : () => Navigator.pop(context),
                              child: const Text('إلغاء'),
                            ),
                            const Gap(12),
                            ElevatedButton.icon(
                              onPressed: _submitting ? null : _submit,
                              icon: _submitting
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.check),
                              label: const Text('تسجيل الاستلام'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildItemRowWidget(int idx) {
    final theme = Theme.of(context);
    final row = _itemRows[idx];
    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: SearchableProductPicker(
                db: widget.db,
                label: 'المنتج / الخامة',
                initialProductId: row.selectedProductId,
                // BUG-006: without a validator the form accepted a row with
                // no product and the submit path crashed on the null id.
                validator: (v) => v == null
                    ? '\u0627\u062E\u062A\u0631 \u0627\u0644\u0645\u0646\u062A\u062C \u0623\u0648 \u0627\u0644\u062E\u0627\u0645\u0629'
                    : null,
                onChanged: (p) => setState(() => row.selectedProductId = p?.id),
              ),
            ),
            const Gap(8),
            Expanded(
              flex: 2,
              child: TextFormField(
                controller: row.qtyReceivedCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'المستلم كلياً',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                validator: (v) {
                  final n = double.tryParse(v ?? '');
                  if (n == null || n <= 0) return 'أدخل كمية > 0';
                  return null;
                },
              ),
            ),
            const Gap(8),
            Expanded(
              flex: 2,
              child: TextFormField(
                controller: row.qtyDefectiveCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'تالف الفحص',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                validator: (v) {
                  final def = double.tryParse(v ?? '0') ?? 0.0;
                  final rec =
                      double.tryParse(row.qtyReceivedCtrl.text.trim()) ?? 0.0;
                  if (def < 0) return 'قيمة سالبة';
                  if (def > rec) return 'التالف > المستلم';
                  return null;
                },
              ),
            ),
            const Gap(8),
            Expanded(
              flex: 3,
              child: TextFormField(
                controller: row.reasonCtrl,
                decoration: const InputDecoration(
                  labelText: 'سبب الرفض/التلف',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            if (_itemRows.length > 1)
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                onPressed: () => _removeItemRow(idx),
                tooltip: 'حذف السطر',
              ),
          ],
        ),
      ),
    );
  }
}

class _ReceiptItemRow {
  int? selectedProductId;
  final TextEditingController qtyReceivedCtrl = TextEditingController(
    text: '100',
  );
  final TextEditingController qtyDefectiveCtrl = TextEditingController(
    text: '0',
  );
  final TextEditingController reasonCtrl = TextEditingController();
  final TextEditingController notesCtrl = TextEditingController();

  _ReceiptItemRow({this.selectedProductId});

  void dispose() {
    qtyReceivedCtrl.dispose();
    qtyDefectiveCtrl.dispose();
    reasonCtrl.dispose();
    notesCtrl.dispose();
  }
}
