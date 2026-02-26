import 'package:flutter/material.dart';
import '../../../core/utils/logger.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/ui/customer/models/transaction_display_model.dart';
import 'package:pos_offline_desktop/ui/customer/widgets/date_range_picker_dialog.dart'
    as custom;
import 'package:pos_offline_desktop/ui/customer/services/transaction_list_pdf_generator.dart';
import 'package:pos_offline_desktop/core/services/unified_print_service.dart'
    as ups;

// Simple transaction tile widget for the customer list
class TransactionTile extends StatelessWidget {
  final TransactionDisplayModel transaction;
  final VoidCallback? onTap;
  final AppDatabase? db;

  const TransactionTile({
    super.key,
    required this.transaction,
    this.onTap,
    this.db,
  });

  @override
  Widget build(BuildContext context) {
    AppLogger.d(
      'DEBUG: Building TransactionTile for ${transaction.origin} transaction',
    );

    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final amountColor = transaction.amount >= 0 ? Colors.green : Colors.red;
    final tagBgColor = isDarkMode ? Colors.grey.shade800 : Colors.grey.shade200;
    final tagTextColor = isDarkMode ? Colors.white : Colors.black87;

    // Icon background color based on transaction type
    Color iconBgColor;
    IconData iconData;
    if (transaction.origin == 'sale') {
      iconBgColor = Colors.red.shade100;
      iconData = Icons.shopping_cart;
    } else if (transaction.origin == 'payment') {
      iconBgColor = Colors.green.shade100;
      iconData = Icons.receipt;
    } else if (transaction.origin == 'opening') {
      iconBgColor = Colors.blue.shade100;
      iconData = Icons.account_balance;
    } else {
      iconBgColor = Colors.grey.shade100;
      iconData = Icons.description;
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.grey.shade800 : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDarkMode ? Colors.grey.shade600 : Colors.grey.shade300,
        ),
      ),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        trailing: Icon(
          Icons.expand_more,
          color: isDarkMode ? Colors.white : Colors.black87,
        ),
        leading: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(color: iconBgColor, shape: BoxShape.circle),
          child: Icon(
            iconData,
            size: 16,
            color: isDarkMode ? Colors.white : Colors.black87,
          ),
        ),
        title: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          child: Row(
            children: [
              // Left column: Amount and tag
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    transaction.formattedAmount,
                    style: TextStyle(
                      fontSize: 16,
                      color: amountColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Gap(6),
                  if (transaction.tag != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: tagBgColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        transaction.tag!,
                        style: TextStyle(
                          fontSize: 12,
                          color: tagTextColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),

              const Gap(16),

              // Center area: Description or product details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (transaction.productDetails != null &&
                        transaction.productDetails!.isNotEmpty) ...[
                      // Show product details for sales
                      ...transaction.productDetails!
                          .take(3)
                          .map(
                            (product) => Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Text(
                                product,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isDarkMode
                                      ? Colors.grey.shade300
                                      : Colors.grey.shade700,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                      if (transaction.productDetails!.length > 3)
                        Text(
                          '... و ${transaction.productDetails!.length - 3} منتجات أخرى',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDarkMode
                                ? Colors.grey.shade400
                                : Colors.grey.shade500,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                    ] else if (transaction.description != null) ...[
                      // Show description for other transactions
                      Text(
                        transaction.description!,
                        style: TextStyle(
                          fontSize: 14,
                          color: isDarkMode
                              ? Colors.grey.shade200
                              : Colors.black87,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ] else ...[
                      // Fallback
                      Text(
                        transaction.rightTitle,
                        style: TextStyle(
                          fontSize: 14,
                          color: isDarkMode
                              ? Colors.grey.shade200
                              : Colors.black87,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const Gap(16),

              // Right area: Bold title and date
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    transaction.rightTitle,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: isDarkMode ? Colors.white : Colors.black87,
                    ),
                  ),
                  const Gap(4),
                  Text(
                    transaction.formattedDate,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDarkMode
                          ? Colors.grey.shade400
                          : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        // NESTED TABLE FOR TRANSACTION DETAILS
        children: [
          if (transaction.origin == 'sale' && db != null)
            FutureBuilder<List<InvoiceItem>>(
              future: _getTransactionDetails(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      'خطأ في تحميل التفاصيل: ${snapshot.error}',
                      style: TextStyle(color: Colors.red.shade400),
                    ),
                  );
                }

                final items = snapshot.data ?? [];

                if (items.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      'لا توجد منتجات لهذه المعاملة',
                      style: TextStyle(
                        color: isDarkMode
                            ? Colors.grey.shade400
                            : Colors.grey.shade600,
                      ),
                    ),
                  );
                }

                return Container(
                  padding: const EdgeInsets.all(8),
                  color: isDarkMode
                      ? Colors.grey.shade900
                      : Colors.grey.shade50,
                  child: Column(
                    children: [
                      // Enhanced table header matching sales reports format
                      Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 6,
                          horizontal: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isDarkMode
                              ? Colors.blueGrey.shade800
                              : Colors.blueGrey.shade100,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(8),
                            topRight: Radius.circular(8),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 4,
                              child: Text(
                                'اسم الصنف',
                                style: TextStyle(
                                  color: isDarkMode
                                      ? Colors.orange.shade300
                                      : Colors.orange.shade800,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            Expanded(
                              flex: 1,
                              child: Text(
                                'الكمية',
                                style: TextStyle(
                                  color: isDarkMode
                                      ? Colors.orange.shade300
                                      : Colors.orange.shade800,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            Expanded(
                              flex: 1,
                              child: Text(
                                'السعر',
                                style: TextStyle(
                                  color: isDarkMode
                                      ? Colors.orange.shade300
                                      : Colors.orange.shade800,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            Expanded(
                              flex: 1,
                              child: Text(
                                'الإجمالي',
                                style: TextStyle(
                                  color: isDarkMode
                                      ? Colors.orange.shade300
                                      : Colors.orange.shade800,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Product rows with real names
                      Container(
                        decoration: BoxDecoration(
                          color: isDarkMode
                              ? Colors.grey.shade800
                              : Colors.white,
                          borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(8),
                            bottomRight: Radius.circular(8),
                          ),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Column(
                          children: [
                            ...items.asMap().entries.map((entry) {
                              final index = entry.key;
                              final item = entry.value;
                              final isLast = index == items.length - 1;

                              return FutureBuilder<String>(
                                future: _getProductName(item.productId),
                                builder: (context, productNameSnapshot) {
                                  final productName =
                                      productNameSnapshot.data ??
                                      'منتج #${item.productId}';

                                  return Container(
                                    decoration: BoxDecoration(
                                      border: Border(
                                        bottom: BorderSide(
                                          color: isLast
                                              ? Colors.transparent
                                              : Colors.grey.shade200,
                                          width: 1,
                                        ),
                                      ),
                                      color: index % 2 == 0
                                          ? (isDarkMode
                                                ? Colors.grey.shade700
                                                : Colors.grey.shade50)
                                          : Colors.transparent,
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 10,
                                        horizontal: 12,
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            flex: 4,
                                            child: Text(
                                              productName,
                                              style: TextStyle(
                                                color: isDarkMode
                                                    ? Colors.white
                                                    : Colors.black87,
                                                fontSize: 13,
                                                fontWeight: FontWeight.w500,
                                              ),
                                              textAlign: TextAlign.start,
                                            ),
                                          ),
                                          Expanded(
                                            flex: 1,
                                            child: Text(
                                              item.quantity.toString(),
                                              style: TextStyle(
                                                color: isDarkMode
                                                    ? Colors.white
                                                    : Colors.black87,
                                                fontSize: 13,
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                          ),
                                          Expanded(
                                            flex: 1,
                                            child: Text(
                                              '${item.price.toStringAsFixed(2)} ج.م',
                                              style: TextStyle(
                                                color: isDarkMode
                                                    ? Colors.white
                                                    : Colors.black87,
                                                fontSize: 13,
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                          ),
                                          Expanded(
                                            flex: 1,
                                            child: Text(
                                              '${(item.quantity * item.price).toStringAsFixed(2)} ج.م',
                                              style: TextStyle(
                                                color: isDarkMode
                                                    ? Colors.white
                                                    : Colors.black87,
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              );
                            }),
                          ],
                        ),
                      ),
                      const Gap(12),
                      // PRINT ACTION BAR
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton.icon(
                            onPressed: onTap,
                            icon: const Icon(Icons.print),
                            label: const Text("طباعة التفاصيل"),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.blue.shade600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            )
          else
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                transaction.origin == 'sale'
                    ? 'لا توجد تفاصيل منتجات لهذه المعاملة'
                    : 'هذه المعاملة لا تحتوي على تفاصيل منتجات',
                style: TextStyle(
                  color: isDarkMode
                      ? Colors.grey.shade400
                      : Colors.grey.shade600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<List<InvoiceItem>> _getTransactionDetails() async {
    if (db == null) return [];

    AppLogger.d(
      'DEBUG: Getting transaction details for ${transaction.origin} transaction',
    );
    AppLogger.d('DEBUG: Transaction date: ${transaction.date}');
    AppLogger.d('DEBUG: Transaction amount: ${transaction.amount}');
    AppLogger.d(
      'DEBUG: Transaction receiptNumber: ${transaction.receiptNumber}',
    );

    try {
      // Try to find invoice by receipt number or date
      final invoices = await db!.invoiceDao.getInvoicesByDateRange(
        transaction.date.subtract(const Duration(days: 1)),
        transaction.date.add(const Duration(days: 1)),
      );

      AppLogger.d('DEBUG: Found ${invoices.length} invoices in date range');

      // Log all invoices for debugging
      for (final inv in invoices) {
        AppLogger.d(
          'DEBUG: Invoice #${inv.id} - Date: ${inv.date} - Amount: ${inv.totalAmount} - InvoiceNumber: ${inv.invoiceNumber}',
        );
      }

      Invoice matchingInvoice;

      // First try: use receiptNumber if available
      if (transaction.receiptNumber != null) {
        AppLogger.d(
          'DEBUG: Trying to find invoice by receiptNumber: ${transaction.receiptNumber}',
        );
        try {
          matchingInvoice = invoices.firstWhere(
            (inv) =>
                inv.invoiceNumber == transaction.receiptNumber ||
                inv.id.toString() == transaction.receiptNumber,
          );
          AppLogger.d('DEBUG: Found invoice by receiptNumber');
        } catch (e) {
          AppLogger.d(
            'DEBUG: No invoice found by receiptNumber, trying date/amount match',
          );
          // Fallback to date/amount matching
          matchingInvoice = invoices.firstWhere(
            (inv) =>
                inv.date.year == transaction.date.year &&
                inv.date.month == transaction.date.month &&
                inv.date.day == transaction.date.day &&
                inv.totalAmount.abs() == transaction.amount.abs(),
            orElse: () {
              AppLogger.d(
                'DEBUG: No matching invoice found, trying any sale transaction',
              );
              // Fallback: try any invoice from that day
              return invoices.firstWhere(
                (inv) =>
                    inv.date.year == transaction.date.year &&
                    inv.date.month == transaction.date.month &&
                    inv.date.day == transaction.date.day,
                orElse: () => throw Exception('No invoice found for this date'),
              );
            },
          );
        }
      } else {
        // No receiptNumber, try date/amount matching
        matchingInvoice = invoices.firstWhere(
          (inv) =>
              inv.date.year == transaction.date.year &&
              inv.date.month == transaction.date.month &&
              inv.date.day == transaction.date.day &&
              inv.totalAmount.abs() == transaction.amount.abs(),
          orElse: () {
            AppLogger.d(
              'DEBUG: No matching invoice found, trying any sale transaction',
            );
            // Fallback: try any invoice from that day
            return invoices.firstWhere(
              (inv) =>
                  inv.date.year == transaction.date.year &&
                  inv.date.month == transaction.date.month &&
                  inv.date.day == transaction.date.day,
              orElse: () => throw Exception('No invoice found for this date'),
            );
          },
        );
      }

      AppLogger.d('DEBUG: Found matching invoice #${matchingInvoice.id}');

      final items = await db!.invoiceDao.getInvoiceItems(matchingInvoice.id);
      AppLogger.d('DEBUG: Found ${items.length} invoice items');

      return items;
    } catch (e) {
      AppLogger.d('DEBUG: Error getting transaction details: $e');
      return [];
    }
  }

  // Helper method to get product name
  Future<String> _getProductName(int productId) async {
    try {
      final products = await (db!.select(
        db!.products,
      )..where((p) => p.id.equals(productId))).get();
      if (products.isNotEmpty) {
        return products.first.name;
      }
    } catch (e) {
      AppLogger.e('DEBUG: Error getting product name for $productId', e);
    }
    return 'منتج #$productId';
  }
}

/// Customer transaction list widget that displays transactions with exact layout
/// Includes date range picker, export, and print functionality
class CustomerTransactionList extends ConsumerStatefulWidget {
  final Customer customer;
  final AppDatabase db;
  final VoidCallback? onRefresh;

  const CustomerTransactionList({
    super.key,
    required this.customer,
    required this.db,
    this.onRefresh,
  });

  @override
  ConsumerState<CustomerTransactionList> createState() =>
      _CustomerTransactionListState();
}

class _CustomerTransactionListState
    extends ConsumerState<CustomerTransactionList> {
  DateTime? _fromDate;
  DateTime? _toDate;
  List<TransactionDisplayModel> _transactions = [];
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Default to last 30 days
    _fromDate = DateTime.now().subtract(const Duration(days: 30));
    _toDate = DateTime.now();
    _loadTransactions();
  }

  Future<void> _loadTransactions() async {
    if (_fromDate == null || _toDate == null) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Get ledger transactions for the customer
      final ledgerTransactions = await widget.db.ledgerDao
          .getTransactionsByDateRange(
            'Customer',
            widget.customer.id,
            _fromDate!,
            _toDate!,
          );

      // Get invoices for the customer in date range
      final invoices = await widget.db.invoiceDao.getInvoicesByDateRange(
        _fromDate!,
        _toDate!,
      );

      // Filter by customer
      final customerInvoices = invoices
          .where((invoice) => invoice.customerId == widget.customer.id)
          .toList();

      // Convert to display models
      final displayModels = <TransactionDisplayModel>[];

      // Add ledger transactions
      for (final transaction in ledgerTransactions) {
        displayModels.add(
          TransactionDisplayModel.fromLedgerTransaction(transaction),
        );
      }

      // Add invoices with product details
      for (final invoice in customerInvoices) {
        // Get invoice items for product details
        final invoiceItems = await widget.db.invoiceDao.getInvoiceItems(
          invoice.id,
        );

        final productDetails = <String>[];
        for (final item in invoiceItems) {
          // Get product name
          final products = await (widget.db.select(
            widget.db.products,
          )..where((p) => p.id.equals(item.productId))).get();
          final product = products.isNotEmpty ? products.first : null;
          if (product != null) {
            final productName = product.name;
            final quantity = item.quantity;
            final unitPrice = item.price;
            final total = quantity * unitPrice;

            productDetails.add(
              '$productName - الكمية: $quantity - السعر: ${unitPrice.toStringAsFixed(2)} - الإجمالي: ${total.toStringAsFixed(2)}',
            );
          }
        }

        displayModels.add(
          TransactionDisplayModel.fromInvoice(
            invoice,
            productDetails: productDetails.isNotEmpty ? productDetails : null,
          ),
        );
      }

      // Sort by date (newest first)
      displayModels.sort((a, b) => b.date.compareTo(a.date));

      setState(() {
        _transactions = displayModels;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _onDateRangeChanged(DateTime from, DateTime to) {
    setState(() {
      _fromDate = from;
      _toDate = to;
    });
    _loadTransactions();
  }

  void _showDateRangePicker() {
    showDialog(
      context: context,
      builder: (context) => custom.DateRangePickerDialog(
        initialFromDate:
            _fromDate ?? DateTime.now().subtract(const Duration(days: 30)),
        initialToDate: _toDate ?? DateTime.now(),
        onDateRangeSelected: _onDateRangeChanged,
      ),
    );
  }

  Future<void> _exportPdf() async {
    try {
      final pdfData =
          await TransactionListPdfGenerator.generateTransactionListPdf(
            _transactions,
            widget.customer.name,
            fromDate: _fromDate != null
                ? DateFormat('yyyy/MM/dd').format(_fromDate!)
                : '',
            toDate: _toDate != null
                ? DateFormat('yyyy/MM/dd').format(_toDate!)
                : '',
            branchName: 'الفرع الرئيسي المصنع',
          );

      // Save and display the PDF
      await Printing.sharePdf(
        bytes: pdfData,
        filename:
            'customer_transactions_${widget.customer.name}_${DateTime.now().millisecondsSinceEpoch}.pdf',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم تصدير ملف PDF بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في تصدير PDF: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _print() async {
    try {
      final pdfData =
          await TransactionListPdfGenerator.generateTransactionListPdf(
            _transactions,
            widget.customer.name,
            fromDate: _fromDate != null
                ? DateFormat('yyyy/MM/dd').format(_fromDate!)
                : '',
            toDate: _toDate != null
                ? DateFormat('yyyy/MM/dd').format(_toDate!)
                : '',
            branchName: 'الفرع الرئيسي المصنع',
          );

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) => pdfData,
        name: 'حركات العميل - ${widget.customer.name}',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في الطباعة: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showInvoicePreview(TransactionDisplayModel transaction) async {
    // Store context before async operations
    final context = this.context;
    if (!mounted) return;

    try {
      // Find the invoice for this transaction
      final invoices = await widget.db.invoiceDao.getInvoicesByDateRange(
        transaction.date.subtract(const Duration(days: 1)),
        transaction.date.add(const Duration(days: 1)),
      );

      final matchingInvoice = invoices.firstWhere(
        (inv) =>
            inv.date.year == transaction.date.year &&
            inv.date.month == transaction.date.month &&
            inv.date.day == transaction.date.day &&
            inv.totalAmount.abs() == transaction.amount.abs(),
        orElse: () => throw Exception('Invoice not found'),
      );

      // Get invoice items
      final items = await widget.db.invoiceDao.getInvoiceItems(
        matchingInvoice.id,
      );

      // Generate PDF using new SOP 4.0 format
      final itemsWithProducts = await widget.db.invoiceDao
          .getItemsWithProductsByInvoice(matchingInvoice.id);

      final invoiceItems = itemsWithProducts.map((itemWithProduct) {
        final item = itemWithProduct.$1;
        final product = itemWithProduct.$2;
        return ups.InvoiceItem(
          id: item.id,
          invoiceId: item.invoiceId,
          description: product?.name ?? 'Product ${item.productId}',
          unit: 'قطعة',
          quantity: item.quantity,
          unitPrice: item.price,
          totalPrice: item.quantity * item.price,
        );
      }).toList();

      final storeInfo = ups.StoreInfo(
        storeName: 'المحل التجاري',
        phone: '01234567890',
        zipCode: '12345',
        state: 'القاهرة',
      );

      final invoiceModel = ups.Invoice(
        id: matchingInvoice.id,
        invoiceNumber:
            matchingInvoice.invoiceNumber ?? 'INV${matchingInvoice.id}',
        customerName: widget.customer.name,
        customerPhone: widget.customer.phone ?? 'N/A',
        customerZipCode: '',
        customerState: '',
        invoiceDate: matchingInvoice.date,
        subtotal: matchingInvoice.totalAmount,
        isCreditAccount: matchingInvoice.status != 'paid',
        previousBalance: 0.0,
        totalAmount: matchingInvoice.totalAmount,
      );

      final invoiceData = ups.InvoiceData(
        invoice: invoiceModel,
        items: invoiceItems,
        storeInfo: storeInfo,
      );

      final pdfFile = await ups.UnifiedPrintService.exportToPDFFile(
        documentType: ups.DocumentType.salesInvoice,
        data: invoiceData,
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم تصدير الفاتورة: ${pdfFile.path}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في عرض الفاتورة: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final dateFormat = DateFormat('yyyy/MM/dd');

    return Container(
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.grey.shade900 : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDarkMode ? Colors.grey.shade700 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        children: [
          // Header with date range and actions
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDarkMode
                  ? Colors.blueGrey.shade800
                  : Colors.blueGrey.shade50,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    // Date range display
                    Expanded(
                      child: InkWell(
                        onTap: _showDateRangePicker,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 12,
                          ),
                          decoration: BoxDecoration(
                            color: isDarkMode
                                ? Colors.blueGrey.shade700
                                : Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isDarkMode
                                  ? Colors.blueGrey.shade600
                                  : Colors.blueGrey.shade300,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.date_range,
                                size: 16,
                                color: isDarkMode
                                    ? Colors.white
                                    : Colors.black87,
                              ),
                              const Gap(8),
                              Expanded(
                                child: Text(
                                  _fromDate != null && _toDate != null
                                      ? '${dateFormat.format(_fromDate!)} - ${dateFormat.format(_toDate!)}'
                                      : 'اختر نطاق التاريخ',
                                  style: TextStyle(
                                    color: isDarkMode
                                        ? Colors.white
                                        : Colors.black87,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.arrow_drop_down,
                                color: isDarkMode
                                    ? Colors.white
                                    : Colors.black87,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const Gap(12),
                    // Export button
                    IconButton(
                      onPressed: _exportPdf,
                      icon: Icon(
                        Icons.picture_as_pdf,
                        color: isDarkMode ? Colors.white : Colors.black87,
                      ),
                      tooltip: 'تصدير PDF',
                    ),
                    // Print button
                    IconButton(
                      onPressed: _print,
                      icon: Icon(
                        Icons.print,
                        color: isDarkMode ? Colors.white : Colors.black87,
                      ),
                      tooltip: 'طباعة',
                    ),
                    // Refresh button
                    if (widget.onRefresh != null)
                      IconButton(
                        onPressed: widget.onRefresh,
                        icon: Icon(
                          Icons.refresh,
                          color: isDarkMode ? Colors.white : Colors.black87,
                        ),
                        tooltip: 'تحديث',
                      ),
                  ],
                ),
                const Gap(8),
                // Transaction summary
                Row(
                  children: [
                    Text(
                      'إجمالي المعاملات: ${_transactions.length}',
                      style: TextStyle(
                        color: isDarkMode ? Colors.white : Colors.black87,
                        fontSize: 12,
                      ),
                    ),
                    const Gap(16),
                    Text(
                      'المجموع: ${_transactions.fold<double>(0.0, (sum, t) => sum + t.amount).toStringAsFixed(2)} ج.م',
                      style: TextStyle(
                        color: isDarkMode ? Colors.white : Colors.black87,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Transaction list
          Expanded(child: _buildTransactionList()),
        ],
      ),
    );
  }

  Widget _buildTransactionList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red.shade400),
            const Gap(16),
            Text(
              'حدث خطأ: $_error',
              style: TextStyle(color: Colors.red.shade400, fontSize: 16),
            ),
            const Gap(16),
            ElevatedButton(
              onPressed: _loadTransactions,
              child: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      );
    }

    if (_transactions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long, size: 48, color: Colors.grey.shade400),
            const Gap(16),
            Text(
              'لا توجد حركات في الفترة المحددة',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _transactions.length,
      itemBuilder: (context, index) {
        final transaction = _transactions[index];
        return TransactionTile(
          transaction: transaction,
          db: widget.db,
          onTap: () {
            // Handle print action from nested table
            if (transaction.origin == 'sale') {
              _showInvoicePreview(transaction);
            }
          },
        );
      },
    );
  }
}
