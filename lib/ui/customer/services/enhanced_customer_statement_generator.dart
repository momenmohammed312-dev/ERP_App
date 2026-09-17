import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/dao/ledger_dao.dart';
import 'package:pos_offline_desktop/core/services/settings_service.dart';
import 'package:pos_offline_desktop/core/utils/pdf_bidi_helper.dart';

/// Shared statement helpers used by the customer screen + customer PDF +
/// supplier screen + supplier PDF (B6–B9: ONE normalizer, ONE label rule).
///
/// ## Display-number contract (consumed, not redefined)
/// Invoice display number = stored `invoice.invoiceNumber` (Agent 1 owns
/// numbering). New-ledger descriptions read 'فاتورة NNNNNN' / 'سداد NNNNNN' /
/// 'عمولة NNNNNN' (Agent 1); legacy rows keep old text.
///
/// ## Label rule (defined once here)
///  - a row linked to an invoice/purchase whose stored number is known →
///    EXACTLY `فاتورة NUMBER` (customer) / `فاتورة مشتريات NUMBER`
///    (supplier). The link is resolved ONLY via the structured
///    `receiptNumber`/`refId` columns — NEVER by parsing free-text
///    descriptions;
///  - every other row → the stored description VERBATIM (legacy untouched,
///    canonical new rows already carry their exact text).
abstract final class StatementHelpers {
  /// Canonical customer invoice label, e.g. 'فاتورة 000001'.
  static String invoiceLabel(String number) => 'فاتورة $number';

  /// Canonical supplier purchase label, e.g. 'فاتورة مشتريات PUR-001'.
  /// (Supplier rows are purchases/payments, so the purchase word is part of
  /// the exact label — defined once here.)
  static String purchaseLabel(String number) => 'فاتورة مشتريات $number';

  /// Already-canonical descriptions (Agent 1 new format) pass through
  /// untouched. Anything else is legacy → also verbatim.
  static final canonicalDescription =
      RegExp(r'^(فاتورة|سداد|عمولة)(\s|$)');

  /// Day-truncated start (00:00:00) — inclusive lower bound.
  static DateTime startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Day-truncated end (23:59:59) — inclusive upper bound.
  static DateTime endOfDay(DateTime d) =>
      DateTime(d.year, d.month, d.day, 23, 59, 59);

  /// Normalizes a UI date range to inclusive day boundaries. Used by
  /// screen queries AND both PDF generators so all three always agree.
  static (DateTime, DateTime) normalizeRange(DateTime from, DateTime to) =>
      (startOfDay(from), endOfDay(to));

  /// Opening-balance cutoff: one second before the (normalized) period
  /// start. Unifies the divergent `customer_report_tab` path (which used
  /// `start − 1 day`) to the canonical `getRunningBalance up-to from−1s`.
  static DateTime openingCutoff(DateTime from) =>
      startOfDay(from).subtract(const Duration(seconds: 1));

  /// Display label for a CUSTOMER ledger row.
  /// [invoiceNumber] is the stored `invoice.invoiceNumber` resolved via the
  /// stable `receiptNumber → invoice` link (null when unresolvable).
  static String customerRowLabel(
    LedgerTransaction tx, {
    String? invoiceNumber,
  }) {
    if (tx.origin == 'sale' &&
        invoiceNumber != null &&
        invoiceNumber.isNotEmpty) {
      return invoiceLabel(invoiceNumber);
    }
    return tx.description;
  }

  /// Display label for a SUPPLIER ledger row.
  /// [purchaseNumber] is the stored `purchase.invoiceNumber` resolved via the
  /// stable `receiptNumber → purchase` link (null when unresolvable).
  static String supplierRowLabel(
    LedgerTransaction tx, {
    String? purchaseNumber,
  }) {
    if ((tx.origin == 'purchase' || tx.origin == 'opening') &&
        purchaseNumber != null &&
        purchaseNumber.isNotEmpty) {
      return purchaseLabel(purchaseNumber);
    }
    return tx.description;
  }

