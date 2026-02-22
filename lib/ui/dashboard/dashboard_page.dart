import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:pos_offline_desktop/core/provider/app_database_provider.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/ui/invoice/widgets/enhanced_new_invoice_page.dart';
import 'package:pos_offline_desktop/ui/purchase/widgets/enhanced_purchase_invoice_page.dart';
import 'package:pos_offline_desktop/ui/suppliers/widgets/supplier_dashboard.dart';
import 'package:pos_offline_desktop/widgets/license/feature_guard.dart';
import 'package:pos_offline_desktop/widgets/dashboard/sales_summary_widget.dart';
import 'package:pos_offline_desktop/widgets/dashboard/sales_purchase_comparison_card.dart';
import 'package:pos_offline_desktop/widgets/dashboard/daily_sales_performance_widget.dart';
import 'package:pos_offline_desktop/widgets/dashboard/inventory_alerts_widget.dart';
import 'package:pos_offline_desktop/ui/customer/widgets/customer_dashboard.dart';
import 'package:pos_offline_desktop/core/database/dao/enhanced_purchase_dao.dart';
import 'package:fl_chart/fl_chart.dart';

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  @override
  Widget build(BuildContext context) {
    final db = ref.watch(appDatabaseProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Welcome Section
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.1),
                    Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.05),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.2),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.1),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'مرحباً بك في نظام نقاط البيع',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const Gap(8),
                  Text(
                    'Developed by MO2 - v1.0.0',
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
            const Gap(24),

            // Charts Section
            _buildChartsSection(context),

            const Gap(24),

            // Customer Dashboard Section
            CustomerDashboard(
              db: db,
              onCustomerSelected: (customer) {
                // Navigate to customer details
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('تم اختيار العميل: ${customer.name}'),
                    backgroundColor: Theme.of(context).colorScheme.primary,
                  ),
                );
              },
              onRefresh: () {
                // Refresh dashboard data
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('تم تحديث البيانات'),
                    backgroundColor: Colors.green,
                  ),
                );
              },
            ),

            const Gap(24),

            // Sales Summary Section
            SalesSummaryWidget(db: db),

            const Gap(24),

            // Daily Sales Performance Section
            DailySalesPerformanceWidget(db: db),

            const Gap(24),

            // Suppliers Dashboard Section
            SupplierDashboard(
              db: db,
              onSupplierSelected: (supplier) {
                // Navigate to supplier details
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('تم اختيار المورد: ${supplier.businessName}'),
                    backgroundColor: Theme.of(context).colorScheme.primary,
                  ),
                );
              },
              onRefresh: () {
                // Refresh dashboard data
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('تم تحديث البيانات'),
                    backgroundColor: Colors.green,
                  ),
                );
              },
            ),

            const Gap(24),

            // Purchase Statistics Section
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'إحصائيات المشتريات',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.onSurface,
                              ),
                        ),
                        IconButton(
                          onPressed: () {
                            // Refresh purchase statistics
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('تم تحديث إحصائيات المشتريات'),
                                backgroundColor: Colors.purple,
                              ),
                            );
                          },
                          icon: const Icon(Icons.refresh),
                          tooltip: 'تحديث إحصائيات المشتريات',
                        ),
                      ],
                    ),
                    const Gap(16),
                    FutureBuilder<PurchaseStats>(
                      future: _getPurchaseStats(db),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        } else if (snapshot.hasError) {
                          return Center(
                            child: Text(
                              'خطأ في تحميل إحصائيات المشتريات: ${snapshot.error}',
                              style: TextStyle(color: Colors.red),
                            ),
                          );
                        } else if (!snapshot.hasData) {
                          return Center(child: Text('لا توجد بيانات مشتريات'));
                        }

                        final stats = snapshot.data!;

                        return Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: _buildMetricCard(
                                    'إجمالي المشتريات',
                                    '${stats.totalPurchases.toStringAsFixed(2)} ج.م',
                                    Icons.shopping_cart,
                                    Colors.purple,
                                  ),
                                ),
                                const Gap(16),
                                Expanded(
                                  child: _buildMetricCard(
                                    'المشتريات المدفوعة',
                                    '${(stats.totalPurchases - stats.creditPurchases).toStringAsFixed(2)} ج.م',
                                    Icons.payment,
                                    Colors.green,
                                  ),
                                ),
                                const Gap(16),
                                Expanded(
                                  child: _buildMetricCard(
                                    'المشتريات الآجلة',
                                    '${stats.creditPurchases.toStringAsFixed(2)} ج.م',
                                    Icons.credit_card,
                                    Colors.orange,
                                  ),
                                ),
                              ],
                            ),
                            const Gap(16),
                            // Top Suppliers by Balance
                            FutureBuilder<List<EnhancedSupplier>>(
                              future: _getTopSuppliers(db),
                              builder: (context, snapshot) {
                                if (!snapshot.hasData ||
                                    snapshot.data!.isEmpty) {
                                  return SizedBox.shrink();
                                }

                                final suppliers = snapshot.data!;

                                return Container(
                                  padding: EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.surfaceContainer,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'أعلى الموردين (بالرصيد)',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurface,
                                        ),
                                      ),
                                      const Gap(12),
                                      ...suppliers
                                          .take(3)
                                          .map(
                                            (supplier) => Padding(
                                              padding: EdgeInsets.only(
                                                bottom: 8,
                                              ),
                                              child: Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment
                                                        .spaceBetween,
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      supplier.businessName,
                                                      style: TextStyle(
                                                        color: Theme.of(
                                                          context,
                                                        ).colorScheme.onSurface,
                                                        fontSize: 14,
                                                      ),
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  Text(
                                                    '${supplier.currentBalance.toStringAsFixed(2)} ج.م',
                                                    style: TextStyle(
                                                      color:
                                                          supplier.currentBalance >
                                                              0
                                                          ? Colors.red
                                                          : Colors.green,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),

            const Gap(24),

            // Inventory Alerts Section
            InventoryAlertsWidget(db: db),

            const Gap(24),

            // Sales vs Purchases Comparison Section
            SalesPurchaseComparisonCard(database: db),

            const Gap(24),

            // Quick Actions Section
            Text(
              'الإجراءات السريعة',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const Gap(16),
            Row(
              children: [
                Expanded(
                  child: _buildQuickActionCard(
                    'فاتورة جديدة',
                    'إنشاء فاتورة مبيعات جديدة',
                    Icons.add_shopping_cart,
                    Colors.green,
                    () => _createNewInvoice(),
                  ),
                ),
                const Gap(16),
                Expanded(
                  child: FeatureGuard(
                    featureName: 'suppliers',
                    child: _buildQuickActionCard(
                      'فاتورة مشتريات',
                      'إنشاء فاتورة مشتريات جديدة',
                      Icons.shopping_cart,
                      Colors.orange,
                      () => _createNewPurchaseInvoice(),
                    ),
                  ),
                ),
              ],
            ),
            const Gap(16),
            Row(
              children: [
                Expanded(
                  child: _buildQuickActionCard(
                    'إضافة منتج',
                    'إضافة منتج جديد للمخزون',
                    Icons.inventory,
                    Colors.indigo,
                    () => _navigateToAddProduct(),
                  ),
                ),
                const Gap(16),
                Expanded(
                  child: _buildQuickActionCard(
                    'إضافة عميل',
                    'إضافة عميل جديد',
                    Icons.person_add,
                    Colors.teal,
                    () => _navigateToAddCustomer(),
                  ),
                ),
              ],
            ),
            const Gap(24),

            // Day Management Section
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.orange.shade50, Colors.red.shade50],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.red.withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.calendar_today, color: Colors.white, size: 32),
                      const Gap(12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'إدارة اليوم',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            'فتح أو غلق اليوم المالي',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white.withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const Gap(20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _openDay(),
                          icon: const Icon(
                            Icons.lock_open,
                            color: Colors.white,
                          ),
                          label: const Text('فتح اليوم'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green.shade600,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ),
                      const Gap(12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _closeDay(),
                          icon: const Icon(Icons.lock, color: Colors.white),
                          label: const Text('غلق اليوم'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.shade600,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionCard(
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
          border: Border.all(color: color.withValues(alpha: 0.2)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const Gap(16),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
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

  Future<void> _createNewInvoice() async {
    final db = ref.read(appDatabaseProvider);
    final isOpen = await db.dayDao.isDayOpen();
    if (!isOpen) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('برجاء فتح اليوم أولاً'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // Navigate to enhanced new invoice page
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => EnhancedNewInvoicePage(db: db)),
      );
    }
  }

  Future<void> _createNewPurchaseInvoice() async {
    final db = ref.read(appDatabaseProvider);
    final isOpen = await db.dayDao.isDayOpen();
    if (!isOpen) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('برجاء فتح اليوم أولاً'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // Navigate to enhanced purchase invoice page
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => EnhancedPurchaseInvoicePage(db: db),
        ),
      );
    }
  }

  void _navigateToAddProduct() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('يمكن الوصول لإضافة المنتجات من القائمة الجانبية'),
        backgroundColor: Colors.blue,
      ),
    );
  }

  void _navigateToAddCustomer() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('يمكن الوصول لإضافة العملاء من القائمة الجانبية'),
        backgroundColor: Colors.blue,
      ),
    );
  }

  Future<void> _openDay() async {
    try {
      final db = ref.read(appDatabaseProvider);
      await db.dayDao.openDay(openingBalance: 0.0);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم فتح اليوم بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في فتح اليوم: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _closeDay() async {
    try {
      final db = ref.read(appDatabaseProvider);
      final today = await db.dayDao.getTodayDay();
      if (today == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('لا يوجد يوم مفتوح'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      await db.dayDao.closeDay(dayId: today['id'] as int, closingBalance: 0.0);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم غلق اليوم بنجاح'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في غلق اليوم: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildMetricCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const Gap(8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.7),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const Gap(8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<PurchaseStats> _getPurchaseStats(AppDatabase db) async {
    final purchaseDao = EnhancedPurchaseDao(db);

    try {
      final totalPurchases = await purchaseDao.getTotalPurchasesByDateRange(
        DateTime.now().subtract(Duration(days: 30)),
        DateTime.now(),
      );

      final creditPurchases = await purchaseDao.getTotalCreditPurchases();
      final cashPurchases = await purchaseDao.getTotalCashPurchases();

      return PurchaseStats(
        totalPurchases: totalPurchases,
        creditPurchases: creditPurchases,
        cashPurchases: cashPurchases,
      );
    } catch (e) {
      // Return default values if there's an error
      return PurchaseStats(
        totalPurchases: 0.0,
        creditPurchases: 0.0,
        cashPurchases: 0.0,
      );
    }
  }

  Future<List<EnhancedSupplier>> _getTopSuppliers(AppDatabase db) async {
    final purchaseDao = EnhancedPurchaseDao(db);

    try {
      return await purchaseDao.getTopSuppliersByBalance(5);
    } catch (e) {
      return [];
    }
  }

  Widget _buildChartsSection(BuildContext context) {
    // Dummy data for demonstration
    final salesData = [
      DailySalesData(
        date: DateTime.now().subtract(Duration(days: 6)),
        totalSales: 1500,
      ),
      DailySalesData(
        date: DateTime.now().subtract(Duration(days: 5)),
        totalSales: 2000,
      ),
      DailySalesData(
        date: DateTime.now().subtract(Duration(days: 4)),
        totalSales: 1800,
      ),
      DailySalesData(
        date: DateTime.now().subtract(Duration(days: 3)),
        totalSales: 2500,
      ),
      DailySalesData(
        date: DateTime.now().subtract(Duration(days: 2)),
        totalSales: 2200,
      ),
      DailySalesData(
        date: DateTime.now().subtract(Duration(days: 1)),
        totalSales: 2800,
      ),
      DailySalesData(date: DateTime.now(), totalSales: 3000),
    ];

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'الرسوم البيانية',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const Gap(16),
          Row(
            children: [
              Expanded(child: _buildSalesChart(salesData)),
              const Gap(16),
              Expanded(child: _buildPaymentTypePieChart(5000, 3000)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSalesChart(List<DailySalesData> salesData) {
    if (salesData.isEmpty) {
      return const Center(child: Text('لا توجد بيانات'));
    }

    final spots = salesData.asMap().entries.map((entry) {
      return FlSpot(entry.key.toDouble(), entry.value.totalSales);
    }).toList();

    return Container(
      height: 200,
      padding: const EdgeInsets.all(16),
      child: LineChart(
        LineChartData(
          gridData: FlGridData(show: true, horizontalInterval: 500),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index >= 0 && index < salesData.length) {
                    return Text(
                      '${salesData[index].date.day}/${salesData[index].date.month}',
                      style: const TextStyle(fontSize: 10),
                    );
                  }
                  return const Text('');
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) => Text(
                  '${value.toInt()}',
                  style: const TextStyle(fontSize: 10),
                ),
              ),
            ),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              color: const Color(0xFF4ECDC4),
              barWidth: 3,
              dotData: FlDotData(show: spots.length < 15),
              belowBarData: BarAreaData(
                show: true,
                color: const Color(0xFF4ECDC4).withValues(alpha: 0.1),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentTypePieChart(double cash, double credit) {
    final total = cash + credit;
    if (total == 0) return const SizedBox.shrink();

    return SizedBox(
      height: 180,
      child: PieChart(
        PieChartData(
          sections: [
            PieChartSectionData(
              value: cash,
              title: 'نقدي\n${(cash / total * 100).toStringAsFixed(0)}%',
              color: Colors.green,
              radius: 60,
            ),
            PieChartSectionData(
              value: credit,
              title: 'آجل\n${(credit / total * 100).toStringAsFixed(0)}%',
              color: Colors.orange,
              radius: 60,
            ),
          ],
          centerSpaceRadius: 40,
        ),
      ),
    );
  }
}

// Purchase statistics data class
class PurchaseStats {
  final double totalPurchases;
  final double creditPurchases;
  final double cashPurchases;

  PurchaseStats({
    required this.totalPurchases,
    required this.creditPurchases,
    required this.cashPurchases,
  });
}

// Daily sales data class for charts
class DailySalesData {
  final DateTime date;
  final double totalSales;

  DailySalesData({required this.date, required this.totalSales});
}
