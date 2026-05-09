import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';

class PurchasesPdfService {
  static pw.Font? _arabicFont;
  static pw.Font? _latinFont;

  static Future<void> _loadFonts() async {
    if (_arabicFont == null) {
      _arabicFont = await PdfGoogleFonts.notoSansArabicRegular();
      _latinFont = pw.Font.helvetica(); // Built-in Latin font
    }
  }

  static Future<void> generatePurchasesPdf(List<Purchase> purchases) async {
    await _loadFonts();

    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(
          base: _arabicFont ?? pw.Font.courier(),
          fontFallback: [_latinFont ?? pw.Font.helvetica()],
        ),
        build: (context) => pw.Column(
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
                      'تقرير المشتريات',
                      style: pw.TextStyle(
                        fontSize: 24,
                        fontWeight: pw.FontWeight.bold,
                        font: _arabicFont,
                      ),
                    ),
                    pw.SizedBox(height: 8),
                    pw.Text(
                      'تاريخ الطباعة: ${DateFormat('yyyy/MM/dd HH:mm').format(DateTime.now())}',
                      style: pw.TextStyle(fontSize: 12, font: _arabicFont),
                    ),
                  ],
                ),
                pw.Text(
                  'Developed by MO2',
                  style: pw.TextStyle(
                    fontSize: 10,
                    font: _latinFont,
                    color: PdfColors.grey,
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 20),

            // Summary
            _buildSummaryCard(purchases),
            pw.SizedBox(height: 20),

            // Purchases Table
            pw.Text(
              'تفاصيل المشتريات',
              style: pw.TextStyle(
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
                font: _arabicFont,
              ),
            ),
            pw.SizedBox(height: 10),

            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300),
              columnWidths: {
                0: const pw.FixedColumnWidth(80), // التاريخ
                1: const pw.FlexColumnWidth(2), // الوصف
                2: const pw.FlexColumnWidth(1.5), // المورد
                3: const pw.FixedColumnWidth(60), // طريقة الدفع
                4: const pw.FixedColumnWidth(80), // المبلغ
              },
              children: [
                // Header
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    _buildTableCell('التاريخ', isHeader: true),
                    _buildTableCell('الوصف', isHeader: true),
                    _buildTableCell('المورد', isHeader: true),
                    _buildTableCell('الدفع', isHeader: true),
                    _buildTableCell('المبلغ', isHeader: true),
                  ],
                ),
                // Data rows
                ...purchases.map(
                  (purchase) => pw.TableRow(
                    children: [
                      _buildTableCell(
                        DateFormat('yyyy/MM/dd').format(purchase.purchaseDate),
                      ),
                      _buildTableCell(purchase.description),
                      _buildTableCell('غير محدد'), // Would need supplier lookup
                      _buildTableCell(
                        purchase.paymentMethod == 'cash' ? 'كاش' : 'آجل',
                      ),
                      _buildTableCell(
                        '${purchase.totalAmount.toStringAsFixed(2)} ج.م',
                        isNumeric: true,
                      ),
                    ],
                  ),
                ),
              ],
            ),

            pw.SizedBox(height: 20),

            // Footer
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                pw.Text(
                  'صفحة ${context.pageNumber} من ${context.pagesCount}',
                  style: pw.TextStyle(fontSize: 10, font: _arabicFont),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    await Printing.layoutPdf(
      onLayout: (format) async => pdf.save(),
      name:
          'تقرير_المشتريات_${DateFormat('yyyy_MM_dd').format(DateTime.now())}.pdf',
    );
  }

  static pw.Widget _buildSummaryCard(List<Purchase> purchases) {
    final totalAmount = purchases.fold<double>(
      0,
      (sum, purchase) => sum + purchase.totalAmount,
    );
    final cashCount = purchases.where((p) => p.paymentMethod == 'cash').length;
    final creditCount = purchases
        .where((p) => p.paymentMethod == 'credit')
        .length;

    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: PdfColors.grey300),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
        children: [
          pw.Column(
            children: [
              pw.Text(
                'إجمالي المشتريات',
                style: pw.TextStyle(
                  fontSize: 12,
                  font: _arabicFont,
                  color: PdfColors.grey700,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                '${totalAmount.toStringAsFixed(2)} ج.م',
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                  font: _arabicFont,
                  color: PdfColors.blue800,
                ),
              ),
            ],
          ),
          pw.Column(
            children: [
              pw.Text(
                'عدد العمليات',
                style: pw.TextStyle(
                  fontSize: 12,
                  font: _arabicFont,
                  color: PdfColors.grey700,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                purchases.length.toString(),
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                  font: _arabicFont,
                  color: PdfColors.green800,
                ),
              ),
            ],
          ),
          pw.Column(
            children: [
              pw.Text(
                'كاش / آجل',
                style: pw.TextStyle(
                  fontSize: 12,
                  font: _arabicFont,
                  color: PdfColors.grey700,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                '$cashCount / $creditCount',
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                  font: _arabicFont,
                  color: PdfColors.orange800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildTableCell(
    String text, {
    bool isHeader = false,
    bool isNumeric = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(8),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: isHeader ? 12 : 10,
          fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
          font: _arabicFont,
        ),
        textAlign: isNumeric ? pw.TextAlign.center : pw.TextAlign.right,
      ),
    );
  }
}
