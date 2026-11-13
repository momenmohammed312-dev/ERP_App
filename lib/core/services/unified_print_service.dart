import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:pos_offline_desktop/core/utils/arabic_helper.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:pos_offline_desktop/core/services/settings_service.dart';

/// SOP 4.0: Global Unified System Redesign & Financial Reporting
/// MANDATORY: Single service for ALL document generation
/// NO EXCEPTIONS - Every export must use this service
class UnifiedPrintService {

  /// Summary-box math for invoice PDFs: returns
  /// (discountTotal, paidTotal, remainingTotal).
  /// - subtotal is already NET (discounts applied at save time), so the
  ///   discount row is informational and remaining never subtracts twice;
  /// - per-line discount is derived (qty*price - line total) because
  ///   InvoiceItem carries no discount field.
  static (double, double, double) invoiceSummaryTotals({
    required List<InvoiceItem> items,
    required double subtotal,
    required double paid,
  }) {
    final discount = items.fold<double>(
      0,
      (s, it) => s + (it.quantity * it.unitPrice - it.totalPrice),
    );
    return (discount, paid, subtotal - paid);
  }

  /// 1. GENERATE UNIFIED DOCUMENT
  /// Central method for all document types (Sales, Purchases, Customers, Suppliers)
  static Future<pw.Document> generateUnifiedDocument({
    required DocumentType documentType,
    required dynamic data,
    StoreInfo? storeInfo,
    Map<String, dynamic>? additionalData,
  }) async {
    final pdf = pw.Document();

    // Load business info from settings if storeInfo is null
    final businessInfo = await SettingsService.getBusinessInfo();
    final effectiveStoreInfo = storeInfo ?? StoreInfo(
      storeName: businessInfo['name'] ?? '',
      phone: businessInfo['phone'] ?? '',
      zipCode: '',
      state: businessInfo['address'] ?? '',
      taxNumber: businessInfo['taxNumber'],
    );
    final footerMsg = businessInfo['footer'] ?? 'شكراً لزيارتكم';

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
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(base: arabicFont, bold: arabicFontBold),
        margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        header: (pw.Context context) {
          if (context.pageNumber == 1) {
            return pw.Column(
              children: [
                _buildGlobalHeader(
                  pdf,
                  arabicFont,
                  arabicFontBold,
                  documentType,
                  effectiveStoreInfo,
                  logoImage,
                ),
                pw.SizedBox(height: 12),
              ],
            );
          }
          return pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 10),
            padding: const pw.EdgeInsets.only(bottom: 4),
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.5),
              ),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  effectiveStoreInfo.storeName,
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                    font: arabicFontBold,
                  ),
                ),
                pw.Text(
                  '${_getDocumentTitle(documentType)} (تابع)',
                  style: pw.TextStyle(
                    fontSize: 9,
                    font: arabicFont,
                    color: PdfColors.grey700,
                  ),
                ),
              ],
            ),
          );
        },
        footer: (pw.Context context) {
          return pw.Column(
            children: [
              _buildGlobalFooter(arabicFont, footerMsg),
              pw.SizedBox(height: 4),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'صفحة ${context.pageNumber} من ${context.pagesCount}',
                    style: pw.TextStyle(
                      fontSize: 8,
                      color: PdfColors.grey600,
                      font: arabicFont,
                    ),
                  ),
                  pw.Text(
                    'Developed by MO2',
                    style: const pw.TextStyle(
                      fontSize: 7,
                      color: PdfColors.grey500,
                    ),
                  ),
                ],
              ),
            ],
          );
        },
        build: (pw.Context context) {
          return documentContent;
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
    if (kIsWeb) {
      throw Exception('PDF export not supported on web platform');
    }
    final pdf = await generateUnifiedDocument(
      documentType: documentType,
      data: data,
      storeInfo: storeInfo,
      additionalData: additionalData,
    );

    final output = await getTemporaryDirectory();
    final file = File(
      '${output.path}/${fileName ?? '${_getDocumentTitle(documentType)}_${DateTime.now().millisecondsSinceEpoch}.pdf'}',
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
        /// Logo (if available)
        if (logoImage != null)
          pw.Center(
            child: pw.Column(
              children: [
                pw.Image(logoImage, width: 80, height: 80),
                pw.SizedBox(height: 8),
              ],
            ),
          ),

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

      case DocumentType.manufacturingCard:
        return await _buildManufacturingCardContent(
          pdf,
          arabicFont,
          arabicFontBold,
          documentType,
          data,
          additionalData,
        );

      case DocumentType.manufacturingReport:
        return await _buildManufacturingReportContent(
          pdf,
          arabicFont,
          arabicFontBold,
          documentType,
          data,
          additionalData,
        );

      case DocumentType.bomRecipeCard:
        return await _buildBomRecipeCardContent(
          pdf,
          arabicFont,
          arabicFontBold,
          documentType,
          data,
          additionalData,
        );

      case DocumentType.customerMaterialReceiptCard:
        return await _buildCustomerReceiptCardContent(
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

    // Summary-box math (computed once, before the tree — package:pdf has
    // no Builder widget). See [invoiceSummaryTotals] for the rules.
    final totals = UnifiedPrintService.invoiceSummaryTotals(
      items: invoiceData.items,
      subtotal: invoiceData.subtotal,
      paid: ((additionalData?['paidAmount'] ??
              invoiceData.invoice.paidAmount) as num)
          .toDouble(),
    );
    final discountTotal = totals.$1;
    final paidTotal = totals.$2;
    final remainingTotal = totals.$3;

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
                      'التاريخ: ${DateFormat('yyyy/MM/dd').format(invoiceData.invoice.invoiceDate.toLocal())}',
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
        columnWidths: const {
          0: pw.FlexColumnWidth(3.2), // Description
          1: pw.FlexColumnWidth(1),   // Quantity
          2: pw.FlexColumnWidth(1.4), // Price
          3: pw.FlexColumnWidth(1.4), // Total
        },
        children: [
          /// Table Header
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: PdfColors.grey300),
            repeat: true,
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
                  padding: invoiceData.items.length > 10
                      ? const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3)
                      : const pw.EdgeInsets.all(5),
                ),
                _buildTableCell(
                  '${item.quantity}',
                  font: arabicFont,
                  padding: invoiceData.items.length > 10
                      ? const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3)
                      : const pw.EdgeInsets.all(5),
                ),
                _buildTableCell(
                  '${item.unitPrice.toStringAsFixed(2)} ج.م',
                  font: arabicFont,
                  padding: invoiceData.items.length > 10
                      ? const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3)
                      : const pw.EdgeInsets.all(5),
                ),
                _buildTableCell(
                  '${item.totalPrice.toStringAsFixed(2)} ج.م',
                  isBold: true,
                  font: arabicFontBold,
                  padding: invoiceData.items.length > 10
                      ? const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3)
                      : const pw.EdgeInsets.all(5),
                ),
              ],
            ),
          ),
        ],
      ),
      pw.SizedBox(height: 10),

      /// Summary Section (keep intact on page boundary)
      pw.Container(
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey400),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        ),
        child: pw.Column(
          children: [
            _buildTotalRow(
              'إجمالي الفاتورة',
              invoiceData.subtotal,
              font: arabicFont,
            ),
            // Discount / paid / remaining rows (see math note above).
            if (discountTotal > 0.005)
              _buildTotalRow(
                'الخصم',
                discountTotal,
                font: arabicFont,
                fontSize: 10,
              ),
            if (paidTotal > 0)
              _buildTotalRow(
                'المدفوع',
                paidTotal,
                font: arabicFont,
                fontSize: 10,
              ),
            _buildTotalRow(
              'المتبقي',
              remainingTotal,
              font: arabicFont,
            ),
            if (additionalData?['cashAmount'] != null ||
                additionalData?['cardAmount'] != null ||
                additionalData?['creditAmount'] != null) ...[
              pw.SizedBox(height: 5),
              pw.Divider(thickness: 0.5, color: PdfColors.grey300),
              if ((additionalData?['cashAmount'] ?? 0) > 0)
                _buildTotalRow(
                  'مدفوع نقدي',
                  additionalData?['cashAmount'],
                  font: arabicFont,
                  fontSize: 10,
                ),
              if ((additionalData?['cardAmount'] ?? 0) > 0)
                _buildTotalRow(
                  'مدفوع فيزا',
                  additionalData?['cardAmount'],
                  font: arabicFont,
                  fontSize: 10,
                ),
              if ((additionalData?['creditAmount'] ?? 0) > 0)
                _buildTotalRow(
                  'مبلغ آجل',
                  additionalData?['creditAmount'],
                  font: arabicFont,
                  fontSize: 10,
                  color: PdfColors.red700,
                ),
            ],
            if (invoiceData.invoice.isCreditAccount ||
                (additionalData?['creditAmount'] ?? 0) > 0) ...[
              pw.Divider(),
              _buildTotalRow(
                'الرصيد الافتتاحي',
                invoiceData.invoice.previousBalance,
                font: arabicFont,
              ),
              pw.Divider(),
              _buildTotalRow(
                'إجمالي الحساب',
                invoiceData.grandTotal,
                isBold: true,
                fontSize: 14,
                font: arabicFontBold,
              ),
            ],
          ],
        ),
      ),
    ];
  }

  /// FEAT-010: production/consumption documentation card per manufacturing
  /// order. `data` = flat order fields map, `additionalData` = resolved
  /// names + custody movement/balance rows (all pre-formatted strings).
  static Future<List<pw.Widget>> _buildManufacturingCardContent(
    pw.Document pdf,
    pw.Font arabicFont,
    pw.Font arabicFontBold,
    DocumentType documentType,
    dynamic data,
    Map<String, dynamic>? additionalData,
  ) async {
    final order = data as Map<String, dynamic>;
    String info(String k, [String fallback = '—']) =>
        (order[k] ?? additionalData?[k])?.toString() ?? fallback;
    double numOf(String k) =>
        (order[k] as num?)?.toDouble() ?? 0.0;

    final movements =
        (additionalData?['movements'] as List<Map<String, dynamic>>?) ??
        const <Map<String, dynamic>>[];
    final balances =
        (additionalData?['balances'] as List<Map<String, dynamic>>?) ??
        const <Map<String, dynamic>>[];
    final scraps =
        (additionalData?['scraps'] as List<Map<String, dynamic>>?) ??
        const <Map<String, dynamic>>[];

    final delivered = numOf('deliveredQuantity');
    final produced = numOf('producedQuantity');
    final remaining = produced - delivered;
    final isInternal = order['orderType'] == 'تصنيع داخلي' ||
        order['orderType'] == 'internal' ||
        (movements.isEmpty && balances.isEmpty);
    final materials =
        (additionalData?['materials'] as List<Map<String, dynamic>>?) ??
            const <Map<String, dynamic>>[];
    final stages =
        (additionalData?['stages'] as List<Map<String, dynamic>>?) ??
            const <Map<String, dynamic>>[];

    return [
      /// Order info box
      pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey400),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Text(
              'أمر التصنيع: ${info('orderNumber')} — ${info('status')} (${info('orderType')})',
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
                font: arabicFontBold,
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              'العميل: ${info('customerName')}    الوصفة: ${info('bomName')}    '
              'المنتج النهائي: ${info('finishedProductName')}    '
              'العهدة: ${info('custodyOnHand')} وحدة',
              style: pw.TextStyle(fontSize: 10.5, font: arabicFont),
            ),
            pw.SizedBox(height: 6),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'التاريخ: ${info('createdDate')}',
                  style: pw.TextStyle(fontSize: 10, font: arabicFont),
                ),
                pw.Text(
                  'التشغيل: ${info('startedDate')}',
                  style: pw.TextStyle(fontSize: 10, font: arabicFont),
                ),
                pw.Text(
                  'الاكتمال: ${info('completedDate')}',
                  style: pw.TextStyle(fontSize: 10, font: arabicFont),
                ),
              ],
            ),
          ],
        ),
      ),
      pw.SizedBox(height: 12),

      /// Quantities summary row
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'مخطط: ${numOf('plannedQuantity').toStringAsFixed(1)}',
            style: pw.TextStyle(font: arabicFont, fontSize: 10),
          ),
          if (isInternal) ...[
            pw.Text(
              'المنجز السليم: ${produced.toStringAsFixed(1)}',
              style: pw.TextStyle(font: arabicFontBold, fontSize: 10, color: PdfColors.green800),
            ),
            pw.Text(
              'المسلّم: ${delivered.toStringAsFixed(1)}',
              style: pw.TextStyle(font: arabicFont, fontSize: 10),
            ),
          ] else ...[
            pw.Text(
              'المستهلك من العهدة: ${numOf('consumedQuantity').toStringAsFixed(1)}',
              style: pw.TextStyle(font: arabicFont, fontSize: 10),
            ),
            pw.Text(
              'رصيد العهدة بالمخزن: ${numOf('custodyOnHand').toStringAsFixed(1)}',
              style: pw.TextStyle(font: arabicFont, fontSize: 10),
            ),
          ],
        ],
      ),
      pw.SizedBox(height: 12),

      if (isInternal) ...[
        if (materials.isNotEmpty) ...[
          pw.Text('المواد الخام المطلوبة للطلب:', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, font: arabicFontBold)),
          pw.SizedBox(height: 4),
          pw.TableHelper.fromTextArray(
            headers: ['المادة الخام', 'الكمية المطلوبة', 'الوحدة', 'المتاح بالمخزن'],
            data: materials.map((m) => [
              m['name']?.toString() ?? '—',
              '${m['quantityRequired'] ?? 0}',
              m['unit']?.toString() ?? '—',
              '${m['available'] ?? 0}',
            ]).toList(),
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, font: arabicFontBold),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
            cellStyle: pw.TextStyle(fontSize: 8.5, font: arabicFont),
            cellAlignment: pw.Alignment.center,
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          ),
          pw.SizedBox(height: 10),
        ],
        if (stages.isNotEmpty) ...[
          pw.Text('مراحل الإنتاج والمخرجات:', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, font: arabicFontBold)),
          pw.SizedBox(height: 4),
          pw.TableHelper.fromTextArray(
            headers: ['المرحلة', 'الكمية الداخلة', 'المنجز السليم', 'الهالك', 'الحالة'],
            data: stages.map((s) => [
              s['stageName']?.toString() ?? '—',
              '${s['inputQuantity'] ?? 0}',
              '${s['outputQuantity'] ?? 0}',
              '${s['scrapQuantity'] ?? 0}',
              s['status'] == 'completed' ? 'مكتملة' : 'جارية',
            ]).toList(),
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, font: arabicFontBold),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
            cellStyle: pw.TextStyle(fontSize: 8.5, font: arabicFont),
            cellAlignment: pw.Alignment.center,
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          ),
          pw.SizedBox(height: 10),
        ],
      ] else ...[
        /// Custody movements table
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey400),
          columnWidths: {
            0: const pw.FlexColumnWidth(1.2), // Date
            1: const pw.FlexColumnWidth(1.4), // Movement
            2: const pw.FlexColumnWidth(2.2), // Product
            3: const pw.FlexColumnWidth(0.9), // Qty
            4: const pw.FlexColumnWidth(1.8), // Reference
          },
          children: [
            pw.TableRow(
              decoration: pw.BoxDecoration(color: PdfColors.grey300),
              children: [
                _buildTableCell('التاريخ', isHeader: true, font: arabicFontBold),
                _buildTableCell('النوع', isHeader: true, font: arabicFontBold),
                _buildTableCell('الصنف', isHeader: true, font: arabicFontBold),
                _buildTableCell('الكمية', isHeader: true, font: arabicFontBold),
                _buildTableCell('المرجع', isHeader: true, font: arabicFontBold),
              ],
            ),
            ...movements.map((m) {
              final qty = (m['quantity'] as num?)?.toDouble() ?? 0.0;
              return pw.TableRow(
                children: [
                  _buildTableCell(m['date']?.toString() ?? '—', font: arabicFont),
                  _buildTableCell(m['movementType']?.toString() ?? '—', font: arabicFont),
                  _buildTableCell(m['productName']?.toString() ?? '—', font: arabicFont),
                  _buildTableCell(qty.toStringAsFixed(qty.truncateToDouble() == qty ? 1 : 2), isBold: true, font: arabicFont),
                  _buildTableCell(m['reference']?.toString() ?? '—', font: arabicFont),
                ],
              );
            }),
          ],
        ),
        if (movements.isEmpty)
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            child: pw.Text(
              'لم يتم تسجيل حركات عهدة على هذا الأمر بعد',
              style: pw.TextStyle(fontSize: 10, font: arabicFont),
              textAlign: pw.TextAlign.center,
            ),
          ),
        pw.SizedBox(height: 14),

        /// Remaining custody balances table
        pw.Text(
          'باقي رصيد العهدة بالمخزن:',
          style: pw.TextStyle(
            fontSize: 11,
            fontWeight: pw.FontWeight.bold,
            font: arabicFontBold,
          ),
        ),
        pw.SizedBox(height: 6),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey400),
          columnWidths: {
            0: const pw.FlexColumnWidth(2.2),
            1: const pw.FlexColumnWidth(1.2),
            2: const pw.FlexColumnWidth(1),
            3: const pw.FlexColumnWidth(1.4),
          },
          children: [
            pw.TableRow(
              decoration: pw.BoxDecoration(color: PdfColors.grey300),
              children: [
                _buildTableCell('الصنف', isHeader: true, font: arabicFontBold),
                _buildTableCell('الرصيد المتاح', isHeader: true, font: arabicFontBold),
                _buildTableCell('المحجوز', isHeader: true, font: arabicFontBold),
                _buildTableCell('اللون / المقاس', isHeader: true, font: arabicFontBold),
              ],
            ),
            ...balances.map((b) {
              final onHand = (b['quantityOnHand'] as num?)?.toDouble() ?? 0.0;
              final allocated = (b['quantityAllocated'] as num?)?.toDouble() ?? 0.0;
              return pw.TableRow(
                children: [
                  _buildTableCell(b['productName']?.toString() ?? '—', font: arabicFont),
                  _buildTableCell(onHand.toStringAsFixed(1), isBold: true, color: PdfColors.green700, font: arabicFont),
                  _buildTableCell(allocated.toStringAsFixed(1), font: arabicFont),
                  _buildTableCell(b['colorSize']?.toString() ?? '—', font: arabicFont),
                ],
              );
            }),
          ],
        ),
        if (balances.isEmpty)
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            child: pw.Text(
              'لا توجد أرصدة عهدة باقية للعميل',
              style: pw.TextStyle(fontSize: 10, font: arabicFont),
              textAlign: pw.TextAlign.center,
            ),
          ),
      ],
      pw.SizedBox(height: 14),
      pw.Container(
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey400),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'المنتج فعلياً: ${produced.toStringAsFixed(1)}',
              style: pw.TextStyle(font: arabicFont, fontSize: 10),
            ),
            pw.Text(
              'المسلّم للعميل: ${delivered.toStringAsFixed(1)}',
              style: pw.TextStyle(font: arabicFont, fontSize: 10),
            ),
            pw.Text(
              'المتبقي للتسليم: ${remaining.toStringAsFixed(1)}',
              style: pw.TextStyle(font: arabicFont, fontSize: 10),
            ),
          ],
        ),
      ),
      if (scraps.isNotEmpty) ...[
        pw.SizedBox(height: 14),
        pw.Text(
          'الهالك والتوالف (Scrap):',
          style: pw.TextStyle(
            fontSize: 11,
            fontWeight: pw.FontWeight.bold,
            font: arabicFontBold,
          ),
        ),
        pw.SizedBox(height: 6),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey400),
          columnWidths: {
            0: const pw.FlexColumnWidth(1.2),
            1: const pw.FlexColumnWidth(2),
            2: const pw.FlexColumnWidth(0.9),
            3: const pw.FlexColumnWidth(1.4),
            4: const pw.FlexColumnWidth(1.2),
            5: const pw.FlexColumnWidth(1.3),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey300),
              children: [
                _buildTableCell('التاريخ', isHeader: true, font: arabicFontBold),
                _buildTableCell('الصنف', isHeader: true, font: arabicFontBold),
                _buildTableCell('الكمية', isHeader: true, font: arabicFontBold),
                _buildTableCell('السبب', isHeader: true, font: arabicFontBold),
                _buildTableCell('المتسبب', isHeader: true, font: arabicFontBold),
                _buildTableCell('إجراء التعويض', isHeader: true, font: arabicFontBold),
              ],
            ),
            ...scraps.map((s) {
              final qty = (s['quantity'] as num?)?.toDouble() ?? 0.0;
              final action = s['compensationAction']?.toString() ?? '—';
              final actionText = action == 'deducted_from_invoice'
                  ? 'خصم (${s['compensationAmount']} ج.م)'
                  : (action == 'replaced'
                      ? 'صرف بديل'
                      : (action == 'labour_waived'
                          ? 'إسقاط مصنعية'
                          : (action == 'none' ? 'بدون تعويض' : action)));
              return pw.TableRow(
                children: [
                  _buildTableCell(s['date']?.toString() ?? '—', font: arabicFont),
                  _buildTableCell(s['productName']?.toString() ?? '—', font: arabicFont),
                  _buildTableCell(
                    qty.toStringAsFixed(qty.truncateToDouble() == qty ? 1 : 2),
                    isBold: true,
                    color: PdfColors.red700,
                    font: arabicFont,
                  ),
                  _buildTableCell(s['reason']?.toString() ?? '—', font: arabicFont),
                  _buildTableCell(s['faultParty']?.toString() ?? '—', font: arabicFont),
                  _buildTableCell(actionText, font: arabicFont),
                ],
              );
            }),
          ],
        ),
      ],
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
  static pw.Widget _buildGlobalFooter(pw.Font arabicFont, String footerMsg) {
    return pw.Column(
      children: [
        pw.Divider(thickness: 2),
        pw.SizedBox(height: 5),
        pw.Center(
          child: pw.Text(
            ArabicHelper.reshapedText(footerMsg),
            style: pw.TextStyle(
              fontSize: 10,
              fontWeight: pw.FontWeight.bold,
              font: arabicFont,
            ),
          ),
        ),
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
    pw.EdgeInsets? padding,
  }) {
    return pw.Container(
      padding: padding ?? const pw.EdgeInsets.all(6),
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
    PdfColor? color,
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
              color: color,
            ),
          ),
          pw.Text(
            '${amount.toStringAsFixed(2)} ج.م',
            style: pw.TextStyle(
              fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
              fontSize: fontSize,
              font: font,
              color: color,
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
      case DocumentType.manufacturingCard:
        return 'بطاقة الإنتاج/الصرف';
      case DocumentType.manufacturingReport:
        return 'تقرير التصنيع';
      case DocumentType.bomRecipeCard:
        return 'بطاقة وصفة التصنيع';
      case DocumentType.customerMaterialReceiptCard:
        return 'إذن استلام خامات العميل';
    }
  }


  /// FEAT-026: Manufacturing Report PDF Generator
  static Future<List<pw.Widget>> _buildManufacturingReportContent(
    pw.Document pdf,
    pw.Font arabicFont,
    pw.Font arabicFontBold,
    DocumentType documentType,
    dynamic data,
    Map<String, dynamic>? additionalData,
  ) async {
    final reportData = data as Map<String, dynamic>;
    if (reportData['orderNumber'] != null) {
      final orderNo = reportData['orderNumber']?.toString() ?? '—';
      final status = reportData['status']?.toString() ?? '—';
      final orderType = reportData['orderType']?.toString() ?? '—';
      final prodName = reportData['finishedProductName']?.toString() ?? '—';
      final bomName = reportData['bomName']?.toString() ?? '—';
      final customerName = reportData['customerName']?.toString() ?? '—';
      final currentStage = reportData['currentStage']?.toString() ?? '—';
      final createdDate = reportData['createdDate']?.toString() ?? '—';

      final plannedQty = (reportData['plannedQuantity'] as num?)?.toDouble() ?? 0.0;
      final producedQty = (reportData['producedQuantity'] as num?)?.toDouble() ?? 0.0;
      final deliveredQty = (reportData['deliveredQuantity'] as num?)?.toDouble() ?? 0.0;

      final stages = (additionalData?['stages'] as List<Map<String, dynamic>>?) ?? [];
      final scraps = (additionalData?['scraps'] as List<Map<String, dynamic>>?) ?? [];
      final materials = (additionalData?['materials'] as List<Map<String, dynamic>>?) ?? [];

      return [
        pw.Container(
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey400),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'تقرير أمر التصنيع: $orderNo ($status)',
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                      font: arabicFontBold,
                    ),
                  ),
                  pw.Text(
                    'النوع: $orderType',
                    style: pw.TextStyle(fontSize: 10, font: arabicFont),
                  ),
                ],
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                'المنتج: $prodName    الوصفة: $bomName    العميل: $customerName',
                style: pw.TextStyle(fontSize: 10, font: arabicFont),
              ),
              pw.SizedBox(height: 4),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('تاريخ الإنشاء: $createdDate', style: pw.TextStyle(fontSize: 9.5, font: arabicFont)),
                  pw.Text('المرحلة الحالية: $currentStage', style: pw.TextStyle(fontSize: 9.5, font: arabicFontBold)),
                ],
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 10),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Expanded(
              child: pw.Container(
                margin: const pw.EdgeInsets.symmetric(horizontal: 4),
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  color: PdfColors.blue50,
                  border: pw.Border.all(color: PdfColors.blue200),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Column(
                  children: [
                    pw.Text('الكمية المخططة', style: pw.TextStyle(fontSize: 9, font: arabicFont)),
                    pw.SizedBox(height: 4),
                    pw.Text('$plannedQty', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, font: arabicFontBold)),
                  ],
                ),
              ),
            ),
            pw.Expanded(
              child: pw.Container(
                margin: const pw.EdgeInsets.symmetric(horizontal: 4),
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  color: PdfColors.green50,
                  border: pw.Border.all(color: PdfColors.green200),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Column(
                  children: [
                    pw.Text('المنجز السليم', style: pw.TextStyle(fontSize: 9, font: arabicFont)),
                    pw.SizedBox(height: 4),
                    pw.Text('$producedQty', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, font: arabicFontBold)),
                  ],
                ),
              ),
            ),
            pw.Expanded(
              child: pw.Container(
                margin: const pw.EdgeInsets.symmetric(horizontal: 4),
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  color: PdfColors.purple50,
                  border: pw.Border.all(color: PdfColors.purple200),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Column(
                  children: [
                    pw.Text('الكمية المسلّمة', style: pw.TextStyle(fontSize: 9, font: arabicFont)),
                    pw.SizedBox(height: 4),
                    pw.Text('$deliveredQty', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, font: arabicFontBold)),
                  ],
                ),
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 12),
        if (stages.isNotEmpty) ...[
          pw.Text('مراحل خط الإنتاج', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, font: arabicFontBold)),
          pw.SizedBox(height: 4),
          pw.TableHelper.fromTextArray(
            headers: ['المرحلة', 'الكمية الداخلة', 'المنجز السليم', 'الهالك', 'التكلفة', 'الحالة'],
            data: stages.map((s) => [
              s['stageName']?.toString() ?? '—',
              '${s['inputQuantity'] ?? 0}',
              '${s['outputQuantity'] ?? 0}',
              '${s['scrapQuantity'] ?? 0}',
              '${(s['stageCost'] as num?)?.toStringAsFixed(2) ?? "0.00"} ج.م',
              s['status'] == 'completed' ? 'مكتملة' : 'جارية',
            ]).toList(),
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, font: arabicFontBold),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
            cellStyle: pw.TextStyle(fontSize: 8.5, font: arabicFont),
            cellAlignment: pw.Alignment.center,
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          ),
          pw.SizedBox(height: 10),
        ],
        if (materials.isNotEmpty) ...[
          pw.Text('المواد الخام المطلوبة', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, font: arabicFontBold)),
          pw.SizedBox(height: 4),
          pw.TableHelper.fromTextArray(
            headers: ['المادة الخام', 'الكمية المطلوبة', 'الوحدة', 'المتاح بالمخزن'],
            data: materials.map((m) => [
              m['name']?.toString() ?? '—',
              '${m['quantityRequired'] ?? 0}',
              m['unit']?.toString() ?? '—',
              '${m['available'] ?? 0}',
            ]).toList(),
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, font: arabicFontBold),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
            cellStyle: pw.TextStyle(fontSize: 8.5, font: arabicFont),
            cellAlignment: pw.Alignment.center,
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          ),
          pw.SizedBox(height: 10),
        ],
        if (scraps.isNotEmpty) ...[
          pw.Text('سجل الهالك', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, font: arabicFontBold)),
          pw.SizedBox(height: 4),
          pw.TableHelper.fromTextArray(
            headers: ['التاريخ', 'الصنف', 'الكمية', 'السبب', 'المسؤول'],
            data: scraps.map((sc) => [
              sc['date']?.toString() ?? '—',
              sc['productName']?.toString() ?? '—',
              '${sc['quantity'] ?? 0}',
              sc['reason']?.toString() ?? '—',
              sc['faultParty']?.toString() ?? '—',
            ]).toList(),
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, font: arabicFontBold),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
            cellStyle: pw.TextStyle(fontSize: 8.5, font: arabicFont),
            cellAlignment: pw.Alignment.center,
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          ),
        ],
      ];
    }
    final title = reportData['title']?.toString() ?? 'تقرير التصنيع';
    final dateRange = reportData['dateRange']?.toString() ?? '';
    final summaryCards = (reportData['summaryCards'] as List<Map<String, dynamic>>?) ?? [];
    final columns = (reportData['columns'] as List<String>?) ?? [];
    final rows = (reportData['rows'] as List<List<String>>?) ?? [];

    return [
      pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey400),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              title,
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
                font: arabicFontBold,
              ),
            ),
            if (dateRange.isNotEmpty)
              pw.Text(
                'الفترة: $dateRange',
                style: pw.TextStyle(fontSize: 10, font: arabicFont),
              ),
          ],
        ),
      ),
      pw.SizedBox(height: 10),
      if (summaryCards.isNotEmpty) ...[
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: summaryCards.map((card) {
            return pw.Expanded(
              child: pw.Container(
                margin: const pw.EdgeInsets.symmetric(horizontal: 4),
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  border: pw.Border.all(color: PdfColors.grey300),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Column(
                  children: [
                    pw.Text(
                      card['label']?.toString() ?? '',
                      style: pw.TextStyle(fontSize: 9, font: arabicFont, color: PdfColors.grey700),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      card['value']?.toString() ?? '',
                      style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, font: arabicFontBold),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        pw.SizedBox(height: 12),
      ],
      if (columns.isNotEmpty && rows.isNotEmpty)
        pw.TableHelper.fromTextArray(
          headers: columns,
          data: rows,
          border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
          headerStyle: pw.TextStyle(
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
            font: arabicFontBold,
          ),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
          cellStyle: pw.TextStyle(fontSize: 8.5, font: arabicFont),
          cellAlignment: pw.Alignment.center,
          cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
        ),
    ];
  }

  /// FEAT-026: BOM Recipe Specification Card PDF
  static Future<List<pw.Widget>> _buildBomRecipeCardContent(
    pw.Document pdf,
    pw.Font arabicFont,
    pw.Font arabicFontBold,
    DocumentType documentType,
    dynamic data,
    Map<String, dynamic>? additionalData,
  ) async {
    final bom = data as Map<String, dynamic>;
    final items = (additionalData?['items'] as List<Map<String, dynamic>>?) ?? [];

    return [
      pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey400),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Text(
              'بطاقة وصفة التصنيع: ${bom['name'] ?? ''}',
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
                font: arabicFontBold,
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('المنتج النهائي: ${bom['productName'] ?? '—'}', style: pw.TextStyle(fontSize: 10, font: arabicFont)),
                pw.Text('الكود: ${bom['code'] ?? '—'}', style: pw.TextStyle(fontSize: 10, font: arabicFont)),
                pw.Text('العائد: ${bom['yieldQuantity'] ?? 1} وحدة', style: pw.TextStyle(fontSize: 10, font: arabicFont)),
                pw.Text('نسبة الهدر: ${bom['wastePercentage'] ?? 0}%', style: pw.TextStyle(fontSize: 10, font: arabicFont)),
              ],
            ),
          ],
        ),
      ),
      pw.SizedBox(height: 12),
      pw.Text('المكونات والخامات المطلوبة:', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, font: arabicFontBold)),
      pw.SizedBox(height: 6),
      pw.TableHelper.fromTextArray(
        headers: ['#', 'المادة الخام', 'الكمية المطلوبة', 'الوحدة', 'هدر خاص %', 'تكلفة الوحدة', 'إجمالي التكلفة'],
        data: items.asMap().entries.map((entry) {
          final it = entry.value;
          return [
            (entry.key + 1).toString(),
            it['productName']?.toString() ?? '',
            it['quantity']?.toString() ?? '',
            it['unit']?.toString() ?? '—',
            it['waste']?.toString() ?? '—',
            it['unitCost']?.toString() ?? '—',
            it['lineCost']?.toString() ?? '—',
          ];
        }).toList(),
        border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
        headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, font: arabicFontBold),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
        cellStyle: pw.TextStyle(fontSize: 8.5, font: arabicFont),
        cellAlignment: pw.Alignment.center,
        cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      ),
    ];
  }

  /// FEAT-026: Customer Material Receipt Note PDF
  static Future<List<pw.Widget>> _buildCustomerReceiptCardContent(
    pw.Document pdf,
    pw.Font arabicFont,
    pw.Font arabicFontBold,
    DocumentType documentType,
    dynamic data,
    Map<String, dynamic>? additionalData,
  ) async {
    final receipt = data as Map<String, dynamic>;
    final items = (additionalData?['items'] as List<Map<String, dynamic>>?) ?? [];

    return [
      pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey400),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'إذن استلام خامات عميل (عهدة): ${receipt['receiptNumber'] ?? ''}',
                  style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, font: arabicFontBold),
                ),
                pw.Text('التاريخ: ${receipt['date'] ?? ''}', style: pw.TextStyle(fontSize: 10, font: arabicFont)),
              ],
            ),
            pw.SizedBox(height: 6),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('العميل: ${receipt['customerName'] ?? '—'}', style: pw.TextStyle(fontSize: 10, font: arabicFont)),
                pw.Text('المستلم / الفاحص: ${receipt['receivedBy'] ?? '—'}', style: pw.TextStyle(fontSize: 10, font: arabicFont)),
              ],
            ),
            if (receipt['notes'] != null && receipt['notes'].toString().isNotEmpty) ...[
              pw.SizedBox(height: 4),
              pw.Text('ملاحظات: ${receipt['notes']}', style: pw.TextStyle(fontSize: 9, font: arabicFont, color: PdfColors.grey700)),
            ],
          ],
        ),
      ),
      pw.SizedBox(height: 12),
      pw.Text('الأصناف المستلمة ونتائج الفحص:', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, font: arabicFontBold)),
      pw.SizedBox(height: 6),
      pw.TableHelper.fromTextArray(
        headers: ['#', 'المنتج / الخامة', 'المستلم كلياً', 'معيب / مرفوض', 'المقبول للعهدة', 'ملاحظات / سبب الرفض'],
        data: items.asMap().entries.map((entry) {
          final it = entry.value;
          return [
            (entry.key + 1).toString(),
            it['productName']?.toString() ?? '',
            it['receivedQty']?.toString() ?? '0',
            it['defectiveQty']?.toString() ?? '0',
            it['acceptedQty']?.toString() ?? '0',
            it['reason']?.toString() ?? '—',
          ];
        }).toList(),
        border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
        headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, font: arabicFontBold),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
        cellStyle: pw.TextStyle(fontSize: 8.5, font: arabicFont),
        cellAlignment: pw.Alignment.center,
        cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      ),
    ];
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
      final logoPath = await SettingsService.getBusinessLogoPath();
      if (logoPath != null && logoPath.isNotEmpty) {
        final file = File(logoPath);
        if (await file.exists()) {
          final logoData = await file.readAsBytes();
          return pw.MemoryImage(logoData);
        }
      }
      return null;
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
  /// FEAT-010: production/consumption documentation card per MO
  manufacturingCard,
  /// FEAT-026: manufacturing reports (costs, stages & variants, consumption, scraps)
  manufacturingReport,
  /// FEAT-026: recipe specification card
  bomRecipeCard,
  /// FEAT-026: customer material receipt note
  customerMaterialReceiptCard,
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
    invoice.isCreditAccount
        ? invoice.previousBalance + (invoice.totalAmount - invoice.paidAmount)
        : invoice.totalAmount;
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
  final double paidAmount;
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
    this.paidAmount = 0,
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
