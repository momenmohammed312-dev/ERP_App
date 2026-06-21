import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/services/export_service.dart';

class CustomerMonthlyReportPage extends StatefulWidget {
  final AppDatabase db;
  final DateTime start;
  final DateTime end;

  const CustomerMonthlyReportPage({
    super.key,
    required this.db,
    required this.start,
    required this.end,
  });

  @override
  State<CustomerMonthlyReportPage> createState() =>
      _CustomerMonthlyReportPageState();
}

class MonthSummary {
  final int year;
  final int month;
  final double debit;
  final double credit;

  const MonthSummary({
    required this.year,
    required this.month,
    required this.debit,
    required this.credit,
  });

  double get net => debit - credit;
}

class CustomerMonthlyReport {
  final Customer customer;
  final List<MonthSummary> months;
  final double currentBalance;
  final double periodStartBalance;

  const CustomerMonthlyReport({
    required this.customer,
    required this.months,
    required this.currentBalance,
    required this.periodStartBalance,
  });

  double get totalDebit => months.fold<double>(0, (s, m) => s + m.debit);
  double get totalCredit => months.fold<double>(0, (s, m) => s + m.credit);
  double get totalNet => totalDebit - totalCredit;
}

class _CustomerMonthlyReportPageState
    extends State<CustomerMonthlyReportPage> {
  List<CustomerMonthlyReport> _reports = [];
  bool _isLoading = true;
  final Set<String> _expandedIds = {};

  static const _months = [
    '', 'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
    'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final customers = await widget.db.customerDao.getAllCustomers();
      final reports = <CustomerMonthlyReport>[];

      for (final customer in customers) {
        final transactions = await widget.db.ledgerDao
            .getTransactionsByDateRange(
              'Customer',
              customer.id,
              widget.start,
              widget.end,
            );

        final Map<String, List<LedgerTransaction>> grouped = {};
        for (final t in transactions) {
          final key = '${t.date.year}-${t.date.month}';
          grouped.putIfAbsent(key, () => []).add(t);
        }

        final months = grouped.entries.map((e) {
          final parts = e.key.split('-');
          final year = int.parse(parts[0]);
          final month = int.parse(parts[1]);
          final debit = e.value.fold<double>(0, (s, t) => s + t.debit);
          final credit = e.value.fold<double>(0, (s, t) => s + t.credit);
          return MonthSummary(
              year: year, month: month, debit: debit, credit: credit);
        }).toList();

        months.sort((a, b) => a.year == b.year
            ? a.month.compareTo(b.month)
            : a.year.compareTo(b.year));

        final periodStartBalance = await widget.db.ledgerDao.getRunningBalance(
          'Customer',
          customer.id,
          upToDate: widget.start.subtract(const Duration(days: 1)),
        );
        final currentBalance = await widget.db.ledgerDao.getCustomerBalance(
          customer.id,
        );

        reports.add(CustomerMonthlyReport(
          customer: customer,
          months: months,
          currentBalance: currentBalance,
          periodStartBalance: periodStartBalance,
        ));
      }

      setState(() {
        _reports = reports;
        _isLoading = false;
      });
      _expandedIds.addAll(
        reports.where((r) => r.months.isNotEmpty).map((r) => r.customer.id),
      );
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في تحميل البيانات: $e')),
        );
      }
    }
  }

  double get _grandDebit =>
      _reports.fold<double>(0, (s, r) => s + r.totalDebit);
  double get _grandCredit =>
      _reports.fold<double>(0, (s, r) => s + r.totalCredit);
  double get _grandNet => _grandDebit - _grandCredit;
  int get _activeCount =>
      _reports.where((r) => r.months.isNotEmpty).length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text('تقرير العملاء الكامل'),
        backgroundColor: const Color(0xFF1E1E2C),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (!_isLoading && _reports.isNotEmpty) ...[
            IconButton(
              icon: const Icon(Icons.picture_as_pdf, color: Colors.redAccent),
              tooltip: 'تصدير PDF',
              onPressed: _exportPdf,
            ),
            IconButton(
              icon: const Icon(Icons.table_chart, color: Colors.green),
              tooltip: 'تصدير Excel',
              onPressed: _exportExcel,
            ),
          ],
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.purple))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(),
                  const Gap(16),
                  ..._reports.map(_buildCustomerCard),
                  const Gap(16),
                  _buildGrandTotal(),
                ],
              ),
            ),
    );
  }

  Widget _buildHeader() {
    return Card(
      color: const Color(0xFF1E1E2C),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.assessment, color: Colors.purple.shade300),
                const Gap(8),
                const Text(
                  'تقرير العملاء الكامل',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'من ${DateFormat('yyyy/MM/dd').format(widget.start)} إلى ${DateFormat('yyyy/MM/dd').format(widget.end)}',
              style: const TextStyle(color: Colors.white54, fontSize: 14),
            ),
            if (_activeCount > 0) ...[
              const SizedBox(height: 16),
              const Divider(color: Colors.white12),
              const SizedBox(height: 12),
              Row(
                children: [
                  _StatBox(
                    label: 'العملاء',
                    value: '$_activeCount',
                    color: Colors.cyan,
                  ),
                  const Gap(8),
                  _StatBox(
                    label: 'إجمالي المشتريات',
                    value: _fmt(_grandDebit),
                    color: Colors.orange,
                  ),
                  const Gap(8),
                  _StatBox(
                    label: 'إجمالي المدفوعات',
                    value: _fmt(_grandCredit),
                    color: Colors.green,
                  ),
                  const Gap(8),
                  _StatBox(
                    label: 'صافي الرصيد',
                    value: _fmt(_grandNet),
                    color: _grandNet > 0 ? Colors.red : Colors.greenAccent,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerCard(CustomerMonthlyReport r) {
    final expanded = _expandedIds.contains(r.customer.id);
    final hasData = r.months.isNotEmpty;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: const Color(0xFF1E1E2C),
      child: Column(
        children: [
          InkWell(
            onTap: hasData
                ? () => setState(() {
                      if (expanded) {
                        _expandedIds.remove(r.customer.id);
                      } else {
                        _expandedIds.add(r.customer.id);
                      }
                    })
                : null,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: r.currentBalance > 0
                        ? Colors.red.withValues(alpha: 0.15)
                        : Colors.green.withValues(alpha: 0.15),
                    child: Text(
                      r.customer.name.isNotEmpty
                          ? r.customer.name[0]
                          : '#',
                      style: TextStyle(
                        color: r.currentBalance > 0
                            ? Colors.red
                            : Colors.green,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Gap(12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.customer.name,
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white)),
                        if (r.customer.phone?.isNotEmpty == true)
                          Text(r.customer.phone!,
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 12)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(_fmt(r.currentBalance),
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: r.currentBalance > 0
                                  ? Colors.redAccent
                                  : Colors.greenAccent)),
                      Text('${r.months.length} شهر',
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 11)),
                    ],
                  ),
                  if (hasData) ...[
                    const Gap(8),
                    Icon(
                        expanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        color: Colors.white54),
                  ],
                ],
              ),
            ),
          ),
          if (expanded && hasData) _buildMonthTable(r),
        ],
      ),
    );
  }

  Widget _buildMonthTable(CustomerMonthlyReport r) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      decoration: const BoxDecoration(
        color: Color(0xFF252535),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(8),
          bottomRight: Radius.circular(8),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(color: Colors.white12),
          const SizedBox(height: 4),
          DataTable(
            headingRowColor: WidgetStateProperty.all(
                Colors.purple.withValues(alpha: 0.15)),
            dataRowColor: WidgetStateProperty.all(Colors.transparent),
            columnSpacing: 8,
            columns: const [
              DataColumn(
                  label: Text('الشهر',
                      style:
                          TextStyle(color: Colors.white70, fontSize: 11))),
              DataColumn(
                  label: Text('مشتريات',
                      style:
                          TextStyle(color: Colors.white70, fontSize: 11))),
              DataColumn(
                  label: Text('مدفوعات',
                      style:
                          TextStyle(color: Colors.white70, fontSize: 11))),
              DataColumn(
                  label: Text('صافي',
                      style:
                          TextStyle(color: Colors.white70, fontSize: 11))),
              DataColumn(
                  label: Text('الرصيد',
                      style:
                          TextStyle(color: Colors.white70, fontSize: 11))),
            ],
            rows: _buildMonthRows(r),
          ),
        ],
      ),
    );
  }

  List<DataRow> _buildMonthRows(CustomerMonthlyReport r) {
    final rows = <DataRow>[];
    double running = r.periodStartBalance;
    for (final m in r.months) {
      running += m.net;
      rows.add(DataRow(cells: [
        DataCell(Text('${_months[m.month]} ${m.year}',
            style: const TextStyle(color: Colors.white, fontSize: 11))),
        DataCell(Text(_fmt(m.debit),
            style:
                const TextStyle(color: Colors.orange, fontSize: 11))),
        DataCell(Text(_fmt(m.credit),
            style:
                const TextStyle(color: Colors.green, fontSize: 11))),
        DataCell(Text(_fmt(m.net),
            style: TextStyle(
                color: m.net > 0 ? Colors.red : Colors.greenAccent,
                fontSize: 11))),
        DataCell(Text(_fmt(running),
            style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.bold))),
      ]));
    }
    rows.add(DataRow(
      color: WidgetStateProperty.all(Colors.amber.withValues(alpha: 0.08)),
      cells: [
        const DataCell(Text('المجموع',
            style: TextStyle(
                color: Colors.amber,
                fontSize: 12,
                fontWeight: FontWeight.bold))),
        DataCell(Text(_fmt(r.totalDebit),
            style: const TextStyle(
                color: Colors.amber,
                fontSize: 12,
                fontWeight: FontWeight.bold))),
        DataCell(Text(_fmt(r.totalCredit),
            style: const TextStyle(
                color: Colors.amber,
                fontSize: 12,
                fontWeight: FontWeight.bold))),
        DataCell(Text(_fmt(r.totalNet),
            style: TextStyle(
                color: r.totalNet > 0
                    ? Colors.redAccent
                    : Colors.greenAccent,
                fontSize: 12,
                fontWeight: FontWeight.bold))),
        DataCell(Text(_fmt(r.currentBalance),
            style: const TextStyle(
                color: Colors.amber,
                fontSize: 12,
                fontWeight: FontWeight.bold))),
      ],
    ));
    return rows;
  }

  Widget _buildGrandTotal() {
    return Card(
      color: const Color(0xFF1E1E2C),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.summarize, color: Colors.amber.shade300),
                const Gap(8),
                const Text('الإجمالي النهائي',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
              ],
            ),
            const Divider(color: Colors.white24, height: 24),
            Row(
              children: [
                _TotalBox(
                    label: 'إجمالي المشتريات',
                    value: _fmt(_grandDebit),
                    color: Colors.orange),
                const Gap(8),
                _TotalBox(
                    label: 'إجمالي المدفوعات',
                    value: _fmt(_grandCredit),
                    color: Colors.green),
                const Gap(8),
                _TotalBox(
                    label: 'صافي الرصيد',
                    value: _fmt(_grandNet),
                    color:
                        _grandNet > 0 ? Colors.red : Colors.greenAccent),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportPdf() async {
    final reports = _reports.where((r) => r.months.isNotEmpty).toList();
    if (reports.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      pw.Font? arabicFont;
      try {
        final fontData = await rootBundle.load(
            'assets/fonts/NotoNaskhArabic-Regular.ttf');
        arabicFont = pw.Font.ttf(fontData);
      } catch (_) {
        arabicFont = pw.Font.helvetica();
      }

      final pdf = pw.Document();

      for (final report in reports) {
        double running = report.periodStartBalance;

        pdf.addPage(pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(20),
          build: (ctx) => [
            pw.Directionality(
              textDirection: pw.TextDirection.rtl,
              child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    _buildPdfCustomerHeader(report, arabicFont),
                    pw.SizedBox(height: 8),
                    pw.Table(
                      border: pw.TableBorder.all(
                          color: PdfColors.grey400, width: 0.5),
                      columnWidths: {
                        0: const pw.FlexColumnWidth(2),
                        1: const pw.FlexColumnWidth(1.5),
                        2: const pw.FlexColumnWidth(1.5),
                        3: const pw.FlexColumnWidth(1.5),
                        4: const pw.FlexColumnWidth(1.5),
                      },
                      children: [
                        pw.TableRow(
                          decoration: const pw.BoxDecoration(
                              color: PdfColors.grey300),
                          children: ['الشهر', 'مشتريات', 'مدفوعات', 'صافي',
                                  'الرصيد']
                              .map((h) => _pdfCell(h,
                                  isHeader: true, font: arabicFont))
                              .toList(),
                        ),
                        ...report.months.map((m) {
                          running += m.net;
                          return pw.TableRow(children: [
                            _pdfCell('${_months[m.month]} ${m.year}',
                                font: arabicFont),
                            _pdfCell(_fmt(m.debit), font: arabicFont),
                            _pdfCell(_fmt(m.credit), font: arabicFont),
                            _pdfCell(_fmt(m.net), font: arabicFont,
                                color: m.net > 0
                                    ? PdfColors.red
                                    : PdfColors.green),
                            _pdfCell(_fmt(running),
                                isBold: true, font: arabicFont),
                          ]);
                        }),
                        pw.TableRow(
                          decoration: const pw.BoxDecoration(
                              color: PdfColors.grey100),
                          children: [
                            _pdfCell('المجموع',
                                isBold: true, font: arabicFont),
                            _pdfCell(_fmt(report.totalDebit),
                                isBold: true, font: arabicFont),
                            _pdfCell(_fmt(report.totalCredit),
                                isBold: true, font: arabicFont),
                            _pdfCell(_fmt(report.totalNet),
                                isBold: true, font: arabicFont,
                                color: report.totalNet > 0
                                    ? PdfColors.red
                                    : PdfColors.green),
                            _pdfCell(_fmt(report.currentBalance),
                                isBold: true, font: arabicFont),
                          ],
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 16),
                    pw.Divider(color: PdfColors.grey300),
                  ]),
            ),
          ],
        ));
      }

      // Grand total page
      pdf.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        build: (ctx) => pw.Directionality(
          textDirection: pw.TextDirection.rtl,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.SizedBox(height: 40),
              pw.Center(
                child: pw.Text('الإجمالي النهائي',
                    style: pw.TextStyle(
                        fontSize: 22,
                        fontWeight: pw.FontWeight.bold,
                        font: arabicFont)),
              ),
              pw.SizedBox(height: 20),
              pw.Container(
                padding: const pw.EdgeInsets.all(20),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey400),
                  borderRadius:
                      const pw.BorderRadius.all(pw.Radius.circular(8)),
                ),
                child: pw.Column(children: [
                  _pdfSummaryRow('عدد العملاء', '$_activeCount', arabicFont),
                  pw.SizedBox(height: 12),
                  _pdfSummaryRow(
                      'إجمالي المشتريات', _fmt(_grandDebit), arabicFont),
                  pw.SizedBox(height: 12),
                  _pdfSummaryRow(
                      'إجمالي المدفوعات', _fmt(_grandCredit), arabicFont),
                  pw.SizedBox(height: 12),
                  _pdfSummaryRow('صافي الرصيد', _fmt(_grandNet), arabicFont,
                      color: _grandNet > 0 ? PdfColors.red : PdfColors.green),
                ]),
              ),
              pw.SizedBox(height: 20),
              pw.Text(
                'تم التوليد في: ${DateFormat('yyyy/MM/dd HH:mm').format(DateTime.now())}',
                style: pw.TextStyle(
                    fontSize: 10, color: PdfColors.grey600, font: arabicFont),
                textDirection: pw.TextDirection.rtl,
              ),
            ],
          ),
        ),
      ));

      await Printing.layoutPdf(
        onLayout: (format) => pdf.save(),
        name:
            'تقرير_العملاء_الكامل_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تصدير PDF بنجاح'),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في تصدير PDF: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  pw.Widget _buildPdfCustomerHeader(
      CustomerMonthlyReport r, pw.Font? font) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Column(children: [
        pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(r.customer.name,
                  style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                      font: font)),
              pw.Text('الرصيد: ${_fmt(r.currentBalance)}',
                  style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                      color: r.currentBalance > 0
                          ? PdfColors.red
                          : PdfColors.green,
                      font: font)),
            ]),
        if (r.customer.phone?.isNotEmpty == true)
          pw.Text(r.customer.phone!,
              style: pw.TextStyle(
                  fontSize: 10, color: PdfColors.grey700, font: font)),
      ]),
    );
  }

  pw.Widget _pdfCell(String text,
      {bool isHeader = false,
      bool isBold = false,
      pw.Font? font,
      PdfColor? color}) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(text,
          style: pw.TextStyle(
            fontSize: 9,
            fontWeight:
                (isHeader || isBold) ? pw.FontWeight.bold : pw.FontWeight.normal,
            font: font,
            color: color ?? PdfColors.black,
          ),
          textDirection: pw.TextDirection.rtl),
    );
  }

  pw.Widget _pdfSummaryRow(
      String label, String value, pw.Font? font,
      {PdfColor? color}) {
    return pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label,
              style: pw.TextStyle(
                  fontSize: 14, fontWeight: pw.FontWeight.bold, font: font)),
          pw.Text(value,
              style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                  color: color ?? PdfColors.black,
                  font: font)),
        ]);
  }

  Future<void> _exportExcel() async {
    final reports = _reports.where((r) => r.months.isNotEmpty).toList();
    if (reports.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      final flatData = <Map<String, dynamic>>[];
      for (final r in reports) {
        double running = r.periodStartBalance;
        for (final m in r.months) {
          running += m.net;
          flatData.add({
            'العميل': r.customer.name,
            'الهاتف': r.customer.phone ?? '',
            'الشهر': '${_months[m.month]} ${m.year}',
            'مشتريات': m.debit,
            'مدفوعات': m.credit,
            'صافي': m.net,
            'الرصيد': running,
          });
        }
        flatData.add({
          'العميل': r.customer.name,
          'الهاتف': '',
          'الشهر': 'المجموع',
          'مشتريات': r.totalDebit,
          'مدفوعات': r.totalCredit,
          'صافي': r.totalNet,
          'الرصيد': r.currentBalance,
        });
      }
      flatData.add({
        'العميل': 'الإجمالي النهائي',
        'الهاتف': '',
        'الشهر': '$_activeCount عميل',
        'مشتريات': _grandDebit,
        'مدفوعات': _grandCredit,
        'صافي': _grandNet,
        'الرصيد': _grandNet,
      });

      final exportService = ExportService();
      await exportService.exportToExcel(
        title: 'تقرير العملاء الكامل',
        data: flatData,
        headers: [
          'العميل',
          'الهاتف',
          'الشهر',
          'مشتريات',
          'مدفوعات',
          'صافي',
          'الرصيد',
        ],
        columns: [
          'العميل',
          'الهاتف',
          'الشهر',
          'مشتريات',
          'مدفوعات',
          'صافي',
          'الرصيد',
        ],
        fileName:
            'تقرير_العملاء_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تصدير Excel بنجاح'),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في تصدير Excel: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  String _fmt(double v) => '${v.toStringAsFixed(2)} ج.م';
}

class _StatBox extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatBox(
      {required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 14),
                textAlign: TextAlign.center),
            const SizedBox(height: 2),
            Text(label,
                style:
                    const TextStyle(color: Colors.white54, fontSize: 10),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _TotalBox extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _TotalBox(
      {required this.label, required this.value, required this.color});
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 18)),
            const SizedBox(height: 4),
            Text(label,
                style:
                    const TextStyle(color: Colors.white54, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
