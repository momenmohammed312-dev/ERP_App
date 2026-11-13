import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:printing/printing.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_scrap_table.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_stages_table.dart';
import 'package:pos_offline_desktop/core/services/unified_print_service.dart' as ups;

/// Manufacturing reports screen with 4 tabs:
/// 1. MO cost breakdown & pricing
/// 2. Stages & variants breakdown
/// 3. Material consumption
/// 4. Scrap report (sellable vs defective)
class ManufacturingReportsScreen extends StatefulWidget {
  final AppDatabase db;
  const ManufacturingReportsScreen({super.key, required this.db});

  @override
  State<ManufacturingReportsScreen> createState() => _ManufacturingReportsScreenState();
}

class _ManufacturingReportsScreenState extends State<ManufacturingReportsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  DateTimeRange? _range;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _range = DateTimeRange(
      start: DateTime.now().subtract(const Duration(days: 30)),
      end: DateTime.now(),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _range,
    );
    if (picked != null) setState(() => _range = picked);
  }

  Future<void> _printReportPdf() async {
    final start = _range?.start ?? DateTime.now().subtract(const Duration(days: 30));
    final end = (_range?.end ?? DateTime.now()).add(const Duration(days: 1));
    final orders = await widget.db.manufacturingOrderDao.getAll();
    final inRangeOrders = orders.where((o) => o.createdAt.isAfter(start.subtract(const Duration(days: 1))) && o.createdAt.isBefore(end)).toList();
    final scraps = await widget.db.manufacturingScrapDao.getScrapsInRange(start: start, end: end);
    final products = await widget.db.productDao.getAllProducts();
    final pMap = {for (var p in products) p.id: p};

    final stagesData = <Map<String, dynamic>>[];
    for (final o in inRangeOrders) {
      final stages = await widget.db.manufacturingStageDao.getStagesForOrder(o.id);
      for (final s in stages) {
        final outputs = await widget.db.manufacturingStageDao.getOutputsForStage(s.id);
        stagesData.add({
          'stageName': '${o.orderNumber}: ${s.stageName}',
          'status': s.status,
          'inputQuantity': s.inputQuantity,
          'outputQuantity': s.outputQuantity,
          'scrapQuantity': s.scrapQuantity,
          'sellableScrapQuantity': 0.0,
          'outputs': outputs.map((out) => {
            'variantName': out.variantName ?? 'قياسي',
            'quantityProduced': out.producedQuantity,
            'quantityScrapped': out.scrapQuantity,
            'sellableScrapQuantity': 0.0,
          }).toList(),
        });
      }
    }

    final scrapRows = scraps.map((s) => {
      'date': DateFormat('yyyy/MM/dd').format(s.createdAt),
      'productName': pMap[s.productId]?.name ?? '#${s.productId}',
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
        data: {
          'orderNumber': 'تقرير عام (${DateFormat('yyyy/MM/dd').format(start)} إلى ${DateFormat('yyyy/MM/dd').format(end)})',
          'status': 'تقرير شامل',
          'orderType': 'جميع الأوامر',
          'customerName': 'جميع العملاء',
          'bomName': 'جميع الوصفات',
          'finishedProductName': 'أصناف متعددة',
          'currentStage': '—',
          'createdDate': DateFormat('yyyy/MM/dd').format(DateTime.now()),
          'plannedQuantity': inRangeOrders.fold<double>(0, (acc, o) => acc + o.plannedQuantity),
          'producedQuantity': inRangeOrders.fold<double>(0, (acc, o) => acc + o.producedQuantity),
          'deliveredQuantity': 0.0,
        },
        additionalData: {
          'stages': stagesData,
          'scraps': scrapRows,
        },
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
                          'تقرير التصنيع الشامل PDF',
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
                    pdfFileName: 'manufacturing_report.pdf',
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
          SnackBar(content: Text('فشل إنشاء تقرير PDF: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('تقارير ومؤشرات التصنيع'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.receipt_long), text: 'تكلفة الأوامر والتسعير'),
            Tab(icon: Icon(Icons.layers_outlined), text: 'المراحل والمقاسات'),
            Tab(icon: Icon(Icons.inventory), text: 'استهلاك الخامات'),
            Tab(icon: Icon(Icons.delete_sweep_outlined), text: 'الهالك والتوالف'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            onPressed: _printReportPdf,
            tooltip: 'تصدير / طباعة التقرير PDF',
          ),
          IconButton(
            icon: const Icon(Icons.date_range),
            onPressed: _pickRange,
            tooltip: 'تحديد الفترة',
          ),
        ],
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
                  OutlinedButton.icon(
                    onPressed: () => context.push('/manufacturing/receipts'),
                    icon: const Icon(Icons.inventory_2_outlined, size: 18),
                    label: const Text('خامات العملاء'),
                  ),
                  const Gap(8),
                  FilledButton.tonalIcon(
                    onPressed: () {},
                    icon: const Icon(Icons.analytics_outlined, size: 18),
                    label: const Text('تقارير التصنيع'),
                  ),
                ],
              ),
            ),
          ),
          if (_range != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today, size: 16),
                  const Gap(8),
                  Text('الفترة: ${DateFormat('yyyy/MM/dd').format(_range!.start)} → ${DateFormat('yyyy/MM/dd').format(_range!.end)}'),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _pickRange,
                    icon: const Icon(Icons.edit_calendar, size: 16),
                    label: const Text('تغيير الفترة'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _MoCostBreakdownTab(db: widget.db, range: _range),
                _StagesAndVariantsTab(db: widget.db, range: _range),
                _MaterialConsumptionTab(db: widget.db, range: _range),
                _ScrapReportTab(db: widget.db, range: _range),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MoCostBreakdownTab extends StatelessWidget {
  final AppDatabase db;
  final DateTimeRange? range;
  const _MoCostBreakdownTab({required this.db, required this.range});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ManufacturingOrder>>(
      future: db.manufacturingOrderDao.getAll(),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        var orders = snap.data!;
        if (range != null) {
          orders = orders.where((o) => o.createdAt.isAfter(range!.start.subtract(const Duration(days: 1))) && o.createdAt.isBefore(range!.end.add(const Duration(days: 1)))).toList();
        }
        final completed = orders.where((o) => o.status == 'completed').toList();
        return FutureBuilder<List<BillOfMaterial>>(
          future: db.bomDao.getAllBoms(),
          builder: (context, bomSnap) {
            final bomMap = {for (var b in (bomSnap.data ?? <BillOfMaterial>[])) b.id: b};
            return FutureBuilder<List<Product>>(
              future: db.productDao.getAllProducts(),
              builder: (context, prodSnap) {
                final prodMap = {for (var p in (prodSnap.data ?? <Product>[])) p.id: p};
                if (completed.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.receipt_long_outlined, size: 48, color: Colors.grey.shade400),
                        const Gap(12),
                        Text('لا توجد أوامر مكتملة في هذه الفترة', style: TextStyle(color: Colors.grey.shade600)),
                      ],
                    ),
                  );
                }
                return FutureBuilder<List<List<ManufacturingCostComponent>>>(
                  future: Future.wait(completed.map((o) => db.manufacturingCostComponentDao.getForOrder(o.id))),
                  builder: (context, compSnap) {
                    if (!compSnap.hasData) return const Center(child: CircularProgressIndicator());
                    final compsPerOrder = compSnap.data!;
                    double totalComponents = 0;
                    final rows = <DataRow>[];
                    for (var i = 0; i < completed.length; i++) {
                      final mo = completed[i];
                      final comps = compsPerOrder[i];
                      final compSum = comps.fold<double>(0, (s, c) => s + (c.computedAmount ?? c.value));
                      totalComponents += compSum;
                      final bom = bomMap[mo.bomId];
                      final product = prodMap[mo.finishedProductId];
                      rows.add(DataRow(cells: [
                        DataCell(Text(mo.orderNumber, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                        DataCell(Text(product?.name ?? '#${mo.finishedProductId}', style: const TextStyle(fontSize: 12))),
                        DataCell(Text(bom?.name ?? '-', style: const TextStyle(fontSize: 12))),
                        DataCell(Text('${mo.producedQuantity}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green))),
                        DataCell(Text(mo.pricingMode ?? 'شامل', style: const TextStyle(fontSize: 12))),
                        DataCell(Text(mo.targetMarginPercent != null ? '${mo.targetMarginPercent}%' : '—', style: const TextStyle(fontSize: 12))),
                        DataCell(Text('${compSum.toStringAsFixed(2)} ج.م', style: const TextStyle(fontSize: 12))),
                      ]));
                    }
                    return Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              _summaryCard('أوامر مكتملة', '${completed.length}', Colors.green, Icons.check_circle),
                              const Gap(12),
                              _summaryCard('إجمالي تكاليف إضافية', '${totalComponents.toStringAsFixed(2)} ج.م', Colors.purple, Icons.category),
                              const Gap(12),
                              _summaryCard('متوسط تكلفة الأمر', completed.isNotEmpty ? '${(totalComponents / completed.length).toStringAsFixed(2)} ج.م' : '0', Colors.blue, Icons.calculate),
                            ],
                          ),
                        ),
                        Expanded(
                          child: SingleChildScrollView(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: DataTable(
                                columns: const [
                                  DataColumn(label: Text('رقم الأمر')),
                                  DataColumn(label: Text('المنتج')),
                                  DataColumn(label: Text('الوصفة')),
                                  DataColumn(label: Text('الكمية')),
                                  DataColumn(label: Text('نظام التسعير')),
                                  DataColumn(label: Text('هامش الربح %')),
                                  DataColumn(label: Text('تكاليف إضافية')),
                                ],
                                rows: rows,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _summaryCard(String title, String value, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withValues(alpha: 0.3))),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const Gap(6),
            Text(title, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            const Gap(4),
            Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }
}

class _StagesAndVariantsTab extends StatelessWidget {
  final AppDatabase db;
  final DateTimeRange? range;
  const _StagesAndVariantsTab({required this.db, required this.range});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ManufacturingOrder>>(
      future: db.manufacturingOrderDao.getAll(),
      builder: (context, moSnap) {
        if (!moSnap.hasData) return const Center(child: CircularProgressIndicator());
        var orders = moSnap.data!;
        if (range != null) {
          orders = orders.where((o) => o.createdAt.isAfter(range!.start.subtract(const Duration(days: 1))) && o.createdAt.isBefore(range!.end.add(const Duration(days: 1)))).toList();
        }
        if (orders.isEmpty) {
          return const Center(child: Text('لا توجد أوامر في هذه الفترة'));
        }

        return FutureBuilder<List<List<ManufacturingStage>>>(
          future: Future.wait(orders.map((o) => db.manufacturingStageDao.getStagesForOrder(o.id))),
          builder: (context, stagesSnap) {
            if (!stagesSnap.hasData) return const Center(child: CircularProgressIndicator());
            final allStages = stagesSnap.data!.expand((l) => l).toList();

            return FutureBuilder<List<Product>>(
              future: db.productDao.getAllProducts(),
              builder: (context, prodSnap) {
                final pMap = {for (var p in prodSnap.data ?? <Product>[]) p.id: p};
                final oMap = {for (var o in orders) o.id: o};

                double totalInput = 0;
                double totalOutput = 0;
                double totalScrap = 0;
                for (final s in allStages) {
                  totalInput += s.inputQuantity;
                  totalOutput += s.outputQuantity;
                  totalScrap += s.scrapQuantity;
                }

                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          _summaryCard('إجمالي المراحل', '${allStages.length}', Colors.blue, Icons.layers),
                          const Gap(12),
                          _summaryCard('إجمالي المدخلات', '$totalInput', Colors.orange, Icons.input),
                          const Gap(12),
                          _summaryCard('المنجز السليم', '$totalOutput', Colors.green, Icons.check_circle_outline),
                          const Gap(12),
                          _summaryCard('الهالك بالمراحل', '$totalScrap', Colors.red, Icons.delete_outline),
                        ],
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            columns: const [
                              DataColumn(label: Text('رقم الأمر')),
                              DataColumn(label: Text('المنتج')),
                              DataColumn(label: Text('المرحلة')),
                              DataColumn(label: Text('الحالة')),
                              DataColumn(label: Text('المدخلات')),
                              DataColumn(label: Text('المنجز السليم')),
                              DataColumn(label: Text('الهالك')),
                              DataColumn(label: Text('تكلفة المرحلة')),
                            ],
                            rows: allStages.map((s) {
                              final o = oMap[s.manufacturingOrderId];
                              final p = o != null ? pMap[o.finishedProductId] : null;
                              final isCompleted = s.status == ManufacturingStageStatus.completed;
                              return DataRow(cells: [
                                DataCell(Text(o?.orderNumber ?? '#${s.manufacturingOrderId}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                                DataCell(Text(p?.name ?? '-', style: const TextStyle(fontSize: 12))),
                                DataCell(Text('${s.stageOrder}. ${s.stageName}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                                DataCell(Chip(
                                  label: Text(isCompleted ? 'مكتملة' : 'جارية', style: TextStyle(fontSize: 11, color: isCompleted ? Colors.green : Colors.orange)),
                                  backgroundColor: (isCompleted ? Colors.green : Colors.orange).withValues(alpha: 0.1),
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                )),
                                DataCell(Text('${s.inputQuantity}', style: const TextStyle(fontSize: 12))),
                                DataCell(Text('${s.outputQuantity}', style: const TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.bold))),
                                DataCell(Text('${s.scrapQuantity}', style: const TextStyle(fontSize: 12, color: Colors.red))),
                                DataCell(Text('${s.stageCost.toStringAsFixed(2)} ج.م', style: const TextStyle(fontSize: 12))),
                              ]);
                            }).toList(),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _summaryCard(String title, String value, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withValues(alpha: 0.3))),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const Gap(6),
            Text(title, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            const Gap(4),
            Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }
}

class _MaterialConsumptionTab extends StatelessWidget {
  final AppDatabase db;
  final DateTimeRange? range;
  const _MaterialConsumptionTab({required this.db, required this.range});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<InventoryMovement>>(
      future: db.inventoryMovementDao.getMovementsByType('manufacturing_consumption'),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        var movements = snap.data!;
        if (range != null) {
          movements = movements.where((m) => m.movementDate.isAfter(range!.start.subtract(const Duration(days: 1))) && m.movementDate.isBefore(range!.end.add(const Duration(days: 1)))).toList();
        }
        if (movements.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.inventory_outlined, size: 48, color: Colors.grey.shade400),
                const Gap(12),
                Text('لا يوجد استهلاك خامات في هذه الفترة', style: TextStyle(color: Colors.grey.shade600)),
              ],
            ),
          );
        }
        return FutureBuilder<List<Product>>(
          future: db.productDao.getAllProducts(),
          builder: (context, prodSnap) {
            final prodMap = {for (var p in (prodSnap.data ?? <Product>[])) p.id: p};
            final Map<int, List<InventoryMovement>> grouped = {};
            for (final m in movements) {
              grouped.putIfAbsent(m.productId, () => []).add(m);
            }
            final rows = <DataRow>[];
            double totalQty = 0;
            double totalVal = 0;
            for (final entry in grouped.entries) {
              final product = prodMap[entry.key];
              final qty = entry.value.fold<int>(0, (s, m) => s + m.quantity.abs());
              final val = entry.value.fold<double>(0, (s, m) => s + m.totalValue.abs());
              totalQty += qty;
              totalVal += val;
              rows.add(DataRow(cells: [
                DataCell(Text(product?.name ?? '#${entry.key}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                DataCell(Text(product?.unit ?? '-', style: const TextStyle(fontSize: 12))),
                DataCell(Text('$qty', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                DataCell(Text('${val.toStringAsFixed(2)} ج.م', style: const TextStyle(fontSize: 12))),
                DataCell(Text('${entry.value.length}', style: const TextStyle(fontSize: 12))),
              ]));
            }
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      _summaryCard2('إجمالي الكمية المستهلكة', totalQty.toStringAsFixed(0), Colors.orange, Icons.arrow_downward),
                      const Gap(12),
                      _summaryCard2('إجمالي القيمة', '${totalVal.toStringAsFixed(2)} ج.م', Colors.red, Icons.attach_money),
                      const Gap(12),
                      _summaryCard2('عدد الحركات', '${movements.length}', Colors.blue, Icons.receipt),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('المادة الخام')),
                          DataColumn(label: Text('الوحدة')),
                          DataColumn(label: Text('الكمية')),
                          DataColumn(label: Text('القيمة')),
                          DataColumn(label: Text('مرات الاستهلاك')),
                        ],
                        rows: rows,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _summaryCard2(String title, String value, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withValues(alpha: 0.3))),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const Gap(6),
            Text(title, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            const Gap(4),
            Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }
}

class _ScrapReportTab extends StatelessWidget {
  final AppDatabase db;
  final DateTimeRange? range;
  const _ScrapReportTab({required this.db, required this.range});

  @override
  Widget build(BuildContext context) {
    final start = range?.start ?? DateTime.now().subtract(const Duration(days: 30));
    final end = (range?.end ?? DateTime.now()).add(const Duration(days: 1));

    return FutureBuilder<List<ManufacturingScrap>>(
      future: db.manufacturingScrapDao.getScrapsInRange(start: start, end: end),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final scraps = snap.data ?? [];
        if (scraps.isEmpty) {
          return const Center(
            child: Text(
              'لا يوجد هالك مسجّل خلال الفترة المحددة',
              style: TextStyle(color: Colors.grey),
            ),
          );
        }

        return FutureBuilder<List<Product>>(
          future: db.productDao.getAllProducts(),
          builder: (context, prodSnap) {
            final prodMap = <int, Product>{
              for (final p in prodSnap.data ?? <Product>[]) p.id: p,
            };

            double totalQty = 0;
            double totalComp = 0;
            double totalSellableQty = 0;
            for (final s in scraps) {
              totalQty += s.quantity;
              totalComp += s.compensationAmount ?? 0.0;
              if (s.isSellable == true) totalSellableQty += s.quantity;
            }

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      _summaryCard('عدد العمليات', '${scraps.length}', Colors.blue, Icons.receipt),
                      const Gap(12),
                      _summaryCard('إجمالي الهالك', totalQty.toStringAsFixed(1), Colors.red, Icons.delete_outline),
                      const Gap(12),
                      _summaryCard('هالك قابل للبيع (فرز ثاني)', totalSellableQty.toStringAsFixed(1), Colors.teal, Icons.recycling),
                      const Gap(12),
                      _summaryCard('إجمالي التعويضات', '${totalComp.toStringAsFixed(2)} ج.م', Colors.orange, Icons.money_off),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('التاريخ')),
                          DataColumn(label: Text('أمر التصنيع')),
                          DataColumn(label: Text('الصنف / المقاس')),
                          DataColumn(label: Text('نوع الهالك')),
                          DataColumn(label: Text('الكمية')),
                          DataColumn(label: Text('سعر البيع المقترح')),
                          DataColumn(label: Text('سبب الهالك')),
                          DataColumn(label: Text('المتسبب')),
                          DataColumn(label: Text('المسؤول')),
                          DataColumn(label: Text('إجراء التعويض')),
                          DataColumn(label: Text('مبلغ التعويض')),
                        ],
                        rows: scraps.map((s) {
                          final prod = prodMap[s.productId];
                          final prodName = s.variantName != null ? '${prod?.name ?? s.productId} (${s.variantName})' : (prod?.name ?? '#${s.productId}');
                          final unit = prod?.unit ?? '';
                          final reasonLabel = ManufacturingScrapReason.label(s.reason);
                          final faultLabel = s.faultParty == 'factory'
                              ? 'المصنع'
                              : (s.faultParty == 'customer' ? 'العميل' : '—');
                          final actionLabel = s.compensationAction == 'deducted_from_invoice'
                              ? 'خصم من الفاتورة'
                              : (s.compensationAction == 'replaced'
                                  ? 'صرف قطعة بديلة'
                                  : (s.compensationAction == 'labour_waived'
                                      ? 'إسقاط مصنعية'
                                      : 'بدون تعويض'));

                          return DataRow(cells: [
                            DataCell(Text(DateFormat('yyyy/MM/dd HH:mm').format(s.createdAt), style: const TextStyle(fontSize: 12))),
                            DataCell(Text('#${s.manufacturingOrderId}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                            DataCell(Text(prodName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                            DataCell(Chip(
                              label: Text((s.isSellable == true) ? 'فرز ثاني (قابل للبيع)' : 'تالف غير صالح', style: TextStyle(fontSize: 11, color: (s.isSellable == true) ? Colors.teal : Colors.red)),
                              backgroundColor: ((s.isSellable == true) ? Colors.teal : Colors.red).withValues(alpha: 0.1),
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                            )),
                            DataCell(Text('${s.quantity} $unit', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.redAccent))),
                            DataCell(Text((s.isSellable == true) && (s.estimatedSellPrice ?? 0) > 0 ? '${s.estimatedSellPrice!.toStringAsFixed(2)} ج.م' : '—', style: const TextStyle(fontSize: 12, color: Colors.teal))),
                            DataCell(Text(reasonLabel, style: const TextStyle(fontSize: 12))),
                            DataCell(Text(faultLabel, style: const TextStyle(fontSize: 12))),
                            DataCell(Text(s.responsibleParty, style: const TextStyle(fontSize: 12))),
                            DataCell(Text(actionLabel, style: const TextStyle(fontSize: 12))),
                            DataCell(Text((s.compensationAmount ?? 0.0) > 0 ? '${s.compensationAmount!.toStringAsFixed(2)} ج.م' : '—', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                          ]);
                        }).toList(),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _summaryCard(String title, String value, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const Gap(6),
            Text(title, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            const Gap(4),
            Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }
}
