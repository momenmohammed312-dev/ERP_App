import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' as drift;
import 'package:pos_offline_desktop/ui/customer/services/enhanced_customer_statement_generator.dart';
import 'package:pos_offline_desktop/core/services/unified_print_service.dart'
    as ups;
import 'package:pos_offline_desktop/core/services/settings_service.dart';
import 'package:pos_offline_desktop/core/database/dao/ledger_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/customer_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/invoice_dao.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';

class PrinterService {
  static const String _branding = 'Developed by MO2';
  static pw.Font? _arabicFont;
  static pw.Font? _arabicBoldFont;
  static pw.Font? _latinFont;

  static Future<void> _loadFonts() async {
    if (_arabicFont == null) {
      try {
        // Load Arabic fonts
        final arabicFontData = await rootBundle.load(
          'assets/fonts/NotoNaskhArabic-Regular.ttf',
        );
        _arabicFont = pw.Font.ttf(arabicFontData);
        _arabicBoldFont =
            _arabicFont; // Use regular font for bold since bold version doesn't exist

        final latinFontData = await rootBundle.load(
          'assets/fonts/DejaVuSans.ttf',
        );
        _latinFont = pw.Font.ttf(latinFontData);
      } catch (e) {
        debugPrint('Failed to load fonts: $e');
        // Fallback to built-in fonts
        _arabicFont = pw.Font.times();
        _arabicBoldFont = pw.Font.timesBold();
        _latinFont = pw.Font.courier(); // Courier has better Unicode support
      }
    }
  }

  // Helper method to get unified theme
  static pw.ThemeData _getTheme() {
    return pw.ThemeData.withFont(base: _arabicFont!, bold: _arabicBoldFont!);
  }

  // Helper method to create TextStyle with proper font fallback
  static pw.TextStyle _getTextStyle({
    double? fontSize,
    pw.FontWeight? fontWeight,
    PdfColor? color,
    bool isBold = false,
  }) {
    return pw.TextStyle(
      font: isBold ? _arabicBoldFont : _arabicFont,
      fontFallback: [_latinFont!],
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
    );
  }

  static Future<void> printInvoice({
    required Map<String, dynamic> invoice,
    required List<Map<String, dynamic>> items,
    required String paymentMethod,
    required bool isThermal,
    LedgerDao? ledgerDao,
    InvoiceDao? invoiceDao,
    CustomerDao? customerDao,
    Printer? printer,
    double previousBalance = 0.0,
    String? customerId,
  }) async {
    if (isThermal && paymentMethod.toLowerCase() == 'cash') {
      await printThermalReceipt(
        items: items,
        totalAmount: invoice['totalAmount'] ?? 0.0,
        paidAmount: invoice['paidAmount'],
        remainingAmount: invoice['remainingAmount'],
        paymentMethod: paymentMethod,
        receiptNumber: invoice['id']?.toString() ?? '1',
        date: invoice['date'] ?? DateTime.now(),
        customerName: invoice['customerName'] ?? 'عميل نقدي',
        printer: printer,
      );
    } else if (ledgerDao != null && invoiceDao != null && customerDao != null) {
      // Create a temporary database instance for the statement
      final db = AppDatabase(drift.DatabaseConnection(NativeDatabase.memory()));

      await printAccountStatement(
        entityName: invoice['customerName'] ?? 'عميل',
        entityType: 'Customer',
        entityId: invoice['customerId'] ?? invoice['id']?.toString() ?? '1',
        fromDate: DateTime.now().subtract(const Duration(days: 30)),
        toDate: DateTime.now(),
        db: db,
        previousBalance: previousBalance,
      );
    } else {
      throw Exception(
        'LedgerDao, InvoiceDao, and CustomerDao required for credit invoice printing',
      );
    }
  }

  // Enhanced printing methods for new invoice system

