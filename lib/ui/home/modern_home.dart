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
import 'package:pos_offline_desktop/ui/staff/employee_dashboard_page.dart';
import 'package:pos_offline_desktop/ui/custody/custody_page.dart';
import 'package:pos_offline_desktop/ui/setting/settings.dart';
import 'package:pos_offline_desktop/widgets/license/feature_guard.dart';
import 'package:pos_offline_desktop/core/provider/auth_provider.dart';
import 'package:pos_offline_desktop/core/config/app_features.dart';
import 'package:pos_offline_desktop/core/platform/platform_utils.dart';
import 'package:pos_offline_desktop/core/services/business_date_service.dart';
import 'package:drift/drift.dart' as drift;

class ModernHomeScreen extends ConsumerStatefulWidget {
  final AppDatabase db;
  const ModernHomeScreen({super.key, required this.db});

  /// Dynamic tab count based on platform (7 on mobile, 8 on desktop when all modules enabled).
  static int get tabCount {
    int count = 5; // Dashboard, Products, Customers, Cash, Reports
    if (AppFeatures.hasSuppliersModule) count++;
    if (AppFeatures.hasStaffModule && !PlatformUtils.hidesStaffFeaturesOnMobile)
      count++;
    if (AppFeatures.hasCustodyModule) count++;
    return count;
  }

  /// Index of the Products tab (1 on both desktop and mobile).
  static int get productsTabIndex => 1;

  /// Index of the Customers tab (2 on both desktop and mobile).
  static int get customersTabIndex => 2;

  /// Index of the Suppliers tab (3 on both desktop and mobile).
  static int get suppliersTabIndex => 3;

  /// Index of the Staff tab (null on mobile, 4 on desktop when enabled).
  static int? get staffTabIndex =>
      (!AppFeatures.hasStaffModule || PlatformUtils.hidesStaffFeaturesOnMobile)
      ? null
      : 4;

  /// Index of the Custody tab (4 on mobile, 5 on desktop when preceding enabled).
  static int get custodyTabIndex {
    int index =
        4; // after Dashboard(0), Products(1), Customers(2), Suppliers(3)
    if (AppFeatures.hasStaffModule && !PlatformUtils.hidesStaffFeaturesOnMobile)
      index++;
    return index;
  }

  /// Index of the Cashier tab (5 on mobile, 6 on desktop when preceding enabled).
  static int get cashierTabIndex {
    int index = 3; // after Dashboard(0), Products(1), Customers(2)
    if (AppFeatures.hasSuppliersModule) index++;
    if (AppFeatures.hasStaffModule && !PlatformUtils.hidesStaffFeaturesOnMobile)
      index++;
    if (AppFeatures.hasCustodyModule) index++;
    return index;
  }

  /// Index of the Reports tab.
  static int get reportsTabIndex => cashierTabIndex + 1;

  /// Returns the list of tabs formatted for [ModernHomeScreen].
  static List<Tab> buildTabs(AppLocalizations l10n) {
    return <Tab>[
      // Index 0
      Tab(icon: const Icon(Icons.dashboard_outlined), text: l10n.dashboard),
      // Index 1
      Tab(icon: const Icon(Icons.shopping_bag_outlined), text: l10n.products),
      // Index 2
      Tab(icon: const Icon(Icons.people_outline), text: l10n.customer_list),
      // Suppliers
      if (AppFeatures.hasSuppliersModule)
        Tab(icon: const Icon(Icons.inventory_outlined), text: l10n.suppliers),
      // Staff (desktop only, index 4)
      if (AppFeatures.hasStaffModule &&
          !PlatformUtils.hidesStaffFeaturesOnMobile)
        const Tab(icon: Icon(Icons.badge_outlined), text: 'الموظفين'),
      // Custody — index 4 on mobile, 5 on desktop
      if (AppFeatures.hasCustodyModule)
        const Tab(
          icon: Icon(Icons.account_balance_wallet_outlined),
          text: 'العهد المالية',
        ),
      // Cash
      Tab(icon: const Icon(Icons.point_of_sale_outlined), text: l10n.cash),
      // Reports
      Tab(icon: const Icon(Icons.analytics), text: l10n.reports),
    ];
  }

  @override
  ConsumerState<ModernHomeScreen> createState() => _ModernHomeScreenState();
}

