import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:excel/excel.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'dart:io';
import 'package:flutter/material.dart' show DateTimeRange;
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/utils/arabic_helper.dart';
import 'package:pos_offline_desktop/core/models/report_dtos.dart';
import 'package:pos_offline_desktop/ui/customer/services/enhanced_customer_statement_generator.dart';

class ExportService {
  static const String _branding = 'Developed by MO2';

  // Helper method to get invoice items with products
  static Future<List<Map<String, dynamic>>> _getInvoiceItemsWithProducts(
    AppDatabase db,
    int invoiceId,
  ) async {
    try {
      final items = await db.invoiceDao.getItemsWithProductsByInvoice(
        invoiceId,
      );
      return items.map((itemWithProduct) {
        final item = itemWithProduct.$1;
        final product = itemWithProduct.$2;
        final unitPrice = item.quantity > 0 ? item.price / item.quantity : 0.0;

        return {
          'productName': product?.name ?? 'منتج ${item.productId}',
          'quantity': item.quantity,
          'unitPrice': unitPrice,
          'total': item.price,
        };
      }).toList();
    } catch (e) {
      debugPrint('Error in _getInvoiceItemsWithProducts: $e');
      return [];
    }
  }

  // Helper method to build detailed description
  static String _buildDetailedDescription(List<Map<String, dynamic>> items) {
    if (items.isEmpty) return '';

    final itemDescriptions = items.map((item) {
      final name = item['productName'] as String;
      final quantity = item['quantity'] as int;
      final unitPrice = (item['unitPrice'] as double).toStringAsFixed(2);

      return '$name ($quantity × $unitPrice ج.م)';
    }).toList();

    return itemDescriptions.join(' + ');
  }

  // Generic PDF Export (Legacy / General Use)
  Future<void> exportToPDF({
    required String title,
    required List<Map<String, dynamic>> data,
    required List<String> headers,
    required List<String> columns,
    String? fileName,
  }) async {
    final pdf = pw.Document();

    // 1. Load Fonts
    pw.Font? arabicFont;
    try {
      final fontData = await rootBundle.load(
        'assets/fonts/NotoNaskhArabic-Regular.ttf',
      );
      if (fontData.lengthInBytes > 0) arabicFont = pw.Font.ttf(fontData);
    } catch (_) {}

    final latinFont = pw.Font.courier();
    final themeData = pw.ThemeData.withFont(
      base: arabicFont ?? latinFont,
      bold: arabicFont ?? latinFont, // simplified
    );

    pdf.addPage(
      pw.Page(
        theme: themeData,
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Directionality(
            textDirection: pw.TextDirection.rtl, // Force RTL generically
            child: pw.Column(
              children: [
                pw.Header(
                  level: 0,
                  child: pw.Center(
                    child: pw.Text(
                      ArabicHelper.reshapedText(title),
                      style: const pw.TextStyle(fontSize: 20),
                    ),
                  ),
                ),
                pw.SizedBox(height: 20),
                pw.TableHelper.fromTextArray(
                  context: context,
                  headers: headers
                      .map((h) => ArabicHelper.reshapedText(h))
                      .toList(),
                  data: data.map((row) {
                    return columns.map((col) {
                      final val = row[col]?.toString() ?? '';
                      return ArabicHelper.reshapedText(val);
                    }).toList();
                  }).toList(),
                  border: pw.TableBorder.all(),
                  headerStyle: pw.TextStyle(
                    fontWeight: pw.FontWeight.bold,
                    font: arabicFont,
                  ),
                  cellStyle: pw.TextStyle(font: arabicFont, fontSize: 10),
                  headerDecoration: const pw.BoxDecoration(
                    color: PdfColors.grey300,
                  ),
                  cellAlignment: pw.Alignment.center,
                ),
              ],
            ),
          );
        },
      ),
    );