  /// Resolves the stored invoice display number via the stable
  /// `receiptNumber = INV + localId` link. Returns null when the row is not
  /// invoice-linked or the invoice is gone (caller falls back to verbatim).
  /// NEVER parses the free-text description.
  static Future<String?> resolveInvoiceNumber(
    AppDatabase db,
    String? receiptNumber,
  ) async {
    final id = extractInvoiceId(receiptNumber);
    if (id == null) return null;
    final inv = await db.invoiceDao.getInvoiceById(id);
    final n = inv?.invoiceNumber;
    return (n == null || n.isEmpty) ? null : n;
  }

  /// Resolves the stored purchase invoice number via the stable
  /// `receiptNumber == purchase.id|invoiceNumber` link. Null → verbatim.
  /// NEVER parses the free-text description.
  static Future<String?> resolvePurchaseNumber(
    AppDatabase db,
    String? receiptNumber,
  ) async {
    if (receiptNumber == null || receiptNumber.isEmpty) return null;
    // Two sequential lookups (no drift `|` import needed in this file).
    var purchase = await (db.select(db.purchases)
          ..where((p) => p.invoiceNumber.equals(receiptNumber)))
        .getSingleOrNull();
    purchase ??= await (db.select(db.purchases)
          ..where((p) => p.id.equals(receiptNumber)))
        .getSingleOrNull();
    final n = purchase?.invoiceNumber;
    return (n == null || n.isEmpty) ? null : n;
  }

  /// Extracts the local invoice id from the structured `receiptNumber`
  /// column (`INV` followed by the id). This parses a STABLE LINK column,
  /// not free text.
  static int? extractInvoiceId(String? receiptNumber) {
    if (receiptNumber == null || receiptNumber.isEmpty) return null;
    if (!receiptNumber.startsWith('INV')) return null;
    return int.tryParse(receiptNumber.substring(3));
  }
}

class EnhancedCustomerStatementGenerator {
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

  /// Extract invoice ID from the structured receiptNumber column
  /// (format: INV followed by integer). Delegates to the single shared
  /// definition in [StatementHelpers].
  static int? _extractInvoiceId(String? receiptNumber) =>
      StatementHelpers.extractInvoiceId(receiptNumber);

  /// Pre-fetch invoice items for all sale transactions.
  static Future<Map<int, List<_InvoiceItemInfo>>> _fetchInvoiceItems(
    AppDatabase db,
    List<LedgerTransactionWithBalance> transactions,
  ) async {
    final result = <int, List<_InvoiceItemInfo>>{};
    for (final txw in transactions) {
      final tx = txw.transaction;
      if (tx.debit <= 0) continue;
      if (tx.receiptNumber == null || tx.receiptNumber!.isEmpty) continue;
      final invoiceId = _extractInvoiceId(tx.receiptNumber);
      if (invoiceId == null) continue;
      if (result.containsKey(invoiceId)) continue;

      try {
        final items = await db.invoiceDao.getItemsWithProductsByInvoice(invoiceId);
        result[invoiceId] = items.map((pair) {
          final item = pair.$1;
          final product = pair.$2;
          return _InvoiceItemInfo(
            productName: product?.name ?? 'منتج',
            quantity: item.quantity,
            unitPrice: item.price,
            discount: item.discount,
          );
        }).toList();
      } catch (_) {
        result[invoiceId] = [];
      }
    }
    return result;
  }

  /// Pre-fetch stored invoice display numbers keyed by receiptNumber, so the
  /// PDF prints the canonical 'فاتورة NNNNNN' label for linked rows and the
  /// stored description verbatim for everything else (legacy untouched).
  static Future<Map<String, String>> _fetchInvoiceNumbers(
    AppDatabase db,
    List<LedgerTransactionWithBalance> transactions,
  ) async {
    final result = <String, String>{};
    for (final txw in transactions) {
      final rn = txw.transaction.receiptNumber;
      if (rn == null || rn.isEmpty || result.containsKey(rn)) continue;
      final number = await StatementHelpers.resolveInvoiceNumber(db, rn);
      if (number != null) result[rn] = number;
    }
    return result;
  }

