import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'package:pos_offline_desktop/core/services/reports/balance_sheet_service.dart';
import 'package:pos_offline_desktop/core/services/settings_service.dart';
import 'package:pos_offline_desktop/core/utils/pdf_bidi_helper.dart';

class BalanceSheetPdfGenerator {
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

  static Future<void> generate(BalanceSheetData data) async {
    final fonts = await _loadFonts();
    final pdf = pw.Document();
    final businessName = await SettingsService.getBusinessName();
    final taxNumber = await SettingsService.getTaxNumber();
    final logoPath = await SettingsService.getBusinessLogoPath();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        header: (c) => _header(fonts, businessName, taxNumber, logoPath, data.asOf),
        footer: (c) => _footer(fonts, c),
        build: (c) => [
          if (!data.isBalanced)
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              color: PdfColors.red100,
              child: pw.Text(_b('⚠ الميزانية غير متوازنة — الفرق: ${_fmt(data.delta)}'), style: pw.TextStyle(font: fonts['arabicBold'], color: PdfColors.red, fontWeight: pw.FontWeight.bold)),
            ),
          pw.SizedBox(height: 8),
          _section(fonts, _b('الأصول'), data.assets, data.totalAssets),
          pw.SizedBox(height: 10),
          _section(fonts, _b('الالتزامات'), data.liabilities, data.totalLiabilities),
          pw.SizedBox(height: 10),
          _section(fonts, _b('حقوق الملكية'), data.equity, data.totalEquity),
          pw.SizedBox(height: 12),
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.black), color: PdfColors.grey200),
            child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
              pw.Text(_b('إجمالي الالتزامات وحقوق الملكية'), style: pw.TextStyle(font: fonts['arabicBold'], fontWeight: pw.FontWeight.bold)),
              pw.Text(_fmt(data.totalLiabilitiesEquity), style: pw.TextStyle(font: fonts['arabicBold'], fontWeight: pw.FontWeight.bold)),
            ]),
          ),
          pw.SizedBox(height: 6),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text(_b('إجمالي الأصول'), style: pw.TextStyle(font: fonts['arabicBold'], fontWeight: pw.FontWeight.bold)),
            pw.Text(_fmt(data.totalAssets), style: pw.TextStyle(font: fonts['arabicBold'], fontWeight: pw.FontWeight.bold, color: data.isBalanced ? PdfColors.green : PdfColors.red)),
          ]),
        ],
      ),
    );

    await Printing.layoutPdf(onLayout: (f) => pdf.save(), name: _b('الميزانية العمومية'), format: PdfPageFormat.a4);
  }

  static pw.Widget _header(Map<String, pw.Font?> fonts, String businessName, String taxNumber, String? logoPath, DateTime asOf) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.black)),
      child: pw.Column(children: [
        if (logoPath != null && logoPath.isNotEmpty) pw.Padding(padding: const pw.EdgeInsets.only(bottom: 6), child: _logo(logoPath)),
        pw.Text(businessName.isNotEmpty ? _b(businessName) : _b('الميزانية العمومية'), style: pw.TextStyle(font: fonts['arabicBold'], fontWeight: pw.FontWeight.bold, fontSize: 16)),
        if (taxNumber.isNotEmpty) pw.Text(_b('الرقم الضريبي: $taxNumber'), style: pw.TextStyle(font: fonts['arabic'], fontSize: 9)),
        pw.SizedBox(height: 6),
        pw.Text(_b('كما في ${DateFormat('yyyy/MM/dd').format(asOf)}'), style: pw.TextStyle(font: fonts['arabic'], fontSize: 10)),
      ]),
    );
  }

  static pw.Widget _section(Map<String, pw.Font?> fonts, String title, List<BalanceSheetAccountRow> rows, double total) {
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(6),
        color: PdfColors.grey200,
        child: pw.Text(title, style: pw.TextStyle(font: fonts['arabicBold'], fontWeight: pw.FontWeight.bold)),
      ),
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: PdfColors.grey100),
            children: [_cell(_b('الحساب'), fonts['arabicBold'], bold: true), _cell(_b('الرصيد'), fonts['arabicBold'], bold: true, alignRight: true)],
          ),
          ...rows.map((r) => pw.TableRow(children: [_cell(_b('${r.account.code} - ${r.account.name}'), fonts['arabic']), _cell(_fmt(r.balance), fonts['arabic'], alignRight: true)])),
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: PdfColors.grey200),
            children: [_cell(_b('الإجمالي'), fonts['arabicBold'], bold: true), _cell(_fmt(total), fonts['arabicBold'], bold: true, alignRight: true)],
          ),
        ],
      ),
    ]);
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

  static pw.Widget _cell(String t, pw.Font? f, {bool bold = false, bool alignRight = false}) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      alignment: alignRight ? pw.Alignment.centerRight : pw.Alignment.centerRight,
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
