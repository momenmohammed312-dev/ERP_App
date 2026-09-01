import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';

/// Manufacturing reports screen with two tabs: MO cost breakdown + material consumption.
/// Read-only, aggregates over existing tables (no new writes).
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
    _tabController = TabController(length: 2, vsync: this);
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('تقارير التصنيع'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.receipt_long), text: 'تكلفة الأوامر'),
            Tab(icon: Icon(Icons.inventory), text: 'استهلاك الخامات'),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.date_range), onPressed: _pickRange, tooltip: 'الفترة'),
        ],
      ),
      body: Column(
        children: [
          if (_range != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: theme.colorScheme.surfaceContainerHighest,
              child: Row(
                children: [
                  const Icon(Icons.calendar_today, size: 16),
                  const Gap(8),
                  Text('الفترة: ${DateFormat('yyyy/MM/dd').format(_range!.start)} → ${DateFormat('yyyy/MM/dd').format(_range!.end)}'),
                  const Spacer(),
                  TextButton(onPressed: _pickRange, child: const Text('تغيير')),
                ],
              ),
            ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _MoCostBreakdownTab(db: widget.db, range: _range),
                _MaterialConsumptionTab(db: widget.db, range: _range),
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
                // For each completed order, load its cost components to compute totals
                return FutureBuilder<List<List<ManufacturingCostComponent>>>(
                  future: Future.wait(completed.map((o) => db.manufacturingCostComponentDao.getForOrder(o.id))),
                  builder: (context, compSnap) {
                    if (!compSnap.hasData) return const Center(child: CircularProgressIndicator());
                    final compsPerOrder = compSnap.data!;
                    double totalMaterial = 0, totalComponents = 0, totalAll = 0;
                    final rows = <DataRow>[];
                    for (var i = 0; i < completed.length; i++) {
                      final mo = completed[i];
                      final comps = compsPerOrder[i];
                      // We don't store materialCost directly; recompute from InventoryMovements or approximate via stored computedAmount?
                      // For report, materialCost = totalCost - componentsCost where totalCost is derived from computedAmounts + material?
                      // Simpler: show total computed from components + approximate via product cost
                      final compSum = comps.fold<double>(0, (s, c) => s + (c.computedAmount ?? c.value));
                      // Try to get InventoryMovements output for this MO to get totalCost
                      // Fallback: compSum only
                      totalComponents += compSum;
                      // We'll fetch totalCost from MO's output movement lazily via FutureBuilder per row? For now show compSum
                      final bom = bomMap[mo.bomId];
                      final product = prodMap[mo.finishedProductId];
                      rows.add(DataRow(cells: [
                        DataCell(Text(mo.orderNumber, style: const TextStyle(fontSize: 12))),
                        DataCell(Text(product?.name ?? '#${mo.finishedProductId}', style: const TextStyle(fontSize: 12))),
                        DataCell(Text(bom?.name ?? '-', style: const TextStyle(fontSize: 12))),
                        DataCell(Text('${mo.producedQuantity}', style: const TextStyle(fontSize: 12))),
                        DataCell(Text(comps.length.toString(), style: const TextStyle(fontSize: 12))),
                        DataCell(Text('${compSum.toStringAsFixed(2)} ج.م', style: const TextStyle(fontSize: 12))),
                      ]));
                    }
                    totalAll = totalMaterial + totalComponents;
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
                              _summaryCard('متوسط لكل أمر', completed.isNotEmpty ? '${(totalComponents / completed.length).toStringAsFixed(2)} ج.م' : '0', Colors.blue, Icons.calculate),
                            ],
                          ),
                        ),
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              columns: const [
                                DataColumn(label: Text('رقم الأمر')),
                                DataColumn(label: Text('المنتج')),
                                DataColumn(label: Text('الوصفة')),
                                DataColumn(label: Text('الكمية')),
                                DataColumn(label: Text('بنود تكلفة')),
                                DataColumn(label: Text('مجموع إضافي')),
                              ],
                              rows: rows,
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

class _MaterialConsumptionTab extends StatelessWidget {
  final AppDatabase db;
  final DateTimeRange? range;
  const _MaterialConsumptionTab({required this.db, required this.range});

  @override
  Widget build(BuildContext context) {
    // Aggregate InventoryMovements with movementType = manufacturing_consumption
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
            // Group by productId
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
                DataCell(Text(product?.name ?? '#${entry.key}', style: const TextStyle(fontSize: 12))),
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
                      _summaryCard2('إجمالي الكمية المستهلكة', '${totalQty.toStringAsFixed(0)}', Colors.orange, Icons.arrow_downward),
                      const Gap(12),
                      _summaryCard2('إجمالي القيمة', '${totalVal.toStringAsFixed(2)} ج.م', Colors.red, Icons.attach_money),
                      const Gap(12),
                      _summaryCard2('عدد الحركات', '${movements.length}', Colors.blue, Icons.receipt),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('المادة الخام')),
                        DataColumn(label: Text('الوحدة')),
                        DataColumn(label: Text('الكمية')),
                        DataColumn(label: Text('القيمة')),
                        DataColumn(label: Text('مرات')),
                      ],
                      rows: rows,
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
