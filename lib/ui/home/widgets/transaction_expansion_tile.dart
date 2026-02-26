import 'package:flutter/material.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/services/printer_service.dart';
import '../../widgets/invoice_items_table.dart';

class TransactionExpansionTile extends StatefulWidget {
  final LedgerTransaction transaction;
  final String entityType; // 'Customer' or 'Supplier'
  final bool isPurchase;
  final bool isSale;
  final AppDatabase db;

  const TransactionExpansionTile({
    super.key,
    required this.transaction,
    required this.entityType,
    required this.isPurchase,
    required this.isSale,
    required this.db,
  });

  @override
  State<TransactionExpansionTile> createState() =>
      TransactionExpansionTileState();
}

class TransactionExpansionTileState extends State<TransactionExpansionTile> {
  bool _isExpanded = false;
  List<InvoiceItemDisplayModel> _displayItems = [];
  bool _isLoadingItems = false;

  Future<void> _loadInvoiceItems() async {
    if (_isExpanded &&
        (widget.isSale || widget.isPurchase) &&
        _displayItems.isEmpty) {
      setState(() => _isLoadingItems = true);
      try {
        if (widget.isSale) {
          final invoiceId = _extractInvoiceId();
          if (invoiceId != null) {
            final items = await widget.db.invoiceDao
                .getItemsWithProductsByInvoice(invoiceId);

            setState(() {
              _displayItems = items.map((e) {
                final item = e.$1;
                final product = e.$2;
                return InvoiceItemDisplayModel(
                  productName: product?.name ?? 'منتج ${item.productId}',
                  quantity: item.quantity.toDouble(),
                  unitPrice: item.quantity > 0
                      ? item.price / item.quantity
                      : item.price,
                  total: item.price,
                  unit: product?.unit,
                );
              }).toList();
              _isLoadingItems = false;
            });
          } else {
            setState(() => _isLoadingItems = false);
          }
        } else if (widget.isPurchase) {
          final purchaseId =
              widget.transaction.receiptNumber ?? widget.transaction.id;
          final items = await widget.db.purchaseDao
              .getItemsWithProductsByPurchase(purchaseId);

          setState(() {
            _displayItems = items.map((e) {
              final item = e.$1;
              final product = e.$2;
              return InvoiceItemDisplayModel(
                productName: product?.name ?? 'منتج ${item.productId}',
                quantity: item.quantity.toDouble(),
                unitPrice: item.unitPrice,
                total: item.totalPrice,
                unit: item.unit,
              );
            }).toList();
            _isLoadingItems = false;
          });
        }
      } catch (e) {
        debugPrint('Error loading items: $e');
        setState(() => _isLoadingItems = false);
      }
    }
  }

  int? _extractInvoiceId() {
    if (widget.transaction.receiptNumber != null &&
        widget.transaction.receiptNumber!.isNotEmpty) {
      final receiptNum = widget.transaction.receiptNumber!;
      final match = RegExp(r'\d+').firstMatch(receiptNum);
      if (match != null) {
        final extractedId = int.tryParse(match.group(0) ?? '');
        if (extractedId != null) return extractedId;
      }
      final directId = int.tryParse(receiptNum);
      if (directId != null) return directId;
      final invMatch = RegExp(
        r'(?:INV|فاتورة|invoice)?[-\s]?(\d+)',
        caseSensitive: false,
      ).firstMatch(receiptNum);
      if (invMatch != null) {
        final extractedId = int.tryParse(invMatch.group(1) ?? '');
        if (extractedId != null) return extractedId;
      }
    }

    final desc = widget.transaction.description;
    if (desc.contains('#')) {
      final parts = desc.split('#');
      if (parts.length > 1) {
        final afterHash = parts[1].split(' ')[0];
        final extractedId = int.tryParse(afterHash);
        if (extractedId != null) return extractedId;
      }
    }

    if (widget.transaction.id.isNotEmpty) {
      final idMatch = RegExp(r'^\d+$').firstMatch(widget.transaction.id);
      if (idMatch != null) {
        final extractedId = int.tryParse(widget.transaction.id);
        if (extractedId != null) return extractedId;
      }
    }

    if (desc.isNotEmpty) {
      final descMatch = RegExp(r'#(\d+)').firstMatch(desc);
      if (descMatch != null) {
        final extractedId = int.tryParse(descMatch.group(1) ?? '');
        if (extractedId != null) return extractedId;
      }
      final numberMatch = RegExp(r'(\d+)').firstMatch(desc);
      if (numberMatch != null) {
        final extractedId = int.tryParse(numberMatch.group(1) ?? '');
        if (extractedId != null) return extractedId;
      }
    }
    return null;
  }

