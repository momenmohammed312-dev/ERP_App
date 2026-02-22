import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:pos_offline_desktop/core/utils/arabic_helper.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

/// SOP 4.0: Global Unified System Redesign & Financial Reporting
/// MANDATORY: Single service for ALL document generation
/// NO EXCEPTIONS - Every export must use this service
class UnifiedPrintService {
  static const String _branding = 'Developed by MO2';
  static const String _logoAssetPath = 'assets/recipt/recipt_logo.png';

  /// 1. GENERATE UNIFIED DOCUMENT
  /// Central method for all document types (Sales, Purchases, Customers, Suppliers)
  static Future<pw.Document> generateUnifiedDocument({
    required DocumentType documentType,
    required dynamic data,
    StoreInfo? storeInfo,
    Map<String, dynamic>? additionalData,
  }) async {
    final pdf = pw.Document();

    // Load Arabic fonts
    final arabicFont = await _loadArabicFont();
    final arabicFontBold = await _loadArabicFontBold();

    // Load logo image
    final logoImage = await _loadLogoImage();

    // Build document content first
    final documentContent = await _buildDocumentContent(
      pdf,
      arabicFont,
      arabicFontBold,
      documentType,
      data,
      additionalData,
    );

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(base: arabicFont, bold: arabicFontBold),
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              /// MANDATORY: Global Header
              _buildGlobalHeader(
                pdf,
                arabicFont,
                arabicFontBold,
                documentType,
                storeInfo,
                logoImage,
              ),
              pw.SizedBox(height: 20),

              /// Document-specific content
              ...documentContent,

              /// MANDATORY: Footer
              pw.Expanded(child: pw.Container()),
              _buildGlobalFooter(arabicFont),
            ],
          );
        },
      ),
    );

    return pdf;
  }

  /// 2. PRINT TO PHYSICAL/THERMAL PRINTER
  static Future<void> printToThermalPrinter({
    required DocumentType documentType,
    required dynamic data,
    StoreInfo? storeInfo,
    Map<String, dynamic>? additionalData,
  }) async {
    final pdf = await generateUnifiedDocument(
      documentType: documentType,
      data: data,
      storeInfo: storeInfo,
      additionalData: additionalData,
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name:
          '${_getDocumentTitle(documentType)}_${DateTime.now().millisecondsSinceEpoch}.pdf',
      format: PdfPageFormat.roll80, // For 80mm thermal printers
    );
  }

  /// 3. EXPORT TO PDF FILE
  static Future<File> exportToPDFFile({
    required DocumentType documentType,
    required dynamic data,
    StoreInfo? storeInfo,
    Map<String, dynamic>? additionalData,
    String? fileName,
  }) async {
    final pdf = await generateUnifiedDocument(
      documentType: documentType,
      data: data,
      storeInfo: storeInfo,
      additionalData: additionalData,
    );

    final output = await getTemporaryDirectory();
    final file = File(
      '${output.path}/${fileName ?? '${_getDocumentTitle(documentType)}_${DateTime.now().millisecondsSinceEpoch}'}.pdf}',
    );
    await file.writeAsBytes(await pdf.save());

    return file;
  }

  /// 4. SHARE DOCUMENT (WhatsApp, Email, etc.)
  static Future<void> shareDocument({
    required DocumentType documentType,
    required dynamic data,
    StoreInfo? storeInfo,
    Map<String, dynamic>? additionalData,
  }) async {
    final file = await exportToPDFFile(
      documentType: documentType,
      data: data,
      storeInfo: storeInfo,
      additionalData: additionalData,
    );

    // Share functionality requires share_plus package integration
    debugPrint('Document saved to: ${file.path}');
  }

  /// MANDATORY: Global Header Implementation
  static pw.Widget _buildGlobalHeader(
    pw.Document pdf,
    pw.Font arabicFont,
    pw.Font arabicFontBold,
    DocumentType documentType,
    StoreInfo? storeInfo,
    pw.MemoryImage? logoImage,
  ) {
    return pw.Column(
      children: [
        /// Logo (Centered at top)
        if (logoImage != null)
          pw.Center(
            child: pw.Image(
              logoImage,
              height: 100, // Enlarged from 60pt to 100pt
              fit: pw.BoxFit.contain,
            ),
          )
        else
          // Fallback to text branding if logo fails to load
          pw.Center(
            child: pw.Text(
              _branding,
              style: pw.TextStyle(
                fontSize: 12,
                color: PdfColors.grey600,
                font: arabicFont,
              ),
            ),
          ),
        pw.SizedBox(height: 10),

        /// Company Info (from StoreInfoTable)
        if (storeInfo != null) ...[
          pw.Center(
            child: pw.Column(
              children: [
                pw.Text(
                  storeInfo.storeName,
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                    font: arabicFontBold,
                  ),
                ),
                pw.Text(
                  storeInfo.phone,
                  style: pw.TextStyle(fontSize: 12, font: arabicFont),
                ),
                if (storeInfo.taxNumber != null)
                  pw.Text(
                    'الرقم الضريبي: ${storeInfo.taxNumber}',
                    style: pw.TextStyle(fontSize: 12, font: arabicFont),
                  ),
              ],
            ),
          ),
          pw.SizedBox(height: 10),
        ],

        /// Date and Time
        pw.Center(
          child: pw.Text(
            ArabicHelper.reshapedText(
              'التاريخ: ${DateFormat('yyyy/MM/dd HH:mm').format(DateTime.now())}',
            ),
            style: pw.TextStyle(fontSize: 12, font: arabicFont),
          ),
        ),
      ],
    );
  }

  /// Document-specific content generation
  static Future<List<pw.Widget>> _buildDocumentContent(
    pw.Document pdf,
    pw.Font arabicFont,
    pw.Font arabicFontBold,
    DocumentType documentType,
    dynamic data,
    Map<String, dynamic>? additionalData,
  ) async {
    switch (documentType) {
      case DocumentType.salesInvoice:
      case DocumentType.purchaseInvoice:
        return await _buildInvoiceContent(
          pdf,
          arabicFont,
          arabicFontBold,
          documentType,
          data,
          additionalData,
        );

      case DocumentType.customerStatement:
      case DocumentType.supplierStatement:
        return await _buildAccountStatementContent(
          pdf,
          arabicFont,
          arabicFontBold,
          documentType,
          data,
          additionalData,
        );

      case DocumentType.salesReport:
      case DocumentType.purchaseReport:
      case DocumentType.expenseReport:
      case DocumentType.paymentVoucher:
      case DocumentType.receiptVoucher:
        return await _buildReportContent(
          pdf,
          arabicFont,
          arabicFontBold,
          documentType,
          data,
          additionalData,
        );
    }
  }

  /// MANDATORY: 5-Column Grid Table for Sales & Purchases
  static Future<List<pw.Widget>> _buildInvoiceContent(
    pw.Document pdf,
    pw.Font arabicFont,
    pw.Font arabicFontBold,
    DocumentType documentType,
    dynamic data,
    Map<String, dynamic>? additionalData,
  ) async {
    final isSales = documentType == DocumentType.salesInvoice;
    final invoiceData = data as InvoiceData;

    return [
      /// Header with Company Name and Title
      pw.Container(
        width: double.infinity,
        child: pw.Column(
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.SizedBox(height: 8),
                    pw.Text(
                      'التاريخ: ${DateFormat('yyyy/MM/dd HH:mm').format(DateTime.now())}',
                      style: pw.TextStyle(font: arabicFont),
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'رقم الفاتورة: ${invoiceData.invoice.invoiceNumber}',
                      style: pw.TextStyle(font: arabicFont),
                    ),
                    pw.Text(
                      'التاريخ: ${DateFormat('yyyy/MM/dd').format(invoiceData.invoice.invoiceDate)}',
                      style: pw.TextStyle(font: arabicFont),
                    ),
                    pw.Text(
                      'العميل: ${invoiceData.invoice.customerName}',
                      style: pw.TextStyle(font: arabicFont),
                    ),
                    pw.Text(
                      'الموبايل: ${invoiceData.invoice.customerPhone}',
                      style: pw.TextStyle(font: arabicFont),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
      pw.SizedBox(height: 20),

      /// MANDATORY: 4-Column Grid Table
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey400),
        columnWidths: {
          0: const pw.FlexColumnWidth(3), // Description
          1: const pw.FlexColumnWidth(1), // Quantity
          2: const pw.FlexColumnWidth(1.5), // Price
          3: const pw.FlexColumnWidth(1.5), // Total
        },
        children: [
          /// Table Header
          pw.TableRow(
            decoration: pw.BoxDecoration(color: PdfColors.grey300),
            children: [
              _buildTableCell('الوصف', isHeader: true, font: arabicFontBold),
              _buildTableCell('الكمية', isHeader: true, font: arabicFontBold),
              _buildTableCell('السعر', isHeader: true, font: arabicFontBold),
              _buildTableCell('الإجمالي', isHeader: true, font: arabicFontBold),
            ],
          ),

          /// Table Data
          ...invoiceData.items.map(
            (item) => pw.TableRow(
              children: [
                _buildTableCell(
                  item.description,
                  isBold: true,
                  font: arabicFontBold,
                ),
                _buildTableCell('${item.quantity}', font: arabicFont),
                _buildTableCell(
                  '${item.unitPrice.toStringAsFixed(2)} ج.م',
                  font: arabicFont,
                ),
                _buildTableCell(
                  '${item.totalPrice.toStringAsFixed(2)} ج.م',
                  isBold: true,
                  font: arabicFontBold,
                ),
              ],
            ),
          ),
        ],
      ),
      pw.SizedBox(height: 10),

      /// Summary Section
      pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey400),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        ),
        child: pw.Column(
          children: [
            if (invoiceData.invoice.isCreditAccount) ...[
              _buildTotalRow(
                'الرصيد السابق',
                invoiceData.invoice.previousBalance,
                font: arabicFont,
              ),
              pw.Divider(),
              _buildTotalRow(
                'الإجمالي',
                invoiceData.subtotal,
                font: arabicFont,
              ),
              if (additionalData?['paidAmount'] != null &&
                  additionalData!['paidAmount'] > 0) ...[
                pw.Divider(),
                _buildTotalRow(
                  'المدفوع',
                  additionalData['paidAmount'],
                  font: arabicFont,
                ),
              ],
              pw.Divider(),
              _buildTotalRow(
                'إجمالي الرصيد المستحق',
                invoiceData.grandTotal,
                isBold: true,
                fontSize: 14,
                font: arabicFontBold,
              ),
            ] else ...[
              pw.Divider(),
              _buildTotalRow(
                'الإجمالي',
                invoiceData.subtotal,
                font: arabicFont,
              ),
              pw.Divider(),
              _buildTotalRow(
                'المدفوع',
                invoiceData.grandTotal,
                font: arabicFont,
              ),
            ],
          ],
        ),
      ),
    ];
  }

  /// Customer & Supplier Ledger with Running Balance
  static Future<List<pw.Widget>> _buildAccountStatementContent(
    pw.Document pdf,
    pw.Font arabicFont,
    pw.Font arabicFontBold,
    DocumentType documentType,
    dynamic data,
    Map<String, dynamic>? additionalData,
  ) async {
    final isCustomer = documentType == DocumentType.customerStatement;
    final transactions = data as List<Map<String, dynamic>>;
    final customerName = additionalData?['customerName'] ?? 'غير محدد';
    final currentBalance = additionalData?['currentBalance'] ?? 0.0;

    return [
      /// Account Info
      pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey400),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        ),
        child: pw.Column(
          children: [
            pw.Text(
              '${isCustomer ? 'العميل' : 'المورد'}: $customerName',
              style: pw.TextStyle(
                fontSize: 16,
                fontWeight: pw.FontWeight.bold,
                font: arabicFontBold,
              ),
            ),
            pw.SizedBox(height: 5),
            pw.Text(
              'الرصيد الحالي: ${currentBalance.toStringAsFixed(2)} ج.م',
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
                color: currentBalance >= 0
                    ? PdfColors.red700
                    : PdfColors.green700,
                font: arabicFontBold,
              ),
            ),
          ],
        ),
      ),
      pw.SizedBox(height: 20),

      /// MANDATORY: Running Balance Table
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey400),
        columnWidths: {
          0: const pw.FlexColumnWidth(1), // Date
          1: const pw.FlexColumnWidth(1.2), // Receipt#
          2: const pw.FlexColumnWidth(2.5), // Statement
          3: const pw.FlexColumnWidth(1), // Debit
          4: const pw.FlexColumnWidth(1), // Credit
          5: const pw.FlexColumnWidth(1.2), // Balance
        },
        children: [
          /// Table Header
          pw.TableRow(
            decoration: pw.BoxDecoration(color: PdfColors.grey300),
            children: [
              _buildTableCell('التاريخ', isHeader: true, font: arabicFontBold),
              _buildTableCell(
                'رقم الإيصال',
                isHeader: true,
                font: arabicFontBold,
              ),
              _buildTableCell('البيان', isHeader: true, font: arabicFontBold),
              _buildTableCell('مدين', isHeader: true, font: arabicFontBold),
              _buildTableCell('دائن', isHeader: true, font: arabicFontBold),
              _buildTableCell('الرصيد', isHeader: true, font: arabicFontBold),
            ],
          ),

          /// Table Data with Running Balance
          ...transactions.asMap().entries.map((entry) {
            final index = entry.key;
            final transaction = entry.value;
            final balance = transaction['balance'] as double? ?? 0.0;

            return pw.TableRow(
              decoration: pw.BoxDecoration(
                color: index % 2 == 0 ? PdfColors.white : PdfColors.grey50,
              ),
              children: [
                _buildTableCell(
                  DateFormat(
                    'yyyy/MM/dd',
                  ).format(transaction['date'] as DateTime),
                  font: arabicFont,
                ),
                _buildTableCell(
                  transaction['receiptNumber']?.toString() ?? '-',
                  font: arabicFont,
                ),
                _buildTableCell(
                  transaction['description']?.toString() ?? '',
                  font: arabicFont,
                ),
                _buildTableCell(
                  (transaction['debit'] as double? ?? 0.0).toStringAsFixed(2),
                  font: arabicFont,
                ),
                _buildTableCell(
                  (transaction['credit'] as double? ?? 0.0).toStringAsFixed(2),
                  font: arabicFont,
                ),
                _buildTableCell(
                  balance.toStringAsFixed(2),
                  isBold: true,
                  color: balance >= 0 ? PdfColors.red700 : PdfColors.green700,
                  font: arabicFontBold,
                ),
              ],
            );
          }),
        ],
      ),
    ];
  }

  /// Report Content (Sales, Purchases, etc.)
  static Future<List<pw.Widget>> _buildReportContent(
    pw.Document pdf,
    pw.Font arabicFont,
    pw.Font arabicFontBold,
    DocumentType documentType,
    dynamic data,
    Map<String, dynamic>? additionalData,
  ) async {
    final reportData = data as List<Map<String, dynamic>>;

    return [
      /// Report Header
      pw.Container(
        width: double.infinity,
        child: pw.Column(
          children: [
            pw.SizedBox(height: 8),
            // Report Title
            pw.Text(
              ArabicHelper.reshapedText(_getDocumentTitle(documentType)),
              style: pw.TextStyle(
                fontSize: 16,
                fontWeight: pw.FontWeight.bold,
                font: arabicFontBold,
              ),
              textDirection: pw.TextDirection.rtl,
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              'التاريخ: ${DateFormat('yyyy/MM/dd HH:mm').format(DateTime.now())}',
              style: pw.TextStyle(font: arabicFont),
            ),
          ],
        ),
      ),
      pw.SizedBox(height: 20),

      /// Report Table
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey400),
        columnWidths: {
          0: const pw.FlexColumnWidth(1), // ID
          1: const pw.FlexColumnWidth(2), // Date
          2: const pw.FlexColumnWidth(2), // Customer/Supplier
          3: const pw.FlexColumnWidth(3), // Description
          4: const pw.FlexColumnWidth(1.5), // Total
          5: const pw.FlexColumnWidth(1.5), // Paid
          6: const pw.FlexColumnWidth(1.5), // Remaining
        },
        children: [
          /// Table Header
          pw.TableRow(
            decoration: pw.BoxDecoration(color: PdfColors.grey300),
            children: [
              _buildTableCell('الرقم', isHeader: true, font: arabicFontBold),
              _buildTableCell('التاريخ', isHeader: true, font: arabicFontBold),
              _buildTableCell(
                documentType == DocumentType.salesReport ? 'العميل' : 'المورد',
                isHeader: true,
                font: arabicFontBold,
              ),
              _buildTableCell('الوصف', isHeader: true, font: arabicFontBold),
              _buildTableCell('الإجمالي', isHeader: true, font: arabicFontBold),
              _buildTableCell('المدفوع', isHeader: true, font: arabicFontBold),
              _buildTableCell('الباقي', isHeader: true, font: arabicFontBold),
            ],
          ),

          /// Table Data
          ...reportData.map(
            (row) => pw.TableRow(
              children: [
                _buildTableCell(row['id']?.toString() ?? '', font: arabicFont),
                _buildTableCell(
                  row['date'] != null
                      ? DateFormat('yyyy/MM/dd').format(row['date'] as DateTime)
                      : '',
                  font: arabicFont,
                ),
                _buildTableCell(
                  row['customerName']?.toString() ?? '',
                  font: arabicFont,
                ),
                _buildTableCell(
                  row['description']?.toString() ?? '',
                  font: arabicFont,
                ),
                _buildTableCell(
                  (row['totalAmount'] as double? ?? 0.0).toStringAsFixed(2),
                  font: arabicFont,
                ),
                _buildTableCell(
                  (row['paidAmount'] as double? ?? 0.0).toStringAsFixed(2),
                  font: arabicFont,
                ),
                _buildTableCell(
                  (row['remainingAmount'] as double? ?? 0.0).toStringAsFixed(2),
                  font: arabicFont,
                ),
              ],
            ),
          ),
        ],
      ),
    ];
  }

  /// MANDATORY: Global Footer
  static pw.Widget _buildGlobalFooter(pw.Font arabicFont) {
    return pw.Column(
      children: [
        pw.Divider(thickness: 2),
        pw.SizedBox(height: 5),
        pw.Center(
          child: pw.Text(
            'تم الإنشاء في ${DateFormat('yyyy/MM/dd HH:mm').format(DateTime.now())}',
            style: pw.TextStyle(
              fontSize: 8,
              color: PdfColors.grey600,
              font: arabicFont,
            ),
          ),
        ),
      ],
    );
  }

  /// Helper: Build table cell with consistent formatting
  static pw.Widget _buildTableCell(
    String text, {
    bool isHeader = false,
    bool isBold = false,
    PdfColor? color,
    pw.Font? font,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text,
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(
          fontWeight: isHeader || isBold
              ? pw.FontWeight.bold
              : pw.FontWeight.normal,
          fontSize: isHeader ? 10 : 9,
          color: color ?? PdfColors.black,
          font: font,
        ),
      ),
    );
  }

  /// Helper: Build total row
  static pw.Widget _buildTotalRow(
    String label,
    double amount, {
    bool isBold = false,
    double fontSize = 12,
    pw.Font? font,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
              fontSize: fontSize,
              font: font,
            ),
          ),
          pw.Text(
            '${amount.toStringAsFixed(2)} ج.م',
            style: pw.TextStyle(
              fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
              fontSize: fontSize,
              font: font,
            ),
          ),
        ],
      ),
    );
  }

  /// Helper: Get document title based on type
  static String _getDocumentTitle(DocumentType documentType) {
    switch (documentType) {
      case DocumentType.salesInvoice:
        return 'فاتورة مبيعات';
      case DocumentType.purchaseInvoice:
        return 'فاتورة مشتريات';
      case DocumentType.customerStatement:
        return 'كشف حساب عميل';
      case DocumentType.supplierStatement:
        return 'كشف حساب مورد';
      case DocumentType.salesReport:
        return 'تقرير المبيعات';
      case DocumentType.purchaseReport:
        return 'تقرير المشتريات';
      case DocumentType.expenseReport:
        return 'تقرير المصروفات';
      case DocumentType.paymentVoucher:
        return 'سند صرف';
      case DocumentType.receiptVoucher:
        return 'سند قبض';
    }
  }

  /// Helper: Load Arabic font
  static Future<pw.Font> _loadArabicFont() async {
    try {
      final fontData = await rootBundle.load(
        'assets/fonts/NotoNaskhArabic-Regular.ttf',
      );
      return pw.Font.ttf(fontData);
    } catch (e) {
      debugPrint('Failed to load Arabic font: $e');
      return pw.Font.courier();
    }
  }

  /// Helper: Load Arabic bold font
  static Future<pw.Font> _loadArabicFontBold() async {
    try {
      final fontData = await rootBundle.load(
        'assets/fonts/NotoNaskhArabic-Regular.ttf',
      );
      return pw.Font.ttf(fontData);
    } catch (e) {
      debugPrint('Failed to load Arabic bold font: $e');
      return pw.Font.courierBold();
    }
  }

  /// Helper: Load logo image for PDF generation
  static Future<pw.MemoryImage?> _loadLogoImage() async {
    try {
      final logoData = await rootBundle.load(_logoAssetPath);
      return pw.MemoryImage(logoData.buffer.asUint8List());
    } catch (e) {
      debugPrint('Failed to load logo image: $e');
      return null;
    }
  }
}

