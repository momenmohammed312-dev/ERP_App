import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/dao/ledger_dao.dart';
import 'package:pos_offline_desktop/core/services/settings_service.dart';

/// Supplier Statement Generator (PDF)
/// مولد كشف حساب المورد - نسخة PDF محسنة
class SupplierStatementGenerator {

  static Future<Map<String, pw.Font?>> _loadFonts() async {
    pw.Font? arabicFont;
    pw.Font? arabicBoldFont;
    pw.Font? latinFont;

    try {
      final regularFontData = await rootBundle.load(
        'assets/fonts/NotoNaskhArabic-Regular.ttf',
      );
      if (regularFontData.lengthInBytes > 100) {
        arabicFont = pw.Font.ttf(regularFontData);
      }
    } catch (e) {
      debugPrint('Failed to load Arabic regular font: $e');
    }

    try {
      final boldFontData = await rootBundle.load(
        'assets/fonts/NotoNaskhArabic-Regular.ttf',
      );
      if (boldFontData.lengthInBytes > 100) {
        arabicBoldFont = pw.Font.ttf(boldFontData);
      }
    } catch (e) {
      debugPrint('Failed to load Arabic bold font: $e');
    }

    latinFont = pw.Font.helvetica();
    arabicFont ??= latinFont;
    arabicBoldFont ??= latinFont;

    return {
      'arabic': arabicFont,
      'arabicBold': arabicBoldFont,
      'latin': latinFont,
    };
  }

