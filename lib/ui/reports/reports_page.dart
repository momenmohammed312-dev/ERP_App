import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:drift/drift.dart' as drift;
import 'package:pos_offline_desktop/core/provider/app_database_provider.dart';
import 'package:pos_offline_desktop/core/theme/madar_colors.dart';
import 'package:pos_offline_desktop/core/utils/logger.dart';
import 'package:pos_offline_desktop/ui/reports/widgets/customer_report_tab.dart';
import 'package:pos_offline_desktop/ui/reports/widgets/expenses_report_tab.dart';
import 'package:pos_offline_desktop/ui/reports/widgets/sales_report_tab.dart';
import 'package:pos_offline_desktop/ui/reports/widgets/purchases_report_tab.dart';
import 'package:pos_offline_desktop/screens/reports/supplier_report_screen.dart';
import 'package:pos_offline_desktop/ui/reports/widgets/staff_expenses_report.dart';
import 'package:pos_offline_desktop/ui/reports/widgets/purchase_by_product_report.dart';
import 'package:pos_offline_desktop/ui/reports/widgets/daily_report_page.dart';
import 'package:pos_offline_desktop/ui/analytics/consolidated_accounts_screen.dart';
import 'package:pos_offline_desktop/ui/reports/widgets/charts/financial_flow_spline_chart.dart';
import 'package:pos_offline_desktop/ui/reports/widgets/charts/product_sales_pie_chart.dart';

class ReportsPage extends ConsumerStatefulWidget {
  const ReportsPage({super.key});

