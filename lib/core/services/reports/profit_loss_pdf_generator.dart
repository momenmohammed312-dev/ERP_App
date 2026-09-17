import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'package:pos_offline_desktop/core/services/reports/profit_loss_service.dart';
import 'package:pos_offline_desktop/core/services/settings_service.dart';
import 'package:pos_offline_desktop/core/utils/pdf_bidi_helper.dart';

class ProfitLossPdfGenerator {
  static Future<Map<String, pw.Font?>> _loadFonts() async {
    pw.Font? arabicFont;
    pw.Font? arabicBoldFont;
    final latinFont = pw.Font.helvetica();
    try {
      final d = await rootBundle.load('assets/fonts/NotoNaskhArabic-Regular.ttf');
      if (d.lengthInBytes > 100) arabicFont = pw.Font.ttf(d);
    } catch (_) {}
    try {
      final d = await rootBundle.load('assets/fonts/NotoNaskhArabic-Regular.ttf');
      if (d.lengthInBytes > 100) arabicBoldFont = pw.Font.ttf(d);
    } catch (_) {}
    arabicFont ??= latinFont;
    arabicBoldFont ??= latinFont;
    return {'arabic': arabicFont, 'arabicBold': arabicBoldFont, 'latin': latinFont};
  }

  static String _b(String t) => PdfBidiHelper.reorder(t);
  static String _fmt(double v) => v.toStringAsFixed(2);

  static Future<void> generate(ProfitLossData data) async {
    final fonts = await _loadFonts();
    final pdf = pw.Document();
    final businessName = await SettingsService.getBusinessName();
    final taxNumber = await SettingsService.getTaxNumber();
    final logoPath = await SettingsService.getBusinessLogoPath();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        header: (c) => _header(fonts, businessName, taxNumber, logoPath, data.from, data.to),
        footer: (c) => _footer(fonts, c),
        build: (c) => [
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
            children: [
              _row(_b('إيرادات المبيعات'), _fmt(data.revenue), fonts, bold: true),
              _row(_b('(-) مردودات المبيعات'), _fmt(data.salesReturns), fonts),
              _row(_b('صافي الإيرادات'), _fmt(data.netRevenue), fonts, bold: true, bg: PdfColors.grey200),
              _row(_b('(-) تكلفة البضاعة المباعة'), _fmt(data.cogs), fonts),
              _row(_b('مجمل الربح'), _fmt(data.grossProfit), fonts, bold: true, bg: PdfColors.grey200, color: data.grossProfit >= 0 ? PdfColors.green : PdfColors.red),
              _row(_b('(-) مصروفات تشغيلية'), _fmt(data.operatingExpenses), fonts),
              _row(_b('صافي الربح'), _fmt(data.netProfit), fonts, bold: true, bg: PdfColors.grey300, color: data.netProfit >= 0 ? PdfColors.green : PdfColors.red),
            ],
          ),
        ],
      ),
    );

    await Printing.layoutPdf(onLayout: (f) => pdf.save(), name: _b('قائمة الأرباح والخسائر'), format: PdfPageFormat.a4);
  }

  static pw.Widget _header(Map<String, pw.Font?> fonts, String businessName, String taxNumber, String? logoPath, DateTime from, DateTime to) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.black)),
      child: pw.Column(children: [
        if (logoPath != null && logoPath.isNotEmpty) pw.Padding(padding: const pw.EdgeInsets.only(bottom: 6), child: _logo(logoPath)),
        pw.Text(businessName.isNotEmpty ? _b(businessName) : _b('قائمة الأرباح والخسائر'), style: pw.TextStyle(font: fonts['arabicBold'], fontWeight: pw.FontWeight.bold, fontSize: 16)),
        if (taxNumber.isNotEmpty) pw.Text(_b('الرقم الضريبي: $taxNumber'), style: pw.TextStyle(font: fonts['arabic'], fontSize: 9)),
        pw.SizedBox(height: 6),
        pw.Text(_b('الفترة: ${DateFormat('yyyy/MM/dd').format(from)} - ${DateFormat('yyyy/MM/dd').format(to)}'), style: pw.TextStyle(font: fonts['arabic'], fontSize: 10)),
      ]),
    );
  }

  static pw.TableRow _row(String label, String value, Map<String, pw.Font?> fonts, {bool bold = false, PdfColor? bg, PdfColor? color}) {
    return pw.TableRow(
      decoration: bg != null ? pw.BoxDecoration(color: bg) : null,
      children: [
        pw.Container(padding: const pw.EdgeInsets.all(6), child: pw.Text(label, style: pw.TextStyle(font: fonts['arabic'], fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal, fontSize: 11))),
        pw.Container(padding: const pw.EdgeInsets.all(6), alignment: pw.Alignment.centerRight, child: pw.Text(value, style: pw.TextStyle(font: fonts['arabic'], fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal, fontSize: 11, color: color ?? PdfColors.black))),
      ],
    );
  }

  static pw.Widget _footer(Map<String, pw.Font?> fonts, pw.Context c) {
    return pw.Column(children: [
      pw.SizedBox(height: 20),
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text(_b('تم الإصدار: ${DateFormat('yyyy/MM/dd hh:mm a').format(DateTime.now())}'), style: pw.TextStyle(font: fonts['arabic'], fontSize: 8)),
        pw.Text(_b('صفحة ${c.pageNumber} من ${c.pagesCount}'), style: pw.TextStyle(font: fonts['arabic'], fontSize: 8)),
      ]),
    ]);
  }

  static pw.Widget _logo(String path) {
    try {
      final file = File(path);
      if (file.existsSync()) return pw.Image(pw.MemoryImage(file.readAsBytesSync()), height: 50);
    } catch (_) {}
    return pw.SizedBox.shrink();
  }
}
