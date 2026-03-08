import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pos_offline_desktop/core/provider/app_database_provider.dart';
import 'package:pos_offline_desktop/ui/reports/widgets/customer_report_tab.dart';
import 'package:pos_offline_desktop/ui/reports/widgets/expenses_report_tab.dart';
import 'package:pos_offline_desktop/ui/reports/widgets/sales_report_tab.dart';
import 'package:pos_offline_desktop/screens/reports/supplier_report_screen.dart';
import 'package:pos_offline_desktop/ui/reports/widgets/staff_expenses_report.dart';
import 'package:pos_offline_desktop/ui/reports/widgets/purchase_by_product_report.dart';
import 'package:pos_offline_desktop/ui/reports/widgets/purchase_vs_sales_report.dart';
import 'package:pos_offline_desktop/ui/reports/widgets/daily_report_page.dart';

class ReportsPage extends ConsumerStatefulWidget {
  const ReportsPage({super.key});

  @override
  ConsumerState<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends ConsumerState<ReportsPage> {
  // State variables
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();
  double _totalSales = 0.0;
  double _totalCash = 0.0;
  double _totalCredit = 0.0;
  int _totalInvoices = 0;
  int _cashInvoices = 0;
  int _creditInvoices = 0;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadReportsData();
  }

  Future<void> _loadReportsData() async {
    try {
      final db = ref.read(appDatabaseProvider);

      final startOfDay = DateTime(
        _startDate.year,
        _startDate.month,
        _startDate.day,
      );
      final endOfDay = DateTime(
        _endDate.year,
        _endDate.month,
        _endDate.day,
        23,
        59,
        59,
      );

      final invoices = await db.invoiceDao.getInvoicesByDateRange(
        startOfDay,
        endOfDay,
      );

      double sales = 0.0;
      double cash = 0.0;
      double credit = 0.0;
      int totalInvCount = 0;
      int cashInvCount = 0;
      int creditInvCount = 0;

      for (var inv in invoices) {
        final totalAmount = inv.totalAmount;
        sales += totalAmount;
        totalInvCount++;

        final pm = (inv.paymentMethod ?? 'cash').toLowerCase().trim();
        if (pm == 'credit' ||
            pm == 'آجل' ||
            pm == 'اجل' ||
            pm.contains('آجل') ||
            pm.contains('credit')) {
          credit += totalAmount;
          creditInvCount++;
        } else {
          cash += inv.paidAmount > 0 ? inv.paidAmount : totalAmount;
          cashInvCount++;
        }
      }

      debugPrint('Sales: $sales, Cash: $cash, Credit: $credit');
      debugPrint(
        'Total: $totalInvCount, Cash: $cashInvCount, Credit: $creditInvCount',
      );

      setState(() {
        _totalSales = sales;
        _totalCash = cash;
        _totalCredit = credit;
        _totalInvoices = totalInvCount;
        _cashInvoices = cashInvCount;
        _creditInvoices = creditInvCount;
      });
    } catch (e, st) {
      debugPrint('Error loading reports data: $e\n$st');
      // Show error state to user
      if (mounted) {
        setState(() {
          _totalSales = 0.0;
          _totalCash = 0.0;
          _totalCredit = 0.0;
          _totalInvoices = 0;
          _cashInvoices = 0;
          _creditInvoices = 0;
        });
      }
    }
  }

  Future<void> _loadAllInvoices() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final db = ref.read(appDatabaseProvider);
      final invoices = await db.invoiceDao.getAllInvoices();

      double sales = 0.0;
      double cash = 0.0;
      double credit = 0.0;
      int totalInvCount = 0;
      int cashInvCount = 0;
      int creditInvCount = 0;

