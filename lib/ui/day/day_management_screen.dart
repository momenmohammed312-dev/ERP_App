import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/database/app_database.dart';
import '../../core/models/user_model.dart';
import '../../core/provider/auth_provider.dart';
import '../../core/services/unified_print_service.dart' as ups;
import '../../widgets/permission_guard.dart';

/// Day Management Screen
/// شاشة إدارة اليومية المركزية
class DayManagementScreen extends ConsumerStatefulWidget {
  final AppDatabase db;

  const DayManagementScreen({super.key, required this.db});

  @override
  ConsumerState<DayManagementScreen> createState() =>
      _DayManagementScreenState();
}

class _DayManagementScreenState extends ConsumerState<DayManagementScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Day> _days = [];
  bool _isLoading = true;
  Day? _selectedDay;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadDays();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadDays() async {
    setState(() => _isLoading = true);
    try {
      final daysData = await widget.db
          .customSelect('SELECT * FROM days ORDER BY date DESC')
          .get();
      final days = daysData.map((row) => Day.fromJson(row.data)).toList();
      setState(() {
        _days = days;
        _isLoading = false;
        if (_days.isNotEmpty) {
          _selectedDay = _days.first;
        }
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('خطأ في تحميل الأيام: $e')));
      }
    }
  }

  Future<void> _printDayReport(Day day) async {
    try {
      // Get day statistics
      final invoices = await widget.db.invoiceDao.getInvoicesByDateRange(
        day.date,
        day.closedAt ?? DateTime.now(),
      );

      final purchases = await widget.db.enhancedPurchaseDao.getAllPurchases();
      final filteredPurchases = purchases
          .where(
            (p) =>
                p.createdAt.isAfter(
                  day.date.subtract(const Duration(days: 1)),
                ) &&
                p.createdAt.isBefore(
                  (day.closedAt ?? DateTime.now()).add(const Duration(days: 1)),
                ),
          )
          .toList();

      final expenses = await widget.db.expenseDao.getAllExpenses();
      final filteredExpenses = expenses
          .where(
            (e) =>
                e.createdAt.isAfter(
                  day.date.subtract(const Duration(days: 1)),
                ) &&
                e.createdAt.isBefore(
                  (day.closedAt ?? DateTime.now()).add(const Duration(days: 1)),
                ),
          )
          .toList();

      // Calculate totals
      double totalSales = invoices.fold(
        0.0,
        (sum, inv) => sum + inv.totalAmount,
      );
      double totalPurchases = filteredPurchases.fold(
        0.0,
        (sum, pur) => sum + pur.totalAmount,
      );
      double totalExpenses = filteredExpenses.fold(
        0.0,
        (sum, exp) => sum + exp.amount,
      );

      // Create day report data
      final dayReportData = {
        'day': day,
        'totalSales': totalSales,
        'totalPurchases': totalPurchases,
        'totalExpenses': totalExpenses,
        'netProfit': totalSales - totalPurchases - totalExpenses,
        'invoicesCount': invoices.length,
        'purchasesCount': filteredPurchases.length,
        'expensesCount': filteredExpenses.length,
        'invoices': invoices,
        'purchases': filteredPurchases,
        'expenses': filteredExpenses,
      };

      // Print using UnifiedPrintService (salesInvoice as placeholder)
      await ups.UnifiedPrintService.printToThermalPrinter(
        documentType: ups.DocumentType.salesInvoice,
        data: dayReportData,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('خطأ في طباعة التقرير: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إدارة اليومية'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.list), text: 'قائمة الأيام'),
            Tab(icon: Icon(Icons.analytics), text: 'تفاصيل اليوم'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDays,
            tooltip: 'تحديث',
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildDaysList(), _buildDayDetails()],
      ),
    );
  }

  Widget _buildDaysList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_days.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.calendar_today, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('لا توجد أيام مسجلة', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _days.length,
      itemBuilder: (context, index) {
        final day = _days[index];
        final isOpen = day.isOpen;

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: isOpen ? Colors.green : Colors.grey,
              child: Icon(
                isOpen ? Icons.play_arrow : Icons.check,
                color: Colors.white,
              ),
            ),
            title: Text(
              'يوم ${DateFormat('yyyy-MM-dd').format(day.date)}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'الرصيد الافتتاحي: ${day.openingBalance.toStringAsFixed(2)} ج.م',
                ),
                if (day.closedAt != null)
                  Text(
                    'الرصيد الختامي: ${day.closingBalance?.toStringAsFixed(2) ?? '0.00'} ج.م',
                  ),
                Text(
                  isOpen ? 'مفتوح' : 'مغلق',
                  style: TextStyle(
                    color: isOpen ? Colors.green : Colors.grey,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isOpen)
                  IconButton(
                    icon: const Icon(Icons.print),
                    onPressed: () => _printDayReport(day),
                    tooltip: 'طباعة تقرير اليوم',
                  ),
                IconButton(
                  icon: const Icon(Icons.info),
                  onPressed: () {
                    setState(() {
                      _selectedDay = day;
                      _tabController.animateTo(1);
                    });
                  },
                  tooltip: 'عرض التفاصيل',
                ),
              ],
            ),
            onTap: () {
              setState(() {
                _selectedDay = day;
                _tabController.animateTo(1);
              });
            },
          ),
        );
      },
    );
  }

  Widget _buildDayDetails() {
    if (_selectedDay == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.calendar_today, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('اختر يوماً من القائمة لعرض التفاصيل'),
          ],
        ),
      );
    }

    return FutureBuilder<Map<String, dynamic>>(
      future: _getDayStatistics(_selectedDay!),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('خطأ: ${snapshot.error}'));
        }

        final stats = snapshot.data ?? {};

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Day Header
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'تفاصيل يوم ${DateFormat('yyyy-MM-dd').format(_selectedDay!.date)}',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Chip(
                            label: Text(
                              _selectedDay!.isOpen ? 'مفتوح' : 'مغلق',
                            ),
                            backgroundColor: _selectedDay!.isOpen
                                ? Colors.green.withValues(alpha: 0.2)
                                : Colors.grey.withValues(alpha: 0.2),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'الرصيد الافتتاحي: ${_selectedDay!.openingBalance.toStringAsFixed(2)} ج.م',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Statistics Cards
              Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      'المبيعات',
                      '${stats['totalSales']?.toStringAsFixed(2) ?? '0.00'} ج.م',
                      '${stats['invoicesCount'] ?? 0} فاتورة',
                      Icons.shopping_cart,
                      Colors.green,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildStatCard(
                      'المشتريات',
                      '${stats['totalPurchases']?.toStringAsFixed(2) ?? '0.00'} ج.م',
                      '${stats['purchasesCount'] ?? 0} فاتورة',
                      Icons.inventory,
                      Colors.blue,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      'المصروفات',
                      '${stats['totalExpenses']?.toStringAsFixed(2) ?? '0.00'} ج.م',
                      '${stats['expensesCount'] ?? 0} عملية',
                      Icons.money_off,
                      Colors.red,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildStatCard(
                      'صافي الربح',
                      '${stats['netProfit']?.toStringAsFixed(2) ?? '0.00'} ج.م',
                      'المبيعات - المصروفات',
                      Icons.trending_up,
                      (stats['netProfit'] ?? 0) >= 0
                          ? Colors.purple
                          : Colors.orange,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Action Buttons
              if (_selectedDay!.isOpen)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'إجراءات اليوم المفتوح',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () => _printDayReport(_selectedDay!),
                                icon: const Icon(Icons.print),
                                label: const Text('طباعة تقرير مؤقت'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: PermissionGuard(
                                permission: Permission.closeDay,
                                fallback: const SizedBox.shrink(),
                                child: ElevatedButton.icon(
                                  onPressed: _closeDay,
                                  icon: const Icon(Icons.lock),
                                  label: const Text('إغلاق اليوم'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                ),
              ),

              // Reopen button for closed days
              if (!_selectedDay!.isOpen)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'إجراءات اليوم المغلق',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 12),
                        PermissionGuard(
                          permission: Permission.openDay,
                          fallback: const SizedBox.shrink(),
                          child: ElevatedButton.icon(
                            onPressed: () => _reopenDay(_selectedDay!),
                            icon: const Icon(Icons.lock_open),
                            label: const Text('إعادة فتح اليوم'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // Recent Transactions
              if (stats['recentTransactions'] != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'آخر المعاملات',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ...List.generate(
                          (stats['recentTransactions'] as List).length > 5
                              ? 5
                              : (stats['recentTransactions'] as List).length,
                          (index) {
                            final transaction =
                                (stats['recentTransactions'] as List)[index];
                            return ListTile(
                              dense: true,
                              leading: Icon(
                                transaction['type'] == 'sale'
                                    ? Icons.shopping_cart
                                    : transaction['type'] == 'purchase'
                                    ? Icons.inventory
                                    : Icons.money_off,
                                size: 20,
                              ),
                              title: Text(transaction['description'] ?? ''),
                              subtitle: Text(
                                DateFormat('HH:mm').format(transaction['date']),
                              ),
                              trailing: Text(
                                '${transaction['amount']?.toStringAsFixed(2) ?? '0.00'} ج.م',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    String subtitle,
    IconData icon,
    Color color,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Future<Map<String, dynamic>> _getDayStatistics(Day day) async {
    try {
      final endDate = day.closedAt ?? DateTime.now();

      // Get all transactions for the day
      final invoices = await widget.db.invoiceDao.getInvoicesByDateRange(
        day.date,
        endDate,
      );

      final purchases = await widget.db.enhancedPurchaseDao
          .getPurchasesByDateRange(day.date, endDate);

      final expenses = await widget.db.expenseDao.getExpensesByDateRange(
        day.date,
        endDate,
      );

      // Calculate totals
      double totalSales = invoices.fold(
        0.0,
        (sum, inv) => sum + inv.totalAmount,
      );
      double totalPurchases = purchases.fold(
        0.0,
        (sum, pur) => sum + pur.totalAmount,
      );
      double totalExpenses = expenses.fold(0.0, (sum, exp) => sum + exp.amount);

      // Create recent transactions list
      final recentTransactions = <Map<String, dynamic>>[];

      for (final invoice in invoices.take(3)) {
        recentTransactions.add({
          'type': 'sale',
          'description': 'فاتورة مبيعات ${invoice.invoiceNumber}',
          'amount': invoice.totalAmount,
          'date': invoice.date,
        });
      }

      for (final purchase in purchases.take(2)) {
        recentTransactions.add({
          'type': 'purchase',
          'description': 'فاتورة مشتريات ${purchase.purchaseNumber}',
          'amount': purchase.totalAmount,
          'date': purchase.createdAt,
        });
      }

      for (final expense in expenses.take(2)) {
        recentTransactions.add({
          'type': 'expense',
          'description': expense.description,
          'amount': expense.amount,
          'date': expense.createdAt,
        });
      }

      // Sort by date
      recentTransactions.sort((a, b) => b['date'].compareTo(a['date']));

      return {
        'totalSales': totalSales,
        'totalPurchases': totalPurchases,
        'totalExpenses': totalExpenses,
        'netProfit': totalSales - totalPurchases - totalExpenses,
        'invoicesCount': invoices.length,
        'purchasesCount': purchases.length,
        'expensesCount': expenses.length,
        'recentTransactions': recentTransactions,
      };
    } catch (e) {
      return {};
    }
  }

  Future<void> _closeDay() async {
    try {
      // Get the current open day
      final todayDay = await widget.db.dayDao.getTodayDay();
      if (todayDay == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('لا يوجد يوم مفتوح حالياً'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // Calculate closing balance (you may need to implement this logic)
      final dayId = todayDay['id'] as int;
      final closingBalance = await _calculateClosingBalance(dayId);

      final currentUser = ref.read(authProvider);
      await widget.db.dayDao.closeDay(
        dayId: dayId,
        closingBalance: closingBalance,
        closedBy: currentUser?.username ?? '',
      );
      await _loadDays();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إغلاق اليوم بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في إغلاق اليوم: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _reopenDay(Day day) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إعادة فتح اليوم'),
        content: Text('هل تريد إعادة فتح يوم ${DateFormat('yyyy-MM-dd').format(day.date)}؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: const Text('إعادة فتح'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final currentUser = ref.read(authProvider);
        await widget.db.dayDao.reopenDay(
          dayId: day.id,
          reopenedBy: currentUser?.username ?? '',
        );
        await _loadDays();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم إعادة فتح اليوم بنجاح'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('خطأ في إعادة فتح اليوم: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<double> _calculateClosingBalance(int dayId) async {
    // Implement your closing balance calculation logic here
    // This might include summing up all transactions for the day
    // For now, returning a default value
    return 0.0;
  }
}