  static Future<void> generateStatement({
    required AppDatabase db,
    required String supplierId,
    required String supplierName,
    required DateTime fromDate,
    required DateTime toDate,
    required double openingBalance,
    required double currentBalance,
  }) async {
    final fonts = await _loadFonts();
    final pdf = pw.Document();

    // Fetch business info from SettingsService
    final businessName = await SettingsService.getBusinessName();
    final taxNumber = await SettingsService.getTaxNumber();

    final transactions = await db.ledgerDao.getTransactionsWithRunningBalance(
      'Supplier',
      supplierId,
      fromDate,
      toDate,
    );

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        build: (pw.Context context) {
          return pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                _buildHeaderSection(
                  fonts,
                  supplierName,
                  openingBalance,
                  currentBalance,
                  fromDate,
                  toDate,
                  businessName: businessName,
                  taxNumber: taxNumber,
                ),
                pw.SizedBox(height: 16),
                _buildFinancialSummary(
                  fonts,
                  openingBalance,
                  currentBalance,
                  transactions,
                ),
                pw.SizedBox(height: 16),
                _buildMainTransactionTable(transactions, fonts, openingBalance),
                pw.SizedBox(height: 16),
                _buildFooterSection(fonts, context),
              ],
            ),
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) => pdf.save(),
      name: 'كشف حساب مورد - $supplierName',
      format: PdfPageFormat.a4,
    );
  }

  static pw.Widget _buildHeaderSection(
    Map<String, pw.Font?> fonts,
    String supplierName,
    double openingBalance,
    double currentBalance,
    DateTime fromDate,
    DateTime toDate, {
    String businessName = '',
    String taxNumber = '',
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text(
            businessName.isNotEmpty ? businessName : 'كشف حساب',
            style: pw.TextStyle(
              fontSize: 18,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.blue800,
              font: fonts['arabicBold'],
            ),
          ),
          if (taxNumber.isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 4),
              child: pw.Text(
                'الرقم الضريبي: $taxNumber',
                style: pw.TextStyle(
                  fontSize: 10,
                  color: PdfColors.grey700,
                  font: fonts['arabic'],
                ),
                textDirection: pw.TextDirection.rtl,
              ),
            ),
          pw.SizedBox(height: 12),
          pw.Container(
            width: double.infinity,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'اسم المورد: $supplierName',
                      style: pw.TextStyle(
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                        font: fonts['arabicBold'],
                      ),
                    ),
                    pw.Text(
                      'كشف حساب مورد',
                      style: pw.TextStyle(
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold,
                        font: fonts['arabicBold'],
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 8),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'الرصيد النهائي: ${formatCurrency(currentBalance)}',
                      style: pw.TextStyle(
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                        color: currentBalance > 0
                            ? PdfColors.green
                            : PdfColors.red,
                        font: fonts['arabicBold'],
                      ),
                    ),
                    pw.Text(
                      'الرصيد الافتتاحي: ${formatCurrency(openingBalance)}',
                      style: pw.TextStyle(fontSize: 12, font: fonts['arabic']),
                    ),
                  ],
                ),
                pw.SizedBox(height: 8),
                pw.Center(
                  child: pw.Text(
                    'الفترة: من ${DateFormat('yyyy/MM/dd').format(fromDate)} إلى ${DateFormat('yyyy/MM/dd').format(toDate)}',
                    style: pw.TextStyle(fontSize: 12, font: fonts['arabic']),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildFinancialSummary(
    Map<String, pw.Font?> fonts,
    double openingBalance,
    double currentBalance,
    List<LedgerTransactionWithBalance> transactions,
  ) {
    double totalPaid = 0.0; // Debit for supplier
    double totalPurchased = 0.0; // Credit for supplier

    for (final tx in transactions) {
      totalPaid += tx.transaction.debit;
      totalPurchased += tx.transaction.credit;
    }

    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        border: pw.Border.all(color: PdfColors.grey400),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Table(
        columnWidths: {
          0: const pw.FlexColumnWidth(2),
          1: const pw.FlexColumnWidth(1),
        },
        border: pw.TableBorder.all(color: PdfColors.grey300),
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: PdfColors.grey200),
            children: [
              _buildTableCell(
                'الرصيد الافتتاحي',
                fonts['arabicBold'],
                isHeader: true,
              ),
              _buildTableCell(
                formatCurrency(openingBalance),
                fonts['arabic'],
                isHeader: true,
              ),
            ],
          ),
          pw.TableRow(
            children: [
              _buildTableCell(
                'إجمالي المَدين (مدفوعاتنا)',
                fonts['arabicBold'],
                isHeader: true,
              ),
              _buildTableCell(
                formatCurrency(totalPaid),
                fonts['arabic'],
                isHeader: true,
              ),
            ],
          ),
          pw.TableRow(
            children: [
              _buildTableCell(
                'إجمالي الدائن (مشترياتنا)',
                fonts['arabicBold'],
                isHeader: true,
              ),
              _buildTableCell(
                formatCurrency(totalPurchased),
                fonts['arabic'],
                isHeader: true,
              ),
            ],
          ),
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: PdfColors.grey300),
            children: [
              _buildTableCell(
                'الرصيد الحالي',
                fonts['arabicBold'],
                isHeader: true,
              ),
              _buildTableCell(
                formatCurrency(currentBalance),
                fonts['arabicBold'],
                isHeader: true,
                color: currentBalance > 0 ? PdfColors.green : PdfColors.red,
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildMainTransactionTable(
    List<LedgerTransactionWithBalance> transactions,
    Map<String, pw.Font?> fonts,
    double openingBalance,
  ) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.black, width: 1),
      columnWidths: {
        0: const pw.FlexColumnWidth(0.6), // م
        1: const pw.FlexColumnWidth(1.2), // التاريخ
        2: const pw.FlexColumnWidth(2.5), // البيان
        3: const pw.FlexColumnWidth(1.2), // مَدين
        4: const pw.FlexColumnWidth(1.2), // دائن
        5: const pw.FlexColumnWidth(1.2), // الرصيد
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey300),
          children: [
            _buildHeaderCell('م', fonts['arabicBold']),
            _buildHeaderCell('التاريخ', fonts['arabicBold']),
            _buildHeaderCell('البيان', fonts['arabicBold']),
            _buildHeaderCell('مَدين (-)', fonts['arabicBold']),
            _buildHeaderCell('دائن (+)', fonts['arabicBold']),
            _buildHeaderCell('الرصيد', fonts['arabicBold']),
          ],
        ),
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.blue50),
          children: [
            _buildTableCell('', fonts['arabic']),
            _buildTableCell(
              DateFormat('yyyy/MM/dd').format(DateTime.now()),
              fonts['arabic'],
            ), // Placeholder date
            _buildTableCell(
              'رصيد افتتاحي / سابق',
              fonts['arabicBold'],
              isBold: true,
            ),
            _buildTableCell(
              openingBalance < 0 ? formatCurrency(openingBalance.abs()) : '',
              fonts['arabic'],
            ),
            _buildTableCell(
              openingBalance > 0 ? formatCurrency(openingBalance) : '',
              fonts['arabic'],
            ),
            _buildTableCell(
              formatCurrency(openingBalance),
              fonts['arabicBold'],
              isBold: true,
            ),
          ],
        ),
        ...transactions.asMap().entries.map((entry) {
          final index = entry.key;
          final tx = entry.value;
          return pw.TableRow(
            children: [
              _buildTableCell(
                '${index + 1}',
                fonts['arabic'],
                isCentered: true,
              ),
              _buildTableCell(
                DateFormat('yyyy/MM/dd').format(tx.transaction.date),
                fonts['arabic'],
                isCentered: true,
              ),
              _buildTableCell(tx.transaction.description, fonts['arabic']),
              _buildTableCell(
                tx.transaction.debit > 0
                    ? formatCurrency(tx.transaction.debit)
                    : '',
                fonts['arabic'],
              ),
              _buildTableCell(
                tx.transaction.credit > 0
                    ? formatCurrency(tx.transaction.credit)
                    : '',
                fonts['arabic'],
              ),
              _buildTableCell(
                formatCurrency(tx.runningBalance),
                fonts['arabicBold'],
                isBold: true,
              ),
            ],
          );
        }),
      ],
    );
  }

  static pw.Widget _buildFooterSection(
    Map<String, pw.Font?> fonts,
    pw.Context context,
  ) {
    return pw.Column(
      children: [
        pw.Divider(color: PdfColors.grey300),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Developed by MO2',
              style: pw.TextStyle(fontSize: 8, font: fonts['arabic']),
            ),
            pw.Text(
              'صفحة ${context.pageNumber} من ${context.pagesCount}',
              style: pw.TextStyle(fontSize: 8, font: fonts['arabic']),
            ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildHeaderCell(String text, pw.Font? font) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      alignment: pw.Alignment.center,
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 10,
          fontWeight: pw.FontWeight.bold,
          font: font,
          color: PdfColors.white,
        ),
      ),
    );
  }

  static pw.Widget _buildTableCell(
    String text,
    pw.Font? font, {
    bool isHeader = false,
    bool isBold = false,
    bool isCentered = false,
    PdfColor? color,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(6),
      alignment: isCentered ? pw.Alignment.center : pw.Alignment.centerRight,
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 9,
          fontWeight: isHeader || isBold
              ? pw.FontWeight.bold
              : pw.FontWeight.normal,
          color: color ?? PdfColors.black,
          font: font,
        ),
      ),
    );
  }

  static String formatCurrency(double amount) {
    return '${amount.toStringAsFixed(2)} ج.م';
  }
}
