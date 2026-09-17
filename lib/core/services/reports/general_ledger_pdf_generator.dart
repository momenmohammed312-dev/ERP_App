import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'package:pos_offline_desktop/core/services/reports/general_ledger_service.dart';
import 'package:pos_offline_desktop/core/services/settings_service.dart';
import 'package:pos_offline_desktop/core/utils/pdf_bidi_helper.dart';

class GeneralLedgerPdfGenerator {
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

  static Future<void> generate(GeneralLedgerData data) async {
    final fonts = await _loadFonts();
    final pdf = pw.Document();
    final businessName = await SettingsService.getBusinessName();
    final taxNumber = await SettingsService.getTaxNumber();
    final logoPath = await SettingsService.getBusinessLogoPath();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        header: (c) => _header(fonts, businessName, taxNumber, logoPath, data),
        footer: (c) => _footer(fonts, c),
        build: (c) => [
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.black)),
            child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
              pw.Text(_b('الرصيد الافتتاحي: ${_fmt(data.openingBalance)}'), style: pw.TextStyle(font: fonts['arabic'], fontSize: 10)),
              pw.Text(_b('الرصيد الختامي: ${_fmt(data.closingBalance)}'), style: pw.TextStyle(font: fonts['arabicBold'], fontWeight: pw.FontWeight.bold, fontSize: 10)),
            ]),
          ),
          pw.SizedBox(height: 8),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
            columnWidths: {
              0: const pw.FlexColumnWidth(1),
              1: const pw.FlexColumnWidth(2),
              2: const pw.FlexColumnWidth(1),
              3: const pw.FlexColumnWidth(1),
              4: const pw.FlexColumnWidth(1),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                children: [
                  _cell(_b('التاريخ'), fonts['arabicBold'], bold: true, centered: true),
                  _cell(_b('البيان'), fonts['arabicBold'], bold: true, centered: true),
                  _cell(_b('مدين'), fonts['arabicBold'], bold: true, centered: true),
                  _cell(_b('دائن'), fonts['arabicBold'], bold: true, centered: true),
                  _cell(_b('الرصيد'), fonts['arabicBold'], bold: true, centered: true),
                ],
              ),
              ...data.lines.map((gl) => pw.TableRow(children: [
                    _cell(DateFormat('yyyy/MM/dd').format(gl.entry.date), fonts['arabic'], centered: true),
                    _cell(_b(gl.entry.description), fonts['arabic']),
                    _cell(gl.line.debit > 0 ? _fmt(gl.line.debit) : '', fonts['arabic'], alignRight: true),
                    _cell(gl.line.credit > 0 ? _fmt(gl.line.credit) : '', fonts['arabic'], alignRight: true),
                    _cell(_fmt(gl.runningBalance), fonts['arabic'], alignRight: true),
                  ])),
            ],
          ),
        ],
      ),
    );

    await Printing.layoutPdf(onLayout: (f) => pdf.save(), name: _b('دفتر الأستاذ العام'), format: PdfPageFormat.a4);
  }

  static pw.Widget _header(Map<String, pw.Font?> fonts, String businessName, String taxNumber, String? logoPath, GeneralLedgerData data) {
    final accountName = data.account != null ? '${data.account!.code} - ${data.account!.name}' : _b('كل الحسابات');
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.black)),
      child: pw.Column(children: [
        if (logoPath != null && logoPath.isNotEmpty) pw.Padding(padding: const pw.EdgeInsets.only(bottom: 6), child: _logo(logoPath)),
        pw.Text(businessName.isNotEmpty ? _b(businessName) : _b('دفتر الأستاذ العام'), style: pw.TextStyle(font: fonts['arabicBold'], fontWeight: pw.FontWeight.bold, fontSize: 16)),
        if (taxNumber.isNotEmpty) pw.Text(_b('الرقم الضريبي: $taxNumber'), style: pw.TextStyle(font: fonts['arabic'], fontSize: 9)),
        pw.SizedBox(height: 6),
        pw.Text(_b('الحساب: $accountName'), style: pw.TextStyle(font: fonts['arabic'], fontSize: 10)),
        pw.Text(_b('الفترة: ${DateFormat('yyyy/MM/dd').format(data.from)} - ${DateFormat('yyyy/MM/dd').format(data.to)}'), style: pw.TextStyle(font: fonts['arabic'], fontSize: 10)),
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
