import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/tables/vegetable_shipments_table.dart';
import 'package:pos_offline_desktop/core/services/shipment_allocation_service.dart';
import 'package:pos_offline_desktop/core/services/shipment_pricing_service.dart';
import 'package:pos_offline_desktop/ui/invoice/models/product_entry.dart';

class OrderLineItem extends StatefulWidget {
  final ProductEntry entry;
  final int index;
  final Function(ProductEntry) onEdit;
  final VoidCallback onDelete;
  final bool canDelete;

  /// When non-null, renders the "change shipment" (manual override) control.
  final VoidCallback? onPickShipment;

  const OrderLineItem({
    super.key,
    required this.entry,
    required this.index,
    required this.onEdit,
    required this.onDelete,
    this.canDelete = true,
    this.onPickShipment,
  });

  @override
  State<OrderLineItem> createState() => _OrderLineItemState();
}

class _OrderLineItemState extends State<OrderLineItem> {
  late TextEditingController _quantityController;
  late TextEditingController _priceController;
  late TextEditingController _discountController;
  late TextEditingController _taxController;

  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _quantityController = TextEditingController(
      text: widget.entry.quantity.toString(),
    );
    _priceController = TextEditingController(
      text: widget.entry.unitPrice.toStringAsFixed(2),
    );
    _discountController = TextEditingController(
      text: widget.entry.discount.toStringAsFixed(2),
    );
    _taxController = TextEditingController(
      text: widget.entry.tax.toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _priceController.dispose();
    _discountController.dispose();
    _taxController.dispose();
    super.dispose();
  }

