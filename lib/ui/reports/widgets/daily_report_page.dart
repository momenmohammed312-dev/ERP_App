import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pos_offline_desktop/core/provider/app_database_provider.dart';
import 'package:pos_offline_desktop/core/utils/app_utils.dart';
import 'package:pos_offline_desktop/core/utils/logger.dart';

/// تقرير اليوم — جدول يومي يعرض الأيام المفتوحة والمبيعات
class DailyReportPage extends ConsumerStatefulWidget {
  const DailyReportPage({super.key});

  @override
  ConsumerState<DailyReportPage> createState() => _DailyReportPageState();
}

class _DailyReportPageState extends ConsumerState<DailyReportPage> {
  List<Map<String, dynamic>> _dailyData = [];
  bool _isLoading = true;
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    _startDate = DateTime.now().subtract(const Duration(days: 30));
    _endDate = DateTime.now();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final db = ref.read(appDatabaseProvider);

      // Load invoices by date range
      final allInvoices = await db.invoiceDao.getInvoicesByDateRange(
        DateTime(_startDate!.year, _startDate!.month, _startDate!.day),
        DateTime(_endDate!.year, _endDate!.month, _endDate!.day, 23, 59, 59),
      );

      final Map<String, List<dynamic>> invoicesByDate = {};
      for (final inv in allInvoices) {
        final dateStr = DateFormat('yyyy-MM-dd').format(inv.date);
        invoicesByDate.putIfAbsent(dateStr, () => []).add(inv);
      }

      // Get all days in range
      final daysRows = await db
          .customSelect(
            '''
        SELECT * FROM days 
        WHERE date >= ? AND date <= ?
        ''',
            variables: [
              drift.Variable.withDateTime(
                DateTime(_startDate!.year, _startDate!.month, _startDate!.day),
              ),
              drift.Variable.withDateTime(
                DateTime(
                  _endDate!.year,
                  _endDate!.month,
                  _endDate!.day,
                  23,
                  59,
                  59,
                ),
              ),
            ],
          )
          .get();

      final Map<String, Map<String, dynamic>> daysByDate = {};
      for (final row in daysRows) {
        final data = row.data;
        final dayDate = parseDate(data['date']);
        final dateStr = DateFormat('yyyy-MM-dd').format(dayDate);
        daysByDate[dateStr] = data;
      }

      // Load expenses
      final expensesRows = await db
          .customSelect(
            '''
        SELECT * FROM expenses 
        WHERE date >= ? AND date <= ?
        ''',
            variables: [
              drift.Variable.withDateTime(DateTime(_startDate!.year, _startDate!.month, _startDate!.day)),
              drift.Variable.withDateTime(DateTime(_endDate!.year, _endDate!.month, _endDate!.day, 23, 59, 59)),
            ],
          )
          .get();

      final Map<String, double> expensesByDate = {};
      for (final row in expensesRows) {
        final data = row.data;
        final date = parseDate(data['date']);
        final dateStr = DateFormat('yyyy-MM-dd').format(date);
        final amount = (data['amount'] as num).toDouble();
        expensesByDate[dateStr] = (expensesByDate[dateStr] ?? 0.0) + amount;
      }

      // Load sales returns
      final returnsRows = await db
          .customSelect(
            '''
        SELECT * FROM sales_returns 
        WHERE return_date >= ? AND return_date <= ?
        ''',
            variables: [
              drift.Variable.withDateTime(DateTime(_startDate!.year, _startDate!.month, _startDate!.day)),
              drift.Variable.withDateTime(DateTime(_endDate!.year, _endDate!.month, _endDate!.day, 23, 59, 59)),
            ],
          )
          .get();

      final Map<String, double> returnsByDate = {};
      for (final row in returnsRows) {
        final data = row.data;
        final date = parseDate(data['return_date']);
        final dateStr = DateFormat('yyyy-MM-dd').format(date);
        final amount = (data['total_amount'] as num).toDouble();
        returnsByDate[dateStr] = (returnsByDate[dateStr] ?? 0.0) + amount;
      }

      final result = <Map<String, dynamic>>[];

      final allDatesSet = <String>{
        ...invoicesByDate.keys,
        ...daysByDate.keys,
        ...expensesByDate.keys,
        ...returnsByDate.keys,
      };
      final allDates = allDatesSet.toList()..sort((a, b) => b.compareTo(a));

