import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_orders_table.dart';
import 'package:pos_offline_desktop/ui/manufacturing/widgets/mo_form_dialog.dart';
import 'package:pos_offline_desktop/ui/manufacturing/mo_detail_screen.dart';

class MoListScreen extends StatefulWidget {
  final AppDatabase db;
  const MoListScreen({super.key, required this.db});

  @override
  State<MoListScreen> createState() => _MoListScreenState();
}

class _MoListScreenState extends State<MoListScreen> {
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  String _statusFilter = 'all';
  Map<int, Product> _productMap = {};
  Map<int, BillOfMaterial> _bomMap = {};
  bool _loadingMeta = true;

  @override
  void initState() {
    super.initState();
    _loadMeta();
  }

  Future<void> _loadMeta() async {
    try {
      final products = await widget.db.productDao.getAllProducts();
      final boms = await widget.db.bomDao.getAllBoms();
      setState(() {
        _productMap = {for (var p in products) p.id: p};
        _bomMap = {for (var b in boms) b.id: b};
        _loadingMeta = false;
      });
    } catch (_) {
      setState(() => _loadingMeta = false);
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

  Future<void> _openForm({ManufacturingOrder? mo}) async {
    final res = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => MoFormDialog(db: widget.db, order: mo),
    );
    if (res == true && mounted) {
      _loadMeta();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(mo == null ? 'تم إنشاء أمر التصنيع' : 'تم تحديث الأمر'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _cancelOrder(ManufacturingOrder mo) async {
    String? reason;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('إلغاء الأمر ${mo.orderNumber}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('هل أنت متأكد من إلغاء أمر التصنيع؟'),
            const Gap(12),
            TextField(
              decoration: const InputDecoration(
                labelText: 'سبب الإلغاء (اختياري)',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => reason = v,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('تراجع')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('إلغاء الأمر'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await widget.db.manufacturingOrderDao.cancelOrder(mo.id, reason: reason);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إلغاء الأمر')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _startOrder(ManufacturingOrder mo) async {
    try {
      await widget.db.manufacturingOrderDao.startOrder(mo.id);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم بدء التنفيذ'), backgroundColor: Colors.green));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('أوامر التصنيع'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadMeta, tooltip: 'تحديث'),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('أمر جديد'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'بحث برقم الأمر أو المنتج...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
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
                    onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()),
                  ),
                ),
                const Gap(12),
                DropdownButton<String>(
                  value: _statusFilter,
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('الكل')),
                    DropdownMenuItem(value: 'planned', child: Text('مخطط')),
                    DropdownMenuItem(value: 'in_progress', child: Text('قيد التنفيذ')),
                    DropdownMenuItem(value: 'completed', child: Text('مكتمل')),
                    DropdownMenuItem(value: 'cancelled', child: Text('ملغي')),
                  ],
                  onChanged: (v) => setState(() => _statusFilter = v ?? 'all'),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<List<ManufacturingOrder>>(
              stream: widget.db.manufacturingOrderDao.watchAll(),
              builder: (context, snapshot) {
                if (snapshot.hasError) return Center(child: Text('خطأ: ${snapshot.error}'));
                if (!snapshot.hasData || _loadingMeta) return const Center(child: CircularProgressIndicator());
                var orders = snapshot.data!;
                if (_statusFilter != 'all') {
                  orders = orders.where((o) => o.status == _statusFilter).toList();
                }
                if (_searchQuery.isNotEmpty) {
                  orders = orders.where((o) {
                    final product = _productMap[o.finishedProductId];
                    final bom = _bomMap[o.bomId];
                    final hay = '${o.orderNumber} ${product?.name ?? ''} ${bom?.name ?? ''}'.toLowerCase();
                    return hay.contains(_searchQuery);
                  }).toList();
                }
                if (orders.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.precision_manufacturing_outlined, size: 64, color: Colors.grey.shade400),
                        const Gap(16),
                        Text(
                          _searchQuery.isEmpty && _statusFilter == 'all' ? 'لا توجد أوامر تصنيع بعد' : 'لا توجد نتائج مطابقة',
                          style: theme.textTheme.titleMedium?.copyWith(color: Colors.grey.shade600),
                        ),
                        const Gap(16),
                        if (_searchQuery.isEmpty && _statusFilter == 'all')
                          ElevatedButton.icon(
                            onPressed: () => _openForm(),
                            icon: const Icon(Icons.add),
                            label: const Text('إنشاء أول أمر'),
                          ),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: orders.length,
                  itemBuilder: (context, index) {
                    final mo = orders[index];
                    final product = _productMap[mo.finishedProductId];
                    final bom = _bomMap[mo.bomId];
                    final color = _statusColor(mo.status);
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 2,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => MoDetailScreen(db: widget.db, orderId: mo.id)),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: color.withValues(alpha: 0.15),
                                    child: Icon(Icons.factory, color: color),
                                  ),
                                  const Gap(12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(mo.orderNumber,
                                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                                        Text(
                                          '${product?.name ?? '#${mo.finishedProductId}'} • ${bom?.name ?? 'وصفة #${mo.bomId}'}',
                                          style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade700),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: color.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: color),
                                    ),
                                    child: Text(_statusLabel(mo.status),
                                        style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
                                  ),
                                ],
                              ),
                              const Divider(height: 20),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('مخطط: ${mo.plannedQuantity} وحدة',
                                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
                                  Text(
                                    'تاريخ: ${mo.plannedDate != null ? DateFormat('yyyy/MM/dd').format(mo.plannedDate!) : DateFormat('yyyy/MM/dd').format(mo.createdAt)}',
                                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
                                  ),
                                ],
                              ),
                              const Gap(8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  if (mo.status == ManufacturingOrderStatus.planned) ...[
                                    TextButton.icon(
                                      onPressed: () => _startOrder(mo),
                                      icon: const Icon(Icons.play_arrow, size: 18),
                                      label: const Text('بدء'),
                                    ),
                                    TextButton.icon(
                                      onPressed: () => _cancelOrder(mo),
                                      icon: const Icon(Icons.cancel, size: 18, color: Colors.red),
                                      label: const Text('إلغاء', style: TextStyle(color: Colors.red)),
                                    ),
                                  ],
                                  if (mo.status == ManufacturingOrderStatus.inProgress)
                                    TextButton.icon(
                                      onPressed: () => _cancelOrder(mo),
                                      icon: const Icon(Icons.cancel, size: 18, color: Colors.red),
                                      label: const Text('إلغاء', style: TextStyle(color: Colors.red)),
                                    ),
                                  TextButton.icon(
                                    onPressed: () => Navigator.of(context).push(
                                      MaterialPageRoute(builder: (_) => MoDetailScreen(db: widget.db, orderId: mo.id)),
                                    ),
                                    icon: const Icon(Icons.visibility, size: 18),
                                    label: const Text('تفاصيل'),
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
