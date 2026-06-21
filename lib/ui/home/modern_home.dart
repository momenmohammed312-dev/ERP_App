import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/provider/license_provider.dart';
import 'package:pos_offline_desktop/l10n/app_localizations.dart';
import 'package:pos_offline_desktop/ui/product/product.dart';
import 'package:pos_offline_desktop/ui/cashier/cashier_page.dart';
import 'package:pos_offline_desktop/ui/home/widgets/customer_transactions_widget.dart';
import 'package:pos_offline_desktop/ui/home/widgets/suppliers_widget.dart';
import 'package:pos_offline_desktop/ui/reports/reports_page.dart';
import 'package:pos_offline_desktop/ui/invoice/widgets/enhanced_new_invoice_page.dart';
import 'package:pos_offline_desktop/ui/backup/enhanced_backup_screen.dart';
import 'package:pos_offline_desktop/ui/staff/employee_dashboard_page.dart';
import 'package:pos_offline_desktop/ui/setting/settings.dart';
import 'package:pos_offline_desktop/widgets/license/feature_guard.dart';
import 'package:pos_offline_desktop/core/provider/auth_provider.dart';

class ModernHomeScreen extends ConsumerStatefulWidget {
  final AppDatabase db;
  const ModernHomeScreen({super.key, required this.db});

  @override
  ConsumerState<ModernHomeScreen> createState() => _ModernHomeScreenState();
}

class _ModernHomeScreenState extends ConsumerState<ModernHomeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  static const int _tabCount = 7;

  bool _licenseWarningShown = false;

  @override
  void initState() {
    super.initState();
    // Length MUST equal TabBar tabs count AND TabBarView children count
    _tabController = TabController(length: _tabCount, vsync: this);
    _checkLicenseWarning();
  }

  Future<void> _checkLicenseWarning() async {
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    final license = await ref.read(currentLicenseProvider.future);
    if (license != null &&
        !license.isExpired &&
        license.daysRemaining <= 5 &&
        !_licenseWarningShown &&
        mounted) {
      _licenseWarningShown = true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تنبيه: تبقى ${license.daysRemaining} أيام على انتهاء الترخيص. يرجى التجديد.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    final tabs = <Tab>[
      // Index 0
      Tab(icon: const Icon(Icons.dashboard_outlined), text: l10n.dashboard),
      // Index 1
      Tab(icon: const Icon(Icons.shopping_bag_outlined), text: l10n.products),
      // Index 2
      Tab(icon: const Icon(Icons.people_outline), text: l10n.customer_list),
      // Index 3
      Tab(icon: const Icon(Icons.inventory_outlined), text: l10n.suppliers),
      // Index 4
      const Tab(icon: Icon(Icons.badge_outlined), text: 'الموظفين'),
      // Index 5
      Tab(
        icon: const Icon(Icons.account_balance_wallet_outlined),
        text: l10n.cash,
      ),
      // Index 6
      Tab(icon: const Icon(Icons.analytics), text: l10n.reports),
    ];

    final tabViews = <Widget>[
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
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const Gap(40),
              Wrap(
                spacing: 20,
                runSpacing: 20,
                alignment: WrapAlignment.center,
                children: [
                  // New Invoice Button — Day Guard
                  _buildLauncherButton(
                    context,
                    'فاتورة جديدة',
                    Icons.receipt_long,
                    Colors.blue,
                    () async {
                      final isOpen = await widget.db.dayDao.isDayOpen();
                      if (!context.mounted) return;
                      if (!isOpen) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text(
                              'يجب فتح اليوم أولاً من تبويب الكاشير',
                            ),
                            backgroundColor: Colors.red,
                            action: SnackBarAction(
                              label: 'الذهاب للكاشير',
                              onPressed: () => _tabController.animateTo(5),
                            ),
                          ),
                        );
                        return;
                      }
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
                          builder: (context) => EnhancedBackupScreen(),
                        ),
                      );
                    },
                  ),
                  // Damaged Items Button
                  _buildLauncherButton(
                    context,
                    'الهالك',
                    Icons.delete_sweep,
                    Colors.redAccent,
                    () {
                      context.push('/damaged-items');
                    },
                  ),
                ],
              ),
              const Gap(40),
            ],
          ),
        ),
      ),
      // Index 1: Products
      ProductScreen(db: widget.db),
      // Index 2: Customers
      CustomerTransactionsWidget(db: widget.db),
      // Index 3: Suppliers
      SuppliersWidget(db: widget.db),
      // Index 4: Staff — Dashboard first
      FeatureGuard(
        featureName: 'staff_management',
        child: const EmployeeDashboardPage(),
      ),
      // Index 5: Cash
      const CashierPage(),
      // Index 6: Reports
      ReportsPage(),
    ];

    assert(
      _tabController.length == tabs.length && tabs.length == tabViews.length,
      'Tab mismatch: TabController.length (${_tabController.length}) must match '
      'TabBar tabs (${tabs.length}) and TabBarView children (${tabViews.length}).',
    );

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
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
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
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const _LicenseBadge(),
                    const Gap(8),
                    IconButton(
                      icon: const Icon(Icons.notifications_outlined),
                      onPressed: () {},
                      tooltip: 'Notifications',
                    ),
                    const Gap(4),
                    IconButton(
                      icon: const Icon(Icons.settings),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const SettingsScreen(),
                          ),
                        );
                      },
                      tooltip: 'الإعدادات',
                    ),
                    const Gap(4),
                    TextButton.icon(
                      icon: const Icon(Icons.logout, color: Colors.redAccent),
                      label: const Text(
                        'تسجيل خروج',
                        style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
                      ),
                      onPressed: () {
                        ref.read(authProvider.notifier).logout();
                        context.go('/login');
                      },
                    ),
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
              tabs: tabs,
            ),
          ),

          // Tab Content
          Expanded(
            child: TabBarView(controller: _tabController, children: tabViews),
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

/// Badge يعرض الأيام المتبقية على الترخيص — أخضر (>5) / برتقالي (<5) / أحمر (منتهي)
class _LicenseBadge extends ConsumerWidget {
  const _LicenseBadge();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final licenseAsync = ref.watch(currentLicenseProvider);

    return licenseAsync.when(
      data: (license) {
        if (license == null) return const SizedBox.shrink();

        final days = license.daysRemaining;
        final color = license.isExpired
            ? Colors.red
            : days <= 5
            ? Colors.orange
            : Colors.green;

        return Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _showLicenseDialog(context, license, days),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: color, width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      license.isExpired ? Icons.error : Icons.verified_user,
                      size: 18,
                      color: color,
                    ),
                    const Gap(6),
                    Text(
                      license.isExpired ? 'منتهي' : '$days يوم',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: color,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }

  void _showLicenseDialog(BuildContext context, dynamic license, int days) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حالة الترخيص'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('النوع: ${license.licenseType}'),
            Text('الشركة: ${license.companyName}'),
            Text(
              'انتهاء الصلاحية: ${license.expiryDate.toString().split(' ')[0]}',
            ),
            Text(
              'الأيام المتبقية: ${license.isExpired ? 0 : days}',
              style: TextStyle(
                color: license.isExpired ? Colors.red : Colors.green,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }
}
