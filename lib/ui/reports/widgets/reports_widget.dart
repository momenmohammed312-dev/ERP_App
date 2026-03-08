import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/l10n/l10n.dart';
import 'package:pos_offline_desktop/ui/reports/widgets/sales_report_tab.dart';
import 'package:pos_offline_desktop/ui/reports/widgets/expenses_report_tab.dart';
import 'package:pos_offline_desktop/ui/reports/widgets/customer_report_tab.dart';
import 'package:pos_offline_desktop/ui/invoice/new_invoice_page.dart';

class ReportsWidget extends StatefulWidget {
  final AppDatabase db;

  const ReportsWidget({super.key, required this.db});

  @override
  State<ReportsWidget> createState() => _ReportsWidgetState();
}

class _ReportsWidgetState extends State<ReportsWidget>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.analytics, size: 32, color: Colors.purple),
              const Gap(16),
              Text(
                context.l10n.reports_and_stats,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.purple,
                ),
              ),
            ],
          ),
          const Gap(20),

          // Tabs
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(
                  context,
                ).colorScheme.outline.withValues(alpha: 0.2),
              ),
            ),
            child: TabBar(
              controller: _tabController,
              labelColor: Colors.purple,
              unselectedLabelColor: Colors.grey,
              indicatorColor: Colors.purple,
              tabs: [
                Tab(
                  icon: const Icon(Icons.dashboard),
                  text: context.l10n.dashboard_tab,
                ),
                Tab(
                  icon: const Icon(Icons.receipt_long),
                  text: context.l10n.sales_report_tab,
                ),
                Tab(
                  icon: const Icon(Icons.money_off),
                  text: context.l10n.expenses_report_tab,
                ),
                Tab(
                  icon: const Icon(Icons.people),
                  text: context.l10n.customer_balances_tab,
                ),
              ],
            ),
          ),
          const Gap(20),

          // Content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildDashboardTab(),
                SalesReportTab(db: widget.db), // Will implement next
                ExpensesReportTab(db: widget.db), // Will implement next
                CustomerReportTab(db: widget.db),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Quick Stats
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  title: 'إجمالي المبيعات اليوم',
                  stream: _getTodayStat('sale'),
                  icon: Icons.trending_up,
                  color: Colors.green,
                ),
              ),
              const Gap(16),
              Expanded(
                child: _StatCard(
                  title: 'إجمالي المصروفات اليوم',
                  stream: _getTodayStat('expense'),
                  icon: Icons.trending_down,
                  color: Colors.red,
                ),
              ),
            ],
          ),
          const Gap(16),
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  title: 'الرصيد الحالي',
                  stream: widget.db.ledgerDao.watchCurrentBalance(),
                  icon: Icons.account_balance_wallet,
                  color: Colors.blue,
                ),
              ),
              const Gap(16),
              Expanded(
                child: _StatCard(
                  title: 'إجمالي المديونيات',
                  stream: widget.db.ledgerDao.watchTotalReceivables(),
                  icon: Icons.people_outline,
                  color: Colors.orange,
                ),
              ),
            ],
          ),
          const Gap(32),

          // Actions
          Center(
            child: SizedBox(
              width: 300,
              height: 60,
              child: ElevatedButton.icon(
                onPressed: () => _showNewInvoiceDialog(context),
                icon: const Icon(Icons.add_shopping_cart, size: 28),
                label: const Text(
                  'فاتورة جديدة',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Stream<double> _getTodayStat(String origin) {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    return widget.db.ledgerDao.watchAllTransactions().map((transactions) {
      return transactions
          .where((t) {
            final isCorrectOrigin = origin == 'sale'
                ? t.origin == 'sale'
                : (t.origin == 'expense' || t.origin == 'purchase');
            return isCorrectOrigin &&
                t.date.isAfter(startOfDay.subtract(const Duration(seconds: 1)));
          })
          .fold(0.0, (sum, t) => sum + (origin == 'sale' ? t.debit : t.credit));
    });
  }

  Future<void> _showNewInvoiceDialog(BuildContext context) async {
    final messengerContext = context; // Capture context before async
    bool isOpen = await widget.db.dayDao.isDayOpen();
    if (!isOpen) {
      await widget.db.dayDao.getOrCreateTodayDay(openingBalance: 0.0);
      isOpen = true;
    }

    if (mounted && messengerContext.mounted) {
      await Navigator.of(
        messengerContext,
      ).push(MaterialPageRoute(builder: (context) => const NewInvoicePage()));
    }
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final Stream<double> stream;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.title,
    required this.stream,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<double>(
      stream: stream,
      builder: (context, snapshot) {
        final value = snapshot.data ?? 0.0;
        return Card(
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Icon(icon, color: color, size: 30),
                    Text(
                      title,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const Gap(15),
                Text(
                  '${value.toStringAsFixed(2)} ج.م',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
