import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';
import 'package:pos_offline_desktop/ui/invoice/models/product_entry.dart';

class OrderLineItem extends StatefulWidget {
  final ProductEntry entry;
  final int index;
  final Function(ProductEntry) onEdit;
  final VoidCallback onDelete;
  final bool canDelete;

  const OrderLineItem({
    super.key,
    required this.entry,
    required this.index,
    required this.onEdit,
    required this.onDelete,
    this.canDelete = true,
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
          widget.entry.product?.price;

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
            subtitle: Row(
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
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
