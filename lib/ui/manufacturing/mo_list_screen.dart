import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
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
  Map<String, Customer> _customerMap = {};
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
      final customers =
          await widget.db.customerDao.getCustomersForManufacturing();
      setState(() {
        _productMap = {for (var p in products) p.id: p};
        _bomMap = {for (var b in boms) b.id: b};
        _customerMap = {for (var c in customers) c.id: c};
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
        title: const Text('أوامر التصنيع وإدارة الخطوط'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadMeta, tooltip: 'تحديث البيانات'),
          IconButton(
            icon: const Icon(Icons.list_alt_outlined),
            onPressed: () => context.push('/manufacturing/bom'),
            tooltip: 'الوصفات (BOM)',
          ),
          IconButton(
            icon: const Icon(Icons.inbox_outlined),
            onPressed: () => context.push('/manufacturing/receipts'),
            tooltip: 'خامات العملاء (تشغيل للغير)',
          ),
          IconButton(
            icon: const Icon(Icons.insights_outlined),
            onPressed: () => context.push('/manufacturing/reports'),
            tooltip: 'تقارير التصنيع',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('أمر تصنيع جديد'),
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
                  FilledButton.tonalIcon(
                    onPressed: () {},
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
            child: StreamBuilder<List<ManufacturingOrder>>(
              stream: widget.db.manufacturingOrderDao.watchAll(),
              builder: (context, snapshot) {
                if (snapshot.hasError) return Center(child: Text('خطأ: ${snapshot.error}'));
                if (!snapshot.hasData || _loadingMeta) return const Center(child: CircularProgressIndicator());

                final allOrders = snapshot.data!;
                final totalCount = allOrders.length;
                final inProgressCount = allOrders.where((o) => o.status == ManufacturingOrderStatus.inProgress).length;
                final completedCount = allOrders.where((o) => o.status == ManufacturingOrderStatus.completed).length;
                final forOthersCount = allOrders.where((o) => o.orderType != 'internal').length;

                var orders = allOrders;
                if (_statusFilter != 'all') {
                  orders = orders.where((o) => o.status == _statusFilter).toList();
                }
                if (_searchQuery.isNotEmpty) {
                  orders = orders.where((o) {
                    final product = _productMap[o.finishedProductId];
                    final bom = _bomMap[o.bomId];
                    final customer = o.customerId != null ? _customerMap[o.customerId] : null;
                    final stage = o.currentStageName ?? '';
                    final hay =
                        '${o.orderNumber} ${product?.name ?? ''} ${bom?.name ?? ''} ${customer?.name ?? ''} ${o.customerId ?? ''} ${customer?.phone ?? ''} $stage'
                            .toLowerCase();
                    return hay.contains(_searchQuery);
                  }).toList();
                }

                return CustomScrollView(
                  slivers: [
                    // KPI Cards Strip
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final isWide = constraints.maxWidth > 700;
                            return isWide
                                ? Row(
                                    children: [
                                      Expanded(child: _kpiCard('إجمالي الأوامر', '$totalCount', Icons.assignment, Colors.blue)),
                                      const Gap(12),
                                      Expanded(child: _kpiCard('قيد التنفيذ', '$inProgressCount', Icons.autorenew, Colors.orange)),
                                      const Gap(12),
                                      Expanded(child: _kpiCard('المكتملة', '$completedCount', Icons.check_circle_outline, Colors.green)),
                                      const Gap(12),
                                      Expanded(child: _kpiCard('تشغيل للغير', '$forOthersCount', Icons.people_alt_outlined, Colors.teal)),
                                    ],
                                  )
                                : Column(
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(child: _kpiCard('إجمالي الأوامر', '$totalCount', Icons.assignment, Colors.blue)),
                                          const Gap(8),
                                          Expanded(child: _kpiCard('قيد التنفيذ', '$inProgressCount', Icons.autorenew, Colors.orange)),
                                        ],
                                      ),
                                      const Gap(8),
                                      Row(
                                        children: [
                                          Expanded(child: _kpiCard('المكتملة', '$completedCount', Icons.check_circle_outline, Colors.green)),
                                          const Gap(8),
                                          Expanded(child: _kpiCard('تشغيل للغير', '$forOthersCount', Icons.people_alt_outlined, Colors.teal)),
                                        ],
                                      ),
                                    ],
                                  );
                          },
                        ),
                      ),
                    ),

                    // Search & Status Filters
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Column(
                          children: [
                            TextField(
                              controller: _searchCtrl,
                              decoration: InputDecoration(
                                hintText: 'بحث برقم الأمر أو المنتج أو العميل أو المرحلة...',
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
                            const Gap(10),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  _filterChip('الكل', 'all'),
                                  const Gap(6),
                                  _filterChip('مخطط', ManufacturingOrderStatus.planned),
                                  const Gap(6),
                                  _filterChip('قيد التنفيذ', ManufacturingOrderStatus.inProgress),
                                  const Gap(6),
                                  _filterChip('مكتمل', ManufacturingOrderStatus.completed),
                                  const Gap(6),
                                  _filterChip('ملغي', ManufacturingOrderStatus.cancelled),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Orders List
                    if (orders.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
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
                                  label: const Text('إنشاء أول أمر تصنيع'),
                                ),
                            ],
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final mo = orders[index];
                              final product = _productMap[mo.finishedProductId];
                              final bom = _bomMap[mo.bomId];
                              final customer = mo.customerId != null ? _customerMap[mo.customerId] : null;
                              final color = _statusColor(mo.status);
                              final progress = mo.plannedQuantity > 0 ? (mo.producedQuantity / mo.plannedQuantity).clamp(0.0, 1.0) : 0.0;

                              return Card(
                                margin: const EdgeInsets.only(bottom: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
                                ),
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
                                                  Row(
                                                    children: [
                                                      Text(
                                                        mo.orderNumber,
                                                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                                                      ),
                                                      if (mo.orderType != 'internal') ...[
                                                        const Gap(8),
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                          decoration: BoxDecoration(
                                                            color: Colors.teal.withValues(alpha: 0.15),
                                                            borderRadius: BorderRadius.circular(6),
                                                          ),
                                                          child: Text(
                                                            'تشغيل للغير: ${customer?.name ?? 'عميل'}',
                                                            style: const TextStyle(color: Colors.teal, fontSize: 11, fontWeight: FontWeight.bold),
                                                          ),
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                  const Gap(2),
                                                  Text(
                                                    '${product?.name ?? '#${mo.finishedProductId}'} • وصفة: ${bom?.name ?? '#${mo.bomId}'}',
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
                                              child: Text(
                                                _statusLabel(mo.status),
                                                style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const Divider(height: 20),
                                        // Badges row: Stage, Pricing mode, Dates
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 6,
                                          children: [
                                            if (mo.currentStageName != null && mo.currentStageName!.isNotEmpty)
                                              Chip(
                                                avatar: const Icon(Icons.layers, size: 14),
                                                label: Text('المرحلة: ${mo.currentStageName}', style: const TextStyle(fontSize: 11)),
                                                visualDensity: VisualDensity.compact,
                                                padding: EdgeInsets.zero,
                                              ),
                                            if (mo.pricingMode != null)
                                              Chip(
                                                avatar: const Icon(Icons.request_quote_outlined, size: 14),
                                                label: Text(
                                                  mo.pricingMode == 'actual_cost_plus_margin'
                                                      ? 'تكلفة + ${mo.targetMarginPercent ?? 20}% هامش'
                                                      : (mo.pricingMode == 'inclusive' ? 'مصنعية شاملة' : mo.pricingMode!),
                                                  style: const TextStyle(fontSize: 11),
                                                ),
                                                visualDensity: VisualDensity.compact,
                                                padding: EdgeInsets.zero,
                                              ),
                                            Chip(
                                              avatar: const Icon(Icons.calendar_today, size: 14),
                                              label: Text(
                                                mo.plannedDate != null
                                                    ? 'مخطط: ${DateFormat('yyyy/MM/dd').format(mo.plannedDate!)}'
                                                    : 'تاريخ: ${DateFormat('yyyy/MM/dd').format(mo.createdAt)}',
                                                style: const TextStyle(fontSize: 11),
                                              ),
                                              visualDensity: VisualDensity.compact,
                                              padding: EdgeInsets.zero,
                                            ),
                                          ],
                                        ),
                                        const Gap(12),
                                        // Production Progress Bar
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            Text(
                                              'المنجز: ${mo.producedQuantity} من ${mo.plannedQuantity} وحدة',
                                              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                                            ),
                                            Text(
                                              '${(progress * 100).toStringAsFixed(0)}%',
                                              style: TextStyle(color: color, fontWeight: FontWeight.bold),
                                            ),
                                          ],
                                        ),
                                        const Gap(6),
                                        LinearProgressIndicator(
                                          value: progress,
                                          backgroundColor: Colors.grey.shade200,
                                          color: color,
                                          minHeight: 6,
                                          borderRadius: BorderRadius.circular(4),
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
                                            FilledButton.tonalIcon(
                                              onPressed: () => Navigator.of(context).push(
                                                MaterialPageRoute(builder: (_) => MoDetailScreen(db: widget.db, orderId: mo.id)),
                                              ),
                                              icon: const Icon(Icons.visibility, size: 18),
                                              label: const Text('تفاصيل ومراحل الأمر'),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                            childCount: orders.length,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _kpiCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.15),
              radius: 18,
              child: Icon(icon, color: color, size: 20),
            ),
            const Gap(10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String label, String value) {
    final isSelected = _statusFilter == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (v) {
        if (v) setState(() => _statusFilter = value);
      },
    );
  }
}
