import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/provider/app_database_provider.dart';
import 'package:pos_offline_desktop/core/services/auth_service.dart';
import 'package:pos_offline_desktop/l10n/l10n.dart';
import 'package:pos_offline_desktop/ui/user/user_management_page.dart';
import 'package:pos_offline_desktop/ui/backup/enhanced_backup_screen.dart';
import 'package:pos_offline_desktop/ui/cashier/cashier_page.dart';
import 'package:pos_offline_desktop/ui/customer/customer.dart';
import 'package:pos_offline_desktop/ui/dashboard/dashboard_page.dart';
import 'package:pos_offline_desktop/ui/setting/settings.dart';
import 'package:pos_offline_desktop/ui/invoice/invoice.dart';
import 'package:pos_offline_desktop/ui/invoice/new_invoice_page.dart';
import 'package:pos_offline_desktop/ui/invoice/widgets/enhanced_invoice_page.dart';
import 'package:pos_offline_desktop/ui/expense/expense_page.dart';
import 'package:pos_offline_desktop/ui/product/product.dart';
import 'package:pos_offline_desktop/ui/supplier/suppliers_page.dart';
import 'package:pos_offline_desktop/ui/purchase/purchase_page.dart';
import 'package:pos_offline_desktop/ui/admin/admin_dashboard_page.dart'
    as admin;
import 'package:pos_offline_desktop/ui/reports/reports_page.dart';
import 'package:pos_offline_desktop/ui/pages/sidebar_page.dart';
import 'package:pos_offline_desktop/ui/widgets/side_bar.dart';
import '../staff/staff_list_page.dart';

class HomeScreen extends StatefulHookConsumerWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  SideBarPage _selectedPage = SideBarPage.home;

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(appDatabaseProvider);
    final authService = ref.watch(authServiceProvider);

    return Scaffold(
      body: Row(
        children: [
          // Sidebar
          Container(
            width: 250,
            decoration: BoxDecoration(
              color: Colors.blueGrey[900],
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 4,
                  offset: Offset(2, 0),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Gap(40),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    context.l10n.brand_name,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                const Gap(30),
                Expanded(
                  child: SideBarMenu(
                    selectedPage: _selectedPage,
                    onPageSelected: (page) {
                      setState(() {
                        _selectedPage = page;
                      });
                    },
                  ),
                ),
                const Divider(color: Colors.white24, height: 1),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const Text(
                        'v2.1.0', // Updated version
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                      const Gap(4),
                      Text(
                        'Developed by MO2',
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 10,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Main Content Area
          Expanded(
            child: Container(
              color: Theme.of(context).colorScheme.surface,
              child: _buildPageContent(db, authService),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPageContent(AppDatabase db, AuthService authService) {
    switch (_selectedPage) {
      case SideBarPage.home:
        return const DashboardPage();
      case SideBarPage.products:
        return ProductScreen(db: db);
      case SideBarPage.customers:
        return const CustomerScreen();
      case SideBarPage.suppliers:
        return const SuppliersPage();
      case SideBarPage.invoice:
        return InvoiceScreen(db: db);
      case SideBarPage.newInvoice:
        return const NewInvoicePage();
      case SideBarPage.enhancedInvoice:
        return EnhancedInvoicePage(db: db);
      case SideBarPage.expenses:
        return ExpensePage(db: db);
      case SideBarPage.purchases:
        return PurchasePage(db: db);
      case SideBarPage.cashier:
        return CashierPage(db: db);
      case SideBarPage.reports:
        return const ReportsPage();
      case SideBarPage.users:
        return UserManagementPage(database: db, authService: authService);
      case SideBarPage.staff:
        return const StaffListPage();
      case SideBarPage.settings:
        return const SettingsScreen();
      case SideBarPage.backup:
        return EnhancedBackupScreen();
      case SideBarPage.admin:
        return const admin.AdminDashboardPage();
    }
  }
}