  static Future<void> printA4Invoice({
    required Map<String, dynamic> invoice,
    required List<Map<String, dynamic>> items,
    Customer? customer,
  }) async {
    await _loadFonts();

    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20 * PdfPageFormat.mm),
        theme: _getTheme(),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'INVOICE',
                        style: _getTextStyle(
                          fontSize: 24,
                          fontWeight: pw.FontWeight.bold,
                          isBold: true,
                        ),
                      ),
                      pw.SizedBox(height: 5),
                      pw.Text(
                        'Invoice #: ${invoice['invoiceNumber']}',
                        style: _getTextStyle(fontSize: 12),
                      ),
                      pw.Text(
                        'Date: ${DateFormat('yyyy-MM-dd HH:mm').format(invoice['date'])}',
                        style: _getTextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                  pw.Text(
                    'Developed by MO2',
                    style: _getTextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                      isBold: true,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 20),

              // Customer info
              if (customer != null) ...[
                pw.Container(
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey300),
                    borderRadius: pw.BorderRadius.circular(5),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Customer: ${customer.name}',
                        style: _getTextStyle(
                          fontSize: 14,
                          fontWeight: pw.FontWeight.bold,
                          isBold: true,
                        ),
                      ),
                      if (customer.phone?.isNotEmpty == true)
                        pw.Text(
                          'Phone: ${customer.phone}',
                          style: _getTextStyle(fontSize: 12),
                        ),
                      if (customer.address?.isNotEmpty == true)
                        pw.Text(
                          'Address: ${customer.address}',
                          style: _getTextStyle(fontSize: 12),
                        ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 20),
              ],

              // Items table
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300),
                columnWidths: {
                  0: const pw.FixedColumnWidth(60), // Product
                  1: const pw.FixedColumnWidth(30), // Quantity
                  2: const pw.FixedColumnWidth(30), // Unit
                  3: const pw.FixedColumnWidth(40), // Price
                  4: const pw.FixedColumnWidth(30), // Discount
                  5: const pw.FixedColumnWidth(40), // Total
                },
                children: [
                  // Header
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(
                      color: PdfColors.grey200,
                    ),
                    children: [
                      _tableCell('Product', isHeader: true),
                      _tableCell('Qty', isHeader: true),
                      _tableCell('Unit', isHeader: true),
                      _tableCell('Price', isHeader: true),
                      _tableCell('Discount', isHeader: true),
                      _tableCell('Total', isHeader: true),
                    ],
                  ),
                  // Items
                  ...items.map(
                    (item) => pw.TableRow(
                      children: [
                        _tableCell(item['productName']),
                        _tableCell('${item['quantity']}'),
                        _tableCell(item['unit']),
                        _tableCell(item['unitPrice'].toStringAsFixed(2)),
                        _tableCell(item['discount'].toStringAsFixed(2)),
                        _tableCell(item['lineTotal'].toStringAsFixed(2)),
                      ],
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 20),

              // Totals
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey300),
                  borderRadius: pw.BorderRadius.circular(5),
                ),
                child: pw.Column(
                  children: [
                    _totalRow('Subtotal:', invoice['totalAmount']),
                    if (invoice['paidAmount'] > 0)
                      _totalRow('Paid Amount:', invoice['paidAmount']),
                    _totalRow(
                      'Remaining:',
                      invoice['remainingAmount'],
                      isBold: true,
                      color: invoice['remainingAmount'] > 0
                          ? PdfColors.red
                          : PdfColors.green,
                    ),
                  ],
                ),
              ),

              pw.SizedBox(height: 20),

              // Footer
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Payment Method: ${invoice['paymentMethod']}',
                      style: _getTextStyle(fontSize: 12),
                    ),
                    if (invoice['notes']?.isNotEmpty == true) ...[
                      pw.SizedBox(height: 5),
                      pw.Text(
                        'Notes: ${invoice['notes']}',
                        style: _getTextStyle(fontSize: 12),
                      ),
                    ],
                    pw.SizedBox(height: 10),
                    pw.Text(
                      'Developed by MO2',
                      style: _getTextStyle(
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                        isBold: true,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );

    try {
      final pdfData = await pdf.save();
      await Printing.sharePdf(
        bytes: pdfData,
        filename: 'invoice_${invoice['invoiceNumber']}',
      );
    } catch (e) {
      throw Exception('فشل في الطباعة: $e');
    }
  }

  static pw.Widget _tableCell(String text, {bool isHeader = false}) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(5),
      child: pw.Text(
        text,
        style: _getTextStyle(fontSize: isHeader ? 10 : 8, isBold: isHeader),
      ),
    );
  }

  static pw.Widget _totalRow(
    String label,
    double amount, {
    bool isBold = false,
    PdfColor? color,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: _getTextStyle(
              fontSize: 12,
              fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
              isBold: isBold,
            ),
          ),
          pw.Text(
            amount.toStringAsFixed(2),
            style: _getTextStyle(
              fontSize: 12,
              fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: color,
              isBold: isBold,
            ),
          ),
        ],
      ),
    );
  }

  static Future<void> autoPrintInvoice({
    required Map<String, dynamic> invoice,
    required List<Map<String, dynamic>> items,
    required String paymentMethod,
    LedgerDao? ledgerDao,
    InvoiceDao? invoiceDao,
    CustomerDao? customerDao,
    String? overridePrinterName,
    double previousBalance = 0.0,
    String? customerId,
  }) async {
    try {
      // Determine if we should use thermal or A4 based on payment method
      final isThermal = paymentMethod.toLowerCase() == 'cash';

      // Resolve preferred printer: override -> saved setting
      final preferredName = (overridePrinterName?.trim().isNotEmpty == true)
          ? overridePrinterName
          : (isThermal
                ? await SettingsService.getThermalPrinter()
                : await SettingsService.getA4Printer());

      Printer? matchedPrinter;
      if (preferredName != null && preferredName.isNotEmpty) {
        try {
          final available = await Printing.listPrinters();
          for (final p in available) {
            if (p.name.trim().toLowerCase() ==
                preferredName.trim().toLowerCase()) {
              matchedPrinter = p;
              break;
            }
          }
        } catch (_) {
          matchedPrinter = null;
        }
      }

      await printInvoice(
        invoice: invoice,
        items: items,
        paymentMethod: paymentMethod,
        isThermal: isThermal,
        ledgerDao: ledgerDao,
        invoiceDao: invoiceDao,
        customerDao: customerDao,
        printer: matchedPrinter,
        previousBalance: previousBalance,
        customerId: customerId,
      );
    } catch (e) {
      throw Exception('فشل في الطباعة التلقائية: $e');
    }
  }

  static Future<void> printThermalReceipt({
    required List<Map<String, dynamic>> items,
    required double totalAmount,
    required String paymentMethod,
    required String receiptNumber,
    required DateTime date,
    required String customerName,
    double? paidAmount,
    double? remainingAmount,
    Printer? printer,
  }) async {
    await _loadFonts();

    final font = _arabicFont ?? _latinFont ?? pw.Font.helvetica();
    final boldFont = _arabicBoldFont ?? _latinFont ?? font;

    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        margin: const pw.EdgeInsets.all(16),
        theme: _getTheme(),
        build: (pw.Context context) => _buildThermalReceiptContent(
          items: items,
          totalAmount: totalAmount,
          paymentMethod: paymentMethod,
          receiptNumber: receiptNumber,
          date: date,
          customerName: customerName,
          paidAmount: paidAmount,
          remainingAmount: remainingAmount,
          font: font,
          boldFont: boldFont,
        ),
      ),
    );

    try {
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
        name: 'Thermal Receipt - $receiptNumber',
        format: PdfPageFormat.roll80,
        usePrinterSettings: true,
      );
    } catch (e) {
      // Fallback to A4 if thermal printing fails
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
        name: 'Receipt - $receiptNumber',
        format: PdfPageFormat.a4,
        usePrinterSettings: true,
      );
    }
  }

  static pw.Widget _buildExpenseReceiptContentFromMap({
    required Map<String, dynamic> expense,
    required pw.Font font,
    required pw.Font boldFont,
  }) {
    return pw.Column(
      children: [
        // Header
        pw.Center(
          child: pw.Column(
            children: [
              pw.Text(
                'إيصال مصروف',
                style: _getTextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                  isBold: true,
                ),
                textDirection: pw.TextDirection.rtl,
              ),
              pw.Text(_branding, style: _getTextStyle(fontSize: 10)),
              pw.SizedBox(height: 8),
              pw.Text('================================'),
            ],
          ),
        ),

        pw.SizedBox(height: 8),

        // Expense info
        pw.Directionality(
          textDirection: pw.TextDirection.rtl,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (expense['receiptNumber'] != null)
                pw.Text('رقم الإيصال: ${expense['receiptNumber']}'),
              pw.Text(
                'التاريخ: ${DateFormat('yyyy/MM/dd HH:mm').format(expense['date'])}',
              ),
              pw.Text(
                'طريقة الدفع: ${_getPaymentMethodName(expense['paymentMethod'])}',
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text('--------------------------------'),

        // Description
        if (expense['description']?.toString().isNotEmpty == true) ...[
          pw.Text(
            'الوصف:',
            style: _getTextStyle(fontWeight: pw.FontWeight.bold, isBold: true),
            textDirection: pw.TextDirection.rtl,
          ),
          pw.Text(
            expense['description'].toString(),
            textDirection: pw.TextDirection.rtl,
          ),
          pw.Text('--------------------------------'),
        ],

        // Total
        pw.Container(
          alignment: pw.Alignment.center,
          child: pw.Text(
            'المبلغ: ${_formatCurrency(expense['amount'])}',
            style: _getTextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
              isBold: true,
            ),
            textDirection: pw.TextDirection.rtl,
          ),
        ),

        pw.SizedBox(height: 8),

        // Footer
        pw.Center(
          child: pw.Column(
            children: [
              pw.Text('================================'),
              pw.Text('شكراً لك', style: _getTextStyle(fontSize: 10)),
              pw.Text(_branding, style: _getTextStyle(fontSize: 8)),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildThermalReceiptContent({
    required List<Map<String, dynamic>> items,
    required double totalAmount,
    required String paymentMethod,
    required String receiptNumber,
    required DateTime date,
    required String customerName,
    required pw.Font font,
    required pw.Font boldFont,
    double? paidAmount,
    double? remainingAmount,
  }) {
    return pw.Column(
      children: [
        // Header
        pw.Center(
          child: pw.Column(
            children: [
              pw.Text(
                'فاتورة ضريبية مبسطة',
                style: _getTextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                  isBold: true,
                ),
                textDirection: pw.TextDirection.rtl,
              ),
              pw.Text(_branding, style: _getTextStyle(fontSize: 10)),
              pw.SizedBox(height: 8),
              pw.Text('================================'),
            ],
          ),
        ),

        pw.SizedBox(height: 8),

        // Receipt info
        pw.Directionality(
          textDirection: pw.TextDirection.rtl,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('رقم الإيصال: $receiptNumber'),
              pw.Text(
                'التاريخ: ${DateFormat('yyyy/MM/dd HH:mm').format(date)}',
              ),
              pw.Text('العميل: $customerName'),
              pw.Text('طريقة الدفع: ${_getPaymentMethodName(paymentMethod)}'),
            ],
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text('--------------------------------'),

        // Items
        pw.Text(
          'المنتجات',
          style: _getTextStyle(fontWeight: pw.FontWeight.bold, isBold: true),
          textDirection: pw.TextDirection.rtl,
        ),
        pw.Text('--------------------------------'),

        ...items.map((item) {
          final name =
              item['productName']?.toString() ??
              item['name']?.toString() ??
              'منتج غير معروف';
          final quantity = (item['quantity'] is num)
              ? (item['quantity'] as num).toDouble()
              : 1.0;
          final price = (item['price'] is num)
              ? (item['price'] as num).toDouble()
              : 0.0;

          // Calculate unit price if it's zero or missing
          double unitPrice = price;
          if (unitPrice <= 0.0 && quantity > 0.0) {
            final itemTotal = (item['total'] is num)
                ? (item['total'] as num).toDouble()
                : quantity * price; // Fallback to calculated total
            unitPrice = itemTotal / quantity;
          }

          final total = quantity * unitPrice;

          return pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('$name x$quantity', style: _getTextStyle()),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      '${_formatCurrency(unitPrice)} للقطعة',
                      style: _getTextStyle(),
                    ),
                    pw.Text(_formatCurrency(total), style: _getTextStyle()),
                  ],
                ),
                pw.SizedBox(height: 2),
              ],
            ),
          );
        }),

        pw.Text('--------------------------------'),

        // Total
        pw.Container(
          alignment: pw.Alignment.center,
          child: pw.Column(
            children: [
              pw.Text(
                'الإجمالي: ${_formatCurrency(totalAmount)}',
                style: _getTextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                  isBold: true,
                ),
                textDirection: pw.TextDirection.rtl,
              ),
              if (paidAmount != null && paidAmount > 0 && paidAmount != totalAmount) ...[
                pw.SizedBox(height: 4),
                pw.Text(
                  'المدفوع: ${_formatCurrency(paidAmount)}',
                  style: _getTextStyle(fontSize: 14),
                  textDirection: pw.TextDirection.rtl,
                ),
                pw.Text(
                  'المتبقي: ${_formatCurrency(remainingAmount ?? (totalAmount - paidAmount))}',
                  style: _getTextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                    isBold: true,
                  ),
                  textDirection: pw.TextDirection.rtl,
                ),
              ],
            ],
          ),
        ),

        pw.SizedBox(height: 8),
        pw.Text('--------------------------------'),

        // Footer
        pw.Center(
          child: pw.Column(
            children: [
              pw.Text(
                'شكراً لتعاملكم معنا!',
                textDirection: pw.TextDirection.rtl,
                style: _getTextStyle(),
              ),
              pw.Text(_branding, style: _getTextStyle()),
            ],
          ),
        ),
      ],
    );
  }

  static String _getPaymentMethodName(String method) {
    switch (method.toLowerCase()) {
      case 'cash':
        return 'نقدي';
      case 'visa':
        return 'فيزا';
      case 'bank':
        return 'تحويل بنكي';
      case 'credit':
        return 'آجل';
      default:
        return method;
    }
  }

  static Future<void> printAccountStatement({
    required String entityName,
    required String entityType,
    required String entityId,
    required DateTime fromDate,
    required DateTime toDate,
    required AppDatabase db,
    Printer? printer,
    double previousBalance = 0.0,
  }) async {
    // Use enhanced customer statement generator
    await EnhancedCustomerStatementGenerator.generateStatement(
      db: db,
      customerId: entityId,
      customerName: entityName,
      fromDate: fromDate,
      toDate: toDate,
      openingBalance: previousBalance,
      currentBalance:
          previousBalance, // This would need to be calculated properly
    );
  }

  static Future<void> printCustomerStatement({
    required String customerId,
    required String customerName,
    required DateTime startDate,
    required DateTime endDate,
    required List invoices,
    LedgerDao? ledgerDao,
    InvoiceDao? invoiceDao,
    CustomerDao? customerDao,
  }) async {
    if (ledgerDao == null) {
      throw Exception('LedgerDao required for customer statement printing');
    }

    // Resolve preferred A4/PDF printer from settings (if any)
    final preferred = await SettingsService.getA4Printer();
    Printer? matchedPrinter;
    if (preferred != null && preferred.isNotEmpty) {
      try {
        final available = await Printing.listPrinters();
        for (final p in available) {
          if (p.name.trim().toLowerCase() == preferred.trim().toLowerCase()) {
            matchedPrinter = p;
            break;
          }
        }
      } catch (_) {
        matchedPrinter = null;
      }
    }

    await printAccountStatement(
      entityName: customerName,
      entityType: 'Customer',
      entityId: customerId,
      fromDate: startDate,
      toDate: endDate,
      db: AppDatabase(drift.DatabaseConnection(NativeDatabase.memory())),
    );
  }

  static Future<List<Map<String, dynamic>>> getAvailablePrinters() async {
    final printers = await Printing.listPrinters();

    return printers
        .map(
          (printer) => {
            'name': printer.name,
            'isDefault': printer.isDefault,
            'isAvailable': printer.isAvailable,
            'type': _classifyPrinter(printer.name),
          },
        )
        .toList();
  }

  static String _classifyPrinter(String printerName) {
    final name = printerName.toLowerCase();

    if (name.contains('thermal') ||
        name.contains('receipt') ||
        name.contains('pos') ||
        name.contains('ticket')) {
      return 'Thermal';
    } else if (name.contains('pdf') ||
        name.contains('microsoft print to pdf')) {
      return 'PDF';
    } else {
      return 'A4';
    }
  }

  static Future<void> printThermalReceiptFromInvoice({
    required Map<String, dynamic> invoice,
    required List<Map<String, dynamic>> items,
  }) async {
    await printThermalReceipt(
      items: items,
      totalAmount: invoice['totalAmount'] ?? 0.0,
      paymentMethod: invoice['paymentMethod'] ?? 'cash',
      receiptNumber:
          invoice['invoiceNumber'] ??
          'INV-${DateTime.now().millisecondsSinceEpoch}',
      date: invoice['date'] ?? DateTime.now(),
      customerName: invoice['customerName'] ?? 'عميل',
    );
  }

  static Future<void> printExpenseReceipt({
    required Map<String, dynamic> expense,
    Printer? printer,
  }) async {
    await _loadFonts();

    final font = _arabicFont ?? _latinFont ?? pw.Font.helvetica();
    final boldFont = _arabicBoldFont ?? _latinFont ?? font;

    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        margin: const pw.EdgeInsets.all(16),
        theme: _getTheme(),
        build: (pw.Context context) => _buildExpenseReceiptContentFromMap(
          expense: expense,
          font: font,
          boldFont: boldFont,
        ),
      ),
    );

    try {
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
        name: 'Expense Receipt - ${expense['receiptNumber'] ?? 'Unknown'}',
        format: PdfPageFormat.roll80,
        usePrinterSettings: true,
      );
    } catch (e) {
      // Fallback to A4 if thermal printing fails
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
        name: 'Expense Receipt - ${expense['receiptNumber'] ?? 'Unknown'}',
        format: PdfPageFormat.a4,
        usePrinterSettings: true,
      );
    }
  }

  static Future<void> printExpense({
    required Expense expense,
    Printer? printer,
  }) async {
    await printExpenseReceipt(
      expense: {
        'description': expense.description,
        'amount': expense.amount,
        'date': expense.date,
        'paymentMethod': expense.paymentMethod,
        'receiptNumber': expense.receiptNumber,
      },
      printer: printer,
    );
  }

  static Future<void> printShiftReport({
    required DateTime date,
    required DateTime startTime,
    required DateTime endTime,
    required double openingCash,
    required double totalRevenue,
    required double totalExpenses,
    required double expectedCash,
    required double actualCash,
    required double variance,
    Printer? printer,
  }) async {
    await _loadFonts();
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        margin: pw.EdgeInsets.all(12),
        theme: _getTheme(),
        build: (pw.Context context) {
          return pw.Column(
            children: [
              pw.Center(
                child: pw.Column(
                  children: [
                    pw.Text(
                      'تقرير الوردية / Shift Report',
                      style: _getTextStyle(fontSize: 14, isBold: true),
                      textDirection: pw.TextDirection.rtl,
                    ),
                    pw.Text(_branding, style: _getTextStyle(fontSize: 8)),
                    pw.SizedBox(height: 8),
                  ],
                ),
              ),
              pw.Directionality(
                textDirection: pw.TextDirection.rtl,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'التاريخ: ${DateFormat('yyyy/MM/dd').format(date)}',
                      style: _getTextStyle(fontSize: 10),
                    ),
                    pw.Text(
                      'البداية: ${DateFormat('HH:mm').format(startTime)}',
                      style: _getTextStyle(fontSize: 10),
                    ),
                    pw.Text(
                      'النهاية: ${DateFormat('HH:mm').format(endTime)}',
                      style: _getTextStyle(fontSize: 10),
                    ),
                    pw.Text(
                      '--------------------------------',
                      style: _getTextStyle(),
                    ),
                    _shiftRow('الرصيد الافتتاحي:', openingCash),
                    _shiftRow('إجمالي الإيرادات:', totalRevenue),
                    _shiftRow('إجمالي المصروفات:', totalExpenses),
                    pw.Text(
                      '--------------------------------',
                      style: _getTextStyle(),
                    ),
                    _shiftRow('الرصيد المتوقع:', expectedCash, isBold: true),
                    _shiftRow('الرصيد الفعلي:', actualCash, isBold: true),
                    pw.Text(
                      '--------------------------------',
                      style: _getTextStyle(),
                    ),
                    _shiftRow(
                      'العجز / الزيادة:',
                      variance,
                      isBold: true,
                      color: variance < 0
                          ? PdfColors.red700
                          : PdfColors.green700,
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),
              pw.Center(
                child: pw.Text(
                  'تمت الطباعة في: ${DateFormat('yyyy/MM/dd HH:mm').format(DateTime.now())}',
                  style: _getTextStyle(fontSize: 8),
                  textDirection: pw.TextDirection.rtl,
                ),
              ),
            ],
          );
        },
      ),
    );

    try {
      await Printing.layoutPdf(
        onLayout: (format) async => pdf.save(),
        name: 'Shift Report - ${DateFormat('yyyyMMdd').format(date)}',
        format: PdfPageFormat.roll80,
      );
    } catch (e) {
      debugPrint('Shift report print error: $e');
    }
  }

  static pw.Widget _shiftRow(
    String label,
    double amount, {
    bool isBold = false,
    PdfColor? color,
  }) {
    return pw.Container(
      padding: pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: _getTextStyle(fontSize: 10, isBold: isBold),
            textDirection: pw.TextDirection.rtl,
          ),
          pw.Text(
            _formatCurrency(amount),
            style: _getTextStyle(fontSize: 10, isBold: isBold, color: color),
            textDirection: pw.TextDirection.rtl,
          ),
        ],
      ),
    );
  }

  static String _formatCurrency(double amount) {
    return NumberFormat.currency(
      locale: 'en_EG',
      symbol: 'ج.م',
      decimalDigits: 2,
    ).format(amount);
  }

  /// Print expenses report
  static Future<void> printExpensesReport(
    Map<String, dynamic> reportData,
  ) async {
    try {
      debugPrint('Printing expenses report...');

      final pdf = pw.Document();
      await _loadFonts();
      final arabicFont = _arabicFont ?? pw.Font.helvetica();

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(20),
          textDirection: pw.TextDirection.rtl,
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Header
                pw.Container(
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.black),
                  ),
                  child: pw.Column(
                    children: [
                      pw.Text(
                        reportData['title'] ?? 'تقرير المصروفات',
                        style: pw.TextStyle(
                          font: _arabicFont,
                          fontSize: 18,
                          fontWeight: pw.FontWeight.bold,
                        ),
                        textDirection: pw.TextDirection.rtl,
                        textAlign: pw.TextAlign.center,
                      ),
                      pw.SizedBox(height: 5),
                      pw.Text(
                        reportData['period'] ?? '',
                        style: pw.TextStyle(font: _arabicFont, fontSize: 12),
                        textDirection: pw.TextDirection.rtl,
                        textAlign: pw.TextAlign.center,
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 20),

                // Summary
                pw.Container(
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.black),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'الإجمالي:',
                        style: pw.TextStyle(
                          font: _arabicFont,
                          fontSize: 14,
                          fontWeight: pw.FontWeight.bold,
                        ),
                        textDirection: pw.TextDirection.rtl,
                      ),
                      pw.Text(
                        _formatCurrency(reportData['total'] ?? 0.0),
                        style: pw.TextStyle(
                          font: _arabicFont,
                          fontSize: 14,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.red,
                        ),
                        textDirection: pw.TextDirection.rtl,
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 20),

                // Expenses Table
                pw.Container(
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.black),
                  ),
                  child: pw.Column(
                    children: [
                      // Table Header
                      pw.Container(
                        padding: const pw.EdgeInsets.all(8),
                        decoration: const pw.BoxDecoration(
                          color: PdfColors.grey300,
                        ),
                        child: pw.Row(
                          children: [
                            pw.Expanded(
                              flex: 2,
                              child: pw.Text(
                                'التاريخ',
                                style: pw.TextStyle(
                                  font: _arabicFont,
                                  fontSize: 10,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                                textDirection: pw.TextDirection.rtl,
                              ),
                            ),
                            pw.Expanded(
                              flex: 3,
                              child: pw.Text(
                                'الوصف',
                                style: pw.TextStyle(
                                  font: _arabicFont,
                                  fontSize: 10,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                                textDirection: pw.TextDirection.rtl,
                              ),
                            ),
                            pw.Expanded(
                              flex: 2,
                              child: pw.Text(
                                'التصنيف',
                                style: pw.TextStyle(
                                  font: _arabicFont,
                                  fontSize: 10,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                                textDirection: pw.TextDirection.rtl,
                              ),
                            ),
                            pw.Expanded(
                              flex: 2,
                              child: pw.Text(
                                'المبلغ',
                                style: pw.TextStyle(
                                  font: _arabicFont,
                                  fontSize: 10,
                                  fontWeight: pw.FontWeight.bold,
                                ),
                                textDirection: pw.TextDirection.rtl,
                                textAlign: pw.TextAlign.left,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Table Data
                      ...((reportData['expenses'] as List<dynamic>?) ?? []).map(
                        (expense) => pw.Container(
                          padding: const pw.EdgeInsets.all(8),
                          decoration: pw.BoxDecoration(
                            border: pw.Border(
                              bottom: pw.BorderSide(color: PdfColors.grey300),
                            ),
                          ),
                          child: pw.Row(
                            children: [
                              pw.Expanded(
                                flex: 2,
                                child: pw.Text(
                                  expense['date'] ?? '',
                                  style: pw.TextStyle(
                                    font: _arabicFont,
                                    fontSize: 9,
                                  ),
                                  textDirection: pw.TextDirection.rtl,
                                ),
                              ),
                              pw.Expanded(
                                flex: 3,
                                child: pw.Text(
                                  expense['description'] ?? '',
                                  style: pw.TextStyle(
                                    font: _arabicFont,
                                    fontSize: 9,
                                  ),
                                  textDirection: pw.TextDirection.rtl,
                                ),
                              ),
                              pw.Expanded(
                                flex: 2,
                                child: pw.Text(
                                  expense['category'] ?? '',
                                  style: pw.TextStyle(
                                    font: _arabicFont,
                                    fontSize: 9,
                                  ),
                                  textDirection: pw.TextDirection.rtl,
                                ),
                              ),
                              pw.Expanded(
                                flex: 2,
                                child: pw.Text(
                                  _formatCurrency(
                                    (expense['amount'] ?? 0.0).toDouble(),
                                  ),
                                  style: pw.TextStyle(
                                    font: _arabicFont,
                                    fontSize: 9,
                                    color: PdfColors.red,
                                  ),
                                  textDirection: pw.TextDirection.rtl,
                                  textAlign: pw.TextAlign.left,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 30),

                // Footer
                pw.Container(
                  padding: const pw.EdgeInsets.all(10),
                  child: pw.Column(
                    children: [
                      pw.Text(
                        'تم الطباعة في: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now())}',
                        style: pw.TextStyle(font: _arabicFont, fontSize: 10),
                        textDirection: pw.TextDirection.rtl,
                      ),
                      pw.SizedBox(height: 5),
                      pw.Text(
                        'Developed by MO2',
                        style: pw.TextStyle(
                          font: _arabicFont,
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                        ),
                        textDirection: pw.TextDirection.rtl,
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      );

      // Print the PDF
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) => pdf.save(),
        name:
            'expenses_report_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.pdf',
      );

      debugPrint('Expenses report printed successfully');
    } catch (e) {
      debugPrint('Error printing expenses report: $e');
      rethrow;
    }
  }

  // Print duplicate invoice using UnifiedPrintService
  static Future<void> printDuplicateInvoice({
    required Map<String, dynamic> invoice,
    required List<Map<String, dynamic>> items,
    required String paymentMethod,
    required LedgerDao ledgerDao,
    required InvoiceDao invoiceDao,
    required CustomerDao customerDao,
  }) async {
    try {
      // Convert items to InvoiceItem models
      final invoiceItems = items.map((item) {
        return ups.InvoiceItem(
          id: 0, // Temporary ID
          invoiceId: invoice['id'] ?? 0,
          description: item['productName'] ?? item['name'] ?? 'Product',
          unit: 'قطعة',
          quantity: item['quantity'] ?? 1,
          unitPrice: (item['price'] ?? 0.0).toDouble(),
          totalPrice: (item['total'] ?? (item['price'] * item['quantity']))
              .toDouble(),
        );
      }).toList();

      // Create store info
      final storeInfo = ups.StoreInfo(
        storeName: 'المحل التجاري',
        phone: '01234567890',
        zipCode: '12345',
        state: 'القاهرة',
      );

      // Create invoice model
      final invoiceModel = ups.Invoice(
        id: invoice['id'] ?? 0,
        invoiceNumber:
            invoice['invoiceNumber']?.toString() ?? invoice['id'].toString(),
        customerName: invoice['customerName'] ?? 'عميل نقدي',
        customerPhone: invoice['customerPhone'] ?? 'N/A',
        customerZipCode: '',
        customerState: '',
        invoiceDate: invoice['date'] ?? DateTime.now(),
        subtotal: (invoice['totalAmount'] ?? 0.0).toDouble(),
        isCreditAccount: paymentMethod.toLowerCase() != 'cash',
        previousBalance: 0.0,
        totalAmount: (invoice['totalAmount'] ?? 0.0).toDouble(),
      );

      // Create InvoiceData
      final invoiceData = ups.InvoiceData(
        invoice: invoiceModel,
        items: invoiceItems,
        storeInfo: storeInfo,
      );

      // Print using new SOP 4.0 format
      await ups.UnifiedPrintService.printToThermalPrinter(
        documentType: ups.DocumentType.salesInvoice,
        data: invoiceData,
      );
    } catch (e) {
      debugPrint('Duplicate invoice print error: $e');
    }
  }
}
