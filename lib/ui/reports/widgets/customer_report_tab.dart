import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/services/export_service.dart';
import 'package:pos_offline_desktop/core/services/settings_service.dart';
import 'package:pos_offline_desktop/l10n/l10n.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class CustomerReportTab extends StatefulWidget {
  final AppDatabase db;

  const CustomerReportTab({super.key, required this.db});

  @override
  State<CustomerReportTab> createState() => _CustomerReportTabState();
}

class _CustomerReportTabState extends State<CustomerReportTab> {
  List<CustomerWithBalance> _customers = [];
  List<CustomerWithBalance> _filteredCustomers = [];
  bool _isLoading = false;
  bool _showOnlyDues = false;
  DateTime _reportStart = DateTime.now().subtract(const Duration(days: 30));
  DateTime _reportEnd = DateTime.now();
  final TextEditingController _searchController = TextEditingController();
  final ExportService _exportService = ExportService();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final customers = await widget.db.customerDao.getAllCustomers();
      final List<CustomerWithBalance> result = [];

      for (final customer in customers) {
        // use getCustomerBalance from LedgerDao
        // Note: LedgerDao returns Debit - Credit.
        // Debit = Sales, Credit = Payments.
        // Balance = Sales - Payments.
        // Positive = They owe us (Receivable).
        // Negative = We owe them (Payable).
        final rawBalance = await widget.db.ledgerDao.getCustomerBalance(
          customer.id,
        );
        // Add opening balance from Customer entity
        final totalBalance = rawBalance + customer.openingBalance;

        result.add(
          CustomerWithBalance(customer: customer, balance: totalBalance),
        );
      }

