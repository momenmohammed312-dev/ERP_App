import 'dart:developer' as developer;
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';

import '../utils/arabic_helper.dart';

/// Generates a small sample PDF containing Arabic text and a table
/// to help verify RTL layout and Arabic font rendering.
class SamplePdfGenerator {
  /// Opens a save dialog and writes a sample PDF demonstrating RTL Arabic.
  /// If [autoSave] is true, the PDF will be saved automatically to the
  /// app documents directory without prompting. Otherwise a save dialog
  /// will be shown to the user.
  static Future<void> generateSamplePdf(
    BuildContext context, {
    bool autoSave = false,
    String? fileName,
  }) async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sample PDF generation not supported on web platform'),
        ),
      );
      return;
    }
    try {
      final regularFontData = await rootBundle.load(
        'assets/fonts/NotoNaskhArabic-Regular.ttf',
      );
      final boldFontData = await rootBundle.load(
        'assets/fonts/NotoNaskhArabic-Regular.ttf',
      );

      final arabicFont = pw.Font.ttf(regularFontData);
      final arabicBold = pw.Font.ttf(boldFontData);

      final pdf = pw.Document();

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          build: (pw.Context ctx) => [
            pw.Directionality(
              textDirection: pw.TextDirection.rtl,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  pw.Text(
                    ArabicHelper.reshapedText('فاتورة تجريبية'),
                    style: pw.TextStyle(
                      font: arabicBold,
                      fontSize: 20,
                      fontWeight: pw.FontWeight.bold,
                    ),
                    textDirection: pw.TextDirection.rtl,
                  ),
                  pw.SizedBox(height: 8),
                  pw.Text(
                    ArabicHelper.reshapedText('هذا نص عربي نموذجي للاختبار.'),
                    style: pw.TextStyle(font: arabicFont, fontSize: 12),
                    textDirection: pw.TextDirection.rtl,
                  ),
                  pw.SizedBox(height: 12),
                  pw.TableHelper.fromTextArray(
                    headers: [
                      ArabicHelper.reshapedText('م'),
                      ArabicHelper.reshapedText('المنتج'),
                      ArabicHelper.reshapedText('الكمية'),
                      ArabicHelper.reshapedText('السعر'),
                      ArabicHelper.reshapedText('المبلغ'),
                    ],
                    data: [
                      ['1', 'موز', '2', '10.00', '20.00'],
                      ['2', 'تفاح', '1', '15.50', '15.50'],
                      ['3', 'برتقال', '3', '7.00', '21.00'],
                    ],
                    headerStyle: pw.TextStyle(font: arabicBold, fontSize: 10),
                    cellStyle: pw.TextStyle(font: arabicFont, fontSize: 10),
                    cellAlignments: {
                      0: pw.Alignment.center,
                      1: pw.Alignment.centerRight,
                      2: pw.Alignment.center,
                      3: pw.Alignment.center,
                      4: pw.Alignment.center,
                    },
                    headerDecoration: pw.BoxDecoration(
                      color: PdfColors.grey300,
                    ),
                  ),
                  pw.SizedBox(height: 12),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.end,
                    children: [
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          pw.Text(
                            ArabicHelper.reshapedText('الإجمالي: 56.50'),
                            style: pw.TextStyle(font: arabicBold, fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );

      String? outputPath;

      if (autoSave) {
        final dir = await getApplicationDocumentsDirectory();
        final name = fileName ?? 'sample_arabic_invoice.pdf';
        outputPath = '${dir.path}${Platform.pathSeparator}$name';
      } else {
        outputPath = await FilePicker.platform.saveFile(
          dialogTitle: 'Save sample Arabic PDF',
          fileName: fileName ?? 'sample_arabic_invoice.pdf',
          type: FileType.custom,
          allowedExtensions: ['pdf'],
        );
      }

      if (outputPath == null) return; // user cancelled or failed to get path

      final file = File(outputPath);
      await file.writeAsBytes(await pdf.save());

      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sample PDF saved successfully')),
      );
    } catch (e) {
      developer.log('Failed to generate sample PDF: $e');
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to generate sample PDF: $e')),
      );
    }
  }
}
