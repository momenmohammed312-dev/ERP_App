import 'package:flutter/material.dart';
import 'package:pos_offline_desktop/l10n/app_localizations.dart';

class InvoiceItemDisplayModel {
  final String productName;
  final double quantity;
  final double unitPrice;
  final double total;
  final String? unit;

  InvoiceItemDisplayModel({
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.total,
    this.unit,
  });
}

class InvoiceItemsTable extends StatelessWidget {
  final List<InvoiceItemDisplayModel> items;
  final Color? backgroundColor;

  const InvoiceItemsTable({
    super.key,
    required this.items,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: backgroundColor ?? theme.cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.1)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(
            theme.primaryColor.withValues(alpha: 0.05),
          ),
          columnSpacing: 20,
          columns: [
            DataColumn(
              label: Text(
                l10n.product_name,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            DataColumn(
              label: Text(
                l10n.quantity,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              numeric: true,
            ),
            DataColumn(
              label: Text(
                l10n.price,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              numeric: true,
            ),
            DataColumn(
              label: Text(
                l10n.total,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              numeric: true,
            ),
          ],
          rows: items.map((item) {
            return DataRow(
              cells: [
                DataCell(
                  SizedBox(
                    width: 150,
                    child: Text(
                      item.productName,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                DataCell(
                  Text(
                    '${item.quantity} ${item.unit ?? ''}',
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ),
                DataCell(
                  Text(
                    item.unitPrice.toStringAsFixed(2),
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ),
                DataCell(
                  Text(
                    item.total.toStringAsFixed(2),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }
}