      setState(() {
        _customers = result;
        _filteredCustomers = result;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.error_loading_data_with_error(e)),
          ),
        );
      }
    }
  }

  void _filterCustomers() {
    setState(() {
      _filteredCustomers = _customers.where((customer) {
        // Apply search filter
        final matchesSearch =
            _searchController.text.isEmpty ||
            customer.customer.name.toLowerCase().contains(
              _searchController.text.toLowerCase(),
            ) ||
            (customer.customer.phone?.toLowerCase().contains(
                  _searchController.text.toLowerCase(),
                ) ??
                false);

        // Apply dues filter
        final hasDues = customer.balance > 0;
        final passesDuesFilter = !_showOnlyDues || hasDues;

        return matchesSearch && passesDuesFilter;
      }).toList();
    });
  }

  Future<void> _exportPDF() async {
    try {
      final customersToExport = _showOnlyDues
          ? _filteredCustomers.where((c) => c.balance > 0).toList()
          : _filteredCustomers;

      final data = customersToExport.map((c) {
        return {
          'name': c.customer.name,
          'phone': c.customer.phone ?? '',
          'balance':
              c.balance, // This will trigger red coloring for positive values
        };
      }).toList();

      await _exportService.exportToPDF(
        title: context.l10n.customer_balances_tab,
        data: data,
        headers: [
          context.l10n.customer,
          context.l10n.phone,
          context.l10n.receivable_balance,
        ],
        columns: [
          'name',
          'phone',
          'balance',
        ],
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.error_exporting_with_error(e))),
        );
      }
    }
  }

  Future<void> _exportFullReport() async {
    final customersToExport = _showOnlyDues
        ? _filteredCustomers.where((c) => c.balance > 0).toList()
        : _filteredCustomers;

    if (customersToExport.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لا يوجد عملاء للتصدير')),
        );
      }
      return;
    }

    setState(() => _isLoading = true);
    try {
      final db = widget.db;
      final businessName = await SettingsService.getBusinessName();
      final taxNumber = await SettingsService.getTaxNumber();
      final logoPath = await SettingsService.getBusinessLogoPath();

      pw.Font? arabicFont;
      pw.Font? arabicBoldFont;
      try {
        final fontData = await rootBundle.load(
          'assets/fonts/NotoNaskhArabic-Regular.ttf',
        );
        arabicFont = pw.Font.ttf(fontData);
        arabicBoldFont = pw.Font.ttf(fontData);
      } catch (_) {
        arabicFont = pw.Font.helvetica();
        arabicBoldFont = pw.Font.helvetica();
      }

      final pdf = pw.Document();

      for (final cwb in customersToExport) {
        final transactions = await db.ledgerDao
            .getTransactionsWithRunningBalance(
              'Customer',
              cwb.customer.id,
              _reportStart,
              _reportEnd,
            );

        final openingBalance = await db.ledgerDao.getRunningBalance(
          'Customer',
          cwb.customer.id,
          upToDate: _reportStart.subtract(const Duration(days: 1)),
        );

        final totalDebit = transactions.fold<double>(
          0, (s, t) => s + t.transaction.debit);
        final totalCredit = transactions.fold<double>(
          0, (s, t) => s + t.transaction.credit);

        pdf.addPage(
          pw.MultiPage(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(20),
            build: (pw.Context ctx) => [
              pw.Directionality(
                textDirection: pw.TextDirection.rtl,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    _buildPdfHeader(
                      arabicFont, arabicBoldFont,
                      cwb.customer.name, businessName, taxNumber, logoPath),
                    pw.SizedBox(height: 8),
                    _buildPdfPeriod(arabicFont, cwb.balance),
                    pw.SizedBox(height: 8),
                    _buildPdfSummaryCards(
                      arabicFont, arabicBoldFont,
                      openingBalance, totalDebit, totalCredit, cwb.balance),
                    pw.SizedBox(height: 12),
                    _buildPdfTransactionTable(
                      transactions, arabicFont, arabicBoldFont, openingBalance),
                    pw.SizedBox(height: 12),
                    pw.Divider(color: PdfColors.grey300),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'تم التوليد في: ${DateFormat('yyyy/MM/dd hh:mm a').format(DateTime.now())}',
                      style: pw.TextStyle(
                        fontSize: 8, color: PdfColors.grey600, font: arabicFont),
                      textDirection: pw.TextDirection.rtl,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) => pdf.save(),
        name: 'تقرير العملاء الكامل',
        format: PdfPageFormat.a4,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم طباعة التقرير الكامل بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في طباعة التقرير الكامل: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  pw.Widget _buildPdfHeader(
    pw.Font? font, pw.Font? boldFont,
    String customerName, String businessName, String taxNumber, String? logoPath,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
      ),
      child: pw.Column(
        children: [
          if (logoPath != null && logoPath.isNotEmpty)
            _buildPdfLogo(logoPath),
          pw.Text(
            businessName.isNotEmpty ? businessName : 'تقرير العملاء',
            style: pw.TextStyle(
              fontSize: 18, fontWeight: pw.FontWeight.bold,
              color: PdfColors.blue800, font: boldFont,
            ),
            textDirection: pw.TextDirection.rtl,
          ),
          if (taxNumber.isNotEmpty)
            pw.Text(
              'الرقم الضريبي: $taxNumber',
              style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700, font: font),
              textDirection: pw.TextDirection.rtl,
            ),
          pw.SizedBox(height: 8),
          pw.Text(
            customerName,
            style: pw.TextStyle(
              fontSize: 14, fontWeight: pw.FontWeight.bold, font: boldFont),
            textDirection: pw.TextDirection.rtl,
          ),
        ],
      ),
    );
  }

  pw.Widget _buildPdfLogo(String logoPath) {
    try {
      final file = File(logoPath);
      if (file.existsSync()) {
        return pw.Image(pw.MemoryImage(file.readAsBytesSync()), height: 50);
      }
    } catch (_) {}
    return pw.SizedBox.shrink();
  }

  pw.Widget _buildPdfPeriod(pw.Font? font, double balance) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey100,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            'الرصيد الحالي: ${_formatCurrency(balance)}',
            style: pw.TextStyle(
              fontSize: 12, fontWeight: pw.FontWeight.bold,
              color: balance > 0 ? PdfColors.red : PdfColors.green,
              font: font,
            ),
            textDirection: pw.TextDirection.rtl,
          ),
          pw.Text(
            'من ${DateFormat('yyyy/MM/dd').format(_reportStart)} إلى ${DateFormat('yyyy/MM/dd').format(_reportEnd)}',
            style: pw.TextStyle(fontSize: 10, font: font),
            textDirection: pw.TextDirection.rtl,
          ),
        ],
      ),
    );
  }

  pw.Widget _buildPdfSummaryCards(
    pw.Font? font, pw.Font? boldFont,
    double opening, double debit, double credit, double closing,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Table(
        columnWidths: {
          0: const pw.FlexColumnWidth(1),
          1: const pw.FlexColumnWidth(1),
        },
        border: pw.TableBorder.all(color: PdfColors.grey300),
        children: [
          pw.TableRow(children: [
            _buildPdfCell('الرصيد الافتتاحي', boldFont, isHeader: true),
            _buildPdfCell(_formatCurrency(opening), font, isHeader: true),
          ]),
          pw.TableRow(children: [
            _buildPdfCell('إجمالي المدين', boldFont, isHeader: true),
            _buildPdfCell(_formatCurrency(debit), font, isHeader: true),
          ]),
          pw.TableRow(children: [
            _buildPdfCell('إجمالي الدائن', boldFont, isHeader: true),
            _buildPdfCell(_formatCurrency(credit), font, isHeader: true),
          ]),
          pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColors.grey200), children: [
            _buildPdfCell('الرصيد النهائي', boldFont, isHeader: true),
            _buildPdfCell(_formatCurrency(closing), boldFont, isHeader: true,
              color: closing > 0 ? PdfColors.red : PdfColors.green),
          ]),
        ],
      ),
    );
  }

  pw.Widget _buildPdfTransactionTable(
    List transactions, pw.Font? font, pw.Font? boldFont, double opening,
  ) {
    if (transactions.isEmpty) {
      return pw.Container(
        padding: const pw.EdgeInsets.all(12),
        child: pw.Text(
          'لا توجد حركات في هذه الفترة',
          style: pw.TextStyle(fontSize: 12, color: PdfColors.grey600, font: font),
          textDirection: pw.TextDirection.rtl,
        ),
      );
    }

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
      columnWidths: {
        0: const pw.FlexColumnWidth(0.6),
        1: const pw.FlexColumnWidth(1.2),
        2: const pw.FlexColumnWidth(2.5),
        3: const pw.FlexColumnWidth(1.2),
        4: const pw.FlexColumnWidth(1.2),
        5: const pw.FlexColumnWidth(1.2),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey300),
          children: [
            _buildPdfHeaderCell('م', boldFont),
            _buildPdfHeaderCell('التاريخ', boldFont),
            _buildPdfHeaderCell('البيان', boldFont),
            _buildPdfHeaderCell('مدين', boldFont),
            _buildPdfHeaderCell('دائن', boldFont),
            _buildPdfHeaderCell('الرصيد', boldFont),
          ],
        ),
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.blue50),
          children: [
            _buildPdfCell('', font),
            _buildPdfCell('رصيد سابق', boldFont, isBold: true),
            _buildPdfCell('الرصيد الافتتاحي', boldFont, isBold: true),
            _buildPdfCell(opening > 0 ? _formatCurrency(opening) : '', boldFont, isCurrency: true, isBold: true),
            _buildPdfCell(opening < 0 ? _formatCurrency(opening.abs()) : '', boldFont, isCurrency: true, isBold: true),
            _buildPdfCell(_formatCurrency(opening.abs()), boldFont, isCurrency: true, isBold: true),
          ],
        ),
        ...transactions.asMap().entries.map((entry) {
          final i = entry.key;
          final tx = entry.value.transaction;
          final desc = (tx.credit ?? 0) > 0
              ? 'سداد: ${tx.description ?? ''}'
              : (tx.description ?? 'عملية نقدية');
          return pw.TableRow(children: [
            _buildPdfCell('${i + 1}', font, isCentered: true),
            _buildPdfCell(DateFormat('dd/MM/yyyy').format(tx.date), font, isCentered: true),
            _buildPdfCell(desc, font),
            _buildPdfCell((tx.debit ?? 0) > 0 ? _formatCurrency(tx.debit) : '', font, isCurrency: true),
            _buildPdfCell((tx.credit ?? 0) > 0 ? _formatCurrency(tx.credit) : '', font, isCurrency: true),
            _buildPdfCell(_formatCurrency(entry.value.runningBalance.abs()), boldFont, isCurrency: true, isBold: true),
          ]);
        }),
      ],
    );
  }

  pw.Widget _buildPdfHeaderCell(String text, pw.Font? font) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      alignment: pw.Alignment.center,
      child: pw.Text(text,
        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, font: font),
        textDirection: pw.TextDirection.rtl,
      ),
    );
  }

  pw.Widget _buildPdfCell(
    String text, pw.Font? font, {
    bool isHeader = false, bool isBold = false,
    bool isCurrency = false, bool isCentered = false, PdfColor? color,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      alignment: isCentered
          ? pw.Alignment.center
          : (isCurrency ? pw.Alignment.centerRight : pw.Alignment.centerRight),
      child: pw.Text(text,
        style: pw.TextStyle(
          fontSize: 9,
          fontWeight: (isHeader || isBold) ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: color ?? PdfColors.black,
          font: font,
        ),
        textDirection: isCurrency ? pw.TextDirection.ltr : pw.TextDirection.rtl,
      ),
    );
  }

  String _formatCurrency(double amount) {
    return '${amount.toStringAsFixed(2)} ج.م';
  }

  Future<void> _exportExcel() async {
    try {
      final customersToExport = _showOnlyDues
          ? _filteredCustomers.where((c) => c.balance > 0).toList()
          : _filteredCustomers;

      final data = customersToExport.map((c) {
        return {
          context.l10n.customer: c.customer.name,
          context.l10n.phone: c.customer.phone ?? '',
          context.l10n.receivable_balance: c.balance,
        };
      }).toList();

      await _exportService.exportToExcel(
        title: context.l10n.customer_balances_tab,
        data: data,
        headers: [
          context.l10n.customer,
          context.l10n.phone,
          context.l10n.receivable_balance,
        ],
        columns: [
          context.l10n.customer,
          context.l10n.phone,
          context.l10n.receivable_balance,
        ],
        fileName:
            'customers_report_${DateTime.now().millisecondsSinceEpoch}.xlsx',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.error_exporting_with_error(e))),
        );
      }
    }
  }

  Future<void> _showStatementDialog(Customer customer) async {
    DateTime start = DateTime.now().subtract(const Duration(days: 30));
    DateTime end = DateTime.now();

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('كشف حساب: ${customer.name}'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    title: const Text('الفترة'),
                    subtitle: Text(
                      '${DateFormat('yyyy/MM/dd').format(start)} - ${DateFormat('yyyy/MM/dd').format(end)}',
                    ),
                    trailing: const Icon(Icons.calendar_month),
                    onTap: () async {
                      final picked = await showDateRangePicker(
                        context: context,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                        initialDateRange: DateTimeRange(start: start, end: end),
                      );
                      if (picked != null) {
                        setDialogState(() {
                          start = picked.start;
                          end = picked.end;
                        });
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('إلغاء'),
                ),
                ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.pop(context);
                    await _exportStatement(customer, start, end);
                  },
                  icon: const Icon(Icons.print),
                  label: const Text('طباعة الكشف'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _exportStatement(
    Customer customer,
    DateTime start,
    DateTime end,
  ) async {
    setState(() => _isLoading = true);
    try {
      // 1. Fetch transactions with running balance
      final transactions = await widget.db.ledgerDao
          .getTransactionsWithRunningBalance(
            'Customer',
            customer.id,
            start,
            end,
          );

      // 2. Map to format expected by ExportService
      final mappedTransactions = transactions.map((tb) {
        final t = tb.transaction;
        return {
          'date': t.date,
          'receiptNumber': t.id.substring(0, 8), // Short ID
          'description': t.description,
          'debit': t.debit,
          'credit': t.credit,
          'balance': tb.runningBalance,
        };
      }).toList();

      // 3. Get opening balance (balance before start date)
      // The first running balance includes the transaction effect.
      // So opening balance = first running balance - (firstDebit - firstCredit) ?
      // actually getTransactionsWithRunningBalance handles internal logic.
      // But we need to pass strict opening/current balance to export function if it asks for it.
      // ExportService asks for 'openingBalance' and 'currentBalance'.
      // We can calculate them from the fetched data or re-query.
      final openingBalance = await widget.db.ledgerDao.getRunningBalance(
        'Customer',
        customer.id,
        upToDate: start.subtract(const Duration(days: 1)),
      );

      final currentBalance = await widget.db.ledgerDao.getCustomerBalance(
        customer.id,
      ); // Total current balance (debt)

      // 4. Export
      await _exportService.exportCustomerStatement(
        db: widget.db,
        customerName: customer.name,
        transactions: mappedTransactions,
        openingBalance: openingBalance,
        currentBalance: -currentBalance, // Flip sign effectively?
        // Note: getCustomerBalance returns (Debit - Credit) usually, i.e. Debt is positive.
        // If Debt is positive, customer expects to see positive "Due".
        // The export service highlights positive balance as Red (Owed).
        // So passing positive is correct.
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.error_exporting_with_error(e))),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Calculate totals from filtered customers
    final totalDue = _filteredCustomers.fold(
      0.0,
      (sum, item) => sum + (item.balance > 0 ? item.balance : 0),
    );
    final totalCredited = _filteredCustomers.fold(
      0.0,
      (sum, item) => sum + (item.balance < 0 ? -item.balance : 0),
    );

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('تقرير العملاء'),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        elevation: Theme.of(context).appBarTheme.elevation,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Search Bar
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'البحث عن عميل...',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        suffixIcon: _showOnlyDues
                            ? Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.orange,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'فقط المدينين',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              )
                            : null,
                      ),
                      onChanged: (value) => _filterCustomers(),
                    ),
                    if (_showOnlyDues)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          children: [
                            Icon(
                              Icons.filter_list,
                              color: Colors.orange,
                              size: 16,
                            ),
                            const Gap(4),
                            Text(
                              'يتم عرض العملاء المدينين فقط',
                              style: TextStyle(
                                color: Colors.orange,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const Gap(16),

            // Controls
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _exportFullReport,
                      icon: const Icon(Icons.picture_as_pdf),
                      label: const Text('تقرير كامل مع الحركات'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFC9A84C),
                        foregroundColor: Colors.black87,
                      ),
                    ),
                    const Gap(8),
                    ElevatedButton.icon(
                      onPressed: _exportPDF,
                      icon: const Icon(Icons.picture_as_pdf),
                      label: Text(context.l10n.pdf_label),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                    ),
                    const Gap(8),
                    ElevatedButton.icon(
                      onPressed: _exportExcel,
                      icon: const Icon(Icons.table_chart),
                      label: Text(context.l10n.excel_label),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Gap(16),

            // Date Range Selector
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.date_range, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'الفترة: ${DateFormat('yyyy/MM/dd').format(_reportStart)} - ${DateFormat('yyyy/MM/dd').format(_reportEnd)}',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () async {
                        final picked = await showDateRangePicker(
                          context: context,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                          initialDateRange: DateTimeRange(
                            start: _reportStart, end: _reportEnd),
                        );
                        if (picked != null) {
                          setState(() {
                            _reportStart = picked.start;
                            _reportEnd = picked.end;
                          });
                        }
                      },
                      icon: const Icon(Icons.edit_calendar, size: 18),
                      label: const Text('تغيير الفترة'),
                    ),
                  ],
                ),
              ),
            ),
            const Gap(16),

            // Summary Cards
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _showOnlyDues = !_showOnlyDues;
                        _filterCustomers();
                      });
                    },
                    child: _SummaryCard(
                      title: context.l10n.total_receivables_us,
                      value: totalDue,
                      color: _showOnlyDues ? Colors.orange : Colors.red,
                      icon: Icons.trending_up,
                    ),
                  ),
                ),
                const Gap(16),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _showOnlyDues = false;
                        _filterCustomers();
                      });
                    },
                    child: _SummaryCard(
                      title: context.l10n.total_payables_us,
                      value: totalCredited,
                      color: Colors.green,
                      icon: Icons.trending_down,
                    ),
                  ),
                ),
                const Gap(16),
                Expanded(child: Container()), // Spacer
              ],
            ),
            const Gap(16),

            // Data Table
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : List.from(_filteredCustomers).isEmpty
                  ? Center(child: Text(context.l10n.no_customers))
                  : SingleChildScrollView(
                      child: SizedBox(
                        width: double.infinity,
                        child: Card(
                          child: DataTable(
                            showCheckboxColumn: false, // Make rows clickable
                            headingRowColor: WidgetStateProperty.all(
                              Colors.purple.withValues(alpha: 0.05),
                            ),
                            columns: [
                              DataColumn(label: Text(context.l10n.customer)),
                              DataColumn(label: Text(context.l10n.phone)),
                              DataColumn(
                                label: Text(
                                  context.l10n.receivable_balance,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                            rows: _filteredCustomers.map((c) {
                              return DataRow(
                                onSelectChanged: (selected) {
                                  if (selected == true) {
                                    _showStatementDialog(c.customer);
                                  }
                                },
                                cells: [
                                  DataCell(Text(c.customer.name)),
                                  DataCell(Text(c.customer.phone ?? '')),
                                  DataCell(
                                    Text(
                                      '${c.balance.toStringAsFixed(2)} ${context.l10n.currency_symbol}',
                                      style: TextStyle(
                                        color: c.balance > 0
                                            ? Colors.red
                                            : Colors.green,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class CustomerWithBalance {
  final Customer customer;
  final double balance;

  CustomerWithBalance({required this.customer, required this.balance});
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final double value;
  final Color color;
  final IconData icon;

  const _SummaryCard({
    required this.title,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const Gap(16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
                ),
                Text(
                  '${value.toStringAsFixed(2)} ${context.l10n.currency_symbol}',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