  void _updateEntry() {
    final updatedEntry = ProductEntry(product: widget.entry.product)
      ..quantity = int.tryParse(_quantityController.text) ?? 1
      ..unit = widget.entry.unit
      ..unitPrice = double.tryParse(_priceController.text) ?? 0.0
      ..discount = double.tryParse(_discountController.text) ?? 0.0
      ..tax = double.tryParse(_taxController.text) ?? 0.0
      ..priceOverride =
          (double.tryParse(_priceController.text) ?? 0.0) !=
          widget.entry.product?.price
      // Preserve shipment allocation state across edits
      ..allocations = widget.entry.allocations
      ..shipmentsById = widget.entry.shipmentsById
      ..allocationError = widget.entry.allocationError
      ..overrideMode = widget.entry.overrideMode
      ..overrideShipmentId = widget.entry.overrideShipmentId;

    // Calculate line total
    updatedEntry.lineTotal =
        (updatedEntry.unitPrice * updatedEntry.quantity) -
        updatedEntry.discount +
        updatedEntry.tax;

    widget.onEdit(updatedEntry);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          // Main row
          ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 4,
            ),
            title: Text(
              widget.entry.product?.name ?? 'Unknown Product',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        widget.entry.unit.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.blue.shade700,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const Gap(8),
                    if (widget.entry.priceOverride) ...[
                      Icon(Icons.edit, size: 12, color: Colors.orange.shade600),
                      const Gap(2),
                      Text(
                        'Price Modified',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.orange.shade600,
                        ),
                      ),
                      const Gap(8),
                    ],
                    Text(
                      'Line Total: ${widget.entry.lineTotal.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                if (widget.entry.isBarnikaTracked &&
                    (widget.entry.allocations.isNotEmpty ||
                        widget.entry.allocationError != null))
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      _allocationSummary(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: widget.entry.allocationError != null
                            ? Colors.red.shade700
                            : Colors.green.shade800,
                      ),
                    ),
                  ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(
                    _isExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                  ),
                  onPressed: () {
                    setState(() {
                      _isExpanded = !_isExpanded;
                    });
                  },
                  tooltip: 'Edit Details',
                ),
                if (widget.canDelete)
                  IconButton(
                    icon:
                        const Icon(Icons.delete, color: Colors.red, size: 20),
                    onPressed: widget.onDelete,
                    tooltip: 'Remove Item',
                  ),
              ],
            ),
          ),

          // Expanded details
          if (_isExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      // Quantity
                      Expanded(
                        child: TextFormField(
                          controller: _quantityController,
                          decoration: const InputDecoration(
                            labelText: 'Quantity',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          onChanged: (_) => _updateEntry(),
                        ),
                      ),
                      const Gap(12),
                      // Unit Price
                      Expanded(
                        child: TextFormField(
                          controller: _priceController,
                          decoration: const InputDecoration(
                            labelText: 'Unit Price',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'^\d+\.?\d{0,2}'),
                            ),
                          ],
                          onChanged: (_) => _updateEntry(),
                        ),
                      ),
                    ],
                  ),
                  const Gap(12),
                  Row(
                    children: [
                      // Discount
                      Expanded(
                        child: TextFormField(
                          controller: _discountController,
                          decoration: const InputDecoration(
                            labelText: 'Discount',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'^\d+\.?\d{0,2}'),
                            ),
                          ],
                          onChanged: (_) => _updateEntry(),
                        ),
                      ),
                      const Gap(12),
                      // Tax
                      Expanded(
                        child: TextFormField(
                          controller: _taxController,
                          decoration: const InputDecoration(
                            labelText: 'Tax',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'^\d+\.?\d{0,2}'),
                            ),
                          ],
                          onChanged: (_) => _updateEntry(),
                        ),
                      ),
                    ],
                  ),
                  if (_shouldShowAllocationSection()) ...[
                    const Gap(12),
                    _buildAllocationSection(),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  bool _shouldShowAllocationSection() {
    return widget.entry.isBarnikaTracked &&
        (widget.entry.allocations.isNotEmpty ||
            widget.entry.allocationError != null ||
            widget.onPickShipment != null);
  }

  String _allocationSummary() {
    final entry = widget.entry;
    if (entry.allocationError != null) {
      return '⚠ لا يوجد مخزون شحنات متاح لهذه الكمية';
    }
    if (entry.allocations.length == 1) {
      final a = entry.allocations.first;
      final shipment = entry.shipmentsById[a.shipmentId];
      final label =
          shipment == null ? '#${a.shipmentId}' : shipment.shipmentNumber;
      return '${entry.overrideMode ? 'يدوي — ' : ''}سحب من شحنة $label: ${a.quantity} برنيكة';
    }
    return '${entry.overrideMode ? 'يدوي — ' : ''}سحب من ${entry.allocations.length} شحنات: ${entry.allocatedQuantity} برنيكة';
  }

  Widget _buildAllocationSection() {
    final entry = widget.entry;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.inventory_2, size: 16, color: Colors.green),
              const Gap(6),
              const Text(
                'الشحنات (سحب البرانيك):',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const Gap(8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: entry.overrideMode
                      ? Colors.orange.shade100
                      : Colors.green.shade200,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  entry.overrideMode ? 'يدوي' : 'تلقائي FIFO',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: entry.overrideMode
                        ? Colors.orange.shade800
                        : Colors.green.shade800,
                  ),
                ),
              ),
            ],
          ),
          const Gap(6),
          if (entry.allocationError != null)
            Text(
              '⚠ ${entry.allocationError}',
              style: TextStyle(color: Colors.red.shade700, fontSize: 12),
            )
          else if (entry.allocations.isEmpty)
            const Text(
              'لا يوجد مخزون شحنات متاح لهذه الكمية',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            )
          else
            for (final allocation in entry.allocations)
              _buildAllocationLine(allocation),
          if (widget.onPickShipment != null) ...[
            const Gap(8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: widget.onPickShipment,
                icon: const Icon(Icons.swap_horiz, size: 16),
                label: Text(
                  entry.overrideMode ? 'تغيير الشحنة المحددة' : 'اختيار شحنة يدوياً',
                  style: const TextStyle(fontSize: 12),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.green.shade800,
                  side: BorderSide(color: Colors.green.shade300),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAllocationLine(ShipmentAllocation allocation) {
    final shipment = widget.entry.shipmentsById[allocation.shipmentId];
    final label = shipment == null
        ? 'شحنة #${allocation.shipmentId}'
        : 'شحنة ${shipment.shipmentNumber}';

    final commissionText = _commissionText(allocation, shipment);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          const Icon(Icons.arrow_left, size: 16, color: Colors.grey),
          const Gap(4),
          Expanded(
            child: Text(
              commissionText == null
                  ? '$label: ${allocation.quantity} برنيكة'
                  : '$label: ${allocation.quantity} برنيكة — $commissionText',
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  /// For commission-based shipments, returns the supplier-due inline summary.
  String? _commissionText(
    ShipmentAllocation allocation,
    VegetableShipment? shipment,
  ) {
    if (shipment == null ||
        shipment.pricingMode != ShipmentPricingMode.commission ||
        shipment.commissionPercentage == null) {
      return null;
    }

    final sellAmount = widget.entry.unitPrice * allocation.quantity;
    final supplierDue = ShipmentPricingService.calculateSupplierDue(
      sellAmount,
      shipment.commissionPercentage!,
    );

    return 'عمولة ${shipment.commissionPercentage!.toStringAsFixed(0)}% — '
        'مستحق للمورد: ${supplierDue.toStringAsFixed(2)} ج';
  }
}
