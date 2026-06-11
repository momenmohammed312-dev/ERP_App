import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:pos_offline_desktop/l10n/l10n.dart';
import 'package:pos_offline_desktop/ui/pages/sidebar_page.dart';
import 'package:pos_offline_desktop/widgets/permission_guard.dart';
import 'package:pos_offline_desktop/core/models/user_model.dart';
import '../../services/feature_gate_service.dart';

class SideBarMenu extends StatelessWidget {
  final SideBarPage selectedPage;
  final ValueChanged<SideBarPage> onPageSelected;

  const SideBarMenu({
    super.key,
    required this.selectedPage,
    required this.onPageSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // الرئيسية - متاحة للجميع
        _buildMenuItem(
          context,
          svgAssetPath: 'assets/svg/house.svg',
          title: context.l10n.home,
          page: SideBarPage.home,
        ),

        // المنتجات - يتطلب صلاحية عرض المنتجات
        PermissionGuard(
          permission: Permission.viewProducts,
          child: _buildMenuItem(
            context,
            svgAssetPath: 'assets/svg/product.svg',
            title: context.l10n.products,
            page: SideBarPage.products,
          ),
        ),

        // العملاء - يتطلب صلاحية عرض العملاء
        PermissionGuard(
          permission: Permission.viewCustomers,
          child: _buildMenuItem(
            context,
            svgAssetPath: 'assets/svg/customer.svg',
            title: context.l10n.customers,
            page: SideBarPage.customers,
          ),
        ),

        // المبيعات والفواتير - يتطلب صلاحية عرض المبيعات
        PermissionGuard(
          permission: Permission.viewSales,
          child: _buildMenuItem(
            context,
            svgAssetPath: 'assets/svg/invoice.svg',
            title: context.l10n.sales_and_invoices,
            page: SideBarPage.invoice,
          ),
        ),

        // الموردين - يتطلب صلاحية عرض الموردين
        PermissionGuard(
          permission: Permission.viewSuppliers,
          child: _buildMenuItem(
            context,
            svgAssetPath: 'assets/svg/customer.svg',
            title: 'الموردين',
            page: SideBarPage.suppliers,
          ),
        ),

        // المشتريات - يتطلب صلاحية عرض المشتريات
        PermissionGuard(
          permission: Permission.viewPurchases,
          child: _buildMenuItem(
            context,
            svgAssetPath: 'assets/svg/graph.svg',
            title: 'المشتريات',
            page: SideBarPage.purchases,
          ),
        ),

        // التقارير - يتطلب صلاحية عرض التقارير
        PermissionGuard(
          permission: Permission.viewReports,
          child: _buildMenuItem(
            context,
            svgAssetPath: 'assets/svg/graph.svg',
            title: 'التقارير والمبيعات',
            page: SideBarPage.reports,
          ),
        ),

        // مرتجعات المبيعات - يتطلب صلاحية عرض المبيعات
        PermissionGuard(
          permission: Permission.viewSales,
          child: _buildMenuItem(
            context,
            svgAssetPath: 'assets/svg/graph.svg',
            title: 'مرتجعات المبيعات',
            page: SideBarPage.returns,
          ),
        ),

        // الكاشير - يتطلب صلاحية عرض المبيعات
        PermissionGuard(
          permission: Permission.viewSales,
          child: _buildMenuItem(
            context,
            svgAssetPath: 'assets/svg/customer.svg',
            title: context.l10n.cashier,
            page: SideBarPage.cashier,
          ),
        ),

        // إدارة المستخدمين - يتطلب صلاحية عرض المستخدمين
        PermissionGuard(
          permission: Permission.viewUsers,
          child: _buildMenuItem(
            context,
            svgAssetPath: 'assets/svg/admin_panel_settings.svg',
            title: 'إدارة المستخدمين',
            page: SideBarPage.users,
          ),
        ),

        // إدارة الموظفين - يتطلب باقة Enterprise
        ConditionalWidget(
          feature: 'staff_management',
          child: _buildMenuItem(
            context,
            svgAssetPath: 'assets/svg/people.svg',
            title: 'الموظفين',
            page: SideBarPage.staff,
          ),
        ),

        // الإعدادات - يتطلب صلاحية عرض الإعدادات
        PermissionGuard(
          permission: Permission.viewSettings,
          child: _buildMenuItem(
            context,
            svgAssetPath: 'assets/svg/settings.svg',
            title: 'الإعدادات',
            page: SideBarPage.settings,
          ),
        ),

        // النسخ الاحتياطي - يتطلب صلاحية النسخ الاحتياطي
        PermissionGuard(
          permission: Permission.createBackup,
          child: _buildMenuItem(
            context,
            svgAssetPath: 'assets/svg/backup.svg',
            title: 'النسخ الاحتياطي',
            page: SideBarPage.backup,
          ),
        ),

        // لوحة تحكم المدير - تتطلب صلاحية إدارة المستخدمين
        PermissionGuard(
          permission: Permission.manageUsers,
          child: _buildMenuItem(
            context,
            svgAssetPath: 'assets/svg/admin_panel_settings.svg',
            title: 'لوحة التحكم',
            page: SideBarPage.admin,
          ),
        ),
      ],
    );
  }

  // List Tile
  Widget _buildMenuItem(
    BuildContext context, {
    required String svgAssetPath,
    required String title,
    required SideBarPage page,
  }) {
    final isSelected = selectedPage == page;
    final colorScheme = Theme.of(context).colorScheme;

    return ListTile(
      leading: SvgPicture.asset(
        svgAssetPath,
        width: 24,
        height: 24,
        colorFilter: ColorFilter.mode(
          isSelected
              ? colorScheme.primary
              : Theme.of(context).colorScheme.onSurface,
          BlendMode.srcIn,
        ),
      ),
      title: Text(
        title,
        style: TextStyle(
          color: isSelected
              ? colorScheme.primary
              : Theme.of(context).colorScheme.onSurface,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      selected: isSelected,
      selectedTileColor: colorScheme.surfaceTint.withValues(alpha: 0.3),
      onTap: () => onPageSelected(page),
    );
  }
}