      for (var inv in invoices) {
        final totalAmount = inv.totalAmount;
        sales += totalAmount;
        totalInvCount++;

        final pm = (inv.paymentMethod ?? 'cash').toLowerCase().trim();
        if (pm == 'credit' ||
            pm == 'آجل' ||
            pm == 'اجل' ||
            pm.contains('آجل') ||
            pm.contains('credit')) {
          credit += totalAmount;
          creditInvCount++;
        } else {
          cash += inv.paidAmount > 0 ? inv.paidAmount : totalAmount;
          cashInvCount++;
        }
      }

      debugPrint('ALL Sales: $sales, Cash: $cash, Credit: $credit');
      debugPrint(
        'ALL Total: $totalInvCount, Cash: $cashInvCount, Credit: $creditInvCount',
      );

      setState(() {
        _totalSales = sales;
        _totalCash = cash;
        _totalCredit = credit;
        _totalInvoices = totalInvCount;
        _cashInvoices = cashInvCount;
        _creditInvoices = creditInvCount;
        _isLoading = false;
      });

      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم تحميل $_totalInvoices فاتورة بنجاح'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e, st) {
      setState(() {
        _isLoading = false;
      });
      debugPrint('Error loading ALL invoices data: $e\n$st');

      // Show error message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ أثناء تحميل الفواتير: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
    );
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      _loadReportsData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('التقارير والمبيعات'),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        elevation: Theme.of(context).appBarTheme.elevation,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Date Range Selector
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Theme.of(
                            context,
                          ).dividerColor.withValues(alpha: 0.3),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'الفترة المحددة',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          const Gap(10),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'من تاريخ:',
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withValues(alpha: 0.6),
                                      ),
                                    ),
                                    Text(
                                      DateFormat(
                                        'dd/MM/yyyy',
                                      ).format(_startDate),
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurface,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Gap(20),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'إلى تاريخ:',
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withValues(alpha: 0.6),
                                      ),
                                    ),
                                    Text(
                                      DateFormat('dd/MM/yyyy').format(_endDate),
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurface,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Gap(20),
                              ElevatedButton.icon(
                                onPressed: _selectDateRange,
                                icon: const Icon(Icons.calendar_month),
                                label: const Text('تغيير التاريخ'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Theme.of(
                                    context,
                                  ).colorScheme.primary.withValues(alpha: 0.1),
                                  foregroundColor: Theme.of(
                                    context,
                                  ).colorScheme.primary,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 12,
                                  ),
                                ),
                              ),
                              const Gap(10),
                              ElevatedButton.icon(
                                onPressed: _isLoading ? null : _loadAllInvoices,
                                icon: _isLoading
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.all_inclusive),
                                label: Text(
                                  _isLoading
                                      ? 'جاري التحميل...'
                                      : 'عرض كل الفواتير',
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange.withValues(
                                    alpha: 0.1,
                                  ),
                                  foregroundColor: Colors.orange,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const Gap(20),

              // Sales Summary Cards
              Text(
                'ملخص المبيعات',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const Gap(15),
              Row(
                children: [
                  Expanded(
                    child: _buildSummaryCard(
                      'إجمالي المبيعات',
                      _totalSales,
                      Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.15),
                      Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const Gap(15),
                  Expanded(
                    child: _buildSummaryCard(
                      'مبيعات كاش',
                      _totalCash,
                      Colors.green.withValues(alpha: 0.15),
                      Colors.green.shade700,
                    ),
                  ),
                  const Gap(15),
                  Expanded(
                    child: _buildSummaryCard(
                      'مبيعات آجل',
                      _totalCredit,
                      Colors.orange.withValues(alpha: 0.15),
                      Colors.orange.shade700,
                    ),
                  ),
                ],
              ),
              const Gap(20),

              // Invoice Count Cards
              Text(
                'إحصائيات الفواتير',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const Gap(15),
              Row(
                children: [
                  Expanded(
                    child: _buildCountCard(
                      'إجمالي الفواتير',
                      _totalInvoices,
                      Theme.of(
                        context,
                      ).colorScheme.secondary.withValues(alpha: 0.15),
                      Theme.of(context).colorScheme.secondary,
                    ),
                  ),
                  const Gap(15),
                  Expanded(
                    child: _buildCountCard(
                      'فواتير كاش',
                      _cashInvoices,
                      Colors.green.withValues(alpha: 0.15),
                      Colors.green.shade700,
                    ),
                  ),
                  const Gap(15),
                  Expanded(
                    child: _buildCountCard(
                      'فواتير آجل',
                      _creditInvoices,
                      Colors.orange.withValues(alpha: 0.15),
                      Colors.orange.shade700,
                    ),
                  ),
                ],
              ),
              const Gap(20),

              // Additional Reports Section
              Text(
                'تقارير إضافية',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const Gap(15),
              Row(
                children: [
                  Expanded(
                    child: _buildActionCard(
                      'تقرير اليوم',
                      'الأيام المفتوحة والمبيعات اليومية',
                      Icons.today,
                      Colors.amber,
                      () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const DailyReportPage(),
                          ),
                        );
                      },
                    ),
                  ),
                  const Gap(15),
                  Expanded(
                    child: _buildActionCard(
                      'تقارير المبيعات',
                      'عرض أكثر المنتجات مبيعاً',
                      Icons.trending_up,
                      Colors.indigo,
                      () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => SalesReportTab(
                              db: ref.read(appDatabaseProvider),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const Gap(15),
                  Expanded(
                    child: _buildActionCard(
                      'تقرير العملاء',
                      'عرض عملاء بأعلى مبيعات',
                      Icons.people,
                      Colors.cyan,
                      () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => CustomerReportTab(
                              db: ref.read(appDatabaseProvider),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const Gap(15),
                  Expanded(
                    child: _buildActionCard(
                      'تقرير المصروفات',
                      'عرض ملخص المصروفات',
                      Icons.receipt_long,
                      Colors.red,
                      () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => ExpensesReportTab(
                              db: ref.read(appDatabaseProvider),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const Gap(15),
                  Expanded(
                    child: _buildActionCard(
                      'مصروفات الموظفين',
                      'سلف ورواتب الموظفين',
                      Icons.assignment_ind,
                      Colors.blueGrey,
                      () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => StaffExpensesReport(
                              db: ref.read(appDatabaseProvider),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
              const Gap(15),
              Row(
                children: [
                  Expanded(
                    child: _buildActionCard(
                      'المشتريات حسب المورد',
                      'عرض مشتريات كل مورد',
                      Icons.business,
                      Colors.orange,
                      () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => SupplierReportScreen(
                              database: ref.read(appDatabaseProvider),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const Gap(15),
                  Expanded(
                    child: _buildActionCard(
                      'المشتريات حسب المنتج',
                      'عرض مشتريات كل منتج',
                      Icons.inventory,
                      Colors.purple,
                      () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) =>
                                const PurchaseByProductReport(),
                          ),
                        );
                      },
                    ),
                  ),
                  const Gap(15),
                  Expanded(
                    child: _buildActionCard(
                      'مقارنة المشتريات بالمبيعات',
                      'عرض الأرباح والهوامش',
                      Icons.compare_arrows,
                      Colors.teal,
                      () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => const PurchaseVsSalesReport(),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCard(
    String title,
    double amount,
    Color bgColor,
    Color textColor,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: textColor.withValues(alpha: 0.8),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Gap(8),
          Text(
            NumberFormat.currency(
              locale: 'en_EG',
              symbol: 'ج.م',
            ).format(amount),
            style: TextStyle(
              color: textColor,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCountCard(
    String title,
    int count,
    Color bgColor,
    Color textColor,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: textColor.withValues(alpha: 0.8),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Gap(8),
          Text(
            count.toString(),
            style: TextStyle(
              color: textColor,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard(
    String title,
    String subtitle,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 32),
            const Gap(12),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const Gap(4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
