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

      // Get all days in range
      final daysRows = await db
          .customSelect(
            '''
        SELECT * FROM days 
        WHERE date >= ? AND date <= ?
        ORDER BY date DESC
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

      final result = <Map<String, dynamic>>[];

      for (final row in daysRows) {
        final data = row.data;
        final dayDate = parseDate(data['date']);
        final dateStr = DateFormat('yyyy-MM-dd').format(dayDate);

        // Get invoices for this day
        final invoices = await db.invoiceDao.getInvoicesByDateRange(
          DateTime(dayDate.year, dayDate.month, dayDate.day),
          DateTime(dayDate.year, dayDate.month, dayDate.day, 23, 59, 59),
        );

        double totalSales = 0.0;
        double cash = 0.0;
        double credit = 0.0;

        for (final inv in invoices) {
          totalSales += inv.totalAmount;
          final pm = (inv.paymentMethod ?? 'cash').toLowerCase().trim();
          if (pm == 'credit' || pm == 'آجل') {
            credit += inv.totalAmount;
          } else {
            cash += inv.paidAmount;
          }
        }

        // Drift uses snake_case for SQL columns
        final openingBalance =
            (data['opening_balance'] as num?)?.toDouble() ?? 0.0;
        final closingBalance = (data['closing_balance'] as num?)?.toDouble();
        final createdAt = parseDate(data['created_at']);
        final closedAt = parseDate(data['closed_at']);
        final surplusDeficit = closingBalance != null
            ? closingBalance - openingBalance - totalSales
            : 0.0;

        result.add({
          'date': dateStr,
          'dateTime': dayDate,
          'openTime': DateFormat('HH:mm').format(createdAt),
          'closeTime': DateFormat('HH:mm').format(closedAt),
          'openingBalance': openingBalance,
          'closingBalance': closingBalance ?? 0.0,
          'totalSales': totalSales,
          'cash': cash,
          'credit': credit,
          'surplusDeficit': surplusDeficit,
          'invoiceCount': invoices.length,
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
    final totalSales = _dailyData.fold<double>(
      0.0,
      (sum, d) => sum + ((d['totalSales'] as num?)?.toDouble() ?? 0.0),
    );
    final totalInvoices = _dailyData.fold<int>(
      0,
      (sum, d) => sum + ((d['invoiceCount'] as int?) ?? 0),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('تقرير اليوم'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
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
                        ),
                      ),
                      const Gap(12),
                      Expanded(
                        child: _buildSummaryCard(
                          'عدد الأيام',
                          _dailyData.length.toString(),
                          Colors.green,
                        ),
                      ),
                      const Gap(12),
                      Expanded(
                        child: _buildSummaryCard(
                          'عدد الفواتير',
                          totalInvoices.toString(),
                          Colors.orange,
                        ),
                      ),
                    ],
                  ),
                  const Gap(24),

                  // Date range
                  Text(
                    'الفترة: ${DateFormat('dd/MM/yyyy').format(_startDate!)} - ${DateFormat('dd/MM/yyyy').format(_endDate!)}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Gap(16),

                  // Table
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columnSpacing: 16,
                      headingRowColor: WidgetStateProperty.all(
                        Theme.of(context).colorScheme.primaryContainer,
                      ),
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
                        return DataRow(
                          cells: [
                            DataCell(Text(d['date'] as String)),
                            DataCell(Text(d['openTime'] as String)),
                            DataCell(Text(d['closeTime'] as String)),
                            DataCell(
                              Text(
                                (d['openingBalance'] as num).toStringAsFixed(2),
                              ),
                            ),
                            DataCell(
                              Text(
                                (d['closingBalance'] as num).toStringAsFixed(2),
                              ),
                            ),
                            DataCell(
                              Text((d['totalSales'] as num).toStringAsFixed(2)),
                            ),
                            DataCell(
                              Text((d['cash'] as num).toStringAsFixed(2)),
                            ),
                            DataCell(
                              Text((d['credit'] as num).toStringAsFixed(2)),
                            ),
                            DataCell(
                              Text(
                                sd.toStringAsFixed(2),
                                style: TextStyle(
                                  color: sd >= 0 ? Colors.green : Colors.red,
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

                  if (_dailyData.isEmpty) ...[
                    const Gap(32),
                    Center(
                      child: Text(
                        'لا توجد أيام في الفترة المحددة',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildSummaryCard(String title, String value, Color color) {
    return Card(
      color: color.withValues(alpha: 0.15),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(color: color, fontWeight: FontWeight.bold),
            ),
            const Gap(8),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
