import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/l10n/app_localizations.dart';
import 'package:pos_offline_desktop/ui/product/product.dart';
import 'package:pos_offline_desktop/ui/cashier/cashier_page.dart';
import 'package:pos_offline_desktop/ui/home/widgets/customer_transactions_widget.dart';
import 'package:pos_offline_desktop/ui/home/widgets/suppliers_widget.dart';
import 'package:pos_offline_desktop/ui/reports/reports_page.dart';
import 'package:pos_offline_desktop/ui/invoice/widgets/enhanced_new_invoice_page.dart';
import 'package:pos_offline_desktop/ui/backup/enhanced_backup_screen.dart';
import 'package:pos_offline_desktop/ui/staff/staff_list_page.dart';
import 'package:pos_offline_desktop/widgets/license/feature_guard.dart';

class ModernHomeScreen extends StatefulWidget {
  final AppDatabase db;
  const ModernHomeScreen({super.key, required this.db});

  @override
  State<ModernHomeScreen> createState() => _ModernHomeScreenState();
}

class _ModernHomeScreenState extends State<ModernHomeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 7, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.1),
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(
                    context,
                  ).colorScheme.outline.withValues(alpha: 0.2),
                ),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.point_of_sale,
                    color: Theme.of(context).colorScheme.onPrimary,
                    size: 28,
                  ),
                ),
                const Gap(16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Gap(4),
                      Text(
                        'Developed by MO2',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.7),
                            ),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    // Notifications
                    IconButton(
                      icon: const Icon(Icons.notifications_outlined),
                      onPressed: () {},
                      tooltip: 'Notifications',
                    ),
                    const Gap(8),
                  ],
                ),
              ],
            ),
          ),

          // Tab Bar
          Container(
            margin: const EdgeInsets.all(16),
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
              isScrollable: true,
              labelColor: Theme.of(context).colorScheme.primary,
              unselectedLabelColor: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.6),
              indicator: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              tabs: [
                Tab(
                  icon: const Icon(Icons.dashboard_outlined),
                  text: l10n.dashboard,
                ),
                Tab(
                  icon: const Icon(Icons.shopping_bag_outlined),
                  text: l10n.products,
                ),
                Tab(
                  icon: const Icon(Icons.people_outline),
                  text: l10n.customer_list,
                ),
                Tab(
                  icon: const Icon(Icons.inventory_outlined),
                  text: l10n.suppliers,
                ),
                Tab(icon: const Icon(Icons.badge_outlined), text: 'الموظفين'),
                Tab(
                  icon: const Icon(Icons.account_balance_wallet_outlined),
                  text: l10n.cash,
                ),
                Tab(
                  icon: const Icon(Icons.analytics),
                  text: l10n.reports,
                ), // Added Reports tab
              ],
            ),
          ),

          // Tab Content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Control Panel - Simplified with functional buttons
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Gap(40),
                        const Text(
                          'لوحة التحكم',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Gap(40),
                        Wrap(
                          spacing: 20,
                          runSpacing: 20,
                          alignment: WrapAlignment.center,
                          children: [
                            // New Invoice Button
                            _buildLauncherButton(
                              context,
                              'فاتورة جديدة',
                              Icons.receipt_long,
                              Colors.blue,
                              () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        EnhancedNewInvoicePage(db: widget.db),
                                  ),
                                );
                              },
                            ),
                            // Add/Edit Customer Button
                            _buildLauncherButton(
                              context,
                              'العملاء',
                              Icons.person_add,
                              Colors.green,
                              () => _tabController.animateTo(2),
                            ),
                            // Add/Edit Product Button
                            _buildLauncherButton(
                              context,
                              'المنتجات',
                              Icons.inventory,
                              Colors.orange,
                              () => _tabController.animateTo(1),
                            ),
                            // Staff Management Button - Guarded
                            FeatureGuard(
                              featureName: 'staff_management',
                              lockedWidget: _buildLauncherButton(
                                context,
                                'الموظفين (مغلق)',
                                Icons.badge_outlined,
                                Colors.grey,
                                () => _tabController.animateTo(4),
                              ),
                              child: _buildLauncherButton(
                                context,
                                'الموظفين',
                                Icons.badge_outlined,
                                Colors.indigo,
                                () => _tabController.animateTo(4),
                              ),
                            ),
                            // Backup Button
                            _buildLauncherButton(
                              context,
                              'النسخ الاحتياطي',
                              Icons.backup,
                              Colors.purple,
                              () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        EnhancedBackupScreen(),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                        const Gap(40),
                      ],
                    ),
                  ),
                ),
                ProductScreen(db: widget.db),
                CustomerTransactionsWidget(db: widget.db),
                SuppliersWidget(db: widget.db),
                FeatureGuard(
                  featureName: 'staff_management',
                  child: const StaffListPage(),
                ),
                CashierPage(db: widget.db),
                ReportsPage(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLauncherButton(
    BuildContext context,
    String label,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return SizedBox(
      width: 180,
      height: 140,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 35),
        label: Text(label, style: const TextStyle(fontSize: 14)),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}