    await _saveAndPrintPdf(pdf, fileName ?? 'export.pdf');
  }

  // Specialized Invoice Export (DTO Based)
  // PDF Export Methods
  Future<void> exportSalesReport({
    required String title,
    required List<InvoiceReportDTO> data,
    String? fileName,
  }) async {
    final pdf = pw.Document();

    // 1. Load Fonts (Arabic and Fallbacks)
    pw.Font? arabicFont;
    pw.Font? arabicBoldFont;
    try {
      final regularData = await rootBundle.load(
        'assets/fonts/NotoNaskhArabic-Regular.ttf',
      );
      if (regularData.lengthInBytes > 0) arabicFont = pw.Font.ttf(regularData);

      // Fallback: Use same font for bold if distinct bold not available, or load bold if you have it
      // For now, reusing regular as bold or using a fallback if you had a bold file
      arabicBoldFont = arabicFont;
    } catch (e) {
      debugPrint('Error loading Arabic fonts: $e');
    }

    final latinFont = pw.Font.courier();
    final themeData = pw.ThemeData.withFont(
      base: arabicFont ?? latinFont,
      bold: arabicBoldFont ?? latinFont,
    );

    pdf.addPage(
      pw.Page(
        theme: themeData,
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                // Header
                pw.Center(
                  child: pw.Column(
                    children: [
                      pw.Text(
                        ArabicHelper.reshapedText(title),
                        style: pw.TextStyle(
                          fontSize: 22,
                          fontWeight: pw.FontWeight.bold,
                        ),
                        textDirection: pw.TextDirection.rtl,
                      ),
                      pw.SizedBox(height: 5),
                      pw.Text(
                        _branding,
                        style: const pw.TextStyle(
                          fontSize: 10,
                          color: PdfColors.grey,
                        ),
                      ),
                      pw.SizedBox(height: 10),
                      pw.Text(
                        ArabicHelper.reshapedText(
                          'التاريخ: ${DateFormat('yyyy/MM/dd HH:mm').format(DateTime.now())}',
                        ),
                        style: const pw.TextStyle(fontSize: 12),
                        textDirection: pw.TextDirection.rtl,
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 20),

                // Table
                _buildPdfTable(data, arabicFont, latinFont),

                pw.SizedBox(height: 20),

                // Footer
                pw.Spacer(),
                pw.Divider(),
                pw.Center(
                  child: pw.Text(
                    ArabicHelper.reshapedText(
                      '$_branding - ${DateFormat('yyyy').format(DateTime.now())}',
                    ),
                    style: const pw.TextStyle(
                      fontSize: 10,
                      color: PdfColors.grey600,
                    ),
                    textDirection: pw.TextDirection.rtl,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    await _saveAndPrintPdf(pdf, fileName ?? 'sales_report.pdf');
  }

  pw.Widget _buildPdfTable(
    List<InvoiceReportDTO> rows,
    pw.Font? arabicFont,
    pw.Font fallbackFont,
  ) {
    const headers = [
      'الرقم',
      'التاريخ',
      'العميل',
      'المنتجات',
      'الإجمالي',
      'المدفوع',
      'المتبقي',
    ];
    // Flex values match column widths: ID=1, Date=2, Customer=2, Products=4, Total=1.5, Paid=1.5, Rem=1.5

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      columnWidths: {
        0: const pw.FlexColumnWidth(1), // ID
        1: const pw.FlexColumnWidth(2), // Date
        2: const pw.FlexColumnWidth(2), // Customer
        3: const pw.FlexColumnWidth(4), // Products (Widest)
        4: const pw.FlexColumnWidth(1.5), // Total
        5: const pw.FlexColumnWidth(1.5), // Paid
        6: const pw.FlexColumnWidth(1.5), // Remaining
      },
      children: [
        // Header
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: headers
              .map(
                (h) => pw.Container(
                  padding: const pw.EdgeInsets.all(6),
                  child: pw.Text(
                    ArabicHelper.reshapedText(h),
                    style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 10,
                    ),
                    textAlign: pw.TextAlign.center,
                    textDirection: pw.TextDirection.rtl,
                  ),
                ),
              )
              .toList(),
        ),
        // Data
        ...rows.map((row) {
          final isBalanceZero = row.remainingAmount <= 0.01;
          return pw.TableRow(
            decoration: const pw.BoxDecoration(color: PdfColors.white),
            children: [
              _cell(row.invoiceNumber),
              _cell(DateFormat('yyyy/MM/dd').format(row.date)),
              _cell(row.customerName),
              _cell(
                row.productNames,
                alignLeft: false,
              ), // Products might be long
              _cell(row.totalAmount.toStringAsFixed(2)),
              _cell(row.paidAmount.toStringAsFixed(2)),
              _cell(
                row.remainingAmount.toStringAsFixed(2),
                color: isBalanceZero ? PdfColors.green700 : PdfColors.red700,
                isBold: true,
              ),
            ],
          );
        }),
      ],
    );
  }

  pw.Widget _cell(
    String text, {
    bool alignLeft = false,
    PdfColor color = PdfColors.black,
    bool isBold = false,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(5),
      child: pw.Text(
        ArabicHelper.reshapedText(text),
        style: pw.TextStyle(
          fontSize: 9,
          color: color,
          fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
        textAlign: alignLeft ? pw.TextAlign.left : pw.TextAlign.center,
        textDirection: pw.TextDirection.rtl,
      ),
    );
  }

  Future<void> _saveAndPrintPdf(pw.Document pdf, String fileName) async {
    final bytes = await pdf.save();
    try {
      await Printing.layoutPdf(
        onLayout: (format) async => bytes,
        name: fileName,
      );
    } catch (e) {
      debugPrint('Print error: $e');
      // Fallback: Share
      await Printing.sharePdf(bytes: bytes, filename: fileName);
    }
  }

  // Excel Export Methods
  Future<void> exportToExcel({
    required String title,
    required List<Map<String, dynamic>> data,
    required List<String> headers,
    required List<String> columns,
    String? fileName,
  }) async {
    final excel = Excel.createExcel();
    final sheet = excel['Sheet1'];

    // Style definitions
    final headerStyle = CellStyle(
      bold: true,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
      fontSize: 12,
    );

    final dataStyle = CellStyle(
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
      fontSize: 11,
    );

    final numberStyle = CellStyle(
      horizontalAlign: HorizontalAlign.Left,
      verticalAlign: VerticalAlign.Center,
      fontSize: 11,
    );

    // Add title row at the top
    final titleCell = sheet.cell(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
    );
    titleCell.value = TextCellValue(title);
    titleCell.cellStyle = CellStyle(
      bold: true,
      fontSize: 16,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );

    // Merge title cells
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
      CellIndex.indexByColumnRow(columnIndex: columns.length - 1, rowIndex: 0),
    );

    // Add headers in the second row
    for (int i = 0; i < headers.length; i++) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 1),
      );
      cell.value = TextCellValue(headers[i]);
      cell.cellStyle = headerStyle;
    }

    // Add data with proper styling
    for (int rowIndex = 0; rowIndex < data.length; rowIndex++) {
      final row = data[rowIndex];
      for (int colIndex = 0; colIndex < columns.length; colIndex++) {
        final cell = sheet.cell(
          CellIndex.indexByColumnRow(
            columnIndex: colIndex,
            rowIndex: rowIndex + 2,
          ),
        );

        final columnName = columns[colIndex];
        final value = row[columnName];

        // Apply appropriate styling based on content type
        if (value is double || value is int) {
          cell.value = DoubleCellValue(value.toDouble());
          cell.cellStyle = numberStyle;
        } else if (value is DateTime) {
          cell.value = DateCellValue(
            year: value.year,
            month: value.month,
            day: value.day,
          );
          cell.cellStyle = dataStyle;
        } else {
          cell.value = TextCellValue(_formatCellValue(value));
          cell.cellStyle = dataStyle;
        }
      }
    }

    // Auto-adjust column widths
    for (int col = 0; col < columns.length; col++) {
      sheet.setColumnAutoFit(col);
    }

    // Add metadata info
    final metadataRow = data.length + 4;
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: metadataRow),
      CellIndex.indexByColumnRow(
        columnIndex: columns.length - 1,
        rowIndex: metadataRow,
      ),
    );

    final metadataCell = sheet.cell(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: metadataRow),
    );
    metadataCell.value = TextCellValue(
      '$_branding - تم الإنشاء في ${DateFormat('yyyy/MM/dd HH:mm').format(DateTime.now())}',
    );
    metadataCell.cellStyle = CellStyle(
      fontSize: 10,
      italic: true,
      horizontalAlign: HorizontalAlign.Center,
    );

    // Save file
    final directory = await getApplicationDocumentsDirectory();
    final filePath = path.join(
      directory.path,
      fileName ??
          '${title}_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx',
    );

    final file = File(filePath);
    await file.writeAsBytes(excel.save()!);

    // Open file
    await Printing.sharePdf(
      bytes: await file.readAsBytes(),
      filename: path.basename(filePath),
    );
  }

  pw.Widget _buildHeaderCell(String text, {pw.Font? font}) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontWeight: pw.FontWeight.bold,
          font: font, // Use provided font parameter
        ),
        textAlign: pw.TextAlign.center,
      ),
    );
  }

  pw.Widget _buildDataCell(String text, {pw.Font? font}) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      child: pw.Text(
        text,
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(font: font), // Use provided font parameter
      ),
    );
  }

  // Helper methods with font parameters
  pw.Widget _buildTableHeaderCell(
    String text, {
    pw.Font? arabicFont,
    pw.Font? arabicBoldFont,
    pw.Font? latinFont,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      child: pw.Text(
        ArabicHelper.reshapedText(text),
        style: pw.TextStyle(
          fontWeight: pw.FontWeight.bold,
          font: arabicBoldFont ?? latinFont,
          fontFallback: [
            if (arabicBoldFont != null) arabicBoldFont,
            latinFont ?? pw.Font.courier(),
            pw.Font.courier(),
          ],
        ),
        textAlign: pw.TextAlign.center,
        textDirection: pw.TextDirection.rtl,
      ),
    );
  }

  pw.Widget _buildTableCell(
    String text, {
    bool isBalance = false,
    pw.Font? arabicFont,
    pw.Font? latinFont,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      child: pw.Text(
        ArabicHelper.reshapedText(text),
        style: pw.TextStyle(
          fontWeight: pw.FontWeight.normal,
          font: arabicFont ?? latinFont,
          fontFallback: [
            if (arabicFont != null) arabicFont,
            latinFont ?? pw.Font.courier(),
            pw.Font.courier(),
          ],
          color: isBalance ? PdfColors.red : PdfColors.black,
        ),
        textAlign: pw.TextAlign.center,
        textDirection: pw.TextDirection.rtl,
      ),
    );
  }

  // Customer Statement PDF - Using EnhancedAccountStatementGenerator
  Future<void> exportCustomerStatement({
    required AppDatabase db,
    required String customerName,
    required List<Map<String, dynamic>> transactions,
    required double openingBalance,
    required double currentBalance,
  }) async {
    try {
      // Generate PDF using the new enhanced customer statement generator
      await EnhancedCustomerStatementGenerator.generateStatement(
        db: db,
        customerId: customerName, // Use customer name as ID for export
        customerName: customerName,
        fromDate: DateTime.now().subtract(
          Duration(days: 365),
        ), // Default to last year
        toDate: DateTime.now(),
        openingBalance: openingBalance,
        currentBalance: currentBalance,
      );

      // Note: The new generator handles PDF saving internally
      debugPrint('Customer statement generated successfully');
    } catch (e) {
      debugPrint('Error in exportCustomerStatement: $e');
      // Fallback to old method if new one fails
      await _exportCustomerStatementLegacy(
        db: db,
        customerName: customerName,
        transactions: transactions,
        openingBalance: openingBalance,
        currentBalance: currentBalance,
      );
    }
  }

  // Legacy fallback method
  Future<void> _exportCustomerStatementLegacy({
    required AppDatabase db,
    required String customerName,
    required List<Map<String, dynamic>> transactions,
    required double openingBalance,
    required double currentBalance,
  }) async {
    // Validate inputs
    final safeCustomerName = customerName.isNotEmpty
        ? customerName
        : 'عميل غير محدد';
    final safeTransactions = transactions.cast<Map<String, dynamic>>().toList();

    final safeCurrentBalance = currentBalance.isNaN ? 0.0 : currentBalance;

    final pdf = pw.Document();

    // Load Arabic fonts
    pw.Font? arabicFont;
    try {
      final fontData = await rootBundle.load(
        'assets/fonts/NotoNaskhArabic-Regular.ttf',
      );
      if (fontData.lengthInBytes > 100) {
        arabicFont = pw.Font.ttf(fontData);
      }
    } catch (e) {
      debugPrint('Failed to load Arabic font: $e');
    }
    pw.Font? arabicBoldFont;
    try {
      final fontData = await rootBundle.load(
        'assets/fonts/NotoNaskhArabic-Regular.ttf',
      );
      if (fontData.lengthInBytes > 100) {
        arabicBoldFont = pw.Font.ttf(fontData);
      }
    } catch (e) {
      debugPrint('Failed to load Arabic bold font: $e');
    }

    final latinFont = pw.Font.helvetica(); // Used as fallback

    // Enhanced transaction processing for sales with product details
    List<Map<String, dynamic>> enhancedTransactions = [];
    for (final transaction in safeTransactions) {
      final description = transaction['description']?.toString() ?? '';
      final receiptNumber = transaction['receiptNumber']?.toString();

      // Check if this is a sale transaction by looking for invoice ID pattern
      if (receiptNumber != null &&
          RegExp(r'\d+').hasMatch(receiptNumber) &&
          description.contains('فاتورة مبيعات')) {
        // Extract invoice ID
        final match = RegExp(r'\d+').firstMatch(receiptNumber);
        final invoiceId = match != null
            ? int.tryParse(match.group(0) ?? '')
            : null;

        if (invoiceId != null) {
          try {
            // Fetch invoice items with product details
            final items = await _getInvoiceItemsWithProducts(db, invoiceId);
            if (items.isNotEmpty) {
              // Build detailed description with product breakdown
              final detailedDescription = _buildDetailedDescription(items);
              enhancedTransactions.add({
                ...transaction,
                'description': detailedDescription,
                'hasProductDetails': true,
                'items': items,
              });
              continue;
            }
          } catch (e) {
            debugPrint('Error fetching invoice items for $invoiceId: $e');
          }
        }
      }

      // Fallback to original description if no enhancement needed
      enhancedTransactions.add({...transaction, 'hasProductDetails': false});
    }

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.all(32),
        build: (pw.Context context) => pw.Column(
          children: [
            // Header
            pw.Center(
              child: pw.Column(
                children: [
                  pw.Text(
                    ArabicHelper.reshapedText('كشف حساب عميل'),
                    style: pw.TextStyle(
                      fontSize: 24,
                      fontWeight: pw.FontWeight.bold,
                      font: arabicBoldFont,
                    ),
                    textDirection: pw.TextDirection.rtl,
                  ),
                  pw.Text(
                    _branding,
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontStyle: pw.FontStyle.italic,
                      font: pw.Font.courier(),
                    ),
                  ),
                  pw.SizedBox(height: 16),
                ],
              ),
            ),

            // Customer Info
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
              ),
              child: pw.Column(
                crossAxisAlignment:
                    pw.CrossAxisAlignment.center, // Center align
                children: [
                  // Name & Date
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        ArabicHelper.reshapedText(
                          'التاريخ: ${DateFormat('yyyy/MM/dd').format(DateTime.now())}',
                        ),
                        style: pw.TextStyle(
                          font: arabicFont,
                          fontFallback: [pw.Font.helvetica()],
                        ),
                        textDirection: pw.TextDirection.rtl,
                      ),
                      pw.Text(
                        ArabicHelper.reshapedText(
                          'اسم العميل: $safeCustomerName',
                        ),
                        style: pw.TextStyle(
                          font: arabicBoldFont,
                          fontFallback: [pw.Font.helvetica()],
                          fontSize: 14,
                        ),
                        textDirection: pw.TextDirection.rtl,
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 10),

                  // Owed Amount (Red)
                  pw.Text(
                    ArabicHelper.reshapedText(
                      'المبلغ المستحق: ${_formatCurrency(safeCurrentBalance)}',
                    ),
                    style: pw.TextStyle(
                      font: arabicBoldFont,
                      fontFallback: [pw.Font.helvetica()],
                      fontSize: 18,
                      color: PdfColors.red,
                    ),
                    textDirection: pw.TextDirection.rtl,
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 20),

            // Transactions Table
            pw.Table(
              border: pw.TableBorder.all(),
              columnWidths: {
                0: const pw.FlexColumnWidth(1.2), // Date
                1: const pw.FlexColumnWidth(1.2), // Receipt#
                2: const pw.FlexColumnWidth(2.5), // Description
                3: const pw.FlexColumnWidth(1), // Debit
                4: const pw.FlexColumnWidth(1), // Credit
                5: const pw.FlexColumnWidth(1.2), // Balance
              },
              children: [
                // Header
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                  children: [
                    _buildTableHeaderCell(
                      'التاريخ',
                      arabicFont: arabicFont,
                      arabicBoldFont: arabicBoldFont,
                      latinFont: latinFont,
                    ),
                    _buildTableHeaderCell(
                      'رقم الإيصال',
                      arabicFont: arabicFont,
                      arabicBoldFont: arabicBoldFont,
                      latinFont: latinFont,
                    ),
                    _buildTableHeaderCell(
                      'البيان',
                      arabicFont: arabicFont,
                      arabicBoldFont: arabicBoldFont,
                      latinFont: latinFont,
                    ),
                    _buildTableHeaderCell(
                      'مدين',
                      arabicFont: arabicFont,
                      arabicBoldFont: arabicBoldFont,
                      latinFont: latinFont,
                    ),
                    _buildTableHeaderCell(
                      'دائن',
                      arabicFont: arabicFont,
                      arabicBoldFont: arabicBoldFont,
                      latinFont: latinFont,
                    ),
                    _buildTableHeaderCell(
                      'الرصيد',
                      arabicFont: arabicFont,
                      arabicBoldFont: arabicBoldFont,
                      latinFont: latinFont,
                    ),
                  ],
                ),
                // Data
                ...safeTransactions.map((transaction) {
                  final index = safeTransactions.indexOf(transaction);
                  return pw.TableRow(
                    decoration: pw.BoxDecoration(
                      color: index % 2 == 0
                          ? PdfColors.white
                          : PdfColors.grey50,
                    ),
                    children: [
                      _buildTableCell(
                        DateFormat('yyyy/MM/dd').format(transaction['date']),
                        arabicFont: arabicFont,
                        latinFont: latinFont,
                      ),
                      _buildTableCell(
                        transaction['receiptNumber']?.toString() ?? '-',
                        arabicFont: arabicFont,
                        latinFont: latinFont,
                      ),
                      _buildTableCell(
                        transaction['description']?.toString() ?? '',
                        arabicFont: arabicFont,
                        latinFont: latinFont,
                      ),
                      _buildTableCell(
                        _formatCurrency(transaction['debit'] ?? 0),
                        arabicFont: arabicFont,
                        latinFont: latinFont,
                      ),
                      _buildTableCell(
                        _formatCurrency(transaction['credit'] ?? 0),
                        arabicFont: arabicFont,
                        latinFont: latinFont,
                      ),
                      _buildTableCell(
                        _formatCurrency(transaction['balance'] ?? 0),
                        isBalance: true,
                        arabicFont: arabicFont,
                        latinFont: latinFont,
                      ),
                    ],
                  );
                }),
              ],
            ),

            pw.Expanded(child: pw.Container()),

            // Footer
            pw.Center(
              child: pw.Column(
                children: [
                  pw.Text(
                    _branding,
                    style: pw.TextStyle(
                      font: arabicFont,
                    ), // Apply Arabic font to footer
                  ),
                  pw.Text(
                    'تم الإنشاء في ${DateFormat('yyyy/MM/dd HH:mm').format(DateTime.now())}',
                    style: pw.TextStyle(
                      fontSize: 8,
                      font: arabicFont,
                    ), // Apply Arabic font to footer
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    try {
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async {
          final output = await pdf.save();
          return output;
        },
        name: 'كشف حساب $safeCustomerName.pdf',
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () async {
          // Fallback: save to file
          final directory = await getApplicationDocumentsDirectory();
          final filePath = path.join(
            directory.path,
            'customer_statement_${DateTime.now().millisecondsSinceEpoch}.pdf',
          );
          final file = File(filePath);
          final output = await pdf.save();
          await file.writeAsBytes(output);
          debugPrint('PDF saved to: $filePath');
          return false; // Return false to indicate fallback was used
        },
      );
    } catch (e) {
      debugPrint('Error in exportCustomerStatement: $e');
      // Fallback: save to file if layout fails
      try {
        final directory = await getApplicationDocumentsDirectory();
        final filePath = path.join(
          directory.path,
          'customer_statement_${DateTime.now().millisecondsSinceEpoch}.pdf',
        );
        final file = File(filePath);
        final output = await pdf.save();
        await file.writeAsBytes(output);
        debugPrint('PDF saved to: $filePath');
      } catch (saveError) {
        debugPrint('Error saving PDF: $saveError');
        rethrow;
      }
    }
  }

  String _formatCellValue(dynamic value) {
    if (value == null) return 'غير متوفر';
    if (value is double || value is int) {
      return _formatCurrency(value.toDouble());
    }
    if (value is DateTime) {
      return DateFormat('dd/MM/yyyy').format(value);
    }
    if (value is String) {
      return value.isEmpty ? 'غير متوفر' : ArabicHelper.reshapedText(value);
    }
    return ArabicHelper.reshapedText(value.toString());
  }

  String _formatCurrency(double amount) {
    if (amount.isNaN) return '0.00 ج.م';
    return NumberFormat.currency(
      locale: 'en_EG',
      symbol: 'ج.م',
      decimalDigits: 2,
    ).format(amount);
  }

  // Cash Report Export Methods
  Future<void> exportCashReportToPDF(Map<String, dynamic> reportData) async {
    // Validate report data
    final safeTotalIncome =
        (reportData['totalIncome'] as double?)?.isNaN == true
        ? 0.0
        : (reportData['totalIncome'] as double?) ?? 0.0;
    final safeTotalExpenses =
        (reportData['totalExpenses'] as double?)?.isNaN == true
        ? 0.0
        : (reportData['totalExpenses'] as double?) ?? 0.0;
    final safeClosingBalance =
        (reportData['closingBalance'] as double?)?.isNaN == true
        ? 0.0
        : (reportData['closingBalance'] as double?) ?? 0.0;
    final safeVisaIncome = reportData['visaIncome'] as double?;
    final safeTransactions =
        (reportData['transactions'] as List?)?.cast<Map<String, dynamic>>() ??
        [];

    final pdf = pw.Document();

    // Load Arabic fonts
    pw.Font? arabicFont;
    try {
      final fontData = await rootBundle.load(
        'assets/fonts/NotoNaskhArabic-Regular.ttf',
      );
      if (fontData.lengthInBytes > 100) {
        arabicFont = pw.Font.ttf(fontData);
      }
    } catch (e) {
      debugPrint('Failed to load Arabic font: $e');
    }
    pw.Font? arabicBoldFont;
    try {
      final fontData = await rootBundle.load(
        'assets/fonts/NotoNaskhArabic-Regular.ttf',
      );
      if (fontData.lengthInBytes > 100) {
        arabicBoldFont = pw.Font.ttf(fontData);
      }
    } catch (e) {
      debugPrint('Failed to load Arabic bold font: $e');
    }

    final latinFont = pw.Font.helvetica(); // Used as fallback

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) => pw.Directionality(
          textDirection: pw.TextDirection.rtl,
          child: pw.Column(
            children: [
              // Header
              pw.Center(
                child: pw.Column(
                  children: [
                    pw.Text(
                      ArabicHelper.reshapedText('تقرير الكاش'),
                      style: pw.TextStyle(
                        fontSize: 24,
                        fontWeight: pw.FontWeight.bold,
                        font: arabicBoldFont,
                      ),
                      textDirection: pw.TextDirection.rtl,
                    ),
                    pw.SizedBox(height: 8),
                    pw.Text(
                      _branding,
                      style: pw.TextStyle(
                        fontSize: 10,
                        fontStyle: pw.FontStyle.italic,
                        font: pw.Font.courier(),
                      ),
                    ),
                    pw.SizedBox(height: 16),
                    pw.Text(
                      ArabicHelper.reshapedText(
                        'التاريخ: ${DateFormat('yyyy/MM/dd HH:mm').format(DateTime.now())}',
                      ),
                      style: pw.TextStyle(font: arabicFont),
                      textDirection: pw.TextDirection.rtl,
                    ),
                    // Opening balance intentionally omitted from header per export format
                    pw.Text(
                      ArabicHelper.reshapedText(
                        'إجمالي الإيرادات: ${_formatCurrency(safeTotalIncome)}',
                      ),
                      style: pw.TextStyle(font: arabicFont),
                      textDirection: pw.TextDirection.rtl,
                    ),
                    pw.SizedBox(height: 16),
                    pw.Text(
                      ArabicHelper.reshapedText(
                        'إجمالي المصروفات: ${_formatCurrency(safeTotalExpenses)}',
                      ),
                      style: pw.TextStyle(font: arabicFont),
                      textDirection: pw.TextDirection.rtl,
                    ),
                    pw.SizedBox(height: 16),
                    if (safeVisaIncome != null) ...[
                      pw.Text(
                        ArabicHelper.reshapedText(
                          'إجمالي الفيزا: ${_formatCurrency(safeVisaIncome)}',
                        ),
                        style: pw.TextStyle(font: arabicFont),
                        textDirection: pw.TextDirection.rtl,
                      ),
                      pw.SizedBox(height: 16),
                    ],
                    pw.Text(
                      ArabicHelper.reshapedText(
                        'الرصيد المغلق: ${_formatCurrency(safeClosingBalance)}',
                      ),
                      style: pw.TextStyle(font: arabicFont),
                      textDirection: pw.TextDirection.rtl,
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),

              // Transactions Table
              pw.Table(
                border: pw.TableBorder.all(),
                columnWidths: {
                  0: const pw.FlexColumnWidth(1.2), // Payment Method
                  1: const pw.FlexColumnWidth(1), // Credit
                  2: const pw.FlexColumnWidth(1), // Debit
                  3: const pw.FlexColumnWidth(2), // Description
                  4: const pw.FlexColumnWidth(1), // Time
                },
                children: [
                  // Header
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(
                      color: PdfColors.grey200,
                    ),
                    children: [
                      _buildTableCell(
                        'طريقة الدفع',
                        arabicFont: arabicFont,
                        latinFont: latinFont,
                      ),
                      _buildTableCell(
                        'دائن (-)',
                        arabicFont: arabicFont,
                        latinFont: latinFont,
                      ),
                      _buildTableCell(
                        'دين (+)',
                        arabicFont: arabicFont,
                        latinFont: latinFont,
                      ),
                      _buildTableCell(
                        'الوصف',
                        arabicFont: arabicFont,
                        latinFont: latinFont,
                      ),
                      _buildTableCell(
                        'الوقت',
                        arabicFont: arabicFont,
                        latinFont: latinFont,
                      ),
                    ],
                  ),
                  // Data rows
                  ...safeTransactions.map(
                    (transaction) => pw.TableRow(
                      children: [
                        _buildTableCell(
                          transaction['paymentMethod']?.toString() ?? 'كاش',
                          arabicFont: arabicFont,
                          latinFont: latinFont,
                        ),
                        _buildTableCell(
                          transaction['credit']?.toString() ?? '0.00',
                          arabicFont: arabicFont,
                          latinFont: latinFont,
                        ),
                        _buildTableCell(
                          transaction['debit']?.toString() ?? '0.00',
                          arabicFont: arabicFont,
                          latinFont: latinFont,
                        ),
                        _buildTableCell(
                          transaction['description']?.toString() ?? 'لا يوجد',
                          arabicFont: arabicFont,
                          latinFont: latinFont,
                        ),
                        _buildTableCell(
                          transaction['time']?.toString() ?? '00:00',
                          arabicFont: arabicFont,
                          latinFont: latinFont,
                        ),
                      ],
                    ),
                  ),
                ],
              ), // Closing parenthesis for pw.Table

              pw.Expanded(child: pw.Container()),

              // Footer
              pw.Center(
                child: pw.Column(
                  children: [
                    pw.Text(_branding),
                    pw.Text(
                      'تم الإنشاء في ${DateFormat('yyyy/MM/dd HH:mm').format(DateTime.now())}',
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    final output = await pdf.save();

    // Try different printing approaches
    try {
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => output,
        name:
            'cash_report_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}',
      );
    } catch (e) {
      try {
        await Printing.sharePdf(
          bytes: output,
          filename:
              'cash_report_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.pdf',
        );
      } catch (e2) {
        // Save to file as fallback
        final directory = await getApplicationDocumentsDirectory();
        final filePath = path.join(
          directory.path,
          'cash_report_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.pdf',
        );
        final file = File(filePath);
        await file.writeAsBytes(output);
      }
    }
  }

  Future<void> exportSalesReportToExcel(
    List<Invoice> invoices,
    List<Customer> customers,
  ) async {
    // Validate inputs
    final safeInvoices = invoices.toList();

    final data = safeInvoices.map((invoice) {
      return {
        'رقم الفاتورة': invoice.id.toString(),
        'العميل': invoice.customerName?.isNotEmpty == true
            ? invoice.customerName!
            : 'عميل غير محدد',
        'التاريخ': DateFormat('yyyy/MM/dd').format(invoice.date),
        'الإجمالي': invoice.totalAmount.isNaN ? 0.0 : invoice.totalAmount,
        'المدفوع': invoice.paidAmount.isNaN ? 0.0 : invoice.paidAmount,
        'المتبقي':
            (invoice.totalAmount.isNaN ? 0.0 : invoice.totalAmount) -
            (invoice.paidAmount.isNaN ? 0.0 : invoice.paidAmount),
        'طريقة الدفع': invoice.paymentMethod?.isNotEmpty == true
            ? invoice.paymentMethod!
            : 'كاش',
        'الحالة': invoice.status.isNotEmpty ? invoice.status : 'غير محدد',
      };
    }).toList();

    await exportToExcel(
      title: 'تقرير المبيعات',
      data: data,
      headers: [
        'رقم الفاتورة',
        'العميل',
        'التاريخ',
        'الإجمالي',
        'المدفوع',
        'المتبقي',
        'طريقة الدفع',
        'الحالة',
      ],
      columns: [
        'رقم الفاتورة',
        'العميل',
        'التاريخ',
        'الإجمالي',
        'المدفوع',
        'المتبقي',
        'طريقة الدفع',
        'الحالة',
      ],
      fileName:
          'sales_report_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}',
    );
  }

  // Customer List Summary Print
  Future<void> printCustomerListSummary({
    required List<Map<String, dynamic>> customers,
    DateTimeRange? dateRange,
  }) async {
    final pdf = pw.Document();

    // Load Arabic fonts
    pw.Font? arabicFont;
    try {
      final fontData = await rootBundle.load(
        'assets/fonts/NotoNaskhArabic-Regular.ttf',
      );
      final bytes = fontData.buffer.asUint8List();
      if (bytes.length > 100) {
        arabicFont = pw.Font.ttf(
          bytes.buffer.asByteData(bytes.offsetInBytes, bytes.lengthInBytes),
        );
      }
    } catch (e) {
      debugPrint('Failed to load Arabic font: $e');
    }
    pw.Font? arabicBoldFont;
    try {
      final fontData = await rootBundle.load(
        'assets/fonts/NotoNaskhArabic-Regular.ttf',
      );
      final bytes = fontData.buffer.asUint8List();
      if (bytes.length > 100) {
        arabicBoldFont = pw.Font.ttf(
          bytes.buffer.asByteData(bytes.offsetInBytes, bytes.lengthInBytes),
        );
      }
    } catch (e) {
      debugPrint('Failed to load Arabic bold font: $e');
    }

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              children: [
                // Header
                pw.Center(
                  child: pw.Column(
                    children: [
                      pw.Text(
                        ArabicHelper.reshapedText(
                          'قائمة العملاء وملخص الأرصدة',
                        ),
                        style: pw.TextStyle(
                          fontSize: 22,
                          fontWeight: pw.FontWeight.bold,
                          font: arabicBoldFont,
                        ),
                        textDirection: pw.TextDirection.rtl,
                      ),
                      pw.SizedBox(height: 8),
                      pw.Text(
                        ArabicHelper.reshapedText(
                          'تاريخ الطباعة: ${DateFormat('yyyy/MM/dd HH:mm').format(DateTime.now())}',
                        ),
                        style: pw.TextStyle(font: arabicFont, fontSize: 10),
                        textDirection: pw.TextDirection.rtl,
                      ),
                      if (dateRange != null)
                        pw.Text(
                          ArabicHelper.reshapedText(
                            'الفترة: من ${DateFormat('yyyy/MM/dd').format(dateRange.start)} إلى ${DateFormat('yyyy/MM/dd').format(dateRange.end)}',
                          ),
                          style: pw.TextStyle(font: arabicFont, fontSize: 10),
                          textDirection: pw.TextDirection.rtl,
                        ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 20),

                // Table
                pw.Table(
                  border: pw.TableBorder.all(),
                  columnWidths: {
                    0: const pw.FlexColumnWidth(0.5), // #
                    1: const pw.FlexColumnWidth(2), // Name
                    2: const pw.FlexColumnWidth(1.5), // Phone
                    3: const pw.FlexColumnWidth(1.5), // Balance
                  },
                  children: [
                    // Header Row
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(
                        color: PdfColors.grey300,
                      ),
                      children: [
                        _buildHeaderCell(
                          ArabicHelper.reshapedText('م'),
                          font: arabicBoldFont,
                        ),
                        _buildHeaderCell(
                          ArabicHelper.reshapedText('الاسم'),
                          font: arabicBoldFont,
                        ),
                        _buildHeaderCell(
                          ArabicHelper.reshapedText('الهاتف'),
                          font: arabicBoldFont,
                        ),
                        _buildHeaderCell(
                          ArabicHelper.reshapedText('الرصيد'),
                          font: arabicBoldFont,
                        ),
                      ],
                    ),
                    // Data Rows
                    ...customers.asMap().entries.map((entry) {
                      final index = entry.key;
                      final customer = entry.value;
                      final balance = customer['balance'] as double;
                      return pw.TableRow(
                        children: [
                          _buildDataCell('${index + 1}', font: arabicFont),
                          _buildDataCell(
                            ArabicHelper.reshapedText(customer['name']),
                            font: arabicFont,
                          ),
                          _buildDataCell(customer['phone'], font: arabicFont),
                          pw.Container(
                            padding: const pw.EdgeInsets.all(8),
                            alignment: pw.Alignment.center,
                            child: pw.Text(
                              ArabicHelper.reshapedText(
                                _formatCurrency(balance),
                              ),
                              style: pw.TextStyle(
                                font: arabicFont,
                                color: balance >= 0
                                    ? PdfColors.green
                                    : PdfColors.red,
                              ),
                              textDirection: pw.TextDirection.rtl,
                            ),
                          ),
                        ],
                      );
                    }),
                  ],
                ),

                pw.Expanded(child: pw.Container()),

                // Footer
                pw.Center(
                  child: pw.Text(
                    _branding,
                    style: pw.TextStyle(
                      fontSize: 10,
                      color: PdfColors.grey600,
                      font: arabicFont,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    final output = await pdf.save();
    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => output,
      name: 'customers_list_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
  }

  // Export Purchases Report
  Future<void> exportPurchaseReport({
    required List<Expense> purchases,
    DateTimeRange? dateRange,
  }) async {
    final pdf = pw.Document();

    // Load Arabic fonts
    pw.Font? arabicFont;
    pw.Font? arabicBoldFont;
    try {
      final regularFontData = await rootBundle.load(
        'assets/fonts/NotoSansArabic-Regular.ttf',
      );
      final regBytes = regularFontData.buffer.asUint8List();
      if (regBytes.length > 100) {
        arabicFont = pw.Font.ttf(
          regBytes.buffer.asByteData(
            regBytes.offsetInBytes,
            regBytes.lengthInBytes,
          ),
        );
      }

      final boldFontData = await rootBundle.load(
        'assets/fonts/NotoNaskhArabic-Regular.ttf',
      );
      final bldBytes = boldFontData.buffer.asUint8List();
      if (bldBytes.length > 100) {
        arabicBoldFont = pw.Font.ttf(
          bldBytes.buffer.asByteData(
            bldBytes.offsetInBytes,
            bldBytes.lengthInBytes,
          ),
        );
      }
    } catch (e) {
      debugPrint('Failed to load Arabic fonts for purchase report: $e');
    }

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              children: [
                // Header
                pw.Center(
                  child: pw.Column(
                    children: [
                      pw.Text(
                        ArabicHelper.reshapedText('تقرير المشتريات'),
                        style: pw.TextStyle(
                          fontSize: 22,
                          fontWeight: pw.FontWeight.bold,
                          font: arabicBoldFont,
                        ),
                        textDirection: pw.TextDirection.rtl,
                      ),
                      pw.SizedBox(height: 8),
                      pw.Text(
                        ArabicHelper.reshapedText(
                          'تاريخ الطباعة: ${DateFormat('yyyy/MM/dd HH:mm').format(DateTime.now())}',
                        ),
                        style: pw.TextStyle(font: arabicFont, fontSize: 10),
                        textDirection: pw.TextDirection.rtl,
                      ),
                      if (dateRange != null)
                        pw.Text(
                          ArabicHelper.reshapedText(
                            'الفترة: من ${DateFormat('yyyy/MM/dd').format(dateRange.start)} إلى ${DateFormat('yyyy/MM/dd').format(dateRange.end)}',
                          ),
                          style: pw.TextStyle(font: arabicFont, fontSize: 10),
                          textDirection: pw.TextDirection.rtl,
                        ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 20),

                // Table
                pw.Table(
                  border: pw.TableBorder.all(),
                  columnWidths: {
                    0: const pw.FlexColumnWidth(0.5), // #
                    1: const pw.FlexColumnWidth(2), // Date
                    2: const pw.FlexColumnWidth(3), // Description
                    3: const pw.FlexColumnWidth(1.5), // Amount
                  },
                  children: [
                    // Header Row
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(
                        color: PdfColors.grey300,
                      ),
                      children: [
                        _buildHeaderCell(
                          ArabicHelper.reshapedText('م'),
                          font: arabicBoldFont,
                        ),
                        _buildHeaderCell(
                          ArabicHelper.reshapedText('التاريخ'),
                          font: arabicBoldFont,
                        ),
                        _buildHeaderCell(
                          ArabicHelper.reshapedText('البيان'),
                          font: arabicBoldFont,
                        ),
                        _buildHeaderCell(
                          ArabicHelper.reshapedText('القيمة'),
                          font: arabicBoldFont,
                        ),
                      ],
                    ),
                    // Data Rows
                    ...purchases.asMap().entries.map((entry) {
                      final index = entry.key;
                      final p = entry.value;
                      return pw.TableRow(
                        children: [
                          _buildDataCell('${index + 1}', font: arabicFont),
                          _buildDataCell(
                            DateFormat('yyyy/MM/dd').format(p.date),
                            font: arabicFont,
                          ),
                          _buildDataCell(
                            ArabicHelper.reshapedText(p.description),
                            font: arabicFont,
                          ),
                          _buildDataCell(
                            ArabicHelper.reshapedText(
                              _formatCurrency(p.amount),
                            ),
                            font: arabicFont,
                          ),
                        ],
                      );
                    }),
                  ],
                ),

                pw.Expanded(child: pw.Container()),

                // Footer
                pw.Center(
                  child: pw.Text(
                    _branding,
                    style: const pw.TextStyle(
                      fontSize: 10,
                      color: PdfColors.grey600,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    final output = await pdf.save();
    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => output);
  }

  Future<void> printCustomerSummaryReport({
    required List<Map<String, dynamic>> customers,
    DateTimeRange? dateRange,
  }) async {
    final pdf = pw.Document();
    final fonts = await _loadRequiredFonts();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          _buildSummaryHeader('تقرير ملخص مديونيات العملاء', dateRange, fonts),
          pw.SizedBox(height: 20),
          _buildSummaryTable(customers, fonts),
        ],
      ),
    );

    await Printing.layoutPdf(
      onLayout: (format) async => pdf.save(),
      name: 'Customer_Summary.pdf',
    );
  }

  Future<Map<String, pw.Font?>> _loadRequiredFonts() async {
    pw.Font? regular;
    pw.Font? bold;
    try {
      final regData = await rootBundle.load(
        'assets/fonts/NotoNaskhArabic-Regular.ttf',
      );
      regular = pw.Font.ttf(regData);
      final boldData = await rootBundle.load(
        'assets/fonts/NotoNaskhArabic-Regular.ttf',
      );
      bold = pw.Font.ttf(boldData);
    } catch (e) {
      debugPrint('Font load error: $e');
    }
    return {'regular': regular, 'bold': bold};
  }

  pw.Widget _buildSummaryHeader(
    String title,
    DateTimeRange? range,
    Map<String, pw.Font?> fonts,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(
          ArabicHelper.reshapedText(title),
          style: pw.TextStyle(font: fonts['bold'], fontSize: 24),
          textDirection: pw.TextDirection.rtl,
        ),
        if (range != null)
          pw.Text(
            ArabicHelper.reshapedText(
              '${DateFormat('yyyy/MM/dd').format(range.start)} - ${DateFormat('yyyy/MM/dd').format(range.end)}',
            ),
            style: pw.TextStyle(font: fonts['regular'], fontSize: 14),
            textDirection: pw.TextDirection.rtl,
          ),
        pw.Divider(),
      ],
    );
  }

  pw.Widget _buildSummaryTable(
    List<Map<String, dynamic>> customers,
    Map<String, pw.Font?> fonts,
  ) {
    return pw.Table(
      border: pw.TableBorder.all(),
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            _buildTableHeader('الاسم', fonts['bold']),
            _buildTableHeader('المدفوع', fonts['bold']),
            _buildTableHeader('المتبقي', fonts['bold']),
          ],
        ),
        ...customers.map(
          (c) => pw.TableRow(
            children: [
              _buildTableData(c['name'] ?? '', fonts['regular']),
              _buildTableData(
                _formatCurrency(c['paid'] ?? 0.0),
                fonts['regular'],
              ),
              _buildTableData(
                _formatCurrency(c['balance'] ?? 0.0),
                fonts['regular'],
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Export expenses to Excel
  static Future<void> exportExpensesToExcel(
    List<Expense> expenses, {
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      debugPrint('Starting expenses export to Excel...');

      // Create Excel file
      final excel = Excel.createExcel();
      final sheet = excel['المصروفات'];

      // Add headers
      final headers = ['التاريخ', 'الوصف', 'التصنيف', 'المبلغ', 'ملاحظات'];

      for (int i = 0; i < headers.length; i++) {
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0))
            .value = TextCellValue(
          headers[i],
        );
      }

      // Add data
      for (int i = 0; i < expenses.length; i++) {
        final expense = expenses[i];
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: i + 1))
            .value = TextCellValue(
          DateFormat('yyyy-MM-dd HH:mm').format(expense.date),
        );
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: i + 1))
            .value = TextCellValue(
          expense.description,
        );
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: i + 1))
            .value = TextCellValue(
          expense.category,
        );
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: i + 1))
            .value = DoubleCellValue(
          expense.amount,
        );
        sheet
            .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: i + 1))
            .value = TextCellValue(
          expense.notes ?? '',
        );
      }

      // Add summary row
      final totalRow = expenses.length + 2;
      final totalAmount = expenses.fold<double>(
        0.0,
        (sum, expense) => sum + expense.amount,
      );

      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: totalRow))
          .value = TextCellValue(
        'الإجمالي:',
      );
      sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: totalRow))
          .value = DoubleCellValue(
        totalAmount,
      );

      // Save file
      final directory = await getApplicationDocumentsDirectory();
      final fileName =
          'expenses_report_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx';
      final file = File('${directory.path}/$fileName');

      final fileBytes = excel.save();
      await file.writeAsBytes(fileBytes!);

      debugPrint('Expenses exported successfully to: ${file.path}');
    } catch (e) {
      debugPrint('Error exporting expenses to Excel: $e');
      rethrow;
    }
  }

  pw.Widget _buildTableHeader(String text, pw.Font? font) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(5),
      child: pw.Text(
        ArabicHelper.reshapedText(text),
        style: pw.TextStyle(
          font: font,
          fontWeight: pw.FontWeight.bold,
          fontFallback: [pw.Font.helvetica()],
        ),
        textDirection: pw.TextDirection.rtl,
        textAlign: pw.TextAlign.center,
      ),
    );
  }

  pw.Widget _buildTableData(String text, pw.Font? font) {
    // Try to detect numeric balances and color positive amounts red (customer owes)
    PdfColor textColor = PdfColors.black;
    try {
      var cleaned = text.replaceAll(RegExp(r'[^0-9\.,-]'), '');
      cleaned = cleaned.replaceAll(',', '');
      double? value = double.tryParse(cleaned);
      value ??= double.tryParse(cleaned.replaceAll(',', '.'));
      if (value != null && value > 0) {
        textColor = PdfColors.red;
      }
    } catch (_) {
      // ignore parse errors
    }

    return pw.Container(
      padding: const pw.EdgeInsets.all(5),
      child: pw.Text(
        ArabicHelper.reshapedText(text),
        style: pw.TextStyle(
          font: font,
          fontFallback: [pw.Font.helvetica()],
          color: textColor,
        ),
        textDirection: pw.TextDirection.rtl,
        textAlign: pw.TextAlign.center,
      ),
    );
  }
}