  @override
  ConsumerState<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends ConsumerState<ReportsPage> {
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();
  double _totalSales = 0.0;
  double _totalCash = 0.0;
  double _totalCredit = 0.0;
  int _totalInvoices = 0;
  int _cashInvoices = 0;
  int _creditInvoices = 0;
  double _totalPurchases = 0.0;
  int _purchasesCount = 0;
  double _totalExpenses = 0.0;
  List<Map<String, dynamic>> _dailyFlow = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadReportsData();
    });
  }

  Future<void> _loadReportsData() async {
    try {
      setState(() => _isLoading = true);
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

      // Invoices in range
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
        } else if (pm == 'mixed') {
          cash += inv.paidAmount;
          credit += (totalAmount - inv.paidAmount);
          if (inv.paidAmount >= totalAmount) {
            cashInvCount++;
          } else {
            creditInvCount++;
          }
        } else {
          cash += inv.paidAmount > 0 ? inv.paidAmount : totalAmount;
          cashInvCount++;
        }
      }

      // Purchases in range
      double purchasesTotal = 0.0;
      int purchasesCount = 0;
      try {
        final pRes = await db.customSelect(
          '''
          SELECT COALESCE(SUM(total_amount), 0) as total, COUNT(*) as count
          FROM purchases
          WHERE purchase_date BETWEEN ? AND ? AND (is_deleted = 0 OR is_deleted IS NULL)
          ''',
          variables: [
            drift.Variable.withDateTime(startOfDay),
            drift.Variable.withDateTime(endOfDay),
          ],
        ).get();
        if (pRes.isNotEmpty) {
          purchasesTotal = (pRes.first.data['total'] as num?)?.toDouble() ?? 0.0;
          purchasesCount = (pRes.first.data['count'] as num?)?.toInt() ?? 0;
        }
      } catch (e) {
        debugPrint('Purchases query notice: $e');
      }

      // Expenses in range
      double expensesTotal = 0.0;
      try {
        final expRes = await db.customSelect(
          '''
          SELECT COALESCE(SUM(amount), 0) as total
          FROM expenses
          WHERE date BETWEEN ? AND ?
          ''',
          variables: [
            drift.Variable.withDateTime(startOfDay),
            drift.Variable.withDateTime(endOfDay),
          ],
        ).get();
        if (expRes.isNotEmpty) {
          expensesTotal = (expRes.first.data['total'] as num?)?.toDouble() ?? 0.0;
        }
      } catch (e) {
        debugPrint('Expenses query notice: $e');
      }

      // Daily comparison points for spline chart
      final Map<String, Map<String, double>> dailyMap = {};
      for (var inv in invoices) {
        final dStr = DateFormat('yyyy-MM-dd').format(inv.date);
        dailyMap.putIfAbsent(dStr, () => {'sales': 0.0, 'purchases': 0.0});
        dailyMap[dStr]!['sales'] = (dailyMap[dStr]!['sales'] ?? 0.0) + inv.totalAmount;
      }

      try {
        final rawPurchases = await db.customSelect(
          '''
          SELECT purchase_date, total_amount
          FROM purchases
          WHERE purchase_date BETWEEN ? AND ? AND (is_deleted = 0 OR is_deleted IS NULL)
          ''',
          variables: [
            drift.Variable.withDateTime(startOfDay),
            drift.Variable.withDateTime(endOfDay),
          ],
        ).get();
        for (var row in rawPurchases) {
          final dt = row.readNullable<DateTime>('purchase_date') ??
              DateTime.tryParse(row.data['purchase_date']?.toString() ?? '');
          if (dt != null) {
            final dStr = DateFormat('yyyy-MM-dd').format(dt);
            dailyMap.putIfAbsent(dStr, () => {'sales': 0.0, 'purchases': 0.0});
            dailyMap[dStr]!['purchases'] = (dailyMap[dStr]!['purchases'] ?? 0.0) +
                ((row.data['total_amount'] as num?)?.toDouble() ?? 0.0);
          }
        }
      } catch (e) {
        debugPrint('Daily purchases query notice: $e');
      }

      final sortedKeys = dailyMap.keys.toList()..sort();
      final dailyFlow = sortedKeys.map((k) => {
        'date': k,
        'sales': dailyMap[k]!['sales'] ?? 0.0,
        'purchases': dailyMap[k]!['purchases'] ?? 0.0,
      }).toList();

      if (mounted) {
        setState(() {
          _totalSales = sales;
          _totalCash = cash;
          _totalCredit = credit;
          _totalInvoices = totalInvCount;
          _cashInvoices = cashInvCount;
          _creditInvoices = creditInvCount;
          _totalPurchases = purchasesTotal;
          _purchasesCount = purchasesCount;
          _totalExpenses = expensesTotal;
          _dailyFlow = dailyFlow;
          _isLoading = false;
        });
      }
    } catch (e, st) {
      AppLogger.e('Failed to load reports data', e, st);
      if (mounted) {
        setState(() => _isLoading = false);
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

  void _setDatePreset(int days) {
    setState(() {
      _endDate = DateTime.now();
      _startDate = DateTime.now().subtract(Duration(days: days));
    });
    _loadReportsData();
  }

  @override
  Widget build(BuildContext context) {
    final netProfit = _totalSales - _totalPurchases - _totalExpenses;
    final profitMargin = _totalSales > 0 ? (netProfit / _totalSales * 100) : 0.0;
    final isDesktop = MediaQuery.of(context).size.width >= 960;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Period Selector Ribbon
            _buildPeriodFilterBar(context),
            const Gap(20),

            // 4 Material 3 Top KPI Cards
            _buildTopKpiCards(context, netProfit, profitMargin),
            const Gap(24),

            // Dual Interactive Charts (Spline & Donut)
            if (isDesktop)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 12,
                    child: _buildSplineChartContainer(),
                  ),
                  const Gap(16),
                  Expanded(
                    flex: 8,
                    child: _buildDonutChartContainer(),
                  ),
                ],
              )
            else
              Column(
                children: [
                  _buildSplineChartContainer(),
                  const Gap(16),
                  _buildDonutChartContainer(),
                ],
              ),
            const Gap(28),

            // 9 Official Sub-report Tiles Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: MadarColors.gold.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.hub_outlined, size: 18, color: MadarColors.gold),
                ),
                const SizedBox(width: 10),
                const Text(
                  'مركز التقارير المتخصصة',
                  style: TextStyle(
                    fontFamily: 'NotoSansArabic',
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                Text(
                  'انقر على أي تقرير لفتحه في صفحة مخصصة',
                  style: TextStyle(
                    fontFamily: 'NotoSansArabic',
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
            const Gap(16),

            // 9 Official Sub-report Tiles (Responsive Grid)
            _buildSubReportsGrid(context),
            const Gap(32),
          ],
        ),
      ),
    );
  }

  Widget _buildPeriodFilterBar(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.15),
        ),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 10,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.date_range_rounded, size: 18, color: MadarColors.gold),
              const SizedBox(width: 8),
              Text(
                'الفترة المحددة: ${dateFormat.format(_startDate)}  ←  ${dateFormat.format(_endDate)}',
                style: const TextStyle(
                  fontFamily: 'NotoSansArabic',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            children: [
              _buildPresetPill('اليوم', () => _setDatePreset(0)),
              _buildPresetPill('7 أيام', () => _setDatePreset(7)),
              _buildPresetPill('30 يوم', () => _setDatePreset(30)),
              ElevatedButton.icon(
                onPressed: _selectDateRange,
                icon: const Icon(Icons.calendar_month, size: 16),
                label: const Text('تخصيص التاريخ', style: TextStyle(fontFamily: 'NotoSansArabic', fontSize: 12.5)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: MadarColors.gold.withValues(alpha: 0.15),
                  foregroundColor: MadarColors.gold,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              IconButton(
                icon: _isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: MadarColors.gold),
                      )
                    : const Icon(Icons.refresh_rounded, size: 20),
                onPressed: _isLoading ? null : _loadReportsData,
                tooltip: 'تحديث البيانات',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPresetPill(String label, VoidCallback onTap) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontFamily: 'NotoSansArabic', fontSize: 11.5)),
      onPressed: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      backgroundColor: Colors.transparent,
      side: BorderSide(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2)),
    );
  }

  Widget _buildTopKpiCards(BuildContext context, double netProfit, double profitMargin) {
    final currencyFormatter = NumberFormat.currency(locale: 'en_EG', symbol: 'ج.م', decimalDigits: 0);
    final totalCashAndCredit = _totalCash + _totalCredit;
    final cashRatio = totalCashAndCredit > 0 ? (_totalCash / totalCashAndCredit) : 0.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth >= 1080 ? 4 : (constraints.maxWidth >= 600 ? 2 : 1);

        final cards = [
          // Card 1: Total Sales
          _buildKpiCard(
            title: 'إجمالي المبيعات',
            amount: currencyFormatter.format(_totalSales),
            badgeText: '$_totalInvoices فاتورة بيع',
            badgeColor: MadarColors.gold,
            icon: Icons.trending_up_rounded,
            iconColor: MadarColors.gold,
          ),

          // Card 2: Cash vs Credit (with inline progress ratio)
          _buildKpiCard(
            title: 'التدفق النقدي والآجل',
            amount: currencyFormatter.format(_totalCash),
            badgeText: 'كاش ($_cashInvoices) ${(cashRatio * 100).toStringAsFixed(0)}% / آجل ($_creditInvoices) ${((1 - cashRatio) * 100).toStringAsFixed(0)}%',
            badgeColor: const Color(0xFF238636),
            icon: Icons.account_balance_wallet_rounded,
            iconColor: const Color(0xFF238636),
            extraWidget: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: cashRatio,
                  backgroundColor: const Color(0xFFD29922).withValues(alpha: 0.3),
                  valueColor: const AlwaysStoppedAnimation(Color(0xFF238636)),
                  minHeight: 6,
                ),
              ),
            ),
          ),

          // Card 3: Purchases
          _buildKpiCard(
            title: 'إجمالي المشتريات',
            amount: currencyFormatter.format(_totalPurchases),
            badgeText: '$_purchasesCount فاتورة توريد',
            badgeColor: const Color(0xFFD29922),
            icon: Icons.shopping_bag_outlined,
            iconColor: const Color(0xFFD29922),
          ),

          // Card 4: Net Margin
          _buildKpiCard(
            title: 'صافي الهامش التقديري',
            amount: currencyFormatter.format(netProfit),
            badgeText: '${profitMargin.toStringAsFixed(1)}% هامش ربح',
            badgeColor: netProfit >= 0 ? const Color(0xFF388BFD) : const Color(0xFFF85149),
            icon: Icons.show_chart_rounded,
            iconColor: netProfit >= 0 ? const Color(0xFF388BFD) : const Color(0xFFF85149),
          ),
        ];

        if (crossAxisCount == 4) {
          return Row(
            children: cards
                .map((c) => Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: c,
                      ),
                    ))
                .toList(),
          );
        } else if (crossAxisCount == 2) {
          return Column(
            children: [
              Row(
                children: [
                  Expanded(child: cards[0]),
                  const SizedBox(width: 12),
                  Expanded(child: cards[1]),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: cards[2]),
                  const SizedBox(width: 12),
                  Expanded(child: cards[3]),
                ],
              ),
            ],
          );
        } else {
          return Column(
            children: cards
                .map((c) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: c,
                    ))
                .toList(),
          );
        }
      },
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String amount,
    required String badgeText,
    required Color badgeColor,
    required IconData icon,
    required Color iconColor,
    Widget? extraWidget,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'NotoSansArabic',
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            amount,
            style: const TextStyle(
              fontFamily: 'NotoSansArabic',
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              badgeText,
              style: TextStyle(
                fontFamily: 'NotoSansArabic',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: badgeColor,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (extraWidget != null) extraWidget,
        ],
      ),
    );
  }

  Widget _buildSplineChartContainer() {
    return Container(
      height: 340,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.waterfall_chart_rounded, size: 18, color: MadarColors.gold),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'منحنى التدفقات المالية (المبيعات vs المشتريات vs الأرباح)',
                  style: TextStyle(
                    fontFamily: 'NotoSansArabic',
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: FinancialFlowSplineChart(dailyFlow: _dailyFlow),
          ),
        ],
      ),
    );
  }

  Widget _buildDonutChartContainer() {
    return Container(
      height: 340,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.pie_chart_outline_rounded, size: 18, color: Color(0xFF388BFD)),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'توزيع المبيعات حسب الأصناف',
                  style: TextStyle(
                    fontFamily: 'NotoSansArabic',
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ProductSalesPieChart(
              dateRange: DateTimeRange(start: _startDate, end: _endDate),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubReportsGrid(BuildContext context) {
    final db = ref.read(appDatabaseProvider);

    final List<Map<String, dynamic>> subReports = [
      {
        'title': 'تقرير اليوم',
        'desc': 'مبيعات الكاشير والوردية وجرد النقدية اليومي',
        'icon': Icons.today_rounded,
        'color': const Color(0xFFD29922),
        'onTap': () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const DailyReportPage()),
            ),
      },
      {
        'title': 'تقارير المبيعات',
        'desc': 'أعلى المنتجات مبيعاً وأرشيف فواتير البيع',
        'icon': Icons.trending_up_rounded,
        'color': MadarColors.gold,
        'onTap': () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => SalesReportTab(db: db)),
            ),
      },
      {
        'title': 'فواتير المشتريات',
        'desc': 'سجل فواتير الموردين والدفعات والتوريدات',
        'icon': Icons.shopping_cart_outlined,
        'color': const Color(0xFF238636),
        'onTap': () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => PurchasesReportTab(db: db)),
            ),
      },
      {
        'title': 'تقرير العملاء والذمم',
        'desc': 'أرصدة العملاء والمديونيات وأعلى المشترين',
        'icon': Icons.people_outline_rounded,
        'color': const Color(0xFF388BFD),
        'onTap': () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => CustomerReportTab(db: db)),
            ),
      },
      {
        'title': 'تقرير المصروفات',
        'desc': 'بنود المصاريف التشغيلية وفئات الصرف اليومية',
        'icon': Icons.receipt_long_outlined,
        'color': const Color(0xFFF85149),
        'onTap': () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => ExpensesReportTab(db: db)),
            ),
      },
      {
        'title': 'مصروفات الموظفين',
        'desc': 'الرواتب والسلف والبدلات واستحقاقات الفريق',
        'icon': Icons.badge_outlined,
        'color': const Color(0xFFA371F7),
        'onTap': () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => StaffExpensesReport(db: db)),
            ),
      },
      {
        'title': 'المشتريات حسب المورد',
        'desc': 'كشف حسابات الموردين وحجم التوريد لكل مورد',
        'icon': Icons.business_outlined,
        'color': const Color(0xFF39C5CF),
        'onTap': () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => SupplierReportScreen(database: db)),
            ),
      },
      {
        'title': 'المشتريات حسب المنتج',
        'desc': 'متوسط أسعار الشراء والكميات المستلمة لكل صنف',
        'icon': Icons.inventory_2_outlined,
        'color': const Color(0xFF58A6FF),
        'onTap': () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PurchaseByProductReport()),
            ),
      },
      {
        'title': 'الأرصدة الموحدة',
        'desc': 'كشوف الحسابات التفصيلية والمختصرة للموردين والعملاء',
        'icon': Icons.account_balance_outlined,
        'color': const Color(0xFF8B949E),
        'onTap': () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ConsolidatedAccountsScreen()),
            ),
      },
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth >= 960 ? 3 : (constraints.maxWidth >= 600 ? 2 : 1);

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: subReports.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            mainAxisExtent: 104,
          ),
          itemBuilder: (context, index) {
            final r = subReports[index];
            return _buildSubReportCard(
              title: r['title'] as String,
              desc: r['desc'] as String,
              icon: r['icon'] as IconData,
              color: r['color'] as Color,
              onTap: r['onTap'] as VoidCallback,
            );
          },
        );
      },
    );
  }

  Widget _buildSubReportCard({
    required String title,
    required String desc,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.15),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontFamily: 'NotoSansArabic',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      desc,
                      style: TextStyle(
                        fontFamily: 'NotoSansArabic',
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
