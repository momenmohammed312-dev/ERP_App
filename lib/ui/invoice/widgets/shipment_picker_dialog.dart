import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/tables/vegetable_shipments_table.dart';

/// Result of picking a shipment for manual override.
///
/// [useFifo] == true means "clear manual override, use automatic FIFO".
/// Otherwise [shipmentId] holds the shipment the user selected.
class ShipmentPickerResult {
  final bool useFifo;
  final int? shipmentId;

  const ShipmentPickerResult.fifo() : useFifo = true, shipmentId = null;

  const ShipmentPickerResult.shipment(this.shipmentId)
      : useFifo = false,
        assert(shipmentId != null);

  static const autoFifo = ShipmentPickerResult.fifo();
}

class ShipmentPickerDialog extends StatefulWidget {
  final AppDatabase db;
  final int? currentOverrideShipmentId;

  const ShipmentPickerDialog({
    super.key,
    required this.db,
    this.currentOverrideShipmentId,
  });

  @override
  State<ShipmentPickerDialog> createState() => _ShipmentPickerDialogState();
}

class _ShipmentPickerDialogState extends State<ShipmentPickerDialog> {
  List<VegetableShipment> _openShipments = [];
  Map<String, Supplier> _suppliers = {};
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final shipments =
          await widget.db.vegetableShipmentDao.getOpenShipmentsFifo();
      final suppliers = await widget.db.supplierDao.getAllSuppliers();
      if (!mounted) return;
      setState(() {
        _openShipments = shipments;
        _suppliers = {for (final s in suppliers) s.id: s};
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 460,
        constraints: const BoxConstraints(maxHeight: 520),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.local_shipping, color: Color(0xFF2E7D32)),
                Gap(8),
                Text(
                  'اختيار الشحنة',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Gap(8),
            const Text(
              'اختر الشحنة اللي هيتم السحب منها، أو ارجع للسحب التلقائي (FIFO).',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const Gap(16),
            // Auto FIFO option
            _buildFifoOption(),
            const Gap(12),
            // Shipment list
            Expanded(child: _buildShipmentsList()),
          ],
        ),
      ),
    );
  }

  Widget _buildFifoOption() {
    final isCurrent = widget.currentOverrideShipmentId == null;
    return Card(
      color: isCurrent ? Colors.green.shade50 : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isCurrent ? Colors.green : Colors.grey.shade300,
        ),
      ),
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.compare_arrows, color: Colors.green),
        title: const Text(
          'سحب تلقائي (FIFO)',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: const Text('أقدم الشحنات المفتوحة أولاً'),
        trailing: isCurrent
            ? const Icon(Icons.check_circle, color: Colors.green)
            : null,
        onTap: () => Navigator.of(context).pop(ShipmentPickerResult.autoFifo),
      ),
    );
  }

  Widget _buildShipmentsList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Text(
          'خطأ في تحميل الشحنات: $_error',
          style: const TextStyle(color: Colors.red),
        ),
      );
    }
    if (_openShipments.isEmpty) {
      return const Center(
        child: Text('لا توجد شحنات مفتوحة بمخزون برانيك متبقٍ'),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      itemCount: _openShipments.length,
      itemBuilder: (context, index) {
        final shipment = _openShipments[index];
        final isCurrent = shipment.id == widget.currentOverrideShipmentId;
        final supplier = _suppliers[shipment.supplierId];
        return Card(
          color: isCurrent ? Colors.blue.shade50 : null,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: isCurrent ? Colors.blue : Colors.grey.shade300,
            ),
          ),
          child: ListTile(
            dense: true,
            title: Row(
              children: [
                Text(
                  'شحنة ${shipment.shipmentNumber}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const Gap(8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _pricingColor(shipment.pricingMode)
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _pricingLabel(shipment.pricingMode),
                    style: TextStyle(
                      fontSize: 10,
                      color: _pricingColor(shipment.pricingMode),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            subtitle: Text(
              'المورد: ${supplier?.name ?? shipment.supplierId} — '
              'متبقي: ${shipment.barnikaRemainingCount} برنيكة',
            ),
            trailing: isCurrent
                ? const Icon(Icons.check_circle, color: Colors.blue)
                : null,
            onTap: () => Navigator.of(context).pop(
              ShipmentPickerResult.shipment(shipment.id),
            ),
          ),
        );
      },
    );
  }

  Color _pricingColor(String mode) {
    switch (mode) {
      case ShipmentPricingMode.commission:
        return Colors.purple;
      case ShipmentPricingMode.lumpSum:
        return Colors.orange;
      default:
        return Colors.teal;
    }
  }

  String _pricingLabel(String mode) {
    switch (mode) {
      case ShipmentPricingMode.commission:
        return 'عمولة';
      case ShipmentPricingMode.lumpSum:
        return 'إجمالي';
      default:
        return 'للقطعة';
    }
  }
}
