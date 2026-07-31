import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:drift/drift.dart' hide Column;

import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/tables/customer_containers_table.dart';

class CustomerRow {
  final String customerId;
  final String customerName;
  final TextEditingController tookCtrl;
  final TextEditingController returnedCtrl;

  CustomerRow({
    required this.customerId,
    required this.customerName,
    int took = 0,
    int returned = 0,
  })  : tookCtrl = TextEditingController(text: took.toString()),
        returnedCtrl = TextEditingController(text: returned.toString());

  int get took => int.tryParse(tookCtrl.text) ?? 0;
  int get returned => int.tryParse(returnedCtrl.text) ?? 0;
  int get remaining => took - returned;

  void dispose() {
    tookCtrl.dispose();
    returnedCtrl.dispose();
  }
}

class BarnekaTrackingScreen extends StatefulWidget {
  final AppDatabase db;
  final Product product;

  const BarnekaTrackingScreen({
    super.key,
    required this.db,
    required this.product,
  });

  @override
  State<BarnekaTrackingScreen> createState() => _BarnekaTrackingScreenState();
}

class _BarnekaTrackingScreenState extends State<BarnekaTrackingScreen> {
  late DateTimeRange _range;
  List<CustomerRow> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    // Start from beginning of today (midnight) so all today's sales are included
    _range = DateTimeRange(
      start: DateTime(now.year, now.month, now.day),
      end: now,
    );
    _load();
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  // Strip time from start → midnight of start day
  DateTime get _rangeStart =>
      DateTime(_range.start.year, _range.start.month, _range.start.day);

  // End at 23:59:59 of end day to capture all sales that day
  DateTime get _rangeEnd =>
      DateTime(_range.end.year, _range.end.month, _range.end.day, 23, 59, 59);

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _range,
      locale: const Locale('ar'),
    );
    if (picked != null) {
      _range = picked;
      await _load();
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    try {
      final customers = await widget.db.customerDao.getAllActiveCustomers();
      final sales = await widget.db.invoiceDao.getProductSalesByCustomer(
        widget.product.id,
        _rangeStart,
        _rangeEnd,
      );
      final autoSales = {for (final s in sales) s.customerId: s.totalQty};

      final records = await widget.db.customerContainerDao
          .watchByProduct(widget.product.id)
          .first
          .timeout(const Duration(seconds: 3), onTimeout: () => []);
      final recordMap = {for (final r in records) r.customerId: r};

      final rows = <CustomerRow>[];
      final seenIds = <String>{};
      for (final c in customers) {
        final rec = recordMap[c.id];
        final took = rec?.quantityOut ?? autoSales[c.id] ?? 0;
        final returned = rec?.quantityReturned ?? 0;
        rows.add(CustomerRow(
          customerId: c.id,
          customerName: c.name,
          took: took,
          returned: returned,
        ));
        seenIds.add(c.id);
      }

      // Walk-in / cash sales (no customer) are shown under a synthetic "نقدي" row
      if (autoSales.containsKey(kWalkInCustomerId) &&
          !seenIds.contains(kWalkInCustomerId)) {
        final rec = recordMap[kWalkInCustomerId];
        final took = rec?.quantityOut ?? autoSales[kWalkInCustomerId]!;
        final returned = rec?.quantityReturned ?? 0;
        rows.add(CustomerRow(
          customerId: kWalkInCustomerId,
          customerName: kWalkInCustomerName,
          took: took,
          returned: returned,
        ));
      }

      if (mounted) {
        setState(() {
          _rows = rows;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading barneka tracking: $e');
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ أثناء تحميل البيانات: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _autoFill() async {
    final sales = await widget.db.invoiceDao.getProductSalesByCustomer(
      widget.product.id,
      _rangeStart,
      _rangeEnd,
    );
    final autoSales = {for (final s in sales) s.customerId: s.totalQty};

    for (final row in _rows) {
      final q = autoSales[row.customerId] ?? 0;
      row.tookCtrl.text = q.toString();
    }

    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم التعبئة التلقائية من المبيعات'),
          backgroundColor: Colors.teal,
        ),
      );
    }
  }

  Future<void> _save() async {
      for (final row in _rows) {
      await widget.db.customerContainerDao.upsert(
        CustomerContainersCompanion(
          productId: Value(widget.product.id),
          customerId: Value(row.customerId),
          quantityOut: Value(row.took),
          quantityReturned: Value(row.returned),
          date: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
      );
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم الحفظ بنجاح'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  int get _totalTook => _rows.fold(0, (sum, r) => sum + r.took);
  int get _totalReturned => _rows.fold(0, (sum, r) => sum + r.returned);
  int get _totalRemaining => _totalTook - _totalReturned;

  @override
  Widget build(BuildContext context) {
    final rangeText =
        '${DateFormat('yyyy/MM/dd').format(_rangeStart)} — ${DateFormat('yyyy/MM/dd').format(_range.end)}';

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.product.name} — برنيكه'),
        actions: [
          TextButton.icon(
            onPressed: _autoFill,
            icon: const Icon(Icons.auto_fix_high),
            label: const Text('تعبئة تلقائية'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: _pickRange,
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'نطاق التاريخ',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.date_range),
                            ),
                            child: Text(rangeText),
                          ),
                        ),
                      ),
                      const Gap(12),
                      OutlinedButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh),
                        label: const Text('تحديث'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columnSpacing: 24,
                      columns: const [
                        DataColumn(label: Text('العميل')),
                        DataColumn(label: Text('أخذ كم')),
                        DataColumn(label: Text('رجع كم')),
                        DataColumn(label: Text('متبقي')),
                      ],
                      rows: _rows.map((row) {
                        return DataRow(
                          cells: [
                            DataCell(SizedBox(
                              width: 180,
                              child: Text(row.customerName),
                            )),
                            DataCell(
                              SizedBox(
                                width: 90,
                                child: TextField(
                                  controller: row.tookCtrl,
                                  keyboardType: TextInputType.number,
                                  textAlign: TextAlign.center,
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                  ),
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                            ),
                            DataCell(
                              SizedBox(
                                width: 90,
                                child: TextField(
                                  controller: row.returnedCtrl,
                                  keyboardType: TextInputType.number,
                                  textAlign: TextAlign.center,
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                  ),
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                            ),
                            DataCell(
                              SizedBox(
                                width: 80,
                                child: Text(
                                  '${row.remaining}',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: row.remaining < 0
                                        ? Colors.red
                                        : Colors.teal,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 6,
                        offset: Offset(0, -2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      _TotalChip(
                        label: 'إجمالي أخذ',
                        value: _totalTook,
                        color: Colors.blue,
                      ),
                      const Gap(16),
                      _TotalChip(
                        label: 'إجمالي رجع',
                        value: _totalReturned,
                        color: Colors.orange,
                      ),
                      const Gap(16),
                      _TotalChip(
                        label: 'إجمالي متبقي',
                        value: _totalRemaining,
                        color: _totalRemaining < 0 ? Colors.red : Colors.teal,
                      ),
                      const Spacer(),
                      ElevatedButton.icon(
                        onPressed: _save,
                        icon: const Icon(Icons.save),
                        label: const Text('حفظ'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _TotalChip extends StatelessWidget {
  final String label;
  final int value;
  final Color color;

  const _TotalChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const Gap(4),
        Text(
          '$value',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}
