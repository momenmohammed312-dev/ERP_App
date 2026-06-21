import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:drift/drift.dart' as drift;
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/dao/sales_returns_dao.dart';
import 'package:pos_offline_desktop/core/services/export_service.dart';
import 'package:pos_offline_desktop/core/services/unified_print_service.dart'
    as ups;
import 'package:pos_offline_desktop/core/services/printer_service.dart';
import 'package:pos_offline_desktop/l10n/l10n.dart';

class SalesReportTab extends StatefulWidget {
  final AppDatabase db;

  const SalesReportTab({super.key, required this.db});

  @override
  State<SalesReportTab> createState() => _SalesReportTabState();
}

class _SalesReportTabState extends State<SalesReportTab> {
  DateTime _startDate = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
  ); // Start of today
  DateTime _endDate = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
    23,
    59,
    59,
  ); // End of today
  List<Invoice> _invoices = [];
  List<Invoice> _filteredInvoices = [];
  bool _isLoading = false;
  final _exportService = ExportService();
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
    _searchController.addListener(_filterInvoices);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterInvoices() {
    final query = _searchController.text.toLowerCase().trim();

    setState(() {
      if (query.isEmpty) {
        _filteredInvoices = List.from(_invoices);
      } else {
        _filteredInvoices = _invoices.where((invoice) {
          final invoiceNumber = (invoice.invoiceNumber ?? '').toLowerCase();
          final customerName = (invoice.customerName ?? '').toLowerCase();
          final totalAmount = invoice.totalAmount.toString();

          return invoiceNumber.contains(query) ||
              customerName.contains(query) ||
              totalAmount.contains(query);
        }).toList();
      }
    });
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // Fetch invoices with date range filtering
      final invoices = await widget.db.invoiceDao.getInvoicesByDateRange(
        _startDate,
        _endDate,
      );

      setState(() {
        _invoices = invoices;
        _filteredInvoices = List.from(invoices);
        _isLoading = false;
      });

      developer.log('✓ Invoice data loaded successfully');
      developer.log('Start date: $_startDate');
      developer.log('End date: $_endDate');
      developer.log('Found ${invoices.length} invoices in date range');
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading sales data: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _selectDateRange(BuildContext context) async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      builder: (context, child) {
        return Theme(
          data: Theme.of(
            context,
          ).copyWith(colorScheme: ColorScheme.light(primary: Colors.purple)),
          child: child ?? const SizedBox(),
        );
      },
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59);
      });
      _loadData();
    }
  }

  Future<void> _exportPDF() async {
    try {
      final List<Map<String, dynamic>> data = [];

      for (final invoice in _invoices) {
        data.add({
          'invoiceNumber': invoice.invoiceNumber ?? invoice.id.toString(),
          'customerName': invoice.customerName ?? 'عميل غير محدد',
          'totalAmount': invoice.totalAmount,
          'paidAmount': invoice.paidAmount,
          'date': DateFormat('yyyy-MM-dd HH:mm').format(invoice.date),
          'status': invoice.status,
        });
      }

      // Use enhanced export with consistent Arabic columns
      await _exportService.exportToPDF(
        title: 'تقارير المبيعات',
        headers: [
          'رقم الفاتورة',
          'اسم العميل',
          'المبلغ الإجمالي',
          'المدفوع',
          'التاريخ',
          'الحالة',
        ],
        columns: [
          'invoiceNumber',
          'customerName',
          'totalAmount',
          'paidAmount',
          'date',
          'status',
        ],
        data: data,
        fileName:
            'sales_report_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.error_exporting_with_error(e))),
        );
      }
    }
  }

  // Thermal receipt printing using UnifiedPrintService
  Future<void> _printThermalReceipt() async {
    try {
      final messengerContext = context; // Capture context before async
      if (_invoices.isEmpty) return;

      final grandTotal = _invoices.fold(
        0.0,
        (sum, inv) => sum + inv.totalAmount,
      );

      // Create sales report data for UnifiedPrintService
      final reportItems = [
        ups.InvoiceItem(
          id: 0,
          invoiceId: 0,
          description: 'ملخص تقرير المبيعات',
          unit: 'تقرير',
          quantity: 1,
          unitPrice: grandTotal,
          totalPrice: grandTotal,
        ),
      ];

      final storeInfo = ups.StoreInfo(
        storeName: 'المحل التجاري',
        phone: '01234567890',
        zipCode: '12345',
        state: 'القاهرة',
      );

      final reportInvoice = ups.Invoice(
        id: 0,
        invoiceNumber: 'SALES-${DateTime.now().millisecondsSinceEpoch}',
        customerName: 'تقارير المبيعات',
        customerPhone: '',
        customerZipCode: '',
        customerState: '',
        invoiceDate: DateTime.now(),
        subtotal: grandTotal,
        isCreditAccount: false,
        previousBalance: 0.0,
        totalAmount: grandTotal,
      );

      final invoiceData = ups.InvoiceData(
        invoice: reportInvoice,
        items: reportItems,
        storeInfo: storeInfo,
      );

      // Print using new SOP 4.0 format
      await ups.UnifiedPrintService.printToThermalPrinter(
        documentType: ups.DocumentType.salesInvoice,
        data: invoiceData,
      );

      if (mounted && messengerContext.mounted) {
        ScaffoldMessenger.of(messengerContext).showSnackBar(
          const SnackBar(content: Text('تم إرسال الطباعة الحرارية')),
        );
      }
    } catch (e) {
      if (mounted && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('خطأ في الطباعة: $e')));
      }
    }
  }

  Future<void> _printIndividualInvoice(Invoice invoice) async {
    try {
      // Get invoice items with product details
      final itemsWithProducts = await widget.db.invoiceDao
          .getItemsWithProductsByInvoice(invoice.id);

      // Convert to maps for printing
      final itemsMaps = itemsWithProducts.map((itemWithProduct) {
        final item = itemWithProduct.$1;
        final product = itemWithProduct.$2;
        return {
          'productName': product?.name ?? 'Product ${item.productId}',
          'name': product?.name ?? 'Product ${item.productId}',
          'quantity': item.quantity,
          'price': item.price,
          'total': item.quantity * item.price,
        };
      }).toList();

      // Print with REPRINT header
      await PrinterService.printDuplicateInvoice(
        invoice: {
          'id': invoice.id,
          'customerName': invoice.customerName,
          'date': invoice.date,
          'totalAmount': invoice.totalAmount,
          'paymentMethod': invoice.paymentMethod,
          'invoiceNumber': invoice.invoiceNumber,
        },
        items: itemsMaps,
        paymentMethod: invoice.paymentMethod ?? 'cash',
        ledgerDao: widget.db.ledgerDao,
        invoiceDao: widget.db.invoiceDao,
        customerDao: widget.db.customerDao,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إعادة طباعة الفاتورة'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('خطأ في الطباعة: $e')));
      }
    }
  }

  Future<void> _exportExcel() async {
    try {
      final List<Map<String, dynamic>> data = [];

      for (final invoice in _invoices) {
        data.add({
          'رقم الفاتورة': invoice.invoiceNumber ?? invoice.id.toString(),
          'اسم العميل': invoice.customerName ?? 'عميل غير محدد',
          'المبلغ الإجمالي': invoice.totalAmount,
          'المدفوع': invoice.paidAmount,
          'التاريخ': DateFormat('yyyy-MM-dd HH:mm').format(invoice.date),
          'الحالة': invoice.status,
        });
      }

      await _exportService.exportToExcel(
        title: 'تقارير المبيعات',
        headers: [
          'رقم الفاتورة',
          'اسم العميل',
          'المبلغ الإجمالي',
          'المدفوع',
          'التاريخ',
          'الحالة',
        ],
        columns: [
          'رقم الفاتورة',
          'اسم العميل',
          'المبلغ الإجمالي',
          'المدفوع',
          'التاريخ',
          'الحالة',
        ],
        data: data,
        fileName:
            'sales_report_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('خطأ في الطباعة: $e')));
      }
    }
  }

  Future<void> _showReturnDialog(Invoice invoice) async {
    try {
      final itemsWithProducts = await widget.db.invoiceDao
          .getItemsWithProductsByInvoice(invoice.id);

      if (itemsWithProducts.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('لا توجد منتجات في هذه الفاتورة')),
          );
        }
        return;
      }

      final result = await showDialog<bool>(
        context: context,
        builder: (ctx) => _ReturnDialog(
          invoice: invoice,
          db: widget.db,
          itemsWithProducts: itemsWithProducts,
        ),
      );

      if (result == true && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم تسجيل المرتجع بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في معالجة المرتجع: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final grandTotal = _filteredInvoices.fold(
      0.0,
      (sum, invoice) => sum + invoice.totalAmount,
    );

    return Scaffold(
      backgroundColor: Color(0xFF121212), // Dark background
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('تقارير المبيعات'),
        backgroundColor: Color(0xFF1E1E2C), // Dark app bar
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Controls
            Card(
              color: Color(0xFF1E1E2C), // Dark theme for controls
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    // Search field
                    TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'البحث عن فاتورة (رقم، عميل، مبلغ)',
                        hintStyle: TextStyle(color: Colors.white54),
                        prefixIcon: Icon(Icons.search, color: Colors.white54),
                        filled: true,
                        fillColor: Color(0xFF252535),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.grey.shade600),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.grey.shade600),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.purple),
                        ),
                      ),
                      style: TextStyle(color: Colors.white),
                    ),
                    const SizedBox(height: 16),
                    // Date range and export buttons
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => _selectDateRange(context),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey.shade600),
                                borderRadius: BorderRadius.circular(8),
                                color: Color(0xFF252535),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.date_range,
                                    color: Colors.purple,
                                  ),
                                  const Gap(8),
                                  Text(
                                    '${DateFormat('yyyy/MM/dd').format(_startDate)} - ${DateFormat('yyyy/MM/dd').format(_endDate)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const Gap(16),
                        ElevatedButton.icon(
                          onPressed: _exportPDF,
                          icon: const Icon(Icons.picture_as_pdf),
                          label: Text(context.l10n.pdf_label),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                          ),
                        ),
                        const Gap(8),
                        ElevatedButton.icon(
                          onPressed: _printThermalReceipt,
                          icon: const Icon(Icons.print),
                          label: const Text('طباعة حرارية'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                          ),
                        ),
                        const Gap(8),
                        ElevatedButton.icon(
                          onPressed: _exportExcel,
                          icon: const Icon(Icons.table_chart),
                          label: Text(context.l10n.excel_label),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const Gap(16),

            // Grand Total Card
            Padding(
              padding: const EdgeInsets.all(16),
              child: Card(
                color: Color(0xFF1E1E2C), // Dark theme for total card
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'الإجمالي الكلي',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${grandTotal.toStringAsFixed(2)} جنيه',
                        style: const TextStyle(
                          color: Colors.greenAccent,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Data Table
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredInvoices.isEmpty
                  ? Center(
                      child: Text(
                        'لا توجد بيانات',
                        style: TextStyle(color: Colors.white54),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _filteredInvoices.length,
                      itemBuilder: (context, index) {
                        final invoice = _filteredInvoices[index];
                        return _InvoiceExpansionTile(
                          invoice: invoice,
                          db: widget.db,
                          onPrint: () => _printIndividualInvoice(invoice),
                          onReturn: () => _showReturnDialog(invoice),
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

class _InvoiceExpansionTile extends StatefulWidget {
  final Invoice invoice;
  final AppDatabase db;
  final VoidCallback onPrint;
  final VoidCallback onReturn;

  const _InvoiceExpansionTile({
    required this.invoice,
    required this.db,
    required this.onPrint,
    required this.onReturn,
  });

  @override
  State<_InvoiceExpansionTile> createState() => _InvoiceExpansionTileState();
}

class _InvoiceExpansionTileState extends State<_InvoiceExpansionTile> {
  bool _isExpanded = false;
  List<(InvoiceItem, Product?)> _invoiceItems = [];
  bool _isLoadingItems = false;

  Future<void> _loadInvoiceItems() async {
    if (_isExpanded && _invoiceItems.isEmpty) {
      setState(() => _isLoadingItems = true);
      try {
        final items = await widget.db.invoiceDao.getItemsWithProductsByInvoice(
          widget.invoice.id,
        );
        setState(() {
          _invoiceItems = items;
          _isLoadingItems = false;
        });
      } catch (e) {
        setState(() => _isLoadingItems = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error loading invoice items: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: Color(0xFF1E1E2C), // Dark theme matching screenshot
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: Colors.purple.withValues(alpha: 0.1),
          child: Text(
            widget.invoice.invoiceNumber?.substring(0, 1) ?? '#',
            style: const TextStyle(
              color: Colors.purple,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          widget.invoice.invoiceNumber ?? widget.invoice.id.toString(),
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white, // White text for dark theme
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.invoice.customerName ?? 'عميل غير محدد',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 4),
            Text(
              DateFormat('yyyy-MM-dd HH:mm').format(widget.invoice.date),
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${widget.invoice.totalAmount.toStringAsFixed(2)} ج.م',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.greenAccent, // Green accent for dark theme
                  ),
                ),
                Text(
                  '${widget.invoice.paidAmount.toStringAsFixed(2)} ج.م',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.print, size: 20, color: Colors.orange),
              onPressed: widget.onPrint,
              tooltip: 'طباعة الفاتورة',
            ),
            IconButton(
              icon: const Icon(Icons.undo, size: 20, color: Colors.redAccent),
              onPressed: widget.onReturn,
              tooltip: 'مرتجع',
            ),
          ],
        ),
        onExpansionChanged: (expanded) {
          setState(() => _isExpanded = expanded);
          if (expanded) {
            _loadInvoiceItems();
          }
        },
        children: [
          if (_isLoadingItems)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_invoiceItems.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('لا توجد منتجات في هذه الفاتورة'),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Color(
                  0xFF252535,
                ), // Slightly lighter dark for expanded content
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(8),
                  bottomRight: Radius.circular(8),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'تفاصيل المنتجات',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 12),
                  DataTable(
                    headingRowColor: WidgetStateProperty.all(
                      Colors.grey.withValues(alpha: 0.2),
                    ),
                    dataRowColor: WidgetStateProperty.all(Colors.transparent),
                    columns: const [
                      DataColumn(
                        label: Text(
                          'اسم المنتج',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      DataColumn(
                        label: Text(
                          'الكمية',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      DataColumn(
                        label: Text(
                          'سعر الوحدة',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      DataColumn(
                        label: Text(
                          'الإجمالي',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                    rows: _invoiceItems.map((itemWithProduct) {
                      final item = itemWithProduct.$1;
                      final product = itemWithProduct.$2;
                      final unitPrice = item.quantity > 0
                          ? item.price / item.quantity
                          : 0.0;

                      return DataRow(
                        cells: [
                          DataCell(
                            Text(
                              product?.name ?? 'منتج ${item.productId}',
                              style: const TextStyle(color: Colors.white70),
                            ),
                          ),
                          DataCell(
                            Text(
                              item.quantity.toString(),
                              style: const TextStyle(color: Colors.white70),
                            ),
                          ),
                          DataCell(
                            Text(
                              '${unitPrice.toStringAsFixed(2)} ج.م',
                              style: const TextStyle(color: Colors.white70),
                            ),
                          ),
                          DataCell(
                            Text(
                              '${item.price.toStringAsFixed(2)} ج.م',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.greenAccent,
                              ),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      ElevatedButton.icon(
                        onPressed: widget.onPrint,
                        icon: const Icon(Icons.print),
                        label: const Text('طباعة الفاتورة'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ReturnDialog extends StatefulWidget {
  final Invoice invoice;
  final AppDatabase db;
  final List<(InvoiceItem, Product?)> itemsWithProducts;

  const _ReturnDialog({
    required this.invoice,
    required this.db,
    required this.itemsWithProducts,
  });

  @override
  State<_ReturnDialog> createState() => _ReturnDialogState();
}

class _ReturnDialogState extends State<_ReturnDialog> {
  late Map<int, int> _returnQty;
  String _reason = 'تالف';
  bool _processing = false;

  @override
  void initState() {
    super.initState();
    _returnQty = {
      for (final entry in widget.itemsWithProducts)
        entry.$1.productId: 0,
    };
  }

  double get _totalReturn {
    double total = 0;
    for (final entry in widget.itemsWithProducts) {
      final item = entry.$1;
      final qty = _returnQty[item.productId] ?? 0;
      if (qty > 0) {
        total += qty * (item.quantity > 0 ? item.price / item.quantity : 0);
      }
    }
    return total;
  }

  bool get _hasItems => _returnQty.values.any((q) => q > 0);

  Future<void> _processReturn() async {
    if (!_hasItems) return;
    setState(() => _processing = true);

    try {
      final returnItems = <SalesReturnItemsCompanion>[];
      for (final entry in widget.itemsWithProducts) {
        final item = entry.$1;
        final product = entry.$2;
        final qty = _returnQty[item.productId] ?? 0;
        if (qty <= 0) continue;
        returnItems.add(
          SalesReturnItemsCompanion.insert(
            returnId: 0,
            productId: item.productId,
            productName: product?.name ?? 'منتج ${item.productId}',
            quantity: qty,
            unitPrice: item.quantity > 0 ? item.price / item.quantity : 0,
            totalPrice: qty * (item.quantity > 0 ? item.price / item.quantity : 0),
          ),
        );
      }

      final returnDao = SalesReturnsDao(widget.db);
      final returnCompanion = SalesReturnsCompanion.insert(
        returnNumber: 'RTR-${widget.invoice.invoiceNumber ?? widget.invoice.id}-${DateTime.now().millisecondsSinceEpoch}',
        originalInvoiceId: widget.invoice.id,
        customerId: (widget.invoice.customerId?.isNotEmpty == true) ? drift.Value(widget.invoice.customerId!) : const drift.Value.absent(),
        customerName: widget.invoice.customerName ?? 'عميل غير محدد',
        returnDate: DateTime.now(),
        totalAmount: _totalReturn,
        returnReason: _reason,
        notes: const drift.Value.absent(),
        status: const drift.Value('completed'),
        processedBy: const drift.Value.absent(),
      );

      await returnDao.processReturn(
        returnCompanion: returnCompanion,
        items: returnItems,
      );

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _processing = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
        title: const Text('مرتجع فاتورة'),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('الفاتورة: ${widget.invoice.invoiceNumber ?? widget.invoice.id}'),
              const SizedBox(height: 8),
              Text('العميل: ${widget.invoice.customerName ?? 'غير محدد'}'),
              const SizedBox(height: 16),
              const Text('اختر الكميات المرتجعة:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: widget.itemsWithProducts.map((entry) {
                      final item = entry.$1;
                      final product = entry.$2;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(product?.name ?? 'منتج ${item.productId}'),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 80,
                              child: TextField(
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  hintText: 'الكمية (${item.quantity})',
                                  isDense: true,
                                  border: const OutlineInputBorder(),
                                ),
                                onChanged: (v) {
                                  final qty = int.tryParse(v) ?? 0;
                                  setState(() {
                                    _returnQty[item.productId] = qty.clamp(0, item.quantity);
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              if (_hasItems) ...[
                const SizedBox(height: 16),
                Text(
                  'إجمالي المرتجع: ${_totalReturn.toStringAsFixed(2)} ج.م',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.red,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _reason,
                decoration: const InputDecoration(
                  labelText: 'سبب المرتجع',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(value: 'تالف', child: Text('تالف')),
                  DropdownMenuItem(value: 'خطأ في الفاتورة', child: Text('خطأ في الفاتورة')),
                  DropdownMenuItem(value: 'استبدال', child: Text('استبدال')),
                  DropdownMenuItem(value: 'أخرى', child: Text('أخرى')),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _reason = v);
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _processing ? null : () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: _hasItems && !_processing ? _processReturn : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: _processing
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('تأكيد المرتجع'),
          ),
        ],
      );
  }
}
