import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/theme/madar_colors.dart';
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
    if (AppFeatures.hasSuppliersModule) {
      count++;
    }
    if (AppFeatures.hasStaffModule && !PlatformUtils.hidesStaffFeaturesOnMobile) {
      count++;
    }
    if (AppFeatures.hasCustodyModule) {
      count++;
    }
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
    if (AppFeatures.hasStaffModule && !PlatformUtils.hidesStaffFeaturesOnMobile) {
      index++;
    }
    return index;
  }

  /// Index of the Cashier tab (5 on mobile, 6 on desktop when preceding enabled).
  static int get cashierTabIndex {
    int index = 3; // after Dashboard(0), Products(1), Customers(2)
    if (AppFeatures.hasSuppliersModule) {
      index++;
    }
    if (AppFeatures.hasStaffModule && !PlatformUtils.hidesStaffFeaturesOnMobile) {
      index++;
    }
    if (AppFeatures.hasCustodyModule) {
      index++;
    }
    return index;
  }

  /// Index of the Reports tab.
  static int get reportsTabIndex => cashierTabIndex + 1;

  /// Returns the list of tabs formatted for [ModernHomeScreen].
  static List<Tab> buildTabs(AppLocalizations l10n) {
    return <Tab>[
      // Index 0
      Tab(
        icon: const Icon(Icons.dashboard_outlined, size: 18),
        text: l10n.dashboard,
        iconMargin: const EdgeInsets.only(bottom: 2),
        height: 48,
      ),
      // Index 1
      Tab(
        icon: const Icon(Icons.shopping_bag_outlined, size: 18),
        text: l10n.products,
        iconMargin: const EdgeInsets.only(bottom: 2),
        height: 48,
      ),
      // Index 2
      Tab(
        icon: const Icon(Icons.people_outline, size: 18),
        text: l10n.customer_list,
        iconMargin: const EdgeInsets.only(bottom: 2),
        height: 48,
      ),
      // Suppliers
      if (AppFeatures.hasSuppliersModule)
        Tab(
          icon: const Icon(Icons.inventory_outlined, size: 18),
          text: l10n.suppliers,
          iconMargin: const EdgeInsets.only(bottom: 2),
          height: 48,
        ),
      // Staff (desktop only, index 4)
      if (AppFeatures.hasStaffModule &&
          !PlatformUtils.hidesStaffFeaturesOnMobile)
        const Tab(
          icon: Icon(Icons.badge_outlined, size: 18),
          text: 'الموظفين',
          iconMargin: EdgeInsets.only(bottom: 2),
          height: 48,
        ),
      // Custody — index 4 on mobile, 5 on desktop
      if (AppFeatures.hasCustodyModule)
        const Tab(
          icon: Icon(Icons.account_balance_wallet_outlined, size: 18),
          text: 'العهد المالية',
          iconMargin: EdgeInsets.only(bottom: 2),
          height: 48,
        ),
      // Cash
      Tab(
        icon: const Icon(Icons.point_of_sale_outlined, size: 18),
        text: l10n.cash,
        iconMargin: const EdgeInsets.only(bottom: 2),
        height: 48,
      ),
      // Reports
      Tab(
        icon: const Icon(Icons.analytics, size: 18),
        text: l10n.reports,
        iconMargin: const EdgeInsets.only(bottom: 2),
        height: 48,
      ),
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
    final isDesktop = MediaQuery.of(context).size.width >= 800;

    final tabs = ModernHomeScreen.buildTabs(l10n);

    final tabViews = <Widget>[
      // Control Panel - Financial KPIs + Quick Action Strip
      Padding(
        padding: EdgeInsets.symmetric(
          horizontal: isDesktop ? 24 : 12,
          vertical: isDesktop ? 16 : 12,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Financial KPIs
              _DashboardSummary(db: widget.db),
              Gap(isDesktop ? 20 : 14),
              // Sleek Quick Action Strip (3 core buttons: New Invoice, Customers, Products)
              _buildQuickActionStrip(context),
              // Flavor-specific modules (if enabled)
              if (AppFeatures.hasManufacturing ||
                  AppFeatures.hasEmptyContainerTracking ||
                  AppFeatures.hasShipmentTracking ||
                  AppFeatures.hasDamagedModule) ...[
                Gap(isDesktop ? 20 : 14),
                _buildFlavorActionGrid(context),
              ],
              Gap(isDesktop ? 24 : 16),
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
      appBar: _buildUnifiedHeader(context, tabs, isDesktop),
      body: TabBarView(
        controller: _tabController,
        children: tabViews,
      ),
    );
  }

  /// Unified 62-64px App Header on Desktop / Tablet (merges Logo, Title, TabBar & Actions into one sleek bar)
  PreferredSizeWidget _buildUnifiedHeader(
    BuildContext context,
    List<Tab> tabs,
    bool isDesktop,
  ) {
    return PreferredSize(
      preferredSize: Size.fromHeight(isDesktop ? 64 : 104),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.15),
            ),
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: isDesktop
              ? SizedBox(
                  height: 64,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        // Brand Logo + Title
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Builder(
                              builder: (ctx) {
                                final isLight = Theme.of(ctx).brightness == Brightness.light;
                                return Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: isLight ? MadarColors.lightBgCard : MadarColors.bgDark,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isLight
                                          ? MadarColors.lightBorder
                                          : MadarColors.border.withValues(alpha: 0.6),
                                    ),
                                  ),
                                  child: isLight
                                      ? ShaderMask(
                                          shaderCallback: (bounds) => const LinearGradient(
                                            begin: Alignment.bottomCenter,
                                            end: Alignment.topCenter,
                                            colors: [
                                              Color(0xFF0A2540),
                                              Color(0xFF0066FF),
                                              Color(0xFF38BDF8),
                                            ],
                                          ).createShader(bounds),
                                          blendMode: BlendMode.srcIn,
                                          child: Image.asset(
                                            'assets/logo/app_logo.png',
                                            width: 28,
                                            height: 28,
                                            fit: BoxFit.contain,
                                            errorBuilder: (c, err, st) => const Icon(
                                              Icons.point_of_sale,
                                              color: MadarColors.lightPrimary,
                                              size: 24,
                                            ),
                                          ),
                                        )
                                      : Image.asset(
                                          'assets/logo/app_logo.png',
                                          width: 28,
                                          height: 28,
                                          fit: BoxFit.contain,
                                          errorBuilder: (c, err, st) => const Icon(
                                            Icons.point_of_sale,
                                            color: MadarColors.gold,
                                            size: 24,
                                          ),
                                        ),
                                );
                              },
                            ),
                            const SizedBox(width: 10),
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'مدار ERP',
                                  style: TextStyle(
                                    fontFamily: 'NotoSansArabic',
                                    fontSize: 15,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                Text(
                                  'Developed by MO2',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w500,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface
                                        .withValues(alpha: 0.5),
                                    letterSpacing: 0.6,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),

                        const SizedBox(width: 16),
                        Container(
                          width: 1,
                          height: 24,
                          color: Theme.of(context)
                              .colorScheme
                              .outline
                              .withValues(alpha: 0.2),
                        ),
                        const SizedBox(width: 12),

                        // Integrated Unified TabBar (compact pills)
                        Expanded(
                          child: TabBar(
                            controller: _tabController,
                            isScrollable: true,
                            tabAlignment: TabAlignment.start,
                            indicatorSize: TabBarIndicatorSize.tab,
                            dividerColor: Colors.transparent,
                            indicator: BoxDecoration(
                              color: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withValues(alpha: 0.35),
                              ),
                            ),
                            labelColor: Theme.of(context).colorScheme.primary,
                            unselectedLabelColor: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.65),
                            padding: EdgeInsets.zero,
                            labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                            tabs: tabs,
                          ),
                        ),

                        const SizedBox(width: 12),

                        // Actions
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const _LicenseBadge(),
                            const SizedBox(width: 6),
                            IconButton(
                              icon: const Icon(Icons.cloud_sync_rounded, size: 20),
                              onPressed: () => context.push('/backup'),
                              tooltip: 'النسخ الاحتياطي (Google Drive & محلي)',
                            ),
                            IconButton(
                              icon: const Icon(Icons.settings_outlined, size: 20),
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
                            IconButton(
                              icon: const Icon(Icons.logout, size: 20, color: Colors.redAccent),
                              tooltip: 'تسجيل خروج',
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
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Top Bar for Mobile
                    SizedBox(
                      height: 54,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: [
                            Image.asset(
                              'assets/logo/app_logo.png',
                              width: 26,
                              height: 26,
                              fit: BoxFit.contain,
                              errorBuilder: (ctx, err, st) => const Icon(
                                Icons.point_of_sale,
                                color: MadarColors.gold,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'مدار ERP',
                              style: TextStyle(
                                fontFamily: 'NotoSansArabic',
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            const _LicenseBadge(),
                            IconButton(
                              icon: const Icon(Icons.settings_outlined, size: 20),
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const SettingsScreen(),
                                  ),
                                );
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.logout, size: 20, color: Colors.redAccent),
                              onPressed: () {
                                ref.read(authProvider.notifier).logout();
                                context.go('/login');
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Mobile Scrollable TabBar
                    SizedBox(
                      height: 48,
                      child: TabBar(
                        controller: _tabController,
                        isScrollable: true,
                        tabAlignment: TabAlignment.start,
                        indicatorSize: TabBarIndicatorSize.tab,
                        dividerColor: Colors.transparent,
                        indicator: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        labelColor: Theme.of(context).colorScheme.primary,
                        unselectedLabelColor: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.6),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        tabs: tabs,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  /// Horizontal Quick Action Strip (New Invoice, Customers, Products)
  Widget _buildQuickActionStrip(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 720;

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
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: MadarColors.gold.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.bolt_rounded, size: 16, color: MadarColors.gold),
              ),
              const SizedBox(width: 10),
              const Text(
                'الإجراءات السريعة',
                style: TextStyle(
                  fontFamily: 'NotoSansArabic',
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (isDesktop)
            Row(
              children: [
                Expanded(
                  child: _buildActionStripButton(
                    context,
                    title: 'فاتورة جديدة',
                    subtitle: 'إنشاء وطباعة فاتورة بيع',
                    icon: Icons.receipt_long_rounded,
                    color: MadarColors.gold,
                    onTap: _onNewInvoiceTap,
                    isPrimary: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildActionStripButton(
                    context,
                    title: 'العملاء',
                    subtitle: 'إدارة وتتبع حسابات العملاء',
                    icon: Icons.people_alt_rounded,
                    color: const Color(0xFF388BFD),
                    onTap: () => _tabController.animateTo(2),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildActionStripButton(
                    context,
                    title: 'المنتجات',
                    subtitle: 'المخزون والأسعار والأصناف',
                    icon: Icons.inventory_2_rounded,
                    color: const Color(0xFF238636),
                    onTap: () => _tabController.animateTo(1),
                  ),
                ),
              ],
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildActionStripButton(
                  context,
                  title: 'فاتورة جديدة',
                  subtitle: 'إنشاء وطباعة فاتورة بيع',
                  icon: Icons.receipt_long_rounded,
                  color: MadarColors.gold,
                  onTap: _onNewInvoiceTap,
                  isPrimary: true,
                ),
                const SizedBox(height: 10),
                _buildActionStripButton(
                  context,
                  title: 'العملاء',
                  subtitle: 'إدارة وتتبع حسابات العملاء',
                  icon: Icons.people_alt_rounded,
                  color: const Color(0xFF388BFD),
                  onTap: () => _tabController.animateTo(2),
                ),
                const SizedBox(height: 10),
                _buildActionStripButton(
                  context,
                  title: 'المنتجات',
                  subtitle: 'المخزون والأسعار والأصناف',
                  icon: Icons.inventory_2_rounded,
                  color: const Color(0xFF238636),
                  onTap: () => _tabController.animateTo(1),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildActionStripButton(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    bool isPrimary = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: isPrimary
                ? color.withValues(alpha: 0.12)
                : Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isPrimary
                  ? color.withValues(alpha: 0.4)
                  : Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
              width: isPrimary ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontFamily: 'NotoSansArabic',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontFamily: 'NotoSansArabic',
                        fontSize: 11,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.55),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
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

  Future<void> _onNewInvoiceTap() async {
    final isOpen = await widget.db.dayDao.isDayOpen();
    if (!mounted) return;
    if (!isOpen) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'يجب فتح اليوم أولاً من تبويب الكاشير',
            style: TextStyle(fontFamily: 'NotoSansArabic'),
          ),
          backgroundColor: Colors.red,
          action: SnackBarAction(
            label: 'الذهاب للكاشير',
            textColor: Colors.white,
            onPressed: () => _tabController.animateTo(_cashierTabIndex),
          ),
        ),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EnhancedNewInvoicePage(db: widget.db),
      ),
    );
  }

  /// Secondary grid for active flavor modules (Barneka, Shipments, Manufacturing, Damaged Goods)
  Widget _buildFlavorActionGrid(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        if (AppFeatures.hasDamagedModule)
          FeatureGuard(
            featureName: 'damaged_goods',
            lockedWidget: _buildFlavorChip(
              context,
              'الهالك (مغلق)',
              Icons.delete_sweep,
              Colors.grey,
              () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('موديول الهوالك والتوالف غير مفعّل في ترخيصك.'),
                    backgroundColor: Colors.orange,
                  ),
                );
              },
            ),
            child: _buildFlavorChip(
              context,
              'الهالك',
              Icons.delete_sweep,
              Colors.redAccent,
              () => context.push('/damaged-items'),
            ),
          ),
        if (AppFeatures.hasManufacturing)
          FeatureGuard(
            featureName: 'manufacturing',
            lockedWidget: _buildFlavorChip(
              context,
              'التصنيع (مغلق)',
              Icons.precision_manufacturing_outlined,
              Colors.grey,
              () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('موديول التصنيع غير متاح في ترخيصك الحالي.'),
                    backgroundColor: Colors.orange,
                  ),
                );
              },
            ),
            child: _buildFlavorChip(
              context,
              'التصنيع',
              Icons.precision_manufacturing_outlined,
              Colors.deepOrange,
              () => context.push('/manufacturing/orders'),
            ),
          ),
        if (AppFeatures.hasEmptyContainerTracking)
          _buildFlavorChip(
            context,
            'البرنيكه',
            Icons.eco,
            Colors.teal,
            () => context.push('/barneka'),
          ),
        if (AppFeatures.hasShipmentTracking)
          _buildFlavorChip(
            context,
            'الشحنات',
            Icons.local_shipping,
            Colors.amber.shade800,
            () => context.push('/shipments'),
          ),
        if (AppFeatures.hasEmptyContainerTracking)
          _buildFlavorChip(
            context,
            'البرانيك المستحقة',
            Icons.assignment_return,
            Colors.teal.shade700,
            () => context.push('/empty-barnika'),
          ),
        if (AppFeatures.hasShipmentTracking)
          _buildFlavorChip(
            context,
            'مديونيات العملاء',
            Icons.account_balance_wallet,
            Colors.red.shade700,
            () => context.push('/customer-debts'),
          ),
        if (AppFeatures.hasShipmentTracking)
          _buildFlavorChip(
            context,
            'استيراد إكسل',
            Icons.table_chart,
            Colors.purple,
            () => context.push('/excel-import'),
          ),
      ],
    );
  }

  Widget _buildFlavorChip(
    BuildContext context,
    String label,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return ActionChip(
      avatar: Icon(icon, size: 16, color: color),
      label: Text(label, style: const TextStyle(fontFamily: 'NotoSansArabic', fontSize: 12.5)),
      onPressed: onTap,
      backgroundColor: color.withValues(alpha: 0.1),
      side: BorderSide(color: color.withValues(alpha: 0.3)),
    );
  }
}

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
        height: 80,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    final isDesktop = MediaQuery.of(context).size.width >= 720;
    final netProfit = _todaySales - _todayPurchases - _todayExpenses;

    if (isDesktop) {
      final baseCardsRow = Row(
        children: [
          Expanded(
            child: _buildCard(
              context,
              'مبيعات اليوم',
              _todaySales,
              Colors.green,
              Icons.trending_up,
              isMobile: false,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildCard(
              context,
              'مشتريات',
              _todayPurchases,
              Colors.orange,
              Icons.shopping_cart,
              isMobile: false,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildCard(
              context,
              'مصروفات',
              _todayExpenses,
              Colors.redAccent,
              Icons.receipt_long,
              isMobile: false,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildCard(
              context,
              'صافي الربح',
              netProfit,
              netProfit >= 0 ? Colors.blue : Colors.red,
              Icons.account_balance,
              isMobile: false,
            ),
          ),
        ],
      );

      if (!AppFeatures.hasShipmentTracking) {
        return SizedBox(height: 100, child: baseCardsRow);
      }

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
                    context,
                    'برانيك بالمخزن',
                    _remainingBarnikas.toDouble(),
                    Colors.teal,
                    Icons.eco,
                    isMobile: false,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildCard(
                    context,
                    'مديونيات آجل',
                    _receivablesDue,
                    Colors.deepPurple,
                    Icons.account_balance_wallet,
                    isMobile: false,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildCard(
                    context,
                    'كاش متوقع',
                    _expectedCash,
                    Colors.indigo,
                    Icons.payments,
                    isMobile: false,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildCard(
                    context,
                    'مستحق للموردين',
                    _supplierCommissionDue,
                    Colors.brown,
                    Icons.storefront,
                    isMobile: false,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    // Mobile / Compact Layout: exactly 4 core cards (Sales, Net Profit, Purchases, Expenses)
    final mobileCards = <Widget>[
      _buildCard(
        context,
        'مبيعات اليوم',
        _todaySales,
        Colors.green,
        Icons.trending_up,
        isMobile: true,
      ),
      _buildCard(
        context,
        'صافي الربح',
        netProfit,
        netProfit >= 0 ? Colors.blue : Colors.red,
        Icons.account_balance,
        isMobile: true,
      ),
      _buildCard(
        context,
        'مشتريات',
        _todayPurchases,
        Colors.orange,
        Icons.shopping_cart,
        isMobile: true,
      ),
      _buildCard(
        context,
        'مصروفات',
        _todayExpenses,
        Colors.redAccent,
        Icons.receipt_long,
        isMobile: true,
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: mobileCards.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        mainAxisExtent: 68,
      ),
      itemBuilder: (context, index) => mobileCards[index],
    );
  }

  Widget _buildCard(
    BuildContext context,
    String label,
    double amount,
    Color color,
    IconData icon, {
    required bool isMobile,
  }) {
    if (isMobile) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      amount.toStringAsFixed(2),
                      style: TextStyle(
                        fontFamily: 'NotoSansArabic',
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'NotoSansArabic',
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.75),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

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
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              amount.toStringAsFixed(2),
              style: TextStyle(
                fontFamily: 'NotoSansArabic',
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'NotoSansArabic',
              fontSize: 11,
              color: color.withValues(alpha: 0.8),
            ),
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
