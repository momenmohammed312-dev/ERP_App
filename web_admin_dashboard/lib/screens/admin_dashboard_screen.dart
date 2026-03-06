import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../utils/constants.dart';
import '../widgets/dashboard_overview.dart';
import '../widgets/customer_management.dart';
import '../widgets/licenses_management.dart';
import '../widgets/revenue_dashboard.dart';
import '../services/data_service.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  int _selectedIndex = 0;
  final DataService _dataService = DataService();

  final List<NavigationItem> _navigationItems = [
    NavigationItem(
      icon: Icons.dashboard,
      title: 'نظرة عامة',
      route: '/overview',
    ),
    NavigationItem(
      icon: Icons.people,
      title: 'العملاء',
      route: '/clients',
    ),
    NavigationItem(
      icon: Icons.key,
      title: 'التراخيص',
      route: '/licenses',
    ),
    NavigationItem(
      icon: Icons.attach_money,
      title: 'الإيرادات',
      route: '/revenue',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _dataService.init();
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 1200;

    return Scaffold(
      backgroundColor: AppColors.backgroundColor,
      appBar: AppBar(
        leading: isDesktop
            ? null
            : Builder(
                builder: (context) => IconButton(
                  icon: const Icon(Icons.menu, color: Colors.white),
                  onPressed: () => Scaffold.of(context).openDrawer(),
                ),
              ),
        title: const Text(
          AppStrings.appName,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: AppColors.primaryColor,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications, color: Colors.white),
            onPressed: () {
              _showExpiringLicensesDialog();
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (value) {
              if (value == 'logout') {
                _logout();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, color: Colors.red),
                    SizedBox(width: 8),
                    Text('تسجيل الخروج'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      drawer: isDesktop ? null : _buildDrawer(),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Row(
          children: [
            // Sidebar (Desktop)
            if (isDesktop) _buildSidebar(),
            // Main Content
            Expanded(
              child: _buildSelectedPage(),
            ),
          ],
        ),
      ),
      // Bottom Navigation Removed for true sidebar/drawer feel if preferred,
      // but keeping flexible as per user request for mobile layout.
      // bottomNavigationBar: isDesktop ? null : _buildBottomNavigationBar(),
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: AppColors.primaryColor,
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.admin_panel_settings,
                  color: Colors.white,
                  size: 24,
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    AppStrings.appName,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: _navigationItems.length,
              itemBuilder: (context, index) {
                final item = _navigationItems[index];
                return _buildNavigationItem(item, index);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Column(
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(
                color: AppColors.primaryColor,
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.admin_panel_settings,
                      color: Colors.white,
                      size: 48,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      AppStrings.appName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: _navigationItems.length,
                itemBuilder: (context, index) {
                  final item = _navigationItems[index];
                  return _buildNavigationItem(item, index, isDrawer: true);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavigationItem(NavigationItem item, int index,
      {bool isDrawer = false}) {
    final isSelected = _selectedIndex == index;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isSelected
            ? AppColors.primaryColor.withValues(alpha: 0.1)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        leading: Icon(
          item.icon,
          color: isSelected ? AppColors.primaryColor : Colors.grey[600],
        ),
        title: Text(
          item.title,
          style: TextStyle(
            color: isSelected ? AppColors.primaryColor : Colors.grey[800],
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        onTap: () {
          setState(() {
            _selectedIndex = index;
          });
          if (isDrawer) {
            Navigator.pop(context);
          }
        },
        selected: isSelected,
      ),
    );
  }

  Widget _buildSelectedPage() {
    switch (_selectedIndex) {
      case 0:
        return const DashboardOverview();
      case 1:
        return const CustomerManagement();
      case 2:
        return const LicensesManagement();
      case 3:
        return const RevenueDashboard();
      default:
        return const DashboardOverview();
    }
  }

  void _logout() {
    Get.offAllNamed('/login');
  }

  void _showExpiringLicensesDialog() {
    final expiring = _dataService.getExpiringSoonLicenses();

    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.warning_amber, color: AppColors.warningColor),
              const SizedBox(width: 12),
              const Text('تراخيص تنتهي قريباً'),
            ],
          ),
          content: SizedBox(
            width: 400,
            child: expiring.isEmpty
                ? const Center(child: Text('لا توجد تراخيص تنتهي قريباً 👍'))
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: expiring.length,
                    itemBuilder: (context, index) {
                      final license = expiring[index];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppColors.warningColor,
                          child: Text('${license.daysRemaining}'),
                        ),
                        title: Text(license.clientName),
                        subtitle:
                            Text('ينتهي خلال ${license.daysRemaining} يوم'),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('حسناً'),
            ),
          ],
        ),
      ),
    );
  }
}

class NavigationItem {
  final IconData icon;
  final String title;
  final String route;

  const NavigationItem({
    required this.icon,
    required this.title,
    required this.route,
  });
}