class _ModernHomeScreenState extends ConsumerState<ModernHomeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  int get _tabCount => ModernHomeScreen.tabCount;
  int get _cashierTabIndex => ModernHomeScreen.cashierTabIndex;

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

    final tabs = ModernHomeScreen.buildTabs(l10n);

    final tabViews = <Widget>[
      // Control Panel - Simplified with functional buttons
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Gap(24),
              // Financial KPIs
              _DashboardSummary(db: widget.db),
              const Gap(24),
              const Text(
                'لوحة التحكم',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const Gap(24),
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
                              onPressed: () =>
                                  _tabController.animateTo(_cashierTabIndex),
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
                  // Backup Launcher Button
                  _buildLauncherButton(
                    context,
                    'النسخ الاحتياطي',
                    Icons.cloud_sync_rounded,
                    const Color(0xFF1F6FEB),
                    () => context.push('/backup'),
                  ),
                  // Staff Management Button - Guarded + hidden without module
                  if (AppFeatures.hasStaffModule)
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
                  // Custody Button — العهد المالية
                  if (AppFeatures.hasCustodyModule)
                    FeatureGuard(
                      featureName: 'custody',
                      lockedWidget: _buildLauncherButton(
                        context,
                        'العهد المالية (مغلق)',
                        Icons.account_balance_wallet_outlined,
                        Colors.grey,
                        () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'موديول العهد المالية غير مفعّل في ترخيصك. تواصل مع الإدارة لتفعيله.',
                              ),
                              backgroundColor: Colors.orange,
                            ),
                          );
                        },
                      ),
                      child: _buildLauncherButton(
                        context,
                        'العهد المالية',
                        Icons.account_balance_wallet_outlined,
                        Colors.teal.shade700,
                        () {
                          int index = 3;
                          if (AppFeatures.hasSuppliersModule) index++;
                          if (AppFeatures.hasStaffModule) index++;
                          _tabController.animateTo(index);
                        },
                      ),
                    ),
                  // Damaged Items Button — الهوالك والتوالف
                  if (AppFeatures.hasDamagedModule)
                    FeatureGuard(
                      featureName: 'damaged_goods',
                      lockedWidget: _buildLauncherButton(
                        context,
                        'الهالك (مغلق)',
                        Icons.delete_sweep,
                        Colors.grey,
                        () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'موديول الهوالك والتوالف غير مفعّل في ترخيصك. تواصل مع الإدارة لتفعيله.',
                              ),
                              backgroundColor: Colors.orange,
                            ),
                          );
                        },
                      ),
                      child: _buildLauncherButton(
                        context,
                        'الهالك',
                        Icons.delete_sweep,
                        Colors.redAccent,
                        () {
                          context.push('/damaged-items');
                        },
                      ),
                    ),
                  // Manufacturing Button — BOM, production orders and scrap.
                  // Pushed as its own route rather than a tab, so the tab count
                  // and every index above stay exactly as they are for the
                  // base and vegetable flavors.
                  //
                  // BUG-018: this launcher had NO FeatureGuard at all — only
                  // the flavor check below — so a basic-license customer was
                  // one tap from BOMs and work orders.
                  if (AppFeatures.hasManufacturing)
                    FeatureGuard(
                      featureName: 'manufacturing',
                      lockedWidget: _buildLauncherButton(
                        context,
                        'التصنيع (مغلق)',
                        Icons.precision_manufacturing_outlined,
                        Colors.grey,
                        () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'موديول التصنيع غير متاح في ترخيصك الحالي. '
                                'للترقية تواصل معنا.',
                              ),
                              backgroundColor: Colors.orange,
                            ),
                          );
                        },
                      ),
                      child: _buildLauncherButton(
                        context,
                        'التصنيع',
                        Icons.precision_manufacturing_outlined,
                        Colors.deepOrange,
                        () {
                          context.push('/manufacturing/orders');
                        },
                      ),
                    ),
                  // Barneka (Returnable Containers) Button — vegetable-market
                  // feature, hidden in the factory (base) flavor.
                  if (AppFeatures.hasEmptyContainerTracking)
                    _buildLauncherButton(
                      context,
                      'البرنيكه',
                      Icons.eco,
                      Colors.teal,
                      () {
                        context.push('/barneka');
                      },
                    ),
                  if (AppFeatures.hasShipmentTracking)
                    _buildLauncherButton(
                      context,
                      'الشحنات',
                      Icons.local_shipping,
                      Colors.amber.shade800,
                      () {
                        context.push('/shipments');
                      },
                    ),
                  if (AppFeatures.hasEmptyContainerTracking)
                    _buildLauncherButton(
                      context,
                      'البرانيك المستحقة',
                      Icons.assignment_return,
                      Colors.teal.shade700,
                      () {
                        context.push('/empty-barnika');
                      },
                    ),

                  if (AppFeatures.hasShipmentTracking)
                    _buildLauncherButton(
                      context,
                      'مديونيات العملاء',
                      Icons.account_balance_wallet,
                      Colors.red.shade700,
                      () {
                        context.push('/customer-debts');
                      },
                    ),
                  if (AppFeatures.hasShipmentTracking)
                    _buildLauncherButton(
                      context,
                      'استيراد إكسل',
                      Icons.table_chart,
                      Colors.purple,
                      () {
                        context.push('/excel-import');
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
      // Suppliers
      if (AppFeatures.hasSuppliersModule) SuppliersWidget(db: widget.db),
      // Staff — Dashboard first (absent without the module; cash/reports
      // indices shift accordingly and _cashierTabIndex tracks it).
      if (AppFeatures.hasStaffModule &&
          !PlatformUtils.hidesStaffFeaturesOnMobile)
        FeatureGuard(
          featureName: 'staff_management',
          child: const EmployeeDashboardPage(),
        ),
      // Custody
      if (AppFeatures.hasCustodyModule)
        FeatureGuard(
          featureName: 'custody',
          child: CustodyPage(db: widget.db),
        ),
      // Cash
      const CashierPage(),
      // Reports
      ReportsPage(),
    ];

    assert(
      _tabController.length == tabs.length && tabs.length == tabViews.length,
      'Tab mismatch: TabController.length (${_tabController.length}) must match '
      'TabBar tabs (${tabs.length}) and TabBarView children (${tabViews.length}).',
    );

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: _buildAppBar(context),
      body: Column(
        children: [
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

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    final isMobile = PlatformUtils.isMobile;

    return AppBar(
      automaticallyImplyLeading: false,
      centerTitle: false,
      backgroundColor: Theme.of(
        context,
      ).colorScheme.primary.withValues(alpha: 0.1),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: isMobile ? 56 : 92,
      titleSpacing: isMobile ? 12 : 20,
      shape: Border(
        bottom: BorderSide(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: EdgeInsets.all(isMobile ? 4 : 6),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(isMobile ? 8 : 12),
              border: Border.all(
                color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(isMobile ? 6 : 8),
              child: Image.asset(
                'assets/logo/app_logo.png',
                width: isMobile ? 32 : 44,
                height: isMobile ? 32 : 44,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => Icon(
                  Icons.point_of_sale,
                  color: Theme.of(context).colorScheme.primary,
                  size: isMobile ? 24 : 32,
                ),
              ),
            ),
          ),
          Gap(isMobile ? 10 : 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'مدار ERP',
                style: (isMobile
                        ? Theme.of(context).textTheme.titleMedium
                        : Theme.of(context).textTheme.headlineSmall)
                    ?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              const Gap(1),
              Text(
                'Developed by MO2',
                style: (isMobile
                        ? Theme.of(context).textTheme.bodySmall
                        : Theme.of(context).textTheme.labelSmall)
                    ?.copyWith(
                  fontSize: isMobile ? 10 : 11,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.55),
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        Padding(
          padding: EdgeInsetsDirectional.only(end: isMobile ? 12 : 20),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const _LicenseBadge(),
              Gap(isMobile ? 4 : 8),
              IconButton(
                icon: const Icon(Icons.cloud_sync_rounded),
                onPressed: () => context.push('/backup'),
                tooltip: 'النسخ الاحتياطي (Google Drive & محلي)',
              ),
              Gap(isMobile ? 2 : 4),
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
              Gap(isMobile ? 2 : 4),
              if (isMobile)
                IconButton(
                  icon: const Icon(Icons.logout, color: Colors.redAccent),
                  tooltip: 'تسجيل خروج',
                  onPressed: () {
                    ref.read(authProvider.notifier).logout();
                    context.go('/login');
                  },
                )
              else
                TextButton.icon(
                  icon: const Icon(Icons.logout, color: Colors.redAccent),
                  label: const Text(
                    'تسجيل خروج',
                    style: TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onPressed: () {
                    ref.read(authProvider.notifier).logout();
                    context.go('/login');
                  },
                ),
            ],
          ),
        ),
      ],
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

/// ملخص مالي سريع يعرض مبيعات ومصروفات وأرباح اليوم
class _DashboardSummary extends ConsumerStatefulWidget {
  final AppDatabase db;
  const _DashboardSummary({required this.db});

  @override
  ConsumerState<_DashboardSummary> createState() => _DashboardSummaryState();
}

class _DashboardSummaryState extends ConsumerState<_DashboardSummary> {
  double _todaySales = 0;
  double _todayExpenses = 0;
  double _todayPurchases = 0;
  bool _isLoading = true;

  // Vegetable-flavor cards (gated behind AppFeatures.hasShipmentTracking)
  int _remainingBarnikas = 0;
  double _receivablesDue = 0;
  double _expectedCash = 0;
  double _supplierCommissionDue = 0;

  @override
  void initState() {
    super.initState();
    _loadTodayData();
  }

  Future<void> _loadTodayData() async {
    try {
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day);
      final end = DateTime(now.year, now.month, now.day, 23, 59, 59);

      final salesResult = await widget.db
          .customSelect(
            '''
        SELECT COALESCE(SUM(total_amount), 0) as total
        FROM invoices WHERE date BETWEEN ? AND ? AND status != 'voided'
      ''',
            variables: [
              drift.Variable.withDateTime(start),
              drift.Variable.withDateTime(end),
            ],
          )
          .get();
      final todaySales =
          (salesResult.first.data['total'] as num?)?.toDouble() ?? 0;

      final expenseResult = await widget.db
          .customSelect(
            '''
        SELECT COALESCE(SUM(amount), 0) as total
        FROM expenses WHERE date BETWEEN ? AND ?
      ''',
            variables: [
              drift.Variable.withDateTime(start),
              drift.Variable.withDateTime(end),
            ],
          )
          .get();
      final todayExpenses =
          (expenseResult.first.data['total'] as num?)?.toDouble() ?? 0;

      final purchaseResult = await widget.db
          .customSelect(
            '''
        SELECT COALESCE(SUM(total_amount), 0) as total
        FROM purchases WHERE purchase_date BETWEEN ? AND ? AND is_deleted = 0
      ''',
            variables: [
              drift.Variable.withDateTime(start),
              drift.Variable.withDateTime(end),
            ],
          )
          .get();
      final todayPurchases =
          (purchaseResult.first.data['total'] as num?)?.toDouble() ?? 0;

      // Vegetable-flavor cards — بتتقرأ بس لما feature الشحنات مفعّل
      int remainingBarnikas = 0;
      double receivablesDue = 0;
      double expectedCash = 0;
      double supplierCommissionDue = 0;

      if (AppFeatures.hasShipmentTracking) {
        remainingBarnikas = await widget.db.vegetableShipmentDao
            .getTotalRemainingBarnikas();
        receivablesDue = await widget.db.ledgerDao.getTotalReceivables();
        expectedCash = await BusinessDateService(widget.db).getExpectedCash();
        supplierCommissionDue = await widget.db.ledgerDao
            .getSupplierCommissionDue();
      }

      if (mounted) {
        setState(() {
          _todaySales = todaySales;
          _todayExpenses = todayExpenses;
          _todayPurchases = todayPurchases;
          _remainingBarnikas = remainingBarnikas;
          _receivablesDue = receivablesDue;
          _expectedCash = expectedCash;
          _supplierCommissionDue = supplierCommissionDue;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
        height: 100,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final netProfit = _todaySales - _todayPurchases - _todayExpenses;
    final baseCardsRow = Row(
      children: [
        Expanded(
          child: _buildCard(
            'مبيعات اليوم',
            _todaySales,
            Colors.green,
            Icons.trending_up,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildCard(
            'مشتريات',
            _todayPurchases,
            Colors.orange,
            Icons.shopping_cart,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildCard(
            'مصروفات',
            _todayExpenses,
            Colors.redAccent,
            Icons.receipt_long,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildCard(
            'صافي الربح',
            netProfit,
            netProfit >= 0 ? Colors.blue : Colors.red,
            Icons.account_balance,
          ),
        ),
      ],
    );

    // الأصل (base flavor) بيشوف الكروت الأربعة بس زي ما هو
    if (!AppFeatures.hasShipmentTracking) {
      return SizedBox(height: 100, child: baseCardsRow);
    }

    // Vegetable flavor: الكروت الأربعة الحالية + 4 كروت جديدة لتحتها
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: 100, child: baseCardsRow),
        const SizedBox(height: 8),
        SizedBox(
          height: 100,
          child: Row(
            children: [
              Expanded(
                child: _buildCard(
                  'برانيك متبقية بالمخزن',
                  _remainingBarnikas.toDouble(),
                  Colors.teal,
                  Icons.eco,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildCard(
                  'مديونيات آجل مستحقة اليوم',
                  _receivablesDue,
                  Colors.deepPurple,
                  Icons.account_balance_wallet,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildCard(
                  'صافي كاش متوقع لسه ما اتقفلش',
                  _expectedCash,
                  Colors.indigo,
                  Icons.payments,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildCard(
                  'مستحق للموردين',
                  _supplierCommissionDue,
                  Colors.brown,
                  Icons.storefront,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCard(String label, double amount, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(
            amount.toStringAsFixed(2),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: color.withValues(alpha: 0.8)),
          ),
        ],
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
          padding: const EdgeInsetsDirectional.only(start: 8),
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
