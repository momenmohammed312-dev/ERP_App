import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/tables/vegetable_shipments_table.dart';
import 'package:pos_offline_desktop/ui/shipments/widgets/shipment_form_dialog.dart';

class ShipmentDetailScreen extends StatefulWidget {
  final AppDatabase db;
  final int shipmentId;

  const ShipmentDetailScreen({
    super.key,
    required this.db,
    required this.shipmentId,
  });

  @override
  State<ShipmentDetailScreen> createState() => _ShipmentDetailScreenState();
}

class _ShipmentDetailScreenState extends State<ShipmentDetailScreen> {
  VegetableShipment? _shipment;
  Supplier? _supplier;
  List<(InvoiceItem, Invoice, Product?)> _linkedItems = [];
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
      final shipment = await widget.db.vegetableShipmentDao.getById(widget.shipmentId);
      if (shipment == null) {
        setState(() {
          _error = 'الشحنة غير موجودة';
          _isLoading = false;
        });
        return;
      }

      final suppliers = await widget.db.supplierDao.getAllSuppliers();
      final supplier = suppliers.firstWhere(
        (s) => s.id == shipment.supplierId,
        orElse: () => Supplier(
          id: shipment.supplierId,
          name: 'مورد غير معروف',
          phone: null,
          address: null,
          openingBalance: 0.0,
          status: 'Active',
          createdAt: DateTime.now(),
        ),
      );

      final items = await widget.db.invoiceDao.getItemsWithDetailsByShipment(shipment.id);

