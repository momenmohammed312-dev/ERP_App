import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/utils/pdf_bidi_helper.dart';

class StaffAdvanceStatementGenerator {
  static Future<Map<String, pw.Font?>> _loadFonts() async {
    pw.Font? arabicFont;
    pw.Font? arabicBoldFont;
    final latinFont = pw.Font.helvetica();

    try {
      final regularFontData = await rootBundle.load(
        'assets/fonts/NotoNaskhArabic-Regular.ttf',
      );
      if (regularFontData.lengthInBytes > 100) {
        arabicFont = pw.Font.ttf(regularFontData);
      }
    } catch (_) {}

    try {
      final boldFontData = await rootBundle.load(
        'assets/fonts/NotoNaskhArabic-Regular.ttf',
      );
      if (boldFontData.lengthInBytes > 100) {
        arabicBoldFont = pw.Font.ttf(boldFontData);
      }
    } catch (_) {}

    arabicFont ??= latinFont;
    arabicBoldFont ??= latinFont;

    return {
      'arabic': arabicFont,
      'arabicBold': arabicBoldFont,
      'latin': latinFont,
    };
  }

  static String _b(String text) => PdfBidiHelper.reorder(text);

  static Future<void> generateAndPrint({
    required BuildContext context,
    required AppDatabase db,
    required Staff staff,
    required List<StaffAdvance> advanceRecords,
  }) async {
    final fonts = await _loadFonts();
    final arabicFont = fonts['arabic'];
    final arabicBoldFont = fonts['arabicBold'];

    final pdf = pw.Document();
    final dateFormat = DateFormat('yyyy-MM-dd');

    final tableHeaders = [
      _b('تاريخ الطلب'),
      _b('المبلغ'),
      _b('الحالة'),
      _b('تاريخ الصرف'),
    ];

    final tableData = advanceRecords.map((a) {
      final reqDateStr = dateFormat.format(a.requestDate);
      final paymentDateStr = a.paymentDate != null
          ? dateFormat.format(a.paymentDate!)
          : '-';
      String statusStr = a.status;
      switch (a.status) {
        case 'paid':
          statusStr = 'مدفوعة';
          break;
        case 'approved':
          statusStr = 'موافقة';
          break;
        case 'pending':
          statusStr = 'معلقة';
          break;
        case 'rejected':
          statusStr = 'مرفوضة';
          break;
      }

      return [
        _b(reqDateStr),
        _b(a.amount.toStringAsFixed(2)),
        _b(statusStr),
        _b(paymentDateStr),
      ];
    }).toList();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        theme: pw.ThemeData.withFont(
          base: arabicFont,
          bold: arabicBoldFont,
        ),
        build: (pw.Context context) {
          return [
            // العنوان الرئيسي
            pw.Center(
              child: pw.Text(
                _b('كشف حساب السلف'),
                style: pw.TextStyle(
                  font: arabicBoldFont,
                  fontSize: 20,
                ),
              ),
            ),
            pw.SizedBox(height: 16),

            // بيانات الموظف
            pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    _b('الاسم: ${staff.name}'),
                    style: pw.TextStyle(font: arabicFont, fontSize: 12),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    _b('الكود: ${staff.staffId}'),
                    style: pw.TextStyle(font: arabicFont, fontSize: 12),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    _b('الوظيفة: ${staff.position}'),
                    style: pw.TextStyle(font: arabicFont, fontSize: 12),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    _b('المرتب الأساسي: ${staff.basicSalary.toStringAsFixed(2)} جنيه'),
                    style: pw.TextStyle(font: arabicFont, fontSize: 12),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 16),

            // جدول السجلات
            pw.TableHelper.fromTextArray(
              headers: tableHeaders,
              data: tableData,
              border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
              headerStyle: pw.TextStyle(
                font: arabicBoldFont,
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
              ),
              cellStyle: pw.TextStyle(
                font: arabicFont,
                fontSize: 9,
              ),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.grey200,
              ),
              cellAlignment: pw.Alignment.center,
              headerAlignment: pw.Alignment.center,
            ),
          ];
        },
      ),
    );

    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }
}
