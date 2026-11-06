import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pos_offline_desktop/core/services/daily_sales_service.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/services/settings_service.dart';

class DailySalesCalendar extends ConsumerStatefulWidget {
  final AppDatabase db;

  const DailySalesCalendar({super.key, required this.db});

  @override
  ConsumerState<DailySalesCalendar> createState() => _DailySalesCalendarState();
}

class _DailySalesCalendarState extends ConsumerState<DailySalesCalendar> {
  late DailySalesService _dailySalesService;
  DateTime _selectedMonth = DateTime.now();
  DateTime? _selectedDate;
  Map<String, Map<String, dynamic>> _dailySalesData = {};
  bool _isLoading = false;
  CalendarThemeMode _calendarTheme = CalendarThemeMode.light;

  @override
  void initState() {
    super.initState();
    _dailySalesService = DailySalesService(widget.db);
    // Load calendar theme from settings
    SettingsService.getCalendarTheme().then((mode) {
      setState(() => _calendarTheme = mode);
    });
    _loadMonthlyData();
  }

  Future<void> _loadMonthlyData() async {
    setState(() => _isLoading = true);
    try {
      final startDate = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
      final endDate = DateTime(
        _selectedMonth.year,
        _selectedMonth.month + 1,
        0,
      );

      final data = await _dailySalesService.getDailySalesSummary(
        startDate,
        endDate,
      );
      setState(() {
        _dailySalesData = data;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('خطأ: $e')));
      }
    }
  }

  void _previousMonth() {
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1);
      _selectedDate = null;
    });
    _loadMonthlyData();
  }

  void _nextMonth() {
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1);
      _selectedDate = null;
    });
    _loadMonthlyData();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Header with month navigation
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  onPressed: _previousMonth,
                  icon: const Icon(Icons.chevron_right),
                ),
                Text(
                  _getMonthYearString(),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  onPressed: _nextMonth,
                  icon: const Icon(Icons.chevron_left),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Calendar grid
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else
              _buildCalendarGrid(),

            if (_selectedDate != null) ...[
              const SizedBox(height: 20),
              _buildSelectedDateDetails(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCalendarGrid() {
    final daysInMonth = DateTime(
      _selectedMonth.year,
      _selectedMonth.month + 1,
      0,
    ).day;
    final firstDayOfMonth = DateTime(
      _selectedMonth.year,
      _selectedMonth.month,
      1,
    );
    final startingWeekday = firstDayOfMonth.weekday == 7
        ? 0
        : firstDayOfMonth.weekday;

    return Column(
      children: [
        // Weekday headers
        Row(
          children: ['إثنين', 'ثلاثاء', 'أربعاء', 'خميس', 'جمعة', 'سبت', 'أحد']
              .map(
                (day) => Expanded(
                  child: Center(
                    child: Text(
                      day,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 8),

        // Calendar days grid
        Column(
          children: List.generate(6, (weekIndex) {
            return Row(
              children: List.generate(7, (dayIndex) {
                final dayNumber =
                    weekIndex * 7 + dayIndex - startingWeekday + 1;
                final isValidDay = dayNumber > 0 && dayNumber <= daysInMonth;

                if (!isValidDay) {
                  return const Expanded(child: SizedBox());
                }

                final date = DateTime(
                  _selectedMonth.year,
                  _selectedMonth.month,
                  dayNumber,
                );
                final dateString = DateFormat('yyyy-MM-dd').format(date);
                final dayData = _dailySalesData[dateString];
                final salesAmount = dayData?['salesAmount'] as double? ?? 0.0;
                final isSelected =
                    _selectedDate != null &&
                    _selectedDate!.year == date.year &&
                    _selectedDate!.month == date.month &&
                    _selectedDate!.day == date.day;
                final isToday = _isToday(date);

                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() => _selectedDate = date);
                    },
                    child: Container(
                      margin: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: _getDayColor(salesAmount, isSelected, isToday),
                        borderRadius: BorderRadius.circular(8),
                        border: isSelected
                            ? Border.all(color: Colors.blue, width: 2)
                            : null,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '$dayNumber',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: isToday
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: _getTextColor(
                                  salesAmount,
                                  isSelected,
                                  isToday,
                                ),
                              ),
                            ),
                            if (salesAmount > 0)
                              Text(
                                '${salesAmount.toInt()}',
                                style: TextStyle(
                                  fontSize: 8,
                                  color: _getTextColor(
                                    salesAmount,
                                    isSelected,
                                    isToday,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildSelectedDateDetails() {
    if (_selectedDate == null) return const SizedBox();

    final dateString = DateFormat('yyyy-MM-dd').format(_selectedDate!);
    final dayData = _dailySalesData[dateString];
    final salesAmount = dayData?['salesAmount'] as double? ?? 0.0;
    final salesCount = dayData?['salesCount'] as int? ?? 0;

    return Card(
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'تفاصيل يوم ${DateFormat('dd/MM/yyyy').format(_selectedDate!)}',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildDetailCard(
                    'إجمالي المبيعات',
                    '${salesAmount.toStringAsFixed(2)} ج.م',
                    Colors.green,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildDetailCard(
                    'عدد الفواتير',
                    '$salesCount',
                    Colors.blue,
                  ),
                ),
              ],
            ),
            if (salesCount > 0) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => _showDayInvoices(),
                  child: Text('عرض فواتير اليوم'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDetailCard(String title, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(title, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Color _getDayColor(double salesAmount, bool isSelected, bool isToday) {
    switch (_calendarTheme) {
      case CalendarThemeMode.dark:
        if (isSelected) return const Color(0xFF1F6FEB); // Distinct vibrant blue
        if (isToday) return const Color(0xFFD29922); // Warm golden amber
        if (salesAmount > 0) return const Color(0xFF238636); // Crisp emerald green
        return const Color(0xFF262C36); // Lighter, clean slate surface (not murky)
      case CalendarThemeMode.gray:
        if (isSelected) return Colors.blueGrey.shade200;
        if (isToday) return Colors.orange.shade200;
        if (salesAmount > 0) return Colors.green.shade200;
        return Colors.grey.shade200;
      case CalendarThemeMode.light:
        if (isSelected) return Colors.blue.shade200;
        if (isToday) return Colors.orange.shade200;
        if (salesAmount > 0) return Colors.green.shade100;
        return Colors.grey.shade100;
    }
  }

  Color _getTextColor(double salesAmount, bool isSelected, bool isToday) {
    switch (_calendarTheme) {
      case CalendarThemeMode.dark:
        if (isSelected || isToday) return Colors.white;
        if (salesAmount > 0) return Colors.white;
        return const Color(0xFFE6EDF3); // High-contrast, bright text
      case CalendarThemeMode.gray:
        if (isSelected || isToday) return Colors.black;
        if (salesAmount > 0) return Colors.green.shade800;
        return Colors.grey.shade600;
      case CalendarThemeMode.light:
        if (isSelected || isToday) return Colors.black;
        if (salesAmount > 0) return Colors.green.shade800;
        return Colors.grey.shade600;
    }
  }

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  String _getMonthYearString() {
    return '${_dailySalesService.getMonthNameArabic(_selectedMonth.month)} ${_selectedMonth.year}';
  }

  void _showDayInvoices() {
    if (_selectedDate == null) return;

    // Navigate to invoices page filtered by selected date
    Navigator.of(context).pushNamed(
      '/invoices',
      arguments: {
        'startDate': _selectedDate,
        'endDate': DateTime(
          _selectedDate!.year,
          _selectedDate!.month,
          _selectedDate!.day,
          23,
          59,
          59,
        ),
      },
    );
  }
}