      setState(() {
        _shipment = shipment;
        _supplier = supplier;
        _linkedItems = items;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'حدث خطأ أثناء تحميل البيانات: $e';
        _isLoading = false;
      });
    }
  }

  String _getPricingModeLabel(String mode) {
    switch (mode) {
      case ShipmentPricingMode.perUnit:
        return 'سعر للبرنيكة';
      case ShipmentPricingMode.lumpSum:
        return 'جملة (Lump Sum)';
      case ShipmentPricingMode.commission:
        return 'عمولة (Commission)';
      default:
        return mode;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('تفاصيل الشحنة')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null || _shipment == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('تفاصيل الشحنة')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: theme.colorScheme.error),
              const Gap(16),
              Text(_error ?? 'خطأ غير معروف', style: theme.textTheme.titleMedium),
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

    final s = _shipment!;
    final totalSoldQuantity = _linkedItems.fold<int>(0, (sum, i) => sum + i.$1.quantity);
    final totalSalesRevenue = _linkedItems.fold<double>(0, (sum, i) => sum + (i.$1.price * i.$1.quantity));
    final totalCommissions = _linkedItems.fold<double>(0, (sum, i) => sum + i.$1.commission);

    return Scaffold(
      appBar: AppBar(
        title: Text('تفاصيل الشحنة #${s.shipmentNumber}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'تحديث',
          ),
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: 'تعديل الشحنة',
            onPressed: () async {
              final updated = await showDialog<bool>(
                context: context,
                builder: (_) => ShipmentFormDialog(db: widget.db, shipment: s),
              );
              if (updated == true) {
                _loadData();
              }
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header summary card
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.local_shipping,
                            color: theme.colorScheme.primary,
                            size: 32,
                          ),
                        ),
                        const Gap(16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'شحنة رقم: ${s.shipmentNumber}',
                                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const Gap(4),
                              Text(
                                'المورد: ${_supplier?.name ?? "غير معروف"} | الهاتف: ${_supplier?.phone ?? "غير متوفر"}',
                                style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey.shade700),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: s.barnikaRemainingCount > 0
                                ? Colors.green.shade100
                                : Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: s.barnikaRemainingCount > 0 ? Colors.green : Colors.grey,
                            ),
                          ),
                          child: Text(
                            s.barnikaRemainingCount > 0 ? 'مفتوحة (متبقي)' : 'مكتملة',
                            style: TextStyle(
                              color: s.barnikaRemainingCount > 0
                                  ? Colors.green.shade900
                                  : Colors.grey.shade800,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 32),

                    // Stats grid
                    Wrap(
                      spacing: 24,
                      runSpacing: 16,
                      children: [
                        _buildStatTile(
                          context,
                          label: 'تاريخ الشحنة',
                          value: DateFormat('yyyy/MM/dd HH:mm').format(s.date),
                          icon: Icons.calendar_month,
                        ),
                        _buildStatTile(
                          context,
                          label: 'نظام التسعير',
                          value: _getPricingModeLabel(s.pricingMode),
                          icon: Icons.sell,
                        ),
                        _buildStatTile(
                          context,
                          label: 'البرانيك (مباع / كلي)',
                          value: '${s.barnikaSoldCount} / ${s.totalBarnikaCount}',
                          subtitle: 'المتبقي: ${s.barnikaRemainingCount} برنيكة',
                          icon: Icons.inventory,
                        ),
                        if (s.pricingMode == ShipmentPricingMode.perUnit)
                          _buildStatTile(
                            context,
                            label: 'تكلفة البرنيكة',
                            value: '${s.costPricePerBarnika?.toStringAsFixed(2) ?? "0.00"} ج.م',
                            icon: Icons.monetization_on,
                          ),
                        if (s.pricingMode == ShipmentPricingMode.lumpSum)
                          _buildStatTile(
                            context,
                            label: 'تكلفة الجملة',
                            value: '${s.lumpSumCost?.toStringAsFixed(2) ?? "0.00"} ج.م',
                            icon: Icons.account_balance_wallet,
                          ),
                        if (s.pricingMode == ShipmentPricingMode.commission)
                          _buildStatTile(
                            context,
                            label: 'نسبة العمولة',
                            value: '${s.commissionPercentage?.toStringAsFixed(1) ?? "0.0"} %',
                            icon: Icons.percent,
                          ),
                        _buildStatTile(
                          context,
                          label: 'التكلفة الإجمالية',
                          value: '${s.totalCost.toStringAsFixed(2)} ج.م',
                          icon: Icons.receipt_long,
                        ),
                        if (s.containerPrice != null)
                          _buildStatTile(
                            context,
                            label: 'سعر تأمين البرنيكة',
                            value: '${s.containerPrice!.toStringAsFixed(2)} ج.م',
                            icon: Icons.shield,
                          ),
                      ],
                    ),

                    if (s.notes != null && s.notes!.isNotEmpty) ...[
                      const Gap(16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.amber.shade200),
                        ),
                        child: Text(
                          'ملاحظات: ${s.notes!}',
                          style: TextStyle(color: Colors.amber.shade900),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const Gap(24),

            // Performance & Linked Invoices Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'المبيعات المنسوبة لهذه الشحنة (${_linkedItems.length} عنصر)',
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                Text(
                  'إجمالي المبيعات: ${totalSalesRevenue.toStringAsFixed(2)} ج.م'
                  '${s.pricingMode == ShipmentPricingMode.commission ? " | العمولة: ${totalCommissions.toStringAsFixed(2)} ج.م" : ""}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Gap(12),

            if (_linkedItems.isEmpty)
              Card(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    children: [
                      Icon(Icons.receipt_long_outlined, size: 48, color: Colors.grey.shade400),
                      const Gap(8),
                      Text(
                        'لم يتم صرف أي مبيعات من هذه الشحنة حتى الآن',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              )
            else
              Card(
                clipBehavior: Clip.antiAlias,
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _linkedItems.length,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = _linkedItems[index].$1;
                    final invoice = _linkedItems[index].$2;
                    final product = _linkedItems[index].$3;

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: theme.colorScheme.primaryContainer,
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(color: theme.colorScheme.primary),
                        ),
                      ),
                      title: Text(
                        '${product?.name ?? "منتج #${item.productId}"} × ${item.quantity} برنيكة',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        'فاتورة #${invoice.invoiceNumber ?? invoice.id} | تاريخ: ${DateFormat('yyyy/MM/dd HH:mm').format(invoice.date)} | العميل: ${invoice.customerName ?? "عميل نقدي"}',
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${(item.price * item.quantity).toStringAsFixed(2)} ج.م',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          if (item.commission > 0)
                            Text(
                              'عمولة المحل: ${item.commission.toStringAsFixed(2)} ج.م',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.green.shade800,
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatTile(
    BuildContext context, {
    required String label,
    required String value,
    String? subtitle,
    required IconData icon,
  }) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const Gap(8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600)),
            Text(value, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
            if (subtitle != null)
              Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: Colors.green.shade800)),
          ],
        ),
      ],
    );
  }
}
