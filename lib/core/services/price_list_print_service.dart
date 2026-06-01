import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/services/settings_service.dart';
import 'package:pos_offline_desktop/core/utils/arabic_reshaper/arabic_reshaper.dart';

class PriceListPrintService {
  static Future<void> printPriceList(List<Product> products) async {
    final pdf = pw.Document();
    final fontData = await _loadFontData();
    final font = pw.Font.ttf(fontData);
    final boldFont = pw.Font.ttf(fontData);

    final storeName = await SettingsService.getBusinessName();
    final storePhone = await SettingsService.getBusinessPhone();
    final printDate = DateTime.now();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: pw.ThemeData.withFont(base: font, bold: boldFont),
        build: (pw.Context context) {
          return [
            pw.Header(
              level: 0,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(_r(storeName), style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
                      if (storePhone.isNotEmpty) pw.Text('${_r('هاتف')}: $storePhone'),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(_r('قائمة الأسعار'), style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                      pw.Text('${_r('التاريخ')}: ${printDate.year}-${printDate.month.toString().padLeft(2, '0')}-${printDate.day.toString().padLeft(2, '0')}'),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 20),

            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300),
              columnWidths: {
                0: const pw.FlexColumnWidth(0.5),
                1: const pw.FlexColumnWidth(3),
                2: const pw.FlexColumnWidth(1),
                3: const pw.FlexColumnWidth(1.5),
                4: const pw.FlexColumnWidth(1.5),
                5: const pw.FlexColumnWidth(2),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    _buildCell('#', isHeader: true),
                    _buildCell(_r('اسم المنتج'), isHeader: true),
                    _buildCell(_r('الوحدة'), isHeader: true),
                    _buildCell(_r('السعر'), isHeader: true),
                    _buildCell(_r('سعر التكلفة'), isHeader: true),
                    _buildCell(_r('الباركود'), isHeader: true),
                  ],
                ),
                ...products.asMap().entries.map((entry) {
                  final i = entry.key + 1;
                  final p = entry.value;
                  return pw.TableRow(
                    children: [
                      _buildCell('$i'),
                      _buildCell(_r(p.name)),
                      _buildCell(p.unit != null ? _r(p.unit!) : '-'),
                      _buildCell('${p.price.toStringAsFixed(2)} ${_r('ج.م')}'),
                      _buildCell(p.costPrice != null ? '${p.costPrice!.toStringAsFixed(2)} ${_r('ج.م')}' : '-'),
                      _buildCell(p.barcode ?? '-'),
                    ],
                  );
                }),
              ],
            ),

            pw.SizedBox(height: 16),
            pw.Text(
              '${_r('إجمالي المنتجات')}: ${products.length}',
              style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
              textDirection: pw.TextDirection.rtl,
            ),
          ];
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'price_list_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
  }

  static String _r(String text) {
    return ArabicReshaper.reshapeText(text);
  }

  static pw.Widget _buildCell(String text, {bool isHeader = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(5),
      child: pw.Text(
        text,
        textAlign: pw.TextAlign.center,
        textDirection: pw.TextDirection.rtl,
        style: pw.TextStyle(
          fontSize: isHeader ? 11 : 9,
          fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  static Future<ByteData> _loadFontData() async {
    return rootBundle.load('assets/fonts/NotoNaskhArabic-Regular.ttf');
  }
}