      for (final dateStr in allDates) {
        final dayInvoices = invoicesByDate[dateStr] ?? [];
        final dayData = daysByDate[dateStr];
        final dailyExpenses = expensesByDate[dateStr] ?? 0.0;
        final dailyReturns = returnsByDate[dateStr] ?? 0.0;

        double totalSales = 0.0;
        double cash = 0.0;
        double credit = 0.0;

        for (final inv in dayInvoices) {
          totalSales += inv.totalAmount;
          final pm = (inv.paymentMethod ?? 'cash').toLowerCase().trim();
          if (pm == 'credit' ||
              pm == 'آجل' ||
              pm == 'اجل' ||
              pm.contains('آجل') ||
              pm.contains('credit')) {
            credit += inv.totalAmount;
          } else if (pm == 'mixed') {
            cash += inv.paidAmount;
            credit += (inv.totalAmount - inv.paidAmount);
          } else {
            cash += inv.paidAmount > 0 ? inv.paidAmount : inv.totalAmount;
          }
        }

        double openingBalance = 0.0;
        double? closingBalance;
        String openTime = '-';
        String closeTime = '-';

        if (dayData != null) {
          openingBalance =
              (dayData['opening_balance'] as num?)?.toDouble() ?? 0.0;
          closingBalance = (dayData['closing_balance'] as num?)?.toDouble();

          if (dayData['created_at'] != null) {
            try {
              openTime = DateFormat(
                'HH:mm',
              ).format(parseDate(dayData['created_at']));
            } catch (_) {}
          }
          if (dayData['closed_at'] != null) {
            try {
              closeTime = DateFormat(
                'HH:mm',
              ).format(parseDate(dayData['closed_at']));
            } catch (_) {}
          }
        }

        // FIX: only calculate surplus/deficit when day is closed
        final surplusDeficit = closingBalance != null
            ? closingBalance -
                  openingBalance -
                  cash + dailyExpenses + dailyReturns // deficit vs cash collected minus expenses and returns
            : null; // null = day still open

        result.add({
          'date': dateStr,
          'openTime': openTime,
          'closeTime': closeTime,
          'openingBalance': openingBalance,
          'closingBalance': closingBalance ?? 0.0,
          'isOpen': closingBalance == null,
          'totalSales': totalSales,
          'cash': cash,
          'credit': credit,
          'expenses': dailyExpenses,
          'returns': dailyReturns,
          'surplusDeficit': surplusDeficit ?? 0.0,
          'surplusKnown': surplusDeficit != null,
          'invoiceCount': dayInvoices.length,
          'rawInvoices': dayInvoices,
        });
      }

