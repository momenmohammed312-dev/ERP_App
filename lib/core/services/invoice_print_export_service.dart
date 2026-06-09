import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'dart:ui' as ui;
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:pos_offline_desktop/widgets/universal_invoice_layout.dart';

/// Universal Invoice Print/Export Service
/// MANDATORY: Handles ALL invoice operations with identical formatting
/// NO EXCEPTIONS - Every export must use this service
class InvoicePrintExportService {
  /// 1. PRINT TO PDF (with preview)
  /// MANDATORY: Uses universal formatting
  static Future<void> printToPDF(InvoiceData invoiceData) async {
    final pdf = await _generatePDF(invoiceData);

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'invoice_${invoiceData.invoice.invoiceNumber}.pdf',
    );
  }

  /// 2. EXPORT TO PDF FILE
  /// MANDATORY: Uses universal formatting
  static Future<File> exportToPDFFile(InvoiceData invoiceData) async {
    final pdf = await _generatePDF(invoiceData);

    final output = await getTemporaryDirectory();
    final file = File(
      '${output.path}/invoice_${invoiceData.invoice.invoiceNumber}.pdf',
    );
    await file.writeAsBytes(await pdf.save());

    return file;
  }

  /// 3. SHARE PDF (WhatsApp, Email, etc.)
  /// MANDATORY: Uses universal formatting
  static Future<void> sharePDF(InvoiceData invoiceData) async {
    final file = await exportToPDFFile(invoiceData);

    // Share functionality requires share_plus package integration
    // PDF is generated and saved - ready for sharing when package is available
    debugPrint('PDF saved to: ${file.path}');
  }

  /// 4. EXPORT TO IMAGE (PNG)
  /// MANDATORY: Uses universal formatting
  static Future<File> exportToImage(
    BuildContext context,
    InvoiceData invoiceData,
  ) async {
    // Create the widget with print styling
    final widget = UniversalInvoiceLayout(
      invoiceData: invoiceData,
      isForPrinting: true,
    );

    // Capture widget as image
    final repaintBoundary = RenderRepaintBoundary();
    final renderView = RenderView(
      view: WidgetsBinding.instance.platformDispatcher.views.first,
      child: RenderPositionedBox(
        alignment: Alignment.center,
        child: repaintBoundary,
      ),
      configuration: ViewConfiguration(),
    );

    final pipelineOwner = PipelineOwner();
    final buildOwner = BuildOwner(focusManager: FocusManager());

    final rootElement = RenderObjectToWidgetAdapter<RenderBox>(
      container: repaintBoundary,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: MediaQuery(data: MediaQueryData(), child: widget),
      ),
    ).attachToRenderTree(buildOwner);

    buildOwner.buildScope(rootElement);
    buildOwner.finalizeTree();

    pipelineOwner.rootNode = renderView;
    renderView.prepareInitialFrame();

    buildOwner.buildScope(rootElement);
    buildOwner.finalizeTree();
    pipelineOwner.flushLayout();
    pipelineOwner.flushCompositingBits();
    pipelineOwner.flushPaint();

    final image = await repaintBoundary.toImage(pixelRatio: 2.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

    final output = await getTemporaryDirectory();
    final file = File(
      '${output.path}/invoice_${invoiceData.invoice.invoiceNumber}.png',
    );
    await file.writeAsBytes(byteData!.buffer.asUint8List());

    return file;
  }

  /// 5. PRINT TO PHYSICAL/THERMAL PRINTER
  /// MANDATORY: Uses universal formatting
  static Future<void> printToPhysicalPrinter(InvoiceData invoiceData) async {
    final pdf = await _generatePDF(invoiceData);

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'invoice_${invoiceData.invoice.invoiceNumber}.pdf',
      format: PdfPageFormat.roll80, // For thermal printers
    );
  }

  /// INTERNAL: Generate PDF with MANDATORY standard formatting
  /// CRITICAL: This must match UniversalInvoiceLayout exactly
  static Future<pw.Document> _generatePDF(InvoiceData invoiceData) async {
    final pdf = pw.Document();

    // Load Arabic fonts
    final arabicFont = await PdfGoogleFonts.cairoRegular();
    final arabicFontBold = await PdfGoogleFonts.cairoBold();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(base: arabicFont, bold: arabicFontBold),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              /// MANDATORY: Developer tag must appear on ALL PDFs
              pw.Center(
                child: pw.Text(
                  'Developed by MO2',
                  style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
                ),
              ),
              pw.SizedBox(height: 10),

              // Header
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'عرض أسعار',
                    style: pw.TextStyle(
                      fontSize: 20,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        invoiceData.storeInfo.storeName,
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                      ),
                      pw.Text(invoiceData.storeInfo.phone),
                      pw.Text(invoiceData.storeInfo.zipCode),
                      pw.Text(invoiceData.storeInfo.state),
                      if (invoiceData.storeInfo.taxNumber != null &&
                          invoiceData.storeInfo.taxNumber!.isNotEmpty)
                        pw.Text(
                          'الرقم الضريبي: ${invoiceData.storeInfo.taxNumber}',
                        ),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 20),

              // Customer Info
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey400),
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        if (invoiceData.invoice.projectName != null)
                          pw.Text(
                            'المشروع: ${invoiceData.invoice.projectName}',
                          ),
                        pw.Text(
                          'رقم الفاتورة: ${invoiceData.invoice.invoiceNumber}',
                        ),
                        pw.Text(
                          'التاريخ: ${_formatDate(invoiceData.invoice.invoiceDate)}',
                        ),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(
                          'العميل: ${invoiceData.invoice.customerName}',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                        ),
                        pw.Text(
                          'الموبايل: ${invoiceData.invoice.customerPhone}',
                        ),
                        pw.Text(
                          'المدينة: ${invoiceData.invoice.customerZipCode}',
                        ),
                        pw.Text(
                          'الولاية: ${invoiceData.invoice.customerState}',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),

              /// MANDATORY: 4-column table format (SOP 4.0)
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey400),
                columnWidths: {
                  0: pw.FlexColumnWidth(3), // Description
                  1: pw.FlexColumnWidth(1), // Quantity
                  2: pw.FlexColumnWidth(1.5), // Price
                  3: pw.FlexColumnWidth(1.5), // Total
                },
                children: [
                  // Header
                  pw.TableRow(
                    decoration: pw.BoxDecoration(color: PdfColors.grey300),
                    children: [
                      _pdfTableCell('الوصف', isHeader: true),
                      _pdfTableCell('الكمية', isHeader: true),
                      _pdfTableCell('السعر', isHeader: true),
                      _pdfTableCell('الإجمالي', isHeader: true),
                    ],
                  ),
                  // Items
                  ...invoiceData.items.map(
                    (item) => pw.TableRow(
                      children: [
                        _pdfTableCell(item.description, isBold: true),
                        _pdfTableCell('${item.quantity}'),
                        _pdfTableCell(
                          '${item.unitPrice.toStringAsFixed(2)} ج.م',
                        ),
                        _pdfTableCell(
                          '${item.totalPrice.toStringAsFixed(2)} ج.م',
                          isBold: true,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 10),

              /// MANDATORY: Totals section with "الصافى"
              pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey400),
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Column(
                  children: [
                    _pdfTotalRow('الصافي', invoiceData.subtotal),
                    if (invoiceData.invoice.isCreditAccount) ...[
                      pw.Divider(thickness: 2),
                      _pdfTotalRow(
                        'الرصيد الافتتاحي',
                        invoiceData.invoice.previousBalance,
                      ),
                      pw.Divider(thickness: 2),
                      _pdfTotalRow(
                        'إجمالي الرصيد المستحق',
                        invoiceData.grandTotal,
                        isBold: true,
                        fontSize: 14,
                      ),
                    ],
                  ],
                ),
              ),

              // Notes
              if (invoiceData.invoice.notes != null &&
                  invoiceData.invoice.notes!.isNotEmpty) ...[
                pw.SizedBox(height: 15),
                pw.Container(
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey400),
                    borderRadius: pw.BorderRadius.circular(4),
                    color: PdfColors.grey100,
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'ملاحظات:',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                      ),
                      pw.SizedBox(height: 5),
                      pw.Text(invoiceData.invoice.notes!),
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );

    return pdf;
  }

  /// Helper: PDF table cell with MANDATORY formatting
  static pw.Widget _pdfTableCell(
    String text, {
    bool isHeader = false,
    bool isBold = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text,
        textAlign: pw.TextAlign.right,
        style: pw.TextStyle(
          fontWeight: isHeader || isBold
              ? pw.FontWeight.bold
              : pw.FontWeight.normal,
          fontSize: 10,
        ),
      ),
    );
  }

  /// Helper: PDF total row with MANDATORY currency format
  static pw.Widget _pdfTotalRow(
    String label,
    double amount, {
    bool isBold = false,
    double fontSize = 12,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 5),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
              fontSize: fontSize,
            ),
          ),

          /// MANDATORY: All amounts formatted as "XX.XX ج.م"
          pw.Text(
            '${amount.toStringAsFixed(2)} ج.م',
            style: pw.TextStyle(
              fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
              fontSize: fontSize,
            ),
          ),
        ],
      ),
    );
  }

  /// Helper: Date formatting
  static String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}
