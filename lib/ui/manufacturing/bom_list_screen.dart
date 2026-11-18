import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:printing/printing.dart';
import 'package:pos_offline_desktop/core/services/unified_print_service.dart' as ups;
import 'package:gap/gap.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/ui/manufacturing/widgets/bom_form_dialog.dart';

class BomListScreen extends StatefulWidget {
  final AppDatabase db;
  const BomListScreen({super.key, required this.db});

  @override
  State<BomListScreen> createState() => _BomListScreenState();
}

class _BomListScreenState extends State<BomListScreen> {
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  String _statusFilter = 'all'; // all | Active | Inactive
  Map<int, Product> _productMap = {};
  bool _loadingProducts = true;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    try {
      final products = await widget.db.productDao.getAllProducts();
      setState(() {
        _productMap = {for (var p in products) p.id: p};
        _loadingProducts = false;
      });
    } catch (_) {
      setState(() => _loadingProducts = false);
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _openForm({BillOfMaterial? bom}) async {
    final res = await showDialog<Object?>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BomFormDialog(db: widget.db, bom: bom),
    );
    if (res != null && mounted) {
      _loadProducts();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            bom == null ? 'تم إنشاء الوصفة بنجاح' : 'تم تحديث الوصفة بنجاح',
          ),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _printBom(BillOfMaterial bom) async {
    final product = _productMap[bom.finishedProductId];
    final itemsWithProducts = await widget.db.bomDao.getItemsWithProducts(bom.id);
    final itemsData = itemsWithProducts.map((pair) {
      final item = pair.$1;
      final raw = pair.$2;
      final cost = raw.costPrice ?? raw.price;
      return {
        'productName': raw.name,
        'quantity': item.quantityRequired,
        'unit': raw.unit ?? 'وحدة',
        'waste': item.wastePercentageOverride != null ? '${item.wastePercentageOverride}%' : '—',
        'unitCost': cost.toStringAsFixed(2),
        'lineCost': (item.quantityRequired * cost).toStringAsFixed(2),
      };
    }).toList();

    try {
      final pdf = await ups.UnifiedPrintService.generateUnifiedDocument(
        documentType: ups.DocumentType.bomRecipeCard,
        data: {
          'name': bom.name,
          'productName': product?.name ?? '—',
          'code': bom.code ?? '—',
          'yieldQuantity': bom.yieldQuantity,
          'wastePercentage': bom.wastePercentage,
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
                          'بطاقة وصفة التصنيع — ${bom.name}',
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
                    pdfFileName: 'bom_${bom.name}.pdf',
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
          SnackBar(content: Text('فشل إنشاء بطاقة الوصفة: $e')),
        );
      }
    }
  }

  Future<void> _toggleStatus(BillOfMaterial bom) async {
    await widget.db.bomDao.toggleBomStatus(bom.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            bom.status == 'Active'
                ? 'تم إلغاء تفعيل الوصفة'
                : 'تم تفعيل الوصفة',
          ),
        ),
      );
    }
  }

  Future<void> _deleteBom(BillOfMaterial bom) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('حذف الوصفة'),
        content: Text(
          'هل أنت متأكد من حذف "${bom.name}"؟\nسيتم حذف كل مكوناتها أيضاً.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await widget.db.bomDao.deleteBom(bom.id);
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم حذف الوصفة')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('وصفات التصنيع (BOM)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadProducts,
            tooltip: 'تحديث',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('وصفة جديدة'),
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
                  FilledButton.tonalIcon(
                    onPressed: () {},
                    icon: const Icon(Icons.playlist_add_check, size: 18),
                    label: const Text('الوصفات (BOM)'),
                  ),
                  const Gap(8),
                  OutlinedButton.icon(
                    onPressed: () => context.push('/manufacturing/receipts'),
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
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'بحث بالاسم أو الكود أو المنتج...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                    ),
                    onChanged: (v) =>
                        setState(() => _searchQuery = v.trim().toLowerCase()),
                  ),
                ),
                const Gap(12),
                DropdownButton<String>(
                  value: _statusFilter,
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('الكل')),
                    DropdownMenuItem(value: 'Active', child: Text('مفعلة')),
                    DropdownMenuItem(
                      value: 'Inactive',
                      child: Text('غير مفعلة'),
                    ),
                  ],
                  onChanged: (v) => setState(() => _statusFilter = v ?? 'all'),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<List<BillOfMaterial>>(
              stream: widget.db.bomDao.watchAllBoms(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('خطأ: ${snapshot.error}'));
                }
                if (!snapshot.hasData || _loadingProducts) {
                  return const Center(child: CircularProgressIndicator());
                }
                var boms = snapshot.data!;

                // status filter
                if (_statusFilter != 'all') {
                  boms = boms.where((b) => b.status == _statusFilter).toList();
                }
                // search filter
                if (_searchQuery.isNotEmpty) {
                  boms = boms.where((b) {
                    final product = _productMap[b.finishedProductId];
                    final hay =
                        '${b.name} ${b.code ?? ''} ${product?.name ?? ''}'
                            .toLowerCase();
                    return hay.contains(_searchQuery);
                  }).toList();
                }

                if (boms.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.factory_outlined,
                          size: 64,
                          color: Colors.grey.shade400,
                        ),
                        const Gap(16),
                        Text(
                          _searchQuery.isEmpty && _statusFilter == 'all'
                              ? 'لا توجد وصفات مسجلة بعد'
                              : 'لا توجد نتائج مطابقة',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const Gap(16),
                        if (_searchQuery.isEmpty && _statusFilter == 'all')
                          ElevatedButton.icon(
                            onPressed: () => _openForm(),
                            icon: const Icon(Icons.add),
                            label: const Text('إضافة أول وصفة'),
                          ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  itemCount: boms.length,
                  itemBuilder: (context, index) {
                    final bom = boms[index];
                    final product = _productMap[bom.finishedProductId];
                    final isActive = bom.status == 'Active';
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _openForm(bom: bom),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: isActive
                                        ? Colors.green.withValues(alpha: 0.15)
                                        : Colors.grey.withValues(alpha: 0.15),
                                    child: Icon(
                                      Icons.receipt_long,
                                      color: isActive
                                          ? Colors.green
                                          : Colors.grey,
                                    ),
                                  ),
                                  const Gap(12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          bom.name,
                                          style: theme.textTheme.titleMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.bold,
                                              ),
                                        ),
                                        Text(
                                          'المنتج: ${product?.name ?? '#${bom.finishedProductId}'}'
                                          '${bom.code != null ? ' • ${bom.code}' : ''}',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                color: theme
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isActive
                                          ? Colors.green.withValues(alpha: 0.15)
                                          : Colors.grey.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isActive
                                            ? Colors.green
                                            : Colors.grey,
                                      ),
                                    ),
                                    child: Text(
                                      isActive ? 'مفعلة' : 'غير مفعلة',
                                      style: TextStyle(
                                        color: isActive
                                            ? Colors.green.shade800
                                            : Colors.grey.shade700,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const Divider(height: 20),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'العائد: ${bom.yieldQuantity} وحدة',
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                  Text(
                                    'هدر: ${bom.wastePercentage}%',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: Colors.orange.shade800,
                                    ),
                                  ),
                                ],
                              ),
                              const Gap(8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton.icon(
                                    onPressed: () => _toggleStatus(bom),
                                    icon: Icon(
                                      isActive
                                          ? Icons.pause_circle
                                          : Icons.play_circle,
                                      size: 18,
                                    ),
                                    label: Text(
                                      isActive ? 'إلغاء تفعيل' : 'تفعيل',
                                    ),
                                  ),
                                  TextButton.icon(
                                    onPressed: () => _printBom(bom),
                                    icon: const Icon(Icons.picture_as_pdf, size: 18),
                                    label: const Text('بطاقة الوصفة PDF'),
                                  ),
                                  TextButton.icon(
                                    onPressed: () => _openForm(bom: bom),
                                    icon: const Icon(Icons.edit, size: 18),
                                    label: const Text('تعديل'),
                                  ),
                                  TextButton.icon(
                                    onPressed: () => _deleteBom(bom),
                                    icon: const Icon(
                                      Icons.delete,
                                      size: 18,
                                      color: Colors.red,
                                    ),
                                    label: const Text(
                                      'حذف',
                                      style: TextStyle(color: Colors.red),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
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