      setState(() {
        _dailyData = result;
        _isLoading = false;
      });
    } catch (e, stack) {
      AppLogger.e('Failed to load daily report', e, stack);
      setState(() => _isLoading = false);
    }
  }

  void _showDetailsDialog(Map<String, dynamic> data) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('تفاصيل يوم ${data['date']}'),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDetailRow('المبيعات الكلية', '${data['totalSales']} ج.م', Colors.blue),
                _buildDetailRow('المبيعات النقدية', '${data['cash']} ج.م', Colors.green),
                _buildDetailRow('المبيعات الآجلة', '${data['credit']} ج.م', Colors.purple),
                const Divider(),
                _buildDetailRow('المصروفات', '${data['expenses']} ج.م', Colors.red),
                _buildDetailRow('المرتجعات', '${data['returns']} ج.م', Colors.redAccent),
                const Divider(),
                _buildDetailRow('صافي الكاش المتوقع', '${(data['cash'] - data['expenses'] - data['returns']).toStringAsFixed(2)} ج.م', Colors.teal),
                if (data['surplusKnown'] == true) ...[
                  _buildDetailRow('العجز / الزيادة', '${data['surplusDeficit']} ج.م', 
                    (data['surplusDeficit'] as num) >= 0 ? Colors.green : Colors.red),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق')),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _startDate!, end: _endDate!),
    );
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF121212) : Colors.grey.shade50;
    final cardBg = isDark ? const Color(0xFF1E1E2C) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? Colors.white70 : Colors.black54;
    final totalSales = _dailyData.fold<double>(
      0.0,
      (sum, d) => sum + ((d['totalSales'] as num?)?.toDouble() ?? 0.0),
    );
    final totalCash = _dailyData.fold<double>(
      0.0,
      (sum, d) => sum + ((d['cash'] as num?)?.toDouble() ?? 0.0),
    );
    final totalCredit = _dailyData.fold<double>(
      0.0,
      (sum, d) => sum + ((d['credit'] as num?)?.toDouble() ?? 0.0),
    );
    final totalInvoices = _dailyData.fold<int>(
      0,
      (sum, d) => sum + ((d['invoiceCount'] as int?) ?? 0),
    );
    final totalReturns = _dailyData.fold<double>(
      0.0,
      (sum, d) => sum + ((d['returns'] as num?)?.toDouble() ?? 0.0),
    );
    final totalExpenses = _dailyData.fold<double>(
      0.0,
      (sum, d) => sum + ((d['expenses'] as num?)?.toDouble() ?? 0.0),
    );
    final netSales = totalSales - totalReturns;
    final netProfit = netSales - totalExpenses;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text('تقرير اليوم'),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        backgroundColor: bgColor,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month),
            onPressed: _selectDateRange,
            tooltip: 'تغيير التاريخ',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'تحديث',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Summary cards
                  Row(
                    children: [
                      Expanded(
                        child: _buildSummaryCard(
                          'إجمالي المبيعات',
                          totalSales.toStringAsFixed(2),
                          Colors.blue,
                          cardBg,
                          textColor,
                          onTap: () => _showDrillDown(context, 'sales', totalSales),
                        ),
                      ),
                      const Gap(12),
                      Expanded(
                        child: _buildSummaryCard(
                          'مبيعات كاش',
                          totalCash.toStringAsFixed(2),
                          Colors.green,
                          cardBg,
                          textColor,
                          onTap: () => _showDrillDown(context, 'cash', totalCash),
                        ),
                      ),
                      const Gap(12),
                      Expanded(
                        child: _buildSummaryCard(
                          'مبيعات آجل',
                          totalCredit.toStringAsFixed(2),
                          Colors.purple,
                          cardBg,
                          textColor,
                          onTap: () => _showDrillDown(context, 'credit', totalCredit),
                        ),
                      ),
                      const Gap(12),
                      Expanded(
                        child: _buildSummaryCard(
                          'عدد الفواتير',
                          totalInvoices.toString(),
                          Colors.orange,
                          cardBg,
                          textColor,
                          onTap: () => _showDrillDown(context, 'invoiceCount', totalInvoices.toDouble()),
                        ),
                      ),
                    ],
                  ),
                  const Gap(12),
                  // Second row: Returns, Net Sales, Expenses, Net Profit
                  Row(
                    children: [
                      Expanded(
                        child: _buildSummaryCard(
                          'إجمالي المرتجعات',
                          totalReturns.toStringAsFixed(2),
                          Colors.redAccent,
                          cardBg,
                          textColor,
                          onTap: () => _showDrillDown(context, 'returns', totalReturns),
                        ),
                      ),
                      const Gap(12),
                      Expanded(
                        child: _buildSummaryCard(
                          'صافي المبيعات',
                          netSales.toStringAsFixed(2),
                          Colors.teal,
                          cardBg,
                          textColor,
                          onTap: () => _showDrillDown(context, 'netSales', netSales),
                        ),
                      ),
                      const Gap(12),
                      Expanded(
                        child: _buildSummaryCard(
                          'إجمالي المصروفات',
                          totalExpenses.toStringAsFixed(2),
                          Colors.red,
                          cardBg,
                          textColor,
                          onTap: () => _showDrillDown(context, 'expenses', totalExpenses),
                        ),
                      ),
                      const Gap(12),
                      Expanded(
                        child: _buildSummaryCard(
                          'صافي الربح',
                          netProfit.toStringAsFixed(2),
                          netProfit >= 0 ? Colors.green : Colors.red,
                          cardBg,
                          textColor,
                          onTap: () => _showDrillDown(context, 'netProfit', netProfit),
                        ),
                      ),
                    ],
                  ),
                  const Gap(24),

                  // Date range
                  Text(
                    'الفترة: ${DateFormat('dd/MM/yyyy').format(_startDate!)} - ${DateFormat('dd/MM/yyyy').format(_endDate!)}',
                    style: Theme.of(
                      context,
                    ).textTheme.titleMedium?.copyWith(color: textColor),
                  ),
                  const Gap(16),

                  // Table — FIX: use LayoutBuilder to ensure full width
                  LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: ConstrainedBox(
                          // ensure table fills at least the available width
                          constraints: BoxConstraints(
                            minWidth: constraints.maxWidth,
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              color: cardBg,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Theme.of(context).dividerColor,
                              ),
                            ),
                            child: DataTable(
                              showCheckboxColumn: false,
                              columnSpacing: 20,
                              headingRowColor: WidgetStateProperty.all(
                                Theme.of(context).colorScheme.primaryContainer
                                    .withValues(alpha: 0.5),
                              ),
                              dataTextStyle: TextStyle(color: textColor),
                              columns: const [
                                DataColumn(label: Text('التاريخ')),
                                DataColumn(label: Text('وقت الفتح')),
                                DataColumn(label: Text('وقت الإغلاق')),
                                DataColumn(label: Text('الرصيد الافتتاحي')),
                                DataColumn(label: Text('الرصيد الختامي')),
                                DataColumn(label: Text('إجمالي المبيعات')),
                                DataColumn(label: Text('كاش')),
                                DataColumn(label: Text('آجل')),
                                DataColumn(label: Text('المصروفات')),
                                DataColumn(label: Text('المرتجعات')),
                                DataColumn(label: Text('عجز/زيادة')),
                                DataColumn(label: Text('عدد الفواتير')),
                              ],
                              rows: _dailyData.map((d) {
                                final sd = (d['surplusDeficit'] as num)
                                    .toDouble();
                                final sdKnown =
                                    d['surplusKnown'] as bool? ?? false;
                                final credit = (d['credit'] as num).toDouble();
                                final expenses = (d['expenses'] as num).toDouble();
                                final returns = (d['returns'] as num).toDouble();
                                final isOpen = d['isOpen'] as bool? ?? false;
                                return DataRow(
                                  onSelectChanged: (_) => _showDetailsDialog(d),
                                  cells: [
                                    DataCell(Text(d['date'] as String)),
                                    DataCell(Text(d['openTime'] as String)),
                                    // FIX: show "مفتوح" when day not closed yet
                                    DataCell(
                                      isOpen
                                          ? Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.orange.withValues(
                                                  alpha: 0.15,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: const Text(
                                                'مفتوح',
                                                style: TextStyle(
                                                  color: Colors.orange,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            )
                                          : Text(d['closeTime'] as String),
                                    ),
                                    DataCell(
                                      Text(
                                        (d['openingBalance'] as num)
                                            .toStringAsFixed(2),
                                      ),
                                    ),
                                    DataCell(
                                      isOpen
                                          ? Text(
                                              '-',
                                              style: TextStyle(
                                                color: textColor.withValues(
                                                  alpha: 0.4,
                                                ),
                                              ),
                                            )
                                          : Text(
                                              (d['closingBalance'] as num)
                                                  .toStringAsFixed(2),
                                            ),
                                    ),
                                    DataCell(
                                      Text(
                                        (d['totalSales'] as num)
                                            .toStringAsFixed(2),
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        (d['cash'] as num).toStringAsFixed(2),
                                      ),
                                    ),
                                    // FIX: show credit amount with color
                                    DataCell(
                                      Text(
                                        credit.toStringAsFixed(2),
                                        style: TextStyle(
                                          color: credit > 0
                                              ? Colors.orange.shade700
                                              : textColor.withValues(
                                                  alpha: 0.5,
                                                ),
                                          fontWeight: credit > 0
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                        ),
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        expenses.toStringAsFixed(2),
                                        style: const TextStyle(color: Colors.red),
                                      ),
                                    ),
                                    DataCell(
                                      Text(
                                        returns.toStringAsFixed(2),
                                        style: const TextStyle(color: Colors.redAccent),
                                      ),
                                    ),
                                    // FIX: show surplus/deficit only when day closed
                                    DataCell(
                                      sdKnown
                                          ? Text(
                                              sd.toStringAsFixed(2),
                                              style: TextStyle(
                                                color: sd >= 0
                                                    ? Colors.green
                                                    : Colors.red,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            )
                                          : Text(
                                              '-',
                                              style: TextStyle(
                                                color: textColor.withValues(
                                                  alpha: 0.4,
                                                ),
                                              ),
                                            ),
                                    ),
                                    DataCell(
                                      Text(
                                        (d['invoiceCount'] as int).toString(),
                                      ),
                                    ),
                                  ],
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                      );
                    },
                  ),

                  if (_dailyData.isEmpty) ...[
                    const Gap(32),
                    Center(
                      child: Text(
                        'لا توجد أيام أو فواتير في الفترة المحددة',
                        style: Theme.of(
                          context,
                        ).textTheme.bodyLarge?.copyWith(color: textColor),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildSummaryCard(
    String title,
    String value,
    Color color,
    Color cardBg,
    Color textColor, {
    VoidCallback? onTap,
  }) {
    return Card(
      color: cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withValues(alpha: 0.3), width: 1),
      ),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const Gap(8),
              Text(
                value,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDrillDown(BuildContext context, String metric, double total) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF121212) : Colors.grey.shade50;
    final cardBg = isDark ? const Color(0xFF1E1E2C) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;

    String title;
    IconData icon;
    Color color;
    List<Map<String, dynamic>> items = [];
    String Function(Map<String, dynamic>) itemTitle;
    String? Function(Map<String, dynamic>)? itemSubtitle;
    Widget? Function(Map<String, dynamic>)? itemTrailing;

    switch (metric) {
      case 'sales':
        title = 'إجمالي المبيعات';
        icon = Icons.attach_money;
        color = Colors.blue;
        itemTitle = (d) => 'فاتورة #${d['invoiceId']}';
        itemSubtitle = (d) =>
            '${d['date']}  |  ${d['totalAmount']} ج.م';
        itemTrailing = null;
        for (final d in _dailyData) {
          for (final inv in (d['rawInvoices'] as List)) {
            items.add({
              'invoiceId': inv.id,
              'date': d['date'],
              'totalAmount': inv.totalAmount.toStringAsFixed(2),
              'paymentMethod': inv.paymentMethod,
              'paidAmount': inv.paidAmount,
            });
          }
        }
        break;
      case 'cash':
        title = 'مبيعات كاش';
        icon = Icons.money;
        color = Colors.green;
        itemTitle = (d) => 'فاتورة #${d['invoiceId']}';
        itemSubtitle = (d) =>
            '${d['date']}  |  ${d['totalAmount']} ج.م';
        itemTrailing = null;
        for (final d in _dailyData) {
          for (final inv in (d['rawInvoices'] as List)) {
            final pm = (inv.paymentMethod ?? 'cash').toLowerCase().trim();
            if (pm == 'cash' || pm == 'نقدي' || pm == 'نقداً' || pm == 'نقدا') {
              items.add({
                'invoiceId': inv.id,
                'date': d['date'],
                'totalAmount': inv.paidAmount > 0
                    ? inv.paidAmount.toStringAsFixed(2)
                    : inv.totalAmount.toStringAsFixed(2),
              });
            }
          }
        }
        break;
      case 'credit':
        title = 'مبيعات آجل';
        icon = Icons.credit_card;
        color = Colors.purple;
        itemTitle = (d) => 'فاتورة #${d['invoiceId']}';
        itemSubtitle = (d) =>
            '${d['date']}  |  ${d['totalAmount']} ج.م';
        itemTrailing = null;
        for (final d in _dailyData) {
          for (final inv in (d['rawInvoices'] as List)) {
            final pm = (inv.paymentMethod ?? 'cash').toLowerCase().trim();
            if (pm == 'credit' || pm == 'آجل' || pm == 'اجل') {
              items.add({
                'invoiceId': inv.id,
                'date': d['date'],
                'totalAmount': inv.totalAmount.toStringAsFixed(2),
              });
            } else if (pm == 'mixed') {
              items.add({
                'invoiceId': inv.id,
                'date': d['date'],
                'totalAmount': (inv.totalAmount - inv.paidAmount).toStringAsFixed(2),
              });
            }
          }
        }
        break;
      case 'invoiceCount':
        title = 'عدد الفواتير';
        icon = Icons.receipt_long;
        color = Colors.orange;
        itemTitle = (d) => 'فاتورة #${d['invoiceId']}';
        itemSubtitle = (d) =>
            '${d['date']}  |  ${d['totalAmount']} ج.م';
        itemTrailing = null;
        for (final d in _dailyData) {
          for (final inv in (d['rawInvoices'] as List)) {
            items.add({
              'invoiceId': inv.id,
              'date': d['date'],
              'totalAmount': inv.totalAmount.toStringAsFixed(2),
              'paymentMethod': inv.paymentMethod,
            });
          }
        }
        break;
      case 'returns':
        title = 'إجمالي المرتجعات';
        icon = Icons.undo;
        color = Colors.redAccent;
        itemTitle = (d) => 'مرتجع #${d['returnId']}';
        itemSubtitle = (d) =>
            '${d['date']}  |  ${d['amount']} ج.م';
        itemTrailing = null;
        for (final d in _dailyData) {
          final r = d['returns'] as num?;
          if (r != null && r > 0) {
            items.add({
              'returnId': '-',
              'date': d['date'],
              'amount': r.toStringAsFixed(2),
            });
          }
        }
        break;
      case 'expenses':
        title = 'إجمالي المصروفات';
        icon = Icons.money_off;
        color = Colors.red;
        itemTitle = (d) => d['date'] as String;
        itemSubtitle = (d) =>
            '${d['amount']} ج.م';
        itemTrailing = null;
        for (final d in _dailyData) {
          final e = d['expenses'] as num?;
          if (e != null && e > 0) {
            items.add({
              'date': d['date'],
              'amount': e.toStringAsFixed(2),
            });
          }
        }
        break;
      case 'netSales':
        title = 'صافي المبيعات';
        icon = Icons.trending_up;
        color = Colors.teal;
        itemTitle = (d) => d['date'] as String;
        itemSubtitle = (d) =>
            'مبيعات: ${d['sales']} ج.م  |  مرتجعات: ${d['returns']} ج.م';
        itemTrailing = (d) => Text(
          '${d['net']} ج.م',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: (d['net'] as num) >= 0 ? Colors.teal : Colors.red,
          ),
        );
        for (final d in _dailyData) {
          final sales = (d['totalSales'] as num).toDouble();
          final returns = (d['returns'] as num).toDouble();
          final net = sales - returns;
          items.add({
            'date': d['date'],
            'sales': sales.toStringAsFixed(2),
            'returns': returns.toStringAsFixed(2),
            'net': double.parse(net.toStringAsFixed(2)),
          });
        }
        break;
      case 'netProfit':
        title = 'صافي الربح';
        icon = Icons.account_balance;
        color = total >= 0 ? Colors.green : Colors.red;
        itemTitle = (d) => d['date'] as String;
        itemSubtitle = (d) =>
            'صافي مبيعات: ${d['netSales']} ج.م  |  مصروفات: ${d['expenses']} ج.م';
        itemTrailing = (d) => Text(
          '${d['net']} ج.م',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: (d['net'] as num) >= 0 ? Colors.green : Colors.red,
          ),
        );
        for (final d in _dailyData) {
          final sales = (d['totalSales'] as num).toDouble();
          final returns = (d['returns'] as num).toDouble();
          final expenses = (d['expenses'] as num).toDouble();
          final netProfit = sales - returns - expenses;
          items.add({
            'date': d['date'],
            'netSales': (sales - returns).toStringAsFixed(2),
            'expenses': expenses.toStringAsFixed(2),
            'net': double.parse(netProfit.toStringAsFixed(2)),
          });
        }
        break;
      default:
        return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(icon, color: color),
            const Gap(8),
            Text('$title: ${total.toStringAsFixed(2)} ج.م'),
          ],
        ),
        content: SizedBox(
          width: 600,
          child: items.isEmpty
              ? const Center(child: Text('لا توجد بيانات'))
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: items.length,
                  itemBuilder: (ctx, i) {
                    final item = items[i];
                    return Card(
                      color: cardBg,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        leading: Icon(icon, color: color, size: 20),
                        title: Text(itemTitle(item)),
                        subtitle: itemSubtitle != null
                            ? Text(itemSubtitle(item) ?? '')
                            : null,
                        trailing: itemTrailing != null
                            ? itemTrailing(item)
                            : Text(
                                '${item['totalAmount'] ?? item['amount'] ?? ''}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: textColor,
                                ),
                              ),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }
}
