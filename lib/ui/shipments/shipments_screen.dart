import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/tables/supplier_table.dart';
import 'package:pos_offline_desktop/core/database/tables/vegetable_shipments_table.dart';
import 'package:pos_offline_desktop/core/services/shipment_allocation_service.dart';
import 'package:pos_offline_desktop/core/services/vegetable_excel_export_service.dart';
import 'package:pos_offline_desktop/core/utils/arabic_name_normalizer.dart';
import 'package:pos_offline_desktop/ui/shipments/widgets/shipment_detail_screen.dart';
import 'package:pos_offline_desktop/ui/shipments/widgets/shipment_form_dialog.dart';

class ShipmentsScreen extends StatefulWidget {
  final AppDatabase db;

  const ShipmentsScreen({super.key, required this.db});

  @override
  State<ShipmentsScreen> createState() => _ShipmentsScreenState();
}

class _ShipmentsScreenState extends State<ShipmentsScreen> {
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  String _statusFilter = 'all'; // all | open | closed
  Map<String, Supplier> _supplierMap = {};
  bool _loadingSuppliers = true;

  @override
  void initState() {
    super.initState();
    _loadSuppliers();
  }

  Future<void> _loadSuppliers() async {
    try {
      final suppliers = await widget.db.supplierDao.getAllSuppliers();
      if (!mounted) return;
      setState(() {
        _supplierMap = {for (var s in suppliers) s.id: s};
        _loadingSuppliers = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingSuppliers = false);
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String _getPricingModeLabel(VegetableShipment s) {
    switch (s.pricingMode) {
      case ShipmentPricingMode.perUnit:
        return 'بالسعر';
      case ShipmentPricingMode.lumpSum:
        return 'جملة';
      case ShipmentPricingMode.commission:
        final pct = s.commissionPercentage?.toStringAsFixed(1) ?? '0';
        return 'عمولة $pct%';
      default:
        return s.pricingMode;
    }
  }

  Color _getPricingModeColor(String mode) {
    switch (mode) {
      case ShipmentPricingMode.perUnit:
        return Colors.blue;
      case ShipmentPricingMode.lumpSum:
        return Colors.purple;
      case ShipmentPricingMode.commission:
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('إدارة الشحنات وطلبيات الخضار'),
          actions: [
            IconButton(
              icon: const Icon(Icons.table_view_outlined),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                try {
                  final p = await VegetableExcelExportService(widget.db)
                      .exportAndShareWorkbook();
                  if (!mounted) return;
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('تم تصدير ملف الإكسل: $p'),
                      backgroundColor: Colors.green,
                    ),
                  );
                } catch (e) {
                  if (!mounted) return;
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('فشل التصدير: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              tooltip: 'تصدير إكسل شامل',
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadSuppliers,
              tooltip: 'تحديث',
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () async {
            final res = await showDialog<bool>(
              context: context,
              builder: (_) => ShipmentFormDialog(db: widget.db),
            );
            if (res == true) {
              _loadSuppliers();
            }
          },
          icon: const Icon(Icons.add),
          label: const Text('استلام شحنة جديدة'),
        ),
        body: Column(
          children: [
            // Search & Filter header bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                children: [
                  TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'بحث برقم الشحنة أو اسم المورد...',
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
                    onChanged: (val) =>
                        setState(() => _searchQuery = val.trim()),
                  ),
                  const Gap(10),
                  Row(
                    children: [
                      ChoiceChip(
                        label: const Text('الكل'),
                        selected: _statusFilter == 'all',
                        onSelected: (_) =>
                            setState(() => _statusFilter = 'all'),
                      ),
                      const Gap(8),
                      ChoiceChip(
                        label: const Text('مفتوحة'),
                        selected: _statusFilter == 'open',
                        onSelected: (_) =>
                            setState(() => _statusFilter = 'open'),
                      ),
                      const Gap(8),
                      ChoiceChip(
                        label: const Text('مقفولة'),
                        selected: _statusFilter == 'closed',
                        onSelected: (_) =>
                            setState(() => _statusFilter = 'closed'),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Main list content driven by watchAll stream
            Expanded(
              child: StreamBuilder<List<VegetableShipment>>(
                stream: widget.db.vegetableShipmentDao.watchAll(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child:
                          Text('حدث خطأ في تحميل الشحنات: ${snapshot.error}'),
                    );
                  }

                  if (!snapshot.hasData || _loadingSuppliers) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  var shipments = snapshot.data!.toList()
                    ..sort((a, b) => b.date.compareTo(a.date));

                  if (_statusFilter == 'open') {
                    shipments = shipments
                        .where(
                            (s) => s.status == VegetableShipmentStatus.open)
                        .toList();
                  } else if (_statusFilter == 'closed') {
                    shipments = shipments
                        .where(
                            (s) => s.status == VegetableShipmentStatus.closed)
                        .toList();
                  }

                  if (_searchQuery.isNotEmpty) {
                    shipments = shipments.where((s) {
                      final supplier = _supplierMap[s.supplierId];
                      final supplierName = supplier?.name ?? '';
                      return ArabicNameNormalizer.matchesQuery(
                            candidate: supplierName,
                            query: _searchQuery,
                            candidatePhone: supplier?.phone,
                          ) ||
                          ArabicNameNormalizer.matchesQuery(
                            candidate: s.shipmentNumber,
                            query: _searchQuery,
                          );
                    }).toList();
                  }

                  if (shipments.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.inventory_2_outlined,
                              size: 64, color: Colors.grey.shade400),
                          const Gap(16),
                          Text(
                            _searchQuery.isEmpty
                                ? 'لا توجد شحنات في هذا التبويب'
                                : 'لا توجد نتائج مطابقة للبحث',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(color: Colors.grey.shade600),
                          ),
                          const Gap(16),
                          if (_searchQuery.isEmpty && _statusFilter == 'all')
                            ElevatedButton.icon(
                              onPressed: () async {
                                final res = await showDialog<bool>(
                                  context: context,
                                  builder: (_) =>
                                      ShipmentFormDialog(db: widget.db),
                                );
                                if (res == true) _loadSuppliers();
                              },
                              icon: const Icon(Icons.add),
                              label: const Text('إضافة أول شحنة'),
                            ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    itemCount: shipments.length,
                    itemBuilder: (context, index) {
                      final s = shipments[index];
                      final supplier = _supplierMap[s.supplierId];
                      final supplierLabel =
                          s.supplierId == DefaultSupplier.unknownId
                              ? DefaultSupplier.unknownName
                              : (supplier?.name ?? 'مورد غير محدد');
                      final isClosed =
                          s.status == VegetableShipmentStatus.closed;
                      final effectiveRemaining =
                          ShipmentAllocationService.effectiveRemaining(s);

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 2,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ShipmentDetailScreen(
                                  db: widget.db,
                                  shipmentId: s.id,
                                ),
                              ),
                            );
                            _loadSuppliers();
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      backgroundColor: isClosed
                                          ? Colors.grey.shade200
                                          : theme.colorScheme.primaryContainer,
                                      child: Icon(
                                        isClosed
                                            ? Icons.lock_outline
                                            : Icons.local_shipping,
                                        color: isClosed
                                            ? Colors.grey.shade700
                                            : theme.colorScheme.primary,
                                      ),
                                    ),
                                    const Gap(10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  'شحنة #${s.shipmentNumber}',
                                                  style: theme
                                                      .textTheme.titleMedium
                                                      ?.copyWith(
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                              const Gap(8),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 2,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: isClosed
                                                      ? Colors.grey.shade200
                                                      : Colors.green.shade50,
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                ),
                                                child: Text(
                                                  isClosed ? 'مقفولة' : 'مفتوحة',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.bold,
                                                    color: isClosed
                                                        ? Colors.grey.shade800
                                                        : Colors.green.shade800,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          Text(
                                            'المورد: $supplierLabel | ${DateFormat("yyyy/MM/dd").format(s.date)}',
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                              color:
                                                  s.supplierId ==
                                                          DefaultSupplier
                                                              .unknownId
                                                      ? Colors.orange.shade800
                                                      : Colors.grey.shade700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    // Pricing badge
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color:
                                            _getPricingModeColor(s.pricingMode)
                                                .withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: _getPricingModeColor(
                                              s.pricingMode),
                                        ),
                                      ),
                                      child: Text(
                                        _getPricingModeLabel(s),
                                        style: TextStyle(
                                          color: _getPricingModeColor(
                                              s.pricingMode),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 11.5,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const Divider(height: 18),
                                Wrap(
                                  spacing: 10,
                                  runSpacing: 6,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(
                                      'المستلم: ${s.totalBarnikaCount} | المباع: ${s.barnikaSoldCount}',
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                    if (s.toppingCount > 0)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.amber.shade50,
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          'تكميل: ${s.toppingCount}',
                                          style: TextStyle(
                                            color: Colors.amber.shade900,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: effectiveRemaining > 0
                                            ? Colors.green.shade50
                                            : Colors.grey.shade100,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        'متبقي: $effectiveRemaining',
                                        style: TextStyle(
                                          color: effectiveRemaining > 0
                                              ? Colors.green.shade800
                                              : Colors.grey.shade700,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
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
      ),
    );
  }
}
