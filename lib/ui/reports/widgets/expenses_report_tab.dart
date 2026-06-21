import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/services/export_service.dart';
import 'package:pos_offline_desktop/core/services/printer_service.dart';
import 'package:pos_offline_desktop/l10n/l10n.dart';

class ExpensesReportTab extends StatefulWidget {
  final AppDatabase db;

  const ExpensesReportTab({super.key, required this.db});

  @override
  State<ExpensesReportTab> createState() => _ExpensesReportTabState();
}

class _ExpensesReportTabState extends State<ExpensesReportTab> {
  DateTime _startDate = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  DateTime _endDate = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day, 23, 59, 59);
  List<Expense> _expenses = []; // Changed from LedgerTransaction to Expense
  bool _isLoading = false;
  final ExportService _exportService = ExportService();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final expenses = await widget.db.expenseDao.getExpensesByDateRange(
        _startDate,
        _endDate,
      );

      setState(() {
        _expenses = expenses;
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

  Future<void> _selectDateRange(BuildContext context) async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      builder: (context, child) {
        return Theme(
          data: Theme.of(
            context,
          ).copyWith(colorScheme: ColorScheme.light(primary: Colors.purple)),
          child: child ?? const SizedBox(),
        );
      },
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59);
      });
      _loadData();
    }
  }

  Future<void> _exportPDF() async {
    try {
      final data = _expenses.map((e) {
        return {
          'id': e.id,
          'description': e.description,
          'date': DateFormat('yyyy/MM/dd HH:mm').format(e.date),
          'amount': e.amount.toStringAsFixed(2),
          'paymentMethod': 'Cash',
        };
      }).toList();

      await _exportService.exportToPDF(
        title: context.l10n.expenses_report,
        data: data,
        headers: [
          context.l10n.date,
          context.l10n.item_description,
          context.l10n.amount,
          context.l10n.payment_method_short,
        ],
        columns: ['date', 'description', 'amount', 'paymentMethod'],
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.error_exporting_with_error(e))),
        );
      }
    }
  }

  Future<void> _exportExcel() async {
    try {
      final data = _expenses.map((e) {
        return {
          context.l10n.date: DateFormat('yyyy/MM/dd').format(e.date),
          context.l10n.description: e.description,
          context.l10n.amount: e.amount,
          context.l10n.payment_method_short: 'Cash',
        };
      }).toList();

      await _exportService.exportToExcel(
        title: context.l10n.expenses_report,
        data: data,
        headers: [
          context.l10n.date,
          context.l10n.description,
          context.l10n.amount,
          context.l10n.payment_method_short,
        ],
        columns: [
          context.l10n.date,
          context.l10n.description,
          context.l10n.amount,
          context.l10n.payment_method_short,
        ],
        fileName:
            'expenses_report_${DateFormat('yyyyMMdd').format(DateTime.now())}.xlsx',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.error_exporting_with_error(e))),
        );
      }
    }
  }

  Future<void> _printExpense(Expense expense) async {
    try {
      await PrinterService.printExpense(expense: expense);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إرسال المصروف إلى الطابعة'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل في الطباعة: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalExpenses = _expenses.fold(0.0, (sum, item) => sum + item.amount);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('تقرير المصروفات'),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        elevation: Theme.of(context).appBarTheme.elevation,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Controls
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => _selectDateRange(context),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.date_range,
                                color: Colors.purple,
                              ),
                              const Gap(8),
                              Text(
                                '${DateFormat('yyyy/MM/dd').format(_startDate)} - ${DateFormat('yyyy/MM/dd').format(_endDate)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const Gap(16),
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

            // Summary Cards
            Row(
              children: [
                Expanded(
                  child: _SummaryCard(
                    title: context.l10n.total_expenses,
                    value: totalExpenses,
                    color: Colors.red,
                    icon: Icons.money_off,
                  ),
                ),
                const Gap(16),
                // Placeholder for charts or category breakdown
                Expanded(flex: 2, child: Container()),
              ],
            ),
            const Gap(16),

            // Data Table
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _expenses.isEmpty
                  ? Center(child: Text(context.l10n.no_expenses_period))
                  : SingleChildScrollView(
                      child: SizedBox(
                        width: double.infinity,
                        child: Card(
                          child: DataTable(
                            headingRowColor: WidgetStateProperty.all(
                              Colors.purple.withValues(alpha: 0.05),
                            ),
                            columns: [
                              DataColumn(label: Text(context.l10n.date)),
                              DataColumn(
                                label: Text(context.l10n.item_description),
                              ),
                              DataColumn(
                                label: Text(
                                  context.l10n.amount,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              DataColumn(
                                label: Text(context.l10n.payment_method_short),
                              ),
                              DataColumn(label: Text('طباعة')),
                            ],
                            rows: _expenses.map((e) {
                              return DataRow(
                                cells: [
                                  DataCell(
                                    Text(
                                      DateFormat(
                                        'yyyy/MM/dd HH:mm',
                                      ).format(e.date),
                                    ),
                                  ),
                                  DataCell(Text(e.description)),
                                  DataCell(
                                    Text(
                                      '${e.amount.toStringAsFixed(2)} ${context.l10n.currency_symbol}',
                                      style: const TextStyle(
                                        color: Colors.red,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  DataCell(Text('Cash')),
                                  DataCell(
                                    IconButton(
                                      icon: const Icon(
                                        Icons.print,
                                        color: Colors.blue,
                                      ),
                                      onPressed: () => _printExpense(e),
                                      tooltip: 'طباعة المصروف',
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