/// Document Types Enumeration
enum DocumentType {
  salesInvoice,
  purchaseInvoice,
  customerStatement,
  supplierStatement,
  salesReport,
  purchaseReport,
  expenseReport,
  paymentVoucher,
  receiptVoucher,
}

/// Enhanced Store Info Model (from StoreInfoTable)
class StoreInfo {
  final String storeName;
  final String phone;
  final String zipCode;
  final String state;
  final String? taxNumber;
  final String? logoPath;

  StoreInfo({
    required this.storeName,
    required this.phone,
    required this.zipCode,
    required this.state,
    this.taxNumber,
    this.logoPath,
  });

  /// Factory to create from database StoreInfo
  factory StoreInfo.fromDatabase(StoreInfo store) {
    return StoreInfo(
      storeName: store.storeName,
      phone: store.phone,
      zipCode: store.zipCode,
      state: store.state,
      taxNumber: store.taxNumber,
      logoPath: store.logoPath,
    );
  }
}

/// Enhanced Invoice Data Model for SOP 4.0
class InvoiceData {
  final Invoice invoice;
  final List<InvoiceItem> items;
  final StoreInfo? storeInfo;

  InvoiceData({required this.invoice, required this.items, this.storeInfo});

  double get subtotal => items.fold(0.0, (sum, item) => sum + item.totalPrice);

