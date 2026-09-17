import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'package:pos_offline_desktop/core/services/reports/equity_statement_service.dart';
import 'package:pos_offline_desktop/core/services/settings_service.dart';
import 'package:pos_offline_desktop/core/utils/pdf_bidi_helper.dart';

class EquityStatementPdfGenerator {
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

  static Future<void> generate(EquityStatementData data) async {
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
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  _cell(_b('الشريك'), fonts['arabicBold'], bold: true, centered: true),
                  _cell(_b('افتتاحي'), fonts['arabicBold'], bold: true, centered: true),
                  _cell(_b('مساهمات'), fonts['arabicBold'], bold: true, centered: true),
                  _cell(_b('أرباح'), fonts['arabicBold'], bold: true, centered: true),
                  _cell(_b('مسحوبات'), fonts['arabicBold'], bold: true, centered: true),
                  _cell(_b('ختامي'), fonts['arabicBold'], bold: true, centered: true),
                ],
              ),
              ...data.partners.map((p) => pw.TableRow(children: [
                    _cell(_b(p.partner.name), fonts['arabic']),
                    _cell(_fmt(p.opening), fonts['arabic'], alignRight: true),
                    _cell(_fmt(p.contributions), fonts['arabic'], alignRight: true),
                    _cell(_fmt(p.profitAllocations), fonts['arabic'], alignRight: true),
                    _cell(_fmt(p.withdrawals), fonts['arabic'], alignRight: true),
                    _cell(_fmt(p.closing), fonts['arabicBold'], bold: true, alignRight: true),
                  ])),
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  _cell(_b('الإجمالي'), fonts['arabicBold'], bold: true, centered: true),
                  _cell(_fmt(data.totalOpening), fonts['arabicBold'], bold: true, alignRight: true),
                  _cell(_fmt(data.totalContributions), fonts['arabicBold'], bold: true, alignRight: true),
                  _cell(_fmt(data.totalProfitAllocations), fonts['arabicBold'], bold: true, alignRight: true),
                  _cell(_fmt(data.totalWithdrawals), fonts['arabicBold'], bold: true, alignRight: true),
                  _cell(_fmt(data.totalClosing), fonts['arabicBold'], bold: true, alignRight: true),
                ],
              ),
            ],
          ),
        ],
      ),
    );

    await Printing.layoutPdf(onLayout: (f) => pdf.save(), name: _b('كشف حقوق الملكية'), format: PdfPageFormat.a4);
  }

  static pw.Widget _header(Map<String, pw.Font?> fonts, String businessName, String taxNumber, String? logoPath, DateTime from, DateTime to) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.black)),
      child: pw.Column(children: [
        if (logoPath != null && logoPath.isNotEmpty) pw.Padding(padding: const pw.EdgeInsets.only(bottom: 6), child: _logo(logoPath)),
        pw.Text(businessName.isNotEmpty ? _b(businessName) : _b('كشف حقوق الملكية'), style: pw.TextStyle(font: fonts['arabicBold'], fontWeight: pw.FontWeight.bold, fontSize: 16)),
        if (taxNumber.isNotEmpty) pw.Text(_b('الرقم الضريبي: $taxNumber'), style: pw.TextStyle(font: fonts['arabic'], fontSize: 9)),
        pw.SizedBox(height: 6),
        pw.Text(_b('الفترة: ${DateFormat('yyyy/MM/dd').format(from)} - ${DateFormat('yyyy/MM/dd').format(to)}'), style: pw.TextStyle(font: fonts['arabic'], fontSize: 10)),
      ]),
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

  static pw.Widget _cell(String t, pw.Font? f, {bool bold = false, bool centered = false, bool alignRight = false}) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      alignment: centered ? pw.Alignment.center : (alignRight ? pw.Alignment.centerRight : pw.Alignment.centerRight),
      child: pw.Text(t, style: pw.TextStyle(font: f, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal, fontSize: 9)),
    );
  }

  static pw.Widget _logo(String path) {
    try {
      final file = File(path);
      if (file.existsSync()) return pw.Image(pw.MemoryImage(file.readAsBytesSync()), height: 50);
    } catch (_) {}
    return pw.SizedBox.shrink();
  }
}
