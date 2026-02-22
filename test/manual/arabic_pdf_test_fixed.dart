import 'package:pdf/widgets.dart' as pw;
import 'dart:io';
import 'dart:typed_data';

/// Simple logging function for test files (uses stderr to avoid print warnings)
void _log(String message) {
  stderr.writeln('[Arabic PDF Test] $message');
}

/// Test script to verify Arabic PDF rendering with proper fonts
void main() async {
  _log('Testing Arabic PDF rendering with proper fonts...');

  try {
    // Load Arabic fonts from assets
    final arabicFontData = await _loadFont(
      'assets/fonts/NotoNaskhArabic-Regular.ttf',
    );
    final arabicFont = pw.Font.ttf(arabicFontData.buffer.asByteData());

    // Use built-in fonts for Latin text
    final latinFont = pw.Font.helvetica();

    // Create test PDF
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Title
              pw.Text(
                'اختبار الخط العربي في PDF',
                style: pw.TextStyle(
                  font: arabicFont,
                  fontSize: 24,
                  fontWeight: pw.FontWeight.bold,
                ),
                textDirection: pw.TextDirection.rtl,
              ),
              pw.SizedBox(height: 30),

              // Test 1: Pure Arabic text
              pw.Text(
                'نص عربي بحت لاختبار عرض الحروف العربية بشكل صحيح',
                style: pw.TextStyle(font: arabicFont, fontSize: 16),
                textDirection: pw.TextDirection.rtl,
              ),
              pw.SizedBox(height: 20),

              // Test 2: Mixed Arabic and English with proper font fallback
              pw.Text(
                'نص عربي Mixed with English text ونص عربي آخر',
                style: pw.TextStyle(
                  font: arabicFont,
                  fontFallback: [latinFont],
                  fontSize: 16,
                ),
                textDirection: pw.TextDirection.rtl,
              ),
              pw.SizedBox(height: 20),

              // Test 3: Arabic with numbers and symbols
              pw.Text(
                'الفاتورة رقم: INV-2024-001 / التاريخ: 15/01/2024 / الإجمالي: 1,234.56 ج.م',
                style: pw.TextStyle(
                  font: arabicFont,
                  fontFallback: [latinFont],
                  fontSize: 14,
                ),
                textDirection: pw.TextDirection.rtl,
              ),
              pw.SizedBox(height: 20),

              // Test 4: Special characters and symbols
              pw.Text(
                'الرموز الخاصة: / - : © ® ™ # @ % & * ( ) [ ] { }',
                style: pw.TextStyle(
                  font: arabicFont,
                  fontFallback: [latinFont],
                  fontSize: 14,
                ),
                textDirection: pw.TextDirection.rtl,
              ),
              pw.SizedBox(height: 20),

              // Test 5: English text with Latin font
              pw.Text(
                'English text with proper font: Invoice #123, Date: 2024/01/15',
                style: pw.TextStyle(font: latinFont, fontSize: 14),
              ),
              pw.SizedBox(height: 20),

              // Test 6: Simple table with Arabic content
              pw.Container(
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(width: 1),
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Column(
                  children: [
                    // Table header
                    pw.Container(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Row(
                        children: [
                          pw.Expanded(
                            flex: 2,
                            child: pw.Text(
                              'اسم الصنف',
                              style: pw.TextStyle(
                                font: arabicFont,
                                fontWeight: pw.FontWeight.bold,
                                fontSize: 12,
                              ),
                              textDirection: pw.TextDirection.rtl,
                            ),
                          ),
                          pw.Expanded(
                            child: pw.Text(
                              'الكمية',
                              style: pw.TextStyle(
                                font: arabicFont,
                                fontWeight: pw.FontWeight.bold,
                                fontSize: 12,
                              ),
                              textDirection: pw.TextDirection.rtl,
                            ),
                          ),
                          pw.Expanded(
                            child: pw.Text(
                              'السعر',
                              style: pw.TextStyle(
                                font: arabicFont,
                                fontWeight: pw.FontWeight.bold,
                                fontSize: 12,
                              ),
                              textDirection: pw.TextDirection.rtl,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Table row 1
                    pw.Container(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Row(
                        children: [
                          pw.Expanded(
                            flex: 2,
                            child: pw.Text(
                              'منتج عربي 1',
                              style: pw.TextStyle(
                                font: arabicFont,
                                fontSize: 12,
                              ),
                              textDirection: pw.TextDirection.rtl,
                            ),
                          ),
                          pw.Expanded(
                            child: pw.Text(
                              '5',
                              style: pw.TextStyle(
                                font: latinFont,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          pw.Expanded(
                            child: pw.Text(
                              '150.00',
                              style: pw.TextStyle(
                                font: latinFont,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Table row 2
                    pw.Container(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Row(
                        children: [
                          pw.Expanded(
                            flex: 2,
                            child: pw.Text(
                              'منتج عربي 2',
                              style: pw.TextStyle(
                                font: arabicFont,
                                fontSize: 12,
                              ),
                              textDirection: pw.TextDirection.rtl,
                            ),
                          ),
                          pw.Expanded(
                            child: pw.Text(
                              '3',
                              style: pw.TextStyle(
                                font: latinFont,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          pw.Expanded(
                            child: pw.Text(
                              '75.50',
                              style: pw.TextStyle(
                                font: latinFont,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 30),

              // Test 7: Footer with mixed content
              pw.Container(
                alignment: pw.Alignment.center,
                child: pw.Text(
                  'Developed by MO2 - تطوير بواسطة MO2',
                  style: pw.TextStyle(
                    font: arabicFont,
                    fontFallback: [latinFont],
                    fontSize: 10,
                    fontStyle: pw.FontStyle.italic,
                  ),
                  textDirection: pw.TextDirection.rtl,
                ),
              ),
            ],
          );
        },
      ),
    );

    // Save PDF
    final pdfBytes = await pdf.save();
    final file = File('arabic_pdf_test_fixed.pdf');
    await file.writeAsBytes(pdfBytes);

    _log('✅ Arabic PDF test completed successfully!');
    _log('📄 PDF saved as: arabic_pdf_test_fixed.pdf');
    _log('🔍 Please check the PDF to verify:');
    _log('   • Arabic text renders correctly with RTL direction');
    _log('   • English text renders correctly');
    _log('   • Numbers and symbols render correctly');
    _log('   • Mixed content works properly');
    _log('   • Tables display Arabic text correctly');
    _log('   • No font warnings or missing characters');
  } catch (e, stackTrace) {
    _log('❌ Arabic PDF test failed: $e');
    _log('Stack trace: $stackTrace');
  }
}

/// Load font data from file
Future<Uint8List> _loadFont(String path) async {
  try {
    final file = File(path);
    if (await file.exists()) {
      return await file.readAsBytes();
    } else {
      throw Exception('Font file not found: $path');
    }
  } catch (e) {
    _log('Error loading font from $path: $e');
    // Fallback to empty font data (will cause issues but prevents crash)
    return Uint8List(0);
  }
}