  double get grandTotal =>
      invoice.isCreditAccount ? subtotal + invoice.previousBalance : subtotal;
}

/// Enhanced Invoice Model for SOP 4.0
class Invoice {
  final int id;
  final String invoiceNumber;
  final String customerName;
  final String customerPhone;
  final String customerZipCode;
  final String customerState;
  final DateTime invoiceDate;
  final double subtotal;
  final bool isCreditAccount;
  final double previousBalance;
  final double totalAmount;
  final String? notes;

  Invoice({
    required this.id,
    required this.invoiceNumber,
    required this.customerName,
    required this.customerPhone,
    required this.customerZipCode,
    required this.customerState,
    required this.invoiceDate,
    required this.subtotal,
    required this.isCreditAccount,
    required this.previousBalance,
    required this.totalAmount,
    this.notes,
  });
}

/// Enhanced Invoice Item Model for SOP 4.0 (with Unit)
class InvoiceItem {
  final int id;
  final int invoiceId;
  final String description;
  final String? unit; // NEW: Unit field
  final int quantity;
  final double unitPrice;
  final double totalPrice;

  InvoiceItem({
    required this.id,
    required this.invoiceId,
    required this.description,
    this.unit,
    required this.quantity,
    required this.unitPrice,
    required this.totalPrice,
  });
}
