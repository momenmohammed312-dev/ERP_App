import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/services/export_service.dart';
import 'package:pos_offline_desktop/core/services/printer_service.dart';
import 'package:pos_offline_desktop/core/theme/madar_colors.dart';
import 'package:pos_offline_desktop/l10n/l10n.dart';

class ExpensesReportTab extends StatefulWidget {
  final AppDatabase db;

  const ExpensesReportTab({super.key, required this.db});

  @override
  State<ExpensesReportTab> createState() => _ExpensesReportTabState();
}

class _ExpensesReportTabState extends State<ExpensesReportTab> {
  DateTime _startDate = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
  );
  DateTime _endDate = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
    23,
    59,
    59,
  );
  List<Expense> _expenses = [];
  List<Expense> _filteredExpenses = [];
  bool _isLoading = false;
  final TextEditingController _searchController = TextEditingController();
  final ExportService _exportService = ExportService();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
      _filterExpenses();
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

  void _filterExpenses() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredExpenses = List.from(_expenses);
      } else {
        _filteredExpenses = _expenses.where((e) {
          return e.description.toLowerCase().contains(query);
        }).toList();
      }
    });
  }

  Future<void> _selectDateRange(BuildContext context) async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = DateTime(
          picked.end.year,
          picked.end.month,
          picked.end.day,
          23,
          59,
          59,
        );
      });
      _loadData();
    }
  }

  Future<void> _exportPDF() async {
    try {
      final data = _filteredExpenses.map((e) {
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
      final data = _filteredExpenses.map((e) {
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
            content: Text('تم إرسال إيصال المصروف إلى الطابعة'),
            backgroundColor: MadarColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل في الطباعة: $e'),
            backgroundColor: MadarColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final totalExpenses = _filteredExpenses.fold(0.0, (sum, item) => sum + item.amount);
    final count = _filteredExpenses.length;
    final avgExpense = count > 0 ? totalExpenses / count : 0.0;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'تقرير المصروفات والمنصرفات',
          style: TextStyle(fontFamily: 'NotoSansArabic', fontWeight: FontWeight.bold),
        ),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          children: [
            // Controls Card
            _buildControlsCard(context, isDark),
            const Gap(12),

            // KPI Summary Strip
            _buildKpiStrip(isDark, totalExpenses, count, avgExpense),
            const Gap(12),

            // Expenses List
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredExpenses.isEmpty
                      ? _buildEmptyState(context)
                      : ListView.builder(
                          itemCount: _filteredExpenses.length,
                          itemBuilder: (context, index) {
                            final expense = _filteredExpenses[index];
                            return _buildExpenseItemCard(context, isDark, expense);
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlsCard(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? MadarColors.bgCard : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? MadarColors.border : Colors.grey.shade200,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Search Input
              Expanded(
                child: SizedBox(
                  height: 42,
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) => _filterExpenses(),
                    decoration: InputDecoration(
                      hintText: 'البحث في بنود المصروفات...',
                      hintStyle: const TextStyle(
                        fontFamily: 'NotoSansArabic',
                        fontSize: 13,
                        color: Colors.grey,
                      ),
                      prefixIcon: const Icon(Icons.search, size: 20, color: MadarColors.gold),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                _filterExpenses();
                              },
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                      filled: true,
                      fillColor: isDark ? MadarColors.bgSurface : Colors.grey.shade100,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ),
              const Gap(10),

              // Date Range Picker Button
              InkWell(
                onTap: () => _selectDateRange(context),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  height: 42,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: isDark ? MadarColors.bgSurface : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isDark ? MadarColors.border : Colors.grey.shade300,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.calendar_month_rounded, size: 18, color: MadarColors.gold),
                      const Gap(8),
                      Text(
                        '${DateFormat('yyyy/MM/dd').format(_startDate)}  -  ${DateFormat('yyyy/MM/dd').format(_endDate)}',
                        style: const TextStyle(
                          fontFamily: 'NotoSansArabic',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Gap(4),
                      const Icon(Icons.arrow_drop_down, size: 18, color: Colors.grey),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const Gap(10),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton.icon(
                onPressed: _exportPDF,
                icon: const Icon(Icons.picture_as_pdf_rounded, size: 18, color: MadarColors.error),
                label: const Text(
                  'تصدير PDF',
                  style: TextStyle(fontFamily: 'NotoSansArabic', fontSize: 13),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: isDark ? MadarColors.border : Colors.grey.shade300),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const Gap(10),
              FilledButton.tonalIcon(
                onPressed: _exportExcel,
                icon: const Icon(Icons.table_view_rounded, size: 18, color: MadarColors.success),
                label: const Text(
                  'تصدير Excel',
                  style: TextStyle(fontFamily: 'NotoSansArabic', fontSize: 13),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: MadarColors.success.withValues(alpha: 0.15),
                  foregroundColor: MadarColors.success,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKpiStrip(bool isDark, double total, int count, double avg) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 650;
        final kpi1 = _KpiCard(
          title: 'إجمالي المصروفات',
          value: total,
          subtitle: 'خلال الفترة المحددة',
          color: MadarColors.error,
          icon: Icons.money_off_csred_rounded,
          isDark: isDark,
        );

        final kpi2 = _KpiCard(
          title: 'عدد بنود الصرف',
          valueText: '$count بند',
          subtitle: 'إجمالي الحركات المسجلة',
          color: MadarColors.gold,
          icon: Icons.receipt_long_rounded,
          isDark: isDark,
        );

        final kpi3 = _KpiCard(
          title: 'متوسط قيمة البند',
          value: avg,
          subtitle: 'معدل الصرف لكل بند',
          color: MadarColors.info,
          icon: Icons.analytics_outlined,
          isDark: isDark,
        );

        if (isNarrow) {
          return Column(
            children: [
              kpi1,
              const Gap(8),
              Row(
                children: [
                  Expanded(child: kpi2),
                  const Gap(8),
                  Expanded(child: kpi3),
                ],
              ),
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: kpi1),
            const Gap(10),
            Expanded(child: kpi2),
            const Gap(10),
            Expanded(child: kpi3),
          ],
        );
      },
    );
  }

  Widget _buildExpenseItemCard(BuildContext context, bool isDark, Expense expense) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? MadarColors.bgCard : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? MadarColors.border : Colors.grey.shade200,
        ),
      ),
      child: Row(
        children: [
          // Icon badge
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: MadarColors.error.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.outbox_rounded, color: MadarColors.error, size: 20),
          ),
          const Gap(12),

          // Description & Date
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  expense.description,
                  style: const TextStyle(
                    fontFamily: 'NotoSansArabic',
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Gap(3),
                Row(
                  children: [
                    Icon(
                      Icons.access_time_rounded,
                      size: 13,
                      color: isDark ? MadarColors.textMuted : Colors.grey.shade600,
                    ),
                    const Gap(4),
                    Text(
                      DateFormat('yyyy/MM/dd  HH:mm').format(expense.date),
                      style: TextStyle(
                        fontFamily: 'NotoSansArabic',
                        fontSize: 12,
                        color: isDark ? MadarColors.textMuted : Colors.grey.shade600,
                      ),
                    ),
                    const Gap(10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isDark ? MadarColors.bgSurface : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'خزينة / نقد',
                        style: TextStyle(
                          fontFamily: 'NotoSansArabic',
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Amount
          Text(
            '${expense.amount.toStringAsFixed(2)} ج.م',
            style: const TextStyle(
              fontFamily: 'NotoSansArabic',
              fontWeight: FontWeight.bold,
              fontSize: 15,
              color: MadarColors.error,
            ),
          ),
          const Gap(12),

          // Print Icon Button
          IconButton(
            onPressed: () => _printExpense(expense),
            icon: const Icon(Icons.print_rounded, size: 20),
            color: MadarColors.info,
            tooltip: 'طباعة إيصال المصروف',
            style: IconButton.styleFrom(
              backgroundColor: MadarColors.info.withValues(alpha: 0.1),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.receipt_long_outlined,
            size: 56,
            color: Colors.grey,
          ),
          const Gap(12),
          Text(
            _searchController.text.isNotEmpty
                ? 'لا توجد بنود مصروفات مطابقة للبحث'
                : 'لا توجد مصروفات مسجلة في هذه الفترة',
            style: TextStyle(
              fontFamily: 'NotoSansArabic',
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String title;
  final double? value;
  final String? valueText;
  final String subtitle;
  final Color color;
  final IconData icon;
  final bool isDark;

  const _KpiCard({
    required this.title,
    this.value,
    this.valueText,
    required this.subtitle,
    required this.color,
    required this.icon,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final display = valueText ?? '${value?.toStringAsFixed(2) ?? '0.00'} ج.م';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? MadarColors.bgCard : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? MadarColors.border : Colors.grey.shade200,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const Gap(10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'NotoSansArabic',
                    fontSize: 11,
                    color: isDark ? MadarColors.textSecondary : Colors.grey.shade600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const Gap(2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    display,
                    style: TextStyle(
                      fontFamily: 'NotoSansArabic',
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: color,
                    ),
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontFamily: 'NotoSansArabic',
                    fontSize: 10,
                    color: isDark ? MadarColors.textMuted : Colors.grey.shade500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
