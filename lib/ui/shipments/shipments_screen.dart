import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/tables/vegetable_shipments_table.dart';
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
      setState(() {
        _supplierMap = {for (var s in suppliers) s.id: s};
        _loadingSuppliers = false;
      });
    } catch (e) {
      setState(() => _loadingSuppliers = false);
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String _getPricingModeLabel(String mode) {
    switch (mode) {
      case ShipmentPricingMode.perUnit:
        return 'بالسعر';
      case ShipmentPricingMode.lumpSum:
        return 'جملة';
      case ShipmentPricingMode.commission:
        return 'عمولة';
      default:
        return mode;
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('إدارة الشحنات وطلبيات الخضار'),
        actions: [
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
        label: const Text('إضافة شحنة جديدة'),
      ),
      body: Column(
        children: [
          // Search & Filter header bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
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
                    onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
                  ),
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
                    child: Text('حدث خطأ في تحميل الشحنات: ${snapshot.error}'),
                  );
                }

                if (!snapshot.hasData || _loadingSuppliers) {
                  return const Center(child: CircularProgressIndicator());
                }

                var shipments = snapshot.data!;
                if (_searchQuery.isNotEmpty) {
                  shipments = shipments.where((s) {
                    final supplier = _supplierMap[s.supplierId];
                    final supplierName = supplier?.name.toLowerCase() ?? '';
                    final number = s.shipmentNumber.toLowerCase();
                    return number.contains(_searchQuery) || supplierName.contains(_searchQuery);
                  }).toList();
                }

                if (shipments.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey.shade400),
                        const Gap(16),
                        Text(
                          _searchQuery.isEmpty ? 'لا توجد شحنات مسجلة بعد' : 'لا توجد نتائج مطابقة للبحث',
                          style: theme.textTheme.titleMedium?.copyWith(color: Colors.grey.shade600),
                        ),
                        const Gap(16),
                        if (_searchQuery.isEmpty)
                          ElevatedButton.icon(
                            onPressed: () async {
                              final res = await showDialog<bool>(
                                context: context,
                                builder: (_) => ShipmentFormDialog(db: widget.db),
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
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: shipments.length,
                  itemBuilder: (context, index) {
                    final s = shipments[index];
                    final supplier = _supplierMap[s.supplierId];

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 2,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => ShipmentDetailScreen(
                                db: widget.db,
                                shipmentId: s.id,
                              ),
                            ),
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
                                    backgroundColor: theme.colorScheme.primaryContainer,
                                    child: Icon(
                                      Icons.local_shipping,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                  const Gap(12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'شحنة #${s.shipmentNumber}',
                                          style: theme.textTheme.titleMedium?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        Text(
                                          'المورد: ${supplier?.name ?? "غير معروف"} | ${DateFormat("yyyy/MM/dd").format(s.date)}',
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            color: Colors.grey.shade700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Pricing badge
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: _getPricingModeColor(s.pricingMode).withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: _getPricingModeColor(s.pricingMode),
                                      ),
                                    ),
                                    child: Text(
                                      _getPricingModeLabel(s.pricingMode),
                                      style: TextStyle(
                                        color: _getPricingModeColor(s.pricingMode),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const Divider(height: 20),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.inventory, size: 18, color: Colors.grey.shade600),
                                      const Gap(6),
                                      Text(
                                        'البرانيك: ',
                                        style: theme.textTheme.bodyMedium,
                                      ),
                                      Text(
                                        '${s.barnikaSoldCount} / ${s.totalBarnikaCount}',
                                        style: const TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                      const Gap(8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: s.barnikaRemainingCount > 0
                                              ? Colors.green.shade50
                                              : Colors.red.shade50,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          'متبقي: ${s.barnikaRemainingCount}',
                                          style: TextStyle(
                                            color: s.barnikaRemainingCount > 0
                                                ? Colors.green.shade800
                                                : Colors.red.shade800,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  Text(
                                    'التكلفة: ${s.totalCost.toStringAsFixed(2)} ج.م',
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: theme.colorScheme.primary,
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