  Future<void> _printInvoice() async {
    try {
      final invoiceId = _extractInvoiceId();
      if (invoiceId == null) return;

      final invoices = await widget.db.invoiceDao.getInvoicesByDateRange(
        DateTime.now().subtract(const Duration(days: 365)),
        DateTime.now(),
      );
      final invoice = invoices.firstWhere(
        (inv) =>
            inv.id == invoiceId || inv.invoiceNumber == invoiceId.toString(),
        orElse: () => throw Exception('Invoice not found'),
      );

      final itemsWithProducts = await widget.db.invoiceDao
          .getItemsWithProductsByInvoice(invoice.id);

      final itemsMaps = itemsWithProducts.map((itemWithProduct) {
        final item = itemWithProduct.$1;
        final product = itemWithProduct.$2;
        final unitPrice = item.quantity > 0
            ? item.price / item.quantity
            : item.price;

        return {
          'productName': product?.name ?? 'Product ${item.productId}',
          'name': product?.name ?? 'Product ${item.productId}',
          'quantity': item.quantity,
          'price': unitPrice,
          'total': item.price,
        };
      }).toList();

      await PrinterService.autoPrintInvoice(
        invoice: {
          'id': invoice.id,
          'customerName': invoice.customerName,
          'date': invoice.date,
          'totalAmount': invoice.totalAmount,
          'paymentMethod': invoice.paymentMethod,
        },
        items: itemsMaps,
        paymentMethod: invoice.paymentMethod ?? 'cash',
        ledgerDao: widget.db.ledgerDao,
      );
    } catch (e) {
      debugPrint('Error printing: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isCustomer = widget.entityType == 'Customer';

    // Debit (+) for customer = Sale (Red)
    // Credit (+) for supplier = Purchase (Red)
    final bool isLiabilityIncrease = isCustomer
        ? widget.transaction.debit > 0
        : widget.transaction.credit > 0;

    final double amount = isLiabilityIncrease
        ? (isCustomer ? widget.transaction.debit : widget.transaction.credit)
        : (isCustomer ? widget.transaction.credit : widget.transaction.debit);

    final bool isPayment =
        widget.transaction.origin == 'payment' ||
        (!isLiabilityIncrease && amount > 0);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: isLiabilityIncrease
              ? Colors.red.withValues(alpha: 0.1)
              : Colors.green.withValues(alpha: 0.1),
          child: Icon(
            isLiabilityIncrease ? Icons.shopping_cart : Icons.payment,
            color: isLiabilityIncrease ? Colors.red : Colors.green,
            size: 20,
          ),
        ),
        title: Text(
          widget.transaction.description,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '${widget.transaction.date.day}/${widget.transaction.date.month}/${widget.transaction.date.year}',
          style: TextStyle(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.7),
            fontSize: 12,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${amount.toStringAsFixed(2)} ج.م',
                  style: TextStyle(
                    color: isLiabilityIncrease ? Colors.red : Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: (isLiabilityIncrease ? Colors.orange : Colors.green)
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isPayment
                        ? 'سداد'
                        : (isLiabilityIncrease ? 'مدين' : 'مدفوع'),
                    style: TextStyle(
                      color: isLiabilityIncrease ? Colors.orange : Colors.green,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            if (widget.isSale && !isPayment) ...[
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.print, size: 20),
                onPressed: _printInvoice,
                tooltip: 'طباعة الفاتورة',
              ),
            ],
          ],
        ),
        onExpansionChanged: (isPayment && !widget.isPurchase && !widget.isSale)
            ? null
            : (expanded) {
                setState(() => _isExpanded = expanded);
                if (expanded) {
                  _loadInvoiceItems();
                }
              },
        children: [_buildProductDetailsSection()],
      ),
    );
  }

  Widget _buildProductDetailsSection() {
    if (_isLoadingItems) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_displayItems.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Text('لا توجد تفاصيل منتجات لهذه المعاملة'),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'تفاصيل المنتجات',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.blue,
            ),
          ),
          const SizedBox(height: 12),
          InvoiceItemsTable(items: _displayItems),
        ],
      ),
    );
  }
}
