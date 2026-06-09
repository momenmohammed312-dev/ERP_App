import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/services/settings_service.dart';

class EnhancedCustomerStatementGenerator {

  // Font loading with better error handling
  static Future<Map<String, pw.Font?>> _loadFonts() async {
    pw.Font? arabicFont;
    pw.Font? arabicBoldFont;
    pw.Font? latinFont;

    try {
      // Load Arabic regular font
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
      // Load Arabic bold font (using regular as fallback)
      final boldFontData = await rootBundle.load(
        'assets/fonts/NotoNaskhArabic-Regular.ttf',
      );
      if (boldFontData.lengthInBytes > 100) {
        arabicBoldFont = pw.Font.ttf(boldFontData);
      }
    } catch (e) {
      debugPrint('Failed to load Arabic bold font: $e');
    }

    // Latin font fallback
    latinFont = pw.Font.helvetica();

    // Ensure we have at least some font for Arabic
    arabicFont ??= latinFont;
    arabicBoldFont ??= latinFont;

    return {
      'arabic': arabicFont,
      'arabicBold': arabicBoldFont,
      'latin': latinFont,
    };
  }

  // Generate enhanced customer statement PDF
  static Future<void> generateStatement({
    required AppDatabase db,
    required String customerId,
    required String customerName,
    required DateTime fromDate,
    required DateTime toDate,
    required double openingBalance,
    required double currentBalance,
  }) async {
    debugPrint('=== GENERATOR START ===');
    debugPrint('Customer: $customerName ($customerId)');
    debugPrint('Date Range: $fromDate to $toDate');

    final fonts = await _loadFonts();
    final pdf = pw.Document();

    // Get transactions with running balance
    debugPrint('GENERATOR: Fetching transactions...');

    // First, try to get all transactions without date filter to compare
    try {
      debugPrint('GENERATOR: Getting all transactions...');
      final allTransactions = await db.ledgerDao.getTransactionsByEntity(
        'Customer',
        customerId,
      );
      debugPrint(
        'GENERATOR: Found ${allTransactions.length} total transactions',
      );

      // Show first 5 transactions for comparison
      for (int i = 0; i < allTransactions.length && i < 5; i++) {
        final tx = allTransactions[i];
        debugPrint(
          'GENERATOR: All TX $i: ${tx.description} - ${tx.date} - Debit: ${tx.debit}, Credit: ${tx.credit}',
        );
      }
    } catch (e) {
      debugPrint('GENERATOR: Error getting all transactions: $e');
    }

    // Now get transactions with running balance
    debugPrint('GENERATOR: Getting transactions with running balance...');
    debugPrint('GENERATOR: Date range: $fromDate to $toDate');
    debugPrint('GENERATOR: Customer ID: $customerId');

    final transactions = await db.ledgerDao.getTransactionsWithRunningBalance(
      'Customer',
      customerId,
      fromDate,
      toDate,
    );

    debugPrint(
      'GENERATOR: Found ${transactions.length} transactions with running balance',
    );
    debugPrint('GENERATOR: Opening Balance: $openingBalance');
    debugPrint('GENERATOR: Current Balance: $currentBalance');

    // Debug each transaction with running balance
    for (int i = 0; i < transactions.length; i++) {
      final tx = transactions[i];
      debugPrint(
        'GENERATOR: TX with Balance $i: ${tx.transaction.description} - ${tx.transaction.date} - Debit: ${tx.transaction.debit}, Credit: ${tx.transaction.credit}, Running: ${tx.runningBalance}',
      );
    }

    // Verify logic: check if transactions make sense
    if (transactions.isNotEmpty) {
      debugPrint('GENERATOR: === LOGIC VERIFICATION ===');
      debugPrint(
        'GENERATOR: First transaction date: ${transactions.first.transaction.date}',
      );
      debugPrint(
        'GENERATOR: Last transaction date: ${transactions.last.transaction.date}',
      );
      debugPrint('GENERATOR: Date range covers: $fromDate to $toDate');

      // Check if transactions are within date range
      int outOfRangeCount = 0;
      for (final tx in transactions) {
        if (tx.transaction.date.isBefore(fromDate) ||
            tx.transaction.date.isAfter(toDate)) {
          outOfRangeCount++;
        }
      }
      debugPrint('GENERATOR: Transactions out of range: $outOfRangeCount');
    }

    // Fetch business info from SettingsService
    final businessName = await SettingsService.getBusinessName();
    final taxNumber = await SettingsService.getTaxNumber();
    final logoPath = await SettingsService.getBusinessLogoPath();

    debugPrint('GENERATOR: Building PDF...');
    debugPrint('GENERATOR: === PDF GENERATION VERIFICATION ===');
    debugPrint('GENERATOR: Customer: $customerName ($customerId)');
    debugPrint('GENERATOR: Transactions count: ${transactions.length}');
    debugPrint('GENERATOR: Opening Balance: $openingBalance');
    debugPrint('GENERATOR: Current Balance: $currentBalance');

    // Verify transaction data before PDF generation
    if (transactions.isNotEmpty) {
      debugPrint('GENERATOR: First transaction verification:');
      final firstTx = transactions.first;
      debugPrint('GENERATOR: - Transaction type: ${firstTx.runtimeType}');
      debugPrint('GENERATOR: - Transaction ID: ${firstTx.transaction.id}');
      debugPrint(
        'GENERATOR: - Description: ${firstTx.transaction.description}',
      );
      debugPrint(
        'GENERATOR: - Debit: ${firstTx.transaction.debit}, Credit: ${firstTx.transaction.credit}',
      );
      debugPrint('GENERATOR: - Running Balance: ${firstTx.runningBalance}');
    }

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
                // Header & Branding Section
                _buildHeaderSection(
                  fonts,
                  customerName,
                  openingBalance,
                  currentBalance,
                  fromDate,
                  toDate,
                  businessName: businessName,
                  taxNumber: taxNumber,
                  logoPath: logoPath,
                ),
                pw.SizedBox(height: 16),

                // Financial Summary
                _buildFinancialSummary(
                  fonts,
                  openingBalance,
                  currentBalance,
                  transactions,
                ),
                pw.SizedBox(height: 16),

                // Main Transaction Table
                _buildMainTransactionTable(transactions, fonts, openingBalance),
                pw.SizedBox(height: 16),

                // Footer
                _buildFooterSection(fonts, context),
              ],
            ),
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) => pdf.save(),
      name: 'كشف حساب عميل - $customerName',
      format: PdfPageFormat.a4,
    );
  }

  // Header & Branding Section
  static pw.Widget _buildHeaderSection(
    Map<String, pw.Font?> fonts,
    String customerName,
    double openingBalance,
    double currentBalance,
    DateTime fromDate,
    DateTime toDate, {
    String businessName = '',
    String taxNumber = '',
    String? logoPath,
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
          // Company Logo
          if (logoPath != null && logoPath.isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 8),
              child: _buildLogo(logoPath),
            ),
          // Company Name (dynamic from SettingsService)
          pw.Text(
            businessName.isNotEmpty ? businessName : 'كشف حساب',
            style: pw.TextStyle(
              fontSize: 18,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.blue800,
              font: fonts['arabicBold'],
            ),
            textDirection: pw.TextDirection.rtl,
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

          // Summary Info
          pw.Container(
            width: double.infinity,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                // Customer Name
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'اسم العميل: $customerName',
                      style: pw.TextStyle(
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                        font: fonts['arabicBold'],
                      ),
                      textDirection: pw.TextDirection.rtl,
                    ),
                    pw.Text(
                      'كشف حساب عميل',
                      style: pw.TextStyle(
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold,
                        font: fonts['arabicBold'],
                      ),
                      textDirection: pw.TextDirection.rtl,
                    ),
                  ],
                ),
                pw.SizedBox(height: 8),

                // Current Balance (Red if debt)
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'الرصيد الحالي: ${formatCurrency(currentBalance)}',
                      style: pw.TextStyle(
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                        color: currentBalance > 0
                            ? PdfColors.red
                            : PdfColors.green,
                        font: fonts['arabicBold'],
                      ),
                      textDirection: pw.TextDirection.rtl,
                    ),
                    pw.Text(
                      'الرصيد الافتتاحي: ${formatCurrency(openingBalance)}',
                      style: pw.TextStyle(fontSize: 12, font: fonts['arabic']),
                      textDirection: pw.TextDirection.rtl,
                    ),
                  ],
                ),
                pw.SizedBox(height: 8),

                // Date Range
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  children: [
                    pw.Text(
                      'الفترة: من ${DateFormat('yyyy/MM/dd').format(fromDate)} إلى ${DateFormat('yyyy/MM/dd').format(toDate)}',
                      style: pw.TextStyle(fontSize: 12, font: fonts['arabic']),
                      textDirection: pw.TextDirection.rtl,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Financial Summary Section
  static pw.Widget _buildFinancialSummary(
    Map<String, pw.Font?> fonts,
    double openingBalance,
    double currentBalance,
    List transactions,
  ) {
    double totalDebit = 0.0;
    double totalCredit = 0.0;

    debugPrint(
      'FINANCIAL SUMMARY: Processing ${transactions.length} transactions',
    );

    for (final tx in transactions) {
      debugPrint('FINANCIAL: Processing transaction type: ${tx.runtimeType}');
      debugPrint('FINANCIAL: Transaction object: ${tx.transaction}');

      final debit =
          tx.transaction.debit ?? 0.0; // Access through transaction property
      final credit =
          tx.transaction.credit ?? 0.0; // Access through transaction property
      totalDebit += debit;
      totalCredit += credit;

      debugPrint('FINANCIAL: TX - Debit: $debit, Credit: $credit');
    }

    debugPrint(
      'FINANCIAL SUMMARY: Total Debit: $totalDebit, Total Credit: $totalCredit',
    );
    debugPrint(
      'FINANCIAL SUMMARY: Opening: $openingBalance, Current: $currentBalance',
    );

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
                'إجمالي المدين',
                fonts['arabicBold'],
                isHeader: true,
              ),
              _buildTableCell(
                formatCurrency(totalDebit),
                fonts['arabic'],
                isHeader: true,
              ),
            ],
          ),
          pw.TableRow(
            children: [
              _buildTableCell(
                'إجمالي الدائن',
                fonts['arabicBold'],
                isHeader: true,
              ),
              _buildTableCell(
                formatCurrency(totalCredit),
                fonts['arabic'],
                isHeader: true,
              ),
            ],
          ),
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: PdfColors.grey300),
            children: [
              _buildTableCell(
                'الرصيد النهائي',
                fonts['arabicBold'],
                isHeader: true,
              ),
              _buildTableCell(
                formatCurrency(currentBalance),
                fonts['arabicBold'],
                isHeader: true,
                color: currentBalance > 0 ? PdfColors.red : PdfColors.green,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Traditional Transaction Table
  static pw.Widget _buildMainTransactionTable(
    List transactions,
    Map<String, pw.Font?> fonts,
    double openingBalance,
  ) {
    if (transactions.isEmpty) {
      return pw.Container(
        padding: const pw.EdgeInsets.all(16),
        alignment: pw.Alignment.center,
        child: pw.Text(
          'No transactions in this period',
          style: pw.TextStyle(
            fontSize: 14,
            color: PdfColors.grey600,
            fontWeight: pw.FontWeight.bold,
            font: fonts['arabicBold'],
          ),
          textDirection: pw.TextDirection.ltr,
        ),
      );
    }

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.black, width: 1),
      columnWidths: {
        0: const pw.FlexColumnWidth(0.8), // م (Serial)
        1: const pw.FlexColumnWidth(1.2), // التاريخ (Date)
        2: const pw.FlexColumnWidth(2.5), // البيان (Description)
        3: const pw.FlexColumnWidth(1.2), // الدين (Debit)
        4: const pw.FlexColumnWidth(1.2), // الدائن (Credit)
        5: const pw.FlexColumnWidth(1.2), // الرصيد (Balance)
      },
      children: [
        // Traditional Header row
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey300),
          children: [
            _buildHeaderCell('م', fonts['arabicBold']),
            _buildHeaderCell('التاريخ', fonts['arabicBold']),
            _buildHeaderCell('البيان', fonts['arabicBold']),
            _buildHeaderCell('الدين', fonts['arabicBold']),
            _buildHeaderCell('الدائن', fonts['arabicBold']),
            _buildHeaderCell('الرصيد', fonts['arabicBold']),
          ],
        ),
        // Opening Balance Row
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.blue50),
          children: [
            _buildTableCell(
              '',
              fonts['arabic'],
            ), // No serial for opening balance
            _buildTableCell(
              'رصيد سابق',
              fonts['arabicBold'],
              isBold: true,
            ), // for opening balance
            _buildTableCell(
              'Opening Balance',
              fonts['arabicBold'],
              isBold: true,
            ),
            _buildTableCell(
              openingBalance > 0 ? formatCurrency(openingBalance) : '',
              fonts['arabicBold'],
              isCurrency: true,
              isBold: true,
            ),
            _buildTableCell(
              openingBalance < 0 ? formatCurrency(openingBalance.abs()) : '',
              fonts['arabicBold'],
              isCurrency: true,
              isBold: true,
            ),
            _buildTableCell(
              formatCurrency(openingBalance.abs()),
              fonts['arabicBold'],
              isCurrency: true,
              isBold: true,
            ),
          ],
        ),
        // Data rows
        ...transactions.asMap().entries.map((entry) {
          final index = entry.key;
          final txWithBalance = entry.value;
          final tx = txWithBalance.transaction;

          // Build description
          String description = '';
          if ((tx.credit ?? 0.0) > 0) {
            description = tx.description?.isNotEmpty == true
                ? 'سداد: ${tx.description}'
                : 'سداد جزئي';
          } else {
            description = tx.description ?? 'عملية نقدية';
          }

          return pw.TableRow(
            children: [
              _buildTableCell(
                '${index + 1}',
                fonts['arabic'],
                isCentered: true,
              ),
              _buildTableCell(
                DateFormat('dd/MM/yyyy').format(tx.date),
                fonts['arabic'],
                isCentered: true,
              ),
              _buildTableCell(description, fonts['arabic']),
              _buildTableCell(
                (tx.debit ?? 0.0) > 0 ? formatCurrency(tx.debit) : '',
                fonts['arabic'],
                isCurrency: true,
              ),
              _buildTableCell(
                (tx.credit ?? 0.0) > 0 ? formatCurrency(tx.credit) : '',
                fonts['arabic'],
                isCurrency: true,
              ),
              _buildTableCell(
                formatCurrency(txWithBalance.runningBalance.abs()),
                fonts['arabicBold'],
                isCurrency: true,
                isBold: true,
              ),
            ],
          );
        }),
      ],
    );
  }

  // Footer Section
  static pw.Widget _buildFooterSection(
    Map<String, pw.Font?> fonts,
    pw.Context context,
  ) {
    return pw.Column(
      children: [
        pw.Divider(color: PdfColors.grey300),
        pw.SizedBox(height: 4),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Developed by MO2',
              style: pw.TextStyle(
                fontSize: 8,
                color: PdfColors.grey600,
                font: fonts['arabic'],
              ),
              textDirection: pw.TextDirection.ltr,
            ),
            pw.Text(
              'Page ${context.pageNumber}/${context.pagesCount}',
              style: pw.TextStyle(
                fontSize: 8,
                color: PdfColors.grey600,
                font: fonts['arabic'],
              ),
              textDirection: pw.TextDirection.ltr,
            ),
          ],
        ),
        pw.SizedBox(height: 2),
        pw.Center(
          child: pw.Text(
            DateFormat(
              'yyyy-MM-dd hh:mm a',
            ).format(DateTime.now()),
            style: pw.TextStyle(
              fontSize: 8,
              color: PdfColors.grey500,
              font: fonts['arabic'],
            ),
            textDirection: pw.TextDirection.ltr,
          ),
        ),
      ],
    );
  }

  // Helper methods
  static pw.Widget _buildHeaderCell(String text, pw.Font? font) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      alignment: pw.Alignment.center,
      child: pw.Text(
        text, // Use simple text without reshaping to avoid Bidi errors
        style: pw.TextStyle(
          fontSize: 12,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.white,
          font: font,
        ),
        textDirection: pw.TextDirection.rtl, // RTL for Arabic
      ),
    );
  }

  static pw.Widget _buildTableCell(
    String text,
    pw.Font? font, {
    bool isHeader = false,
    bool isBold = false,
    bool isCurrency = false,
    bool isCentered = false,
    PdfColor? color,
  }) {
    // Handle Arabic text properly but avoid Bidi issues
    String displayText = text;
    pw.TextDirection textDirection = pw.TextDirection.rtl;

    // For currency, use LTR to avoid Bidi issues
    if (isCurrency) {
      textDirection = pw.TextDirection.ltr;
    } else {
      // For Arabic text, use simple approach without reshaping to avoid Bidi errors
      textDirection = pw.TextDirection.rtl;
      // Don't use reshaping to avoid Bidi processing errors
    }

    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      alignment: isCentered
          ? pw.Alignment.center
          : (isCurrency ? pw.Alignment.centerRight : pw.Alignment.centerRight),
      child: pw.Text(
        displayText,
        style: pw.TextStyle(
          fontSize: 10,
          fontWeight: isHeader || isBold
              ? pw.FontWeight.bold
              : pw.FontWeight.normal,
          color: color ?? PdfColors.black,
          font: font ?? pw.Font.helvetica(),
        ),
        textDirection: textDirection,
      ),
    );
  }

  static pw.Widget _buildLogo(String logoPath) {
    try {
      final file = File(logoPath);
      if (file.existsSync()) {
        final bytes = file.readAsBytesSync();
        return pw.Image(pw.MemoryImage(bytes), height: 60);
      }
    } catch (e) {
      debugPrint('Logo load failed: $e');
    }
    return pw.SizedBox.shrink();
  }

  static String formatCurrency(double amount) {
    // Use simple format without Arabic characters to avoid Bidi issues
    return '${amount.toStringAsFixed(2)} EGP';
  }
}
