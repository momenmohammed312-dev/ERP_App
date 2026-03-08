import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pos_offline_desktop/core/provider/app_database_provider.dart';
import 'package:pos_offline_desktop/core/utils/app_utils.dart';

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

      final result = <Map<String, dynamic>>[];

      final allDatesSet = <String>{...invoicesByDate.keys, ...daysByDate.keys};
      final allDates = allDatesSet.toList()..sort((a, b) => b.compareTo(a));

      for (final dateStr in allDates) {
        final dayInvoices = invoicesByDate[dateStr] ?? [];
        final dayData = daysByDate[dateStr];

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
            openTime = DateFormat(
              'HH:mm',
            ).format(parseDate(dayData['created_at']));
          }
          if (dayData['closed_at'] != null) {
            closeTime = DateFormat(
              'HH:mm',
            ).format(parseDate(dayData['closed_at']));
          }
        }

        final surplusDeficit = closingBalance != null
            ? closingBalance - openingBalance - totalSales
            : 0.0;

        result.add({
          'date': dateStr,
          'openTime': openTime,
          'closeTime': closeTime,
          'openingBalance': openingBalance,
          'closingBalance': closingBalance ?? 0.0,
          'totalSales': totalSales,
          'cash': cash,
          'credit': credit,
          'surplusDeficit': surplusDeficit,
          'invoiceCount': dayInvoices.length,
        });
      }

      setState(() {
        _dailyData = result;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في تحميل التقرير: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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
    final subTextColor =isDark ? Colors.white70 : Colors.black54;
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

                  // Table
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Container(
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Theme.of(context).dividerColor,
                        ),
                      ),
                      child: DataTable(
                        columnSpacing: 16,
                        headingRowColor: WidgetStateProperty.all(
                          Theme.of(
                            context,
                          ).colorScheme.primaryContainer.withValues(alpha: 0.5),
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
                          DataColumn(label: Text('عجز/زيادة')),
                          DataColumn(label: Text('عدد الفواتير')),
                        ],
                        rows: _dailyData.map((d) {
                          final sd = (d['surplusDeficit'] as num).toDouble();
                          final credit = (d['credit'] as num).toDouble();
                          return DataRow(
                            cells: [
                              DataCell(Text(d['date'] as String)),
                              DataCell(Text(d['openTime'] as String)),
                              DataCell(Text(d['closeTime'] as String)),
                              DataCell(
                                Text(
                                  (d['openingBalance'] as num).toStringAsFixed(
                                    2,
                                  ),
                                ),
                              ),
                              DataCell(
                                Text(
                                  (d['closingBalance'] as num).toStringAsFixed(
                                    2,
                                  ),
                                ),
                              ),
                              DataCell(
                                Text(
                                  (d['totalSales'] as num).toStringAsFixed(2),
                                ),
                              ),
                              DataCell(
                                Text((d['cash'] as num).toStringAsFixed(2)),
                              ),
                              DataCell(
                                Text(
                                  credit.toStringAsFixed(2),
                                  style: TextStyle(
                                    color: credit > 0
                                        ? textColor
                                        : textColor,
                                    fontWeight: credit > 0
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                              DataCell(
                                Text(
                                  sd.toStringAsFixed(2),
                                  style: TextStyle(
                                    color: sd >= 0 ? Colors.green : Colors.red,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              DataCell(
                                Text((d['invoiceCount'] as int).toString()),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
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
    Color textColor,
  ) {
    return Card(
      color: cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withValues(alpha: 0.3), width: 1),
      ),
      elevation: 2,
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
    );
  }
}