  static Future<void> generateStatement({
    required AppDatabase db,
    required String customerId,
    required String customerName,
    required DateTime fromDate,
    required DateTime toDate,
    required double openingBalance,
    required double currentBalance,
    List<LedgerTransactionWithBalance>? transactions,
  }) async {
    final fonts = await _loadFonts();
    final pdf = pw.Document();

    final (fromDateNormalized, normalizedToDate) =
        StatementHelpers.normalizeRange(fromDate, toDate);

    final effectiveTransactions = transactions ??
        await db.ledgerDao.getTransactionsWithRunningBalance(
          'Customer',
          customerId,
          fromDateNormalized,
          normalizedToDate,
        );

    final invoiceItems = await _fetchInvoiceItems(db, effectiveTransactions);
    final invoiceNumbers = await _fetchInvoiceNumbers(
      db,
      effectiveTransactions,
    );

    final businessName = await SettingsService.getBusinessName();
    final taxNumber = await SettingsService.getTaxNumber();
    final logoPath = await SettingsService.getBusinessLogoPath();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        header: (pw.Context context) => _buildHeader(
          fonts,
          title: _b('كشف حساب عميل (مفصل)'),
          partyLabel: _b('اسم العميل'),
          partyName: _b(customerName),
          fromDate: fromDate,
          toDate: toDate,
          openingBalance: openingBalance,
          currentBalance: currentBalance,
          businessName: _b(businessName),
          taxNumber: taxNumber,
          logoPath: logoPath,
        ),
        footer: (pw.Context context) => _buildFooter(fonts, context),
        build: (pw.Context context) => [
          _buildFinancialSummary(
            fonts,
            openingBalance: openingBalance,
            currentBalance: currentBalance,
            totalDebit: effectiveTransactions.fold<double>(
              0,
              (s, t) => s + t.transaction.debit,
            ),
            totalCredit: effectiveTransactions.fold<double>(
              0,
              (s, t) => s + t.transaction.credit,
            ),
          ),
          pw.SizedBox(height: 12),
          _buildDetailedTable(
            effectiveTransactions,
            fonts,
            openingBalance,
            invoiceItems,
            invoiceNumbers,
          ),
        ],
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) => pdf.save(),
      name: _b('كشف حساب عميل مفصل - $customerName'),
      format: PdfPageFormat.a4,
    );
  }

  // ─── SUMMARY STATEMENT ────────────────────────────────────────────

  static Future<void> generateSummaryStatement({
    required AppDatabase db,
    required String customerId,
    required String customerName,
    required DateTime fromDate,
    required DateTime toDate,
    required double openingBalance,
    required double currentBalance,
    List<LedgerTransactionWithBalance>? transactions,
  }) async {
    final fonts = await _loadFonts();
    final pdf = pw.Document();

    final (fromDateNormalized, normalizedToDate) =
        StatementHelpers.normalizeRange(fromDate, toDate);

    final effectiveTransactions = transactions ??
        await db.ledgerDao.getTransactionsWithRunningBalance(
          'Customer',
          customerId,
          fromDateNormalized,
          normalizedToDate,
        );

    final businessName = await SettingsService.getBusinessName();
    final taxNumber = await SettingsService.getTaxNumber();
    final logoPath = await SettingsService.getBusinessLogoPath();

    final totalDebit =
        effectiveTransactions.fold<double>(0, (s, t) => s + t.transaction.debit);
    final totalCredit =
        effectiveTransactions.fold<double>(0, (s, t) => s + t.transaction.credit);

    final monthlyData = _aggregateByMonth(effectiveTransactions);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        header: (pw.Context context) => _buildHeader(
          fonts,
          title: _b('كشف حساب عميل (مختصر)'),
          partyLabel: _b('اسم العميل'),
          partyName: _b(customerName),
          fromDate: fromDate,
          toDate: toDate,
          openingBalance: openingBalance,
          currentBalance: currentBalance,
          businessName: _b(businessName),
          taxNumber: taxNumber,
          logoPath: logoPath,
        ),
        footer: (pw.Context context) => _buildFooter(fonts, context),
        build: (pw.Context context) => [
          _buildFinancialSummary(
            fonts,
            openingBalance: openingBalance,
            currentBalance: currentBalance,
            totalDebit: totalDebit,
            totalCredit: totalCredit,
          ),
          pw.SizedBox(height: 12),
          _buildSummaryTable(monthlyData, fonts, openingBalance),
        ],
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) => pdf.save(),
      name: _b('كشف حساب عميل مختصر - $customerName'),
      format: PdfPageFormat.a4,
    );
  }

  // ─── SHARED: Header ──────────────────────────────────────────────

  static pw.Widget _buildHeader(
    Map<String, pw.Font?> fonts, {
    required String title,
    required String partyLabel,
    required String partyName,
    required DateTime fromDate,
    required DateTime toDate,
    required double openingBalance,
    required double currentBalance,
    String businessName = '',
    String taxNumber = '',
    String? logoPath,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black, width: 1),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          if (logoPath != null && logoPath.isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 6),
              child: _buildLogo(logoPath),
            ),
          pw.Text(
            businessName.isNotEmpty ? businessName : title,
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
              font: fonts['arabicBold'],
            ),
          ),
          if (taxNumber.isNotEmpty)
            pw.Text(
              _b('الرقم الضريبي: $taxNumber'),
              style: pw.TextStyle(fontSize: 9, font: fonts['arabic']),
            ),
          pw.SizedBox(height: 8),
          pw.Text(
            title,
            style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
              font: fonts['arabicBold'],
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                '$partyLabel: $partyName',
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  font: fonts['arabicBold'],
                ),
              ),
              pw.Text(
                _b(
                  'الفترة: ${DateFormat('yyyy/MM/dd').format(fromDate)} - ${DateFormat('yyyy/MM/dd').format(toDate)}',
                ),
                style: pw.TextStyle(fontSize: 10, font: fonts['arabic']),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── SHARED: Financial Summary ───────────────────────────────────

  static pw.Widget _buildFinancialSummary(
    Map<String, pw.Font?> fonts, {
    required double openingBalance,
    required double currentBalance,
    required double totalDebit,
    required double totalCredit,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black, width: 1),
      ),
      child: pw.Table(
        columnWidths: {
          0: const pw.FlexColumnWidth(2),
          1: const pw.FlexColumnWidth(1),
        },
        border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
        children: [
          _summaryRow(_b('الرصيد الافتتاحي'), _fmt(openingBalance), fonts),
          _summaryRow(
            _b('إجمالي المدين (المشتريات)'),
            _fmt(totalDebit),
            fonts,
          ),
          _summaryRow(
            _b('إجمالي الدائن (المدفوعات)'),
            _fmt(totalCredit),
            fonts,
          ),
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: PdfColors.grey200),
            children: [
              _cell(_b('الرصيد النهائي'), fonts['arabicBold'], bold: true),
              _cell(
                _fmt(currentBalance),
                fonts['arabicBold'],
                bold: true,
                color: currentBalance > 0 ? PdfColors.red : PdfColors.green,
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.TableRow _summaryRow(
    String label,
    String value,
    Map<String, pw.Font?> fonts,
  ) {
    return pw.TableRow(
      children: [
        _cell(label, fonts['arabicBold'], bold: true),
        _cell(value, fonts['arabic']),
      ],
    );
  }

  // ─── DETAILED TABLE (with invoice item sub-rows) ─────────────────

  static pw.Widget _buildDetailedTable(
    List<LedgerTransactionWithBalance> transactions,
    Map<String, pw.Font?> fonts,
    double openingBalance,
    Map<int, List<_InvoiceItemInfo>> invoiceItems,
    Map<String, String> invoiceNumbers,
  ) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.black, width: 1),
      columnWidths: {
        0: const pw.FlexColumnWidth(0.5),
        1: const pw.FlexColumnWidth(1.0),
        2: const pw.FlexColumnWidth(2.5),
        3: const pw.FlexColumnWidth(1.0),
        4: const pw.FlexColumnWidth(1.0),
        5: const pw.FlexColumnWidth(1.0),
      },
      children: [
        _tableHeaderRow(fonts),
        _openingRow(openingBalance, fonts),
        ...transactions.asMap().entries.expand((e) {
          final i = e.key;
          final txw = e.value;
          final tx = txw.transaction;
          final rows = <pw.TableRow>[];

          // Main row — label rule (StatementHelpers): linked invoice with a
          // known stored number → exactly 'فاتورة NNNNNN'; everything else
          // (legacy or new-canonical) → stored description verbatim.
          final desc = _b(
            StatementHelpers.customerRowLabel(
              tx,
              invoiceNumber: tx.receiptNumber == null
                  ? null
                  : invoiceNumbers[tx.receiptNumber],
            ),
          );

          rows.add(pw.TableRow(
            children: [
              _cell('${i + 1}', fonts['arabic'], centered: true),
              _cell(
                DateFormat('dd/MM/yyyy').format(tx.date),
                fonts['arabic'],
                centered: true,
              ),
              _cell(desc, fonts['arabic']),
              _cell(
                tx.debit > 0 ? _fmt(tx.debit) : '',
                fonts['arabic'],
                alignRight: true,
              ),
              _cell(
                tx.credit > 0 ? _fmt(tx.credit) : '',
                fonts['arabic'],
                alignRight: true,
              ),
              _cell(
                _fmt(txw.runningBalance),
                fonts['arabicBold'],
                bold: true,
                alignRight: true,
              ),
            ],
          ));

          // Sub-rows for invoice items (only for sale transactions).
          // Nested items stay — resolved via the stable receiptNumber link.
          final isCredit = tx.credit > 0;
          if (!isCredit && tx.receiptNumber != null && tx.receiptNumber!.isNotEmpty) {
            final invoiceId = _extractInvoiceId(tx.receiptNumber);
            if (invoiceId != null && invoiceItems.containsKey(invoiceId)) {
              final items = invoiceItems[invoiceId]!;
              for (final item in items) {
                final lineTotal = (item.quantity * item.unitPrice) - item.discount;
                final itemDesc = item.discount > 0
                    ? '${item.productName}  (${item.quantity} × ${_fmt(item.unitPrice)}) - ${_fmt(item.discount)}'
                    : '${item.productName}  (${item.quantity} × ${_fmt(item.unitPrice)}) = ${_fmt(lineTotal)}';
                rows.add(pw.TableRow(
                  children: [
                    _cell('', fonts['arabic']),
                    _cell('', fonts['arabic']),
                    pw.Container(
                      padding: const pw.EdgeInsets.only(right: 12),
                      child: pw.Container(
                        padding: const pw.EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: pw.BoxDecoration(
                          color: PdfColors.grey100,
                          border: pw.Border.all(
                            color: PdfColors.grey300,
                            width: 0.5,
                          ),
                          borderRadius: const pw.BorderRadius.all(
                            pw.Radius.circular(3),
                          ),
                        ),
                        child: pw.Text(
                          _b(itemDesc),
                          style: pw.TextStyle(
                            fontSize: 7,
                            font: fonts['arabic'],
                          ),
                        ),
                      ),
                    ),
                    _cell('', fonts['arabic']),
                    _cell('', fonts['arabic']),
                    _cell('', fonts['arabic']),
                  ],
                ));
              }
            }
          }
          return rows;
        }),
        _totalRow(transactions, fonts),
      ],
    );
  }

  // ─── SUMMARY TABLE ───────────────────────────────────────────────

  static pw.Widget _buildSummaryTable(
    List<_MonthData> months,
    Map<String, pw.Font?> fonts,
    double openingBalance,
  ) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.black, width: 1),
      columnWidths: {
        0: const pw.FlexColumnWidth(1.5),
        1: const pw.FlexColumnWidth(1.2),
        2: const pw.FlexColumnWidth(1.2),
        3: const pw.FlexColumnWidth(1.2),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            _cell(
              _b('الشهر'),
              fonts['arabicBold'],
              bold: true,
              centered: true,
            ),
            _cell(
              _b('المشتريات'),
              fonts['arabicBold'],
              bold: true,
              centered: true,
            ),
            _cell(
              _b('المدفوعات'),
              fonts['arabicBold'],
              bold: true,
              centered: true,
            ),
            _cell(
              _b('الرصيد'),
              fonts['arabicBold'],
              bold: true,
              centered: true,
            ),
          ],
        ),
        pw.TableRow(
          children: [
            _cell(_b('رصيد سابق'), fonts['arabicBold'], bold: true),
            _cell('', fonts['arabic']),
            _cell('', fonts['arabic']),
            _cell(
              _fmt(openingBalance),
              fonts['arabicBold'],
              bold: true,
              alignRight: true,
            ),
          ],
        ),
        ...months.map((m) {
          return pw.TableRow(
            children: [
              _cell(_b(m.label), fonts['arabic'], centered: true),
              _cell(_fmt(m.totalDebit), fonts['arabic'], alignRight: true),
              _cell(_fmt(m.totalCredit), fonts['arabic'], alignRight: true),
              _cell(
                _fmt(m.balance),
                fonts['arabicBold'],
                bold: true,
                alignRight: true,
              ),
            ],
          );
        }),
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            _cell(
              _b('الإجمالي'),
              fonts['arabicBold'],
              bold: true,
              centered: true,
            ),
            _cell(
              _fmt(months.fold<double>(0, (s, m) => s + m.totalDebit)),
              fonts['arabicBold'],
              bold: true,
              alignRight: true,
            ),
            _cell(
              _fmt(months.fold<double>(0, (s, m) => s + m.totalCredit)),
              fonts['arabicBold'],
              bold: true,
              alignRight: true,
            ),
            _cell(
              _fmt(months.isNotEmpty ? months.last.balance : openingBalance),
              fonts['arabicBold'],
              bold: true,
              alignRight: true,
            ),
          ],
        ),
      ],
    );
  }

  // ─── SHARED: Footer ──────────────────────────────────────────────

  static pw.Widget _buildFooter(
    Map<String, pw.Font?> fonts,
    pw.Context context,
  ) {
    return pw.Column(
      children: [
        pw.SizedBox(height: 20),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              _b(
                'تم الإصدار: ${DateFormat('yyyy/MM/dd hh:mm a').format(DateTime.now())}',
              ),
              style: pw.TextStyle(fontSize: 8, font: fonts['arabic']),
            ),
            pw.Text(
              _b('صفحة ${context.pageNumber} من ${context.pagesCount}'),
              style: pw.TextStyle(fontSize: 8, font: fonts['arabic']),
            ),
          ],
        ),
        pw.SizedBox(height: 16),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Container(
                  width: 120,
                  height: 1,
                  color: PdfColors.black,
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  _b('توقيع العميل'),
                  style: pw.TextStyle(
                    fontSize: 9,
                    font: fonts['arabicBold'],
                  ),
                ),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Container(
                  width: 120,
                  height: 1,
                  color: PdfColors.black,
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  _b('ختم الشركة'),
                  style: pw.TextStyle(
                    fontSize: 9,
                    font: fonts['arabicBold'],
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  // ─── SHARED: Table Helpers ───────────────────────────────────────

  static pw.TableRow _tableHeaderRow(Map<String, pw.Font?> fonts) {
    return pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.grey200),
      children: [
        _cell(_b('م'), fonts['arabicBold'], bold: true, centered: true),
        _cell(_b('التاريخ'), fonts['arabicBold'], bold: true, centered: true),
        _cell(_b('البيان'), fonts['arabicBold'], bold: true, centered: true),
        _cell(
          _b('قيمة المشتريات'),
          fonts['arabicBold'],
          bold: true,
          centered: true,
        ),
        _cell(
          _b('قيمة المدفوعات'),
          fonts['arabicBold'],
          bold: true,
          centered: true,
        ),
        _cell(_b('الرصيد'), fonts['arabicBold'], bold: true, centered: true),
      ],
    );
  }

  static pw.TableRow _openingRow(
    double openingBalance,
    Map<String, pw.Font?> fonts,
  ) {
    return pw.TableRow(
      children: [
        _cell('', fonts['arabic']),
        _cell('', fonts['arabic']),
        _cell(_b('رصيد سابق'), fonts['arabicBold'], bold: true),
        _cell(
          openingBalance > 0 ? _fmt(openingBalance) : '',
          fonts['arabicBold'],
          bold: true,
          alignRight: true,
        ),
        _cell(
          openingBalance < 0 ? _fmt(openingBalance.abs()) : '',
          fonts['arabicBold'],
          bold: true,
          alignRight: true,
        ),
        _cell(
          _fmt(openingBalance.abs()),
          fonts['arabicBold'],
          bold: true,
          alignRight: true,
        ),
      ],
    );
  }

  static pw.TableRow _totalRow(
    List<LedgerTransactionWithBalance> transactions,
    Map<String, pw.Font?> fonts,
  ) {
    final totalDebit =
        transactions.fold<double>(0, (s, t) => s + t.transaction.debit);
    final totalCredit =
        transactions.fold<double>(0, (s, t) => s + t.transaction.credit);
    return pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColors.grey200),
      children: [
        _cell('', fonts['arabic']),
        _cell('', fonts['arabic']),
        _cell(
          _b('الإجمالي'),
          fonts['arabicBold'],
          bold: true,
          centered: true,
        ),
        _cell(
          _fmt(totalDebit),
          fonts['arabicBold'],
          bold: true,
          alignRight: true,
        ),
        _cell(
          _fmt(totalCredit),
          fonts['arabicBold'],
          bold: true,
          alignRight: true,
        ),
        _cell('', fonts['arabicBold']),
      ],
    );
  }

  static pw.Widget _cell(
    String text,
    pw.Font? font, {
    bool bold = false,
    bool centered = false,
    bool alignRight = false,
    PdfColor? color,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      alignment: centered
          ? pw.Alignment.center
          : (alignRight
              ? pw.Alignment.centerRight
              : pw.Alignment.centerRight),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 9,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: color ?? PdfColors.black,
          font: font,
        ),
      ),
    );
  }

  // ─── Logo ────────────────────────────────────────────────────────

  static pw.Widget _buildLogo(String logoPath) {
    try {
      final file = File(logoPath);
      if (file.existsSync()) {
        final bytes = file.readAsBytesSync();
        return pw.Image(pw.MemoryImage(bytes), height: 50);
      }
    } catch (_) {}
    return pw.SizedBox.shrink();
  }

  // ─── Helpers ─────────────────────────────────────────────────────

  static String _fmt(double amount) => amount.toStringAsFixed(2);

  static List<_MonthData> _aggregateByMonth(
    List<LedgerTransactionWithBalance> transactions,
  ) {
    final map = <String, _MonthData>{};
    for (final txw in transactions) {
      final key = DateFormat('yyyy-MM').format(txw.transaction.date);
      map.putIfAbsent(
        key,
        () => _MonthData(
          label: _arabicMonth(txw.transaction.date),
          totalDebit: 0,
          totalCredit: 0,
          balance: 0,
        ),
      );
      final m = map[key]!;
      m.totalDebit += txw.transaction.debit;
      m.totalCredit += txw.transaction.credit;
      m.balance = txw.runningBalance;
    }
    return map.values.toList();
  }

  static String _arabicMonth(DateTime date) {
    const months = [
      'يناير',
      'فبراير',
      'مارس',
      'أبريل',
      'مايو',
      'يونيو',
      'يوليو',
      'أغسطس',
      'سبتمبر',
      'أكتوبر',
      'نوفمبر',
      'ديسمبر',
    ];
    return '${months[date.month - 1]} ${date.year}';
  }
}

class _MonthData {
  String label;
  double totalDebit;
  double totalCredit;
  double balance;

  _MonthData({
    required this.label,
    required this.totalDebit,
    required this.totalCredit,
    required this.balance,
  });
}

class _InvoiceItemInfo {
  final String productName;
  final int quantity;
  final double unitPrice;
  final double discount;

  _InvoiceItemInfo({
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.discount,
  });
}
