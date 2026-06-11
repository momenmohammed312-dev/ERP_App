// ════════════════════════════════════════════════════════════════════════
// Admin Dashboard Web - POS SaaS Offline
// ════════════════════════════════════════════════════════════════════════

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pos_offline_desktop/core/provider/app_database_provider.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/ui/product/widgets/product_form.dart';
import 'package:pos_offline_desktop/ui/customer/add_edit_customer_page.dart';
import 'package:pos_offline_desktop/core/models/user_model.dart' as models;

// ════════════════════════════════════════════════════════════════════════
// 1. الصفحة الرئيسية للـ Dashboard
// ════════════════════════════════════════════════════════════════════════

class AdminDashboardPage extends ConsumerWidget {
  const AdminDashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(appDatabaseProvider);

    return _AdminDashboardPageContent(db: db);
  }
}

class _AdminDashboardPageContent extends StatefulWidget {
  final AppDatabase db;

  const _AdminDashboardPageContent({required this.db});

  @override
  State<_AdminDashboardPageContent> createState() =>
      _AdminDashboardPageContentState();
}

class _AdminDashboardPageContentState
    extends State<_AdminDashboardPageContent> {
  int _selectedIndex = 0;

  late List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
      const OverviewPage(),
      const SalesAnalyticsPage(),
      const InventoryPage(),
      const CustomersPage(),
      const UsersPage(),
      const ReportsPage(),
      const SettingsPage(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // Sidebar
          NavigationRail(
            extended: MediaQuery.of(context).size.width > 800,
            backgroundColor: const Color(0xFF1E293B),
            selectedIndex: _selectedIndex,
            onDestinationSelected: (index) {
              setState(() => _selectedIndex = index);
            },
            labelType: NavigationRailLabelType.none,
            leading: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  const CircleAvatar(
                    radius: 30,
                    backgroundColor: Colors.white,
                    child: Icon(Icons.admin_panel_settings, size: 40),
                  ),
                  const SizedBox(height: 8),
                  if (MediaQuery.of(context).size.width > 800)
                    const Text(
                      'لوحة التحكم',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                ],
              ),
            ),
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.dashboard, color: Colors.white70),
                selectedIcon: Icon(Icons.dashboard, color: Colors.white),
                label: Text('نظرة عامة', style: TextStyle(color: Colors.white)),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.analytics, color: Colors.white70),
                selectedIcon: Icon(Icons.analytics, color: Colors.white),
                label: Text('المبيعات', style: TextStyle(color: Colors.white)),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.inventory, color: Colors.white70),
                selectedIcon: Icon(Icons.inventory, color: Colors.white),
                label: Text('المخزون', style: TextStyle(color: Colors.white)),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.people, color: Colors.white70),
                selectedIcon: Icon(Icons.people, color: Colors.white),
                label: Text('العملاء', style: TextStyle(color: Colors.white)),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.admin_panel_settings, color: Colors.white70),
                selectedIcon: Icon(
                  Icons.admin_panel_settings,
                  color: Colors.white,
                ),
                label: Text(
                  'المستخدمين',
                  style: TextStyle(color: Colors.white),
                ),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.bar_chart, color: Colors.white70),
                selectedIcon: Icon(Icons.bar_chart, color: Colors.white),
                label: Text('التقارير', style: TextStyle(color: Colors.white)),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings, color: Colors.white70),
                selectedIcon: Icon(Icons.settings, color: Colors.white),
                label: Text('الإعدادات', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),

          const VerticalDivider(thickness: 1, width: 1),

          // Main Content
          Expanded(child: _pages[_selectedIndex]),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════
// 2. صفحة النظرة العامة
// ════════════════════════════════════════════════════════════════════════

class OverviewPage extends ConsumerWidget {
  const OverviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(appDatabaseProvider);
    return _OverviewPageContent(db: db);
  }
}

class _OverviewPageContent extends StatefulWidget {
  final AppDatabase db;

  const _OverviewPageContent({required this.db});

  @override
  State<_OverviewPageContent> createState() => _OverviewPageContentState();
}

class _OverviewPageContentState extends State<_OverviewPageContent> {
  late Future<Map<String, dynamic>> _dashboardData;

  @override
  void initState() {
    super.initState();
    _refreshData();
  }

  void _refreshData() {
    setState(() {
      _dashboardData = _getDashboardData();
    });
  }

  Future<Map<String, dynamic>> _getDashboardData() async {
    try {
      final today = DateTime.now();
      final todayStart = DateTime(today.year, today.month, today.day);
      final todayEnd = DateTime(today.year, today.month, today.day, 23, 59, 59);

      // Get today's invoices
      final todayInvoices = await widget.db.invoiceDao.getInvoicesByDate(today);
      final todaySales = todayInvoices.fold<double>(
        0,
        (sum, invoice) => sum + invoice.totalAmount,
      );

      // Get customer count
      final totalCustomers = await widget.db.customerDao
          .getTotalCustomerCount();

      // Get product count
      final allProducts = await widget.db.productDao.filterProducts();
      final totalProducts = allProducts.length;

      // Get supplier count
      final allSuppliers = await widget.db.supplierDao.getAllSuppliers();
      final totalSuppliers = allSuppliers.length;

      // Calculate average invoice amount
      final avgInvoice = todayInvoices.isNotEmpty
          ? todaySales / todayInvoices.length
          : 0.0;

      // Get recent transactions (last 5 invoices)
      final recentInvoices = todayInvoices.take(5).toList();

      return {
        'todaySales': todaySales,
        'todayInvoiceCount': todayInvoices.length,
        'avgInvoice': avgInvoice,
        'totalCustomers': totalCustomers,
        'totalProducts': totalProducts,
        'totalSuppliers': totalSuppliers,
        'recentInvoices': recentInvoices,
        'lastUpdated': DateTime.now(),
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'نظرة عامة',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'اليوم: ${_formatDate(DateTime.now())}',
                      style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  onPressed: () => _exportReport(),
                  icon: const Icon(Icons.download),
                  label: const Text('تصدير التقرير'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 32),

            // Stats Cards
            FutureBuilder<Map<String, dynamic>>(
              future: _dashboardData,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError || !snapshot.hasData) {
                  return const Center(child: Text('خطأ في تحميل البيانات'));
                }

                final data = snapshot.data!;
                if (data.containsKey('error')) {
                  return Center(child: Text('خطأ: ${data['error']}'));
                }

                return GridView.count(
                  crossAxisCount: MediaQuery.of(context).size.width > 1200
                      ? 4
                      : 2,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 1.5,
                  children: [
                    _buildStatCard(
                      'إجمالي المبيعات اليوم',
                      '${data['todaySales']?.toStringAsFixed(2) ?? '0.00'} ج.م',
                      Icons.attach_money,
                      Colors.green,
                      '+12.5%',
                      true,
                    ),
                    _buildStatCard(
                      'عدد الفواتير',
                      '${data['todayInvoiceCount'] ?? 0}',
                      Icons.receipt_long,
                      Colors.blue,
                      '+8.2%',
                      true,
                    ),
                    _buildStatCard(
                      'متوسط الفاتورة',
                      '${data['avgInvoice']?.toStringAsFixed(2) ?? '0.00'} ج.م',
                      Icons.calculate,
                      Colors.orange,
                      '-2.3%',
                      false,
                    ),
                    _buildStatCard(
                      'العملاء',
                      '${data['totalCustomers'] ?? 0}',
                      Icons.people,
                      Colors.purple,
                      '+15.0%',
                      true,
                    ),
                  ],
                );
              },
            ),

            const SizedBox(height: 32),

            // Charts Row
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 2, child: _buildSalesChart()),
                const SizedBox(width: 16),
                Expanded(child: _buildTopProductsCard()),
              ],
            ),

            const SizedBox(height: 16),

            // Recent Transactions
            FutureBuilder<Map<String, dynamic>>(
              future: _dashboardData,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.containsKey('error')) {
                  return const Center(child: Text('لا توجد معاملات'));
                }

                final recentInvoices =
                    snapshot.data!['recentInvoices'] as List? ?? [];

                return _buildRecentTransactions(recentInvoices);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportReport() async {
    try {
      final data = await _dashboardData;

      if (data.containsKey('error')) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('لا يمكن تصدير التقرير: خطأ في البيانات'),
            ),
          );
        }
        return;
      }

      // Create CSV content
      final csvContent = _generateCSV(data);

      // Save to file
      final dir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = 'admin_report_$timestamp.csv';
      final file = File('${dir.path}/$fileName');
      await file.writeAsString(csvContent);

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('تم تصدير التقرير: ${file.path}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('خطأ في التصدير: $e')));
      }
    }
  }

  String _generateCSV(Map<String, dynamic> data) {
    final buffer = StringBuffer();

    // Header
    buffer.writeln('المبلغ,الوصف,التاريخ');

    // Add data rows
    buffer.writeln(
      '${data['todaySales']?.toStringAsFixed(2) ?? '0.00'},إجمالي المبيعات اليوم,${DateTime.now().toIso8601String()}',
    );
    buffer.writeln(
      '${data['todayInvoiceCount'] ?? 0},عدد الفواتير اليوم,${DateTime.now().toIso8601String()}',
    );
    buffer.writeln(
      '${data['avgInvoice']?.toStringAsFixed(2) ?? '0.00'},متوسط قيمة الفاتورة,${DateTime.now().toIso8601String()}',
    );
    buffer.writeln(
      '${data['totalCustomers'] ?? 0},إجمالي العملاء,${DateTime.now().toIso8601String()}',
    );

    return buffer.toString();
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
    String change,
    bool isPositive,
  ) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            Row(
              children: [
                Icon(
                  isPositive ? Icons.trending_up : Icons.trending_down,
                  color: isPositive ? Colors.green : Colors.red,
                  size: 16,
                ),
                const SizedBox(width: 4),
                Text(
                  change,
                  style: TextStyle(
                    color: isPositive ? Colors.green : Colors.red,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                const Text(
                  'عن الأمس',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSalesChart() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'المبيعات الأسبوعية',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 300,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(show: true),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          const days = [
                            'السبت',
                            'الأحد',
                            'الاثنين',
                            'الثلاثاء',
                            'الأربعاء',
                            'الخميس',
                            'الجمعة',
                          ];
                          return Text(
                            days[value.toInt() % 7],
                            style: const TextStyle(fontSize: 12),
                          );
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                      ),
                    ),
                    topTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  borderData: FlBorderData(show: true),
                  lineBarsData: [
                    LineChartBarData(
                      spots: [
                        const FlSpot(0, 30),
                        const FlSpot(1, 45),
                        const FlSpot(2, 35),
                        const FlSpot(3, 50),
                        const FlSpot(4, 40),
                        const FlSpot(5, 55),
                        const FlSpot(6, 45),
                      ],
                      isCurved: true,
                      color: Colors.blue,
                      barWidth: 3,
                      dotData: FlDotData(show: true),
                      belowBarData: BarAreaData(
                        show: true,
                        color: Colors.blue.withValues(alpha: 0.1),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopProductsCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'أكثر المنتجات مبيعاً',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildProductItem('منتج A', '1,234', 85),
            _buildProductItem('منتج B', '987', 70),
            _buildProductItem('منتج C', '765', 55),
            _buildProductItem('منتج D', '543', 40),
            _buildProductItem('منتج E', '321', 25),
          ],
        ),
      ),
    );
  }

  Widget _buildProductItem(String name, String sales, double percentage) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(sales, style: const TextStyle(color: Colors.grey)),
            ],
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: percentage / 100,
            backgroundColor: Colors.grey[200],
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.blue),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentTransactions(List<dynamic> invoices) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'آخر المعاملات',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            DataTable(
              columns: const [
                DataColumn(label: Text('رقم الفاتورة')),
                DataColumn(label: Text('العميل')),
                DataColumn(label: Text('المبلغ')),
                DataColumn(label: Text('الحالة')),
                DataColumn(label: Text('التاريخ')),
              ],
              rows: invoices.isEmpty
                  ? [
                      const DataRow(
                        cells: [
                          DataCell(Text('لا توجد معاملات')),
                          DataCell(Text('')),
                          DataCell(Text('')),
                          DataCell(Text('')),
                          DataCell(Text('')),
                        ],
                      ),
                    ]
                  : invoices.map((invoice) {
                      final invoiceNumber =
                          invoice.invoiceNumber ?? 'غير معروف';
                      final customerName = invoice.customerName ?? 'عميل نقدي';
                      final amount =
                          '${invoice.totalAmount?.toStringAsFixed(2) ?? '0.00'} ج.م';
                      final status = invoice.isPaid == true ? 'مكتمل' : 'معلق';
                      final time = DateFormat(
                        'HH:mm',
                      ).format(invoice.date ?? DateTime.now());

                      return _buildTransactionRow(
                        invoiceNumber,
                        customerName,
                        amount,
                        status,
                        time,
                      );
                    }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  DataRow _buildTransactionRow(
    String invoice,
    String customer,
    String amount,
    String status,
    String time,
  ) {
    return DataRow(
      cells: [
        DataCell(Text(invoice)),
        DataCell(Text(customer)),
        DataCell(
          Text(amount, style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        DataCell(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: status == 'مكتمل' ? Colors.green[100] : Colors.orange[100],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              status,
              style: TextStyle(
                color: status == 'مكتمل'
                    ? Colors.green[900]
                    : Colors.orange[900],
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        DataCell(Text(time)),
      ],
    );
  }

  String _formatDate(DateTime date) {
    final formatter = DateFormat('EEEE، d MMMM yyyy', 'ar_EG');
    return formatter.format(date);
  }
}

// ════════════════════════════════════════════════════════════════════════
// 3. صفحة تحليلات المبيعات
// ════════════════════════════════════════════════════════════════════════

class SalesAnalyticsPage extends ConsumerStatefulWidget {
  const SalesAnalyticsPage({super.key});

  @override
  ConsumerState<SalesAnalyticsPage> createState() => _SalesAnalyticsPageState();
}

class _SalesAnalyticsPageState extends ConsumerState<SalesAnalyticsPage> {
  String _selectedPeriod = 'اليوم';

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(appDatabaseProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'تحليلات المبيعات',
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 32),

            // Period Selector
            Row(
              children: [
                _buildPeriodChip('اليوم', _selectedPeriod == 'اليوم'),
                const SizedBox(width: 8),
                _buildPeriodChip(
                  'هذا الأسبوع',
                  _selectedPeriod == 'هذا الأسبوع',
                ),
                const SizedBox(width: 8),
                _buildPeriodChip('هذا الشهر', _selectedPeriod == 'هذا الشهر'),
                const SizedBox(width: 8),
                _buildPeriodChip('هذا العام', _selectedPeriod == 'هذا العام'),
              ],
            ),

            const SizedBox(height: 24),

            // Charts
            Row(
              children: [
                Expanded(child: _buildPieChart(db)),
                const SizedBox(width: 16),
                Expanded(child: _buildBarChart(db)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPeriodChip(String label, bool isSelected) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedPeriod = label;
        });
      },
      child: Chip(
        label: Text(label),
        backgroundColor: isSelected ? Colors.blue : Colors.grey[200],
        labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.black),
      ),
    );
  }

  Widget _buildPieChart(AppDatabase db) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _getSalesByCategory(db),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        final categoryData = snapshot.data ?? [];

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'المبيعات حسب الفئة',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  height: 300,
                  child: PieChart(
                    PieChartData(
                      sections: categoryData.isNotEmpty
                          ? categoryData.map((category) {
                              final value = category['total'] as double;
                              final percentage =
                                  category['percentage'] as double;
                              return PieChartSectionData(
                                value: value,
                                title: '${percentage.toStringAsFixed(1)}%',
                                color: _getCategoryColor(
                                  category['name'] as String,
                                ),
                                radius: 100,
                              );
                            }).toList()
                          : [
                              PieChartSectionData(
                                value: 1,
                                title: 'لا توجد بيانات',
                                color: Colors.grey,
                                radius: 100,
                              ),
                            ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                ...categoryData.map(
                  (category) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: _getCategoryColor(
                              category['name'] as String,
                            ),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(category['name'] as String),
                        const Spacer(),
                        Text(
                          '${category['total']?.toStringAsFixed(2) ?? '0.00'} ج.م',
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> _getSalesByCategory(AppDatabase db) async {
    try {
      // Get date range based on selected period
      final (start, end) = _getDateRangeForPeriod(_selectedPeriod);

      // Get invoices for the period
      final invoices = await db.invoiceDao.getInvoicesByDateRange(start, end);

      // Group by category (this is simplified - in real implementation you'd join with products)
      final Map<String, double> categoryTotals = {};
      double grandTotal = 0;

      for (final invoice in invoices) {
        // For now, we'll use a simple categorization based on invoice amounts
        // In a real implementation, you'd get this from invoice items and product categories
        final amount = invoice.totalAmount;
        grandTotal += amount;

        String category;
        if (amount < 500) {
          category = 'أقل من 500';
        } else if (amount < 1000) {
          category = '500-1000';
        } else if (amount < 2000) {
          category = '1000-2000';
        } else {
          category = 'أكثر من 2000';
        }

        categoryTotals[category] = (categoryTotals[category] ?? 0) + amount;
      }

      // Convert to list with percentages
      final result = categoryTotals.entries.map((entry) {
        final percentage = grandTotal > 0
            ? (entry.value / grandTotal) * 100
            : 0.0;
        return {
          'name': entry.key,
          'total': entry.value,
          'percentage': percentage,
        };
      }).toList();

      // Sort by total descending
      result.sort(
        (a, b) => (b['total'] as double).compareTo(a['total'] as double),
      );

      return result;
    } catch (e) {
      return [];
    }
  }

  (DateTime, DateTime) _getDateRangeForPeriod(String period) {
    final now = DateTime.now();
    switch (period) {
      case 'اليوم':
        final start = DateTime(now.year, now.month, now.day);
        final end = DateTime(now.year, now.month, now.day, 23, 59, 59);
        return (start, end);
      case 'هذا الأسبوع':
        final start = now.subtract(Duration(days: now.weekday - 1));
        final end = start.add(const Duration(days: 6, hours: 23, minutes: 59));
        return (start, end);
      case 'هذا الشهر':
        final start = DateTime(now.year, now.month, 1);
        final end = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
        return (start, end);
      case 'هذا العام':
        final start = DateTime(now.year, 1, 1);
        final end = DateTime(now.year, 12, 31, 23, 59, 59);
        return (start, end);
      default:
        return (now, now);
    }
  }

  Color _getCategoryColor(String categoryName) {
    final colors = [
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.red,
      Colors.purple,
    ];
    final index = categoryName.hashCode.abs() % colors.length;
    return colors[index];
  }

  Widget _buildBarChart(AppDatabase db) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _getMonthlySalesData(db),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        final monthlyData = snapshot.data ?? [];

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'المبيعات الشهرية',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  height: 300,
                  child: BarChart(
                    BarChartData(
                      barGroups: monthlyData.isNotEmpty
                          ? monthlyData.map((data) {
                              final index = monthlyData.indexOf(data);
                              return BarChartGroupData(
                                x: index,
                                barRods: [
                                  BarChartRodData(
                                    toY: data['total'] as double,
                                    color: Colors.blue,
                                    width: 20,
                                  ),
                                ],
                              );
                            }).toList()
                          : [
                              BarChartGroupData(
                                x: 0,
                                barRods: [
                                  BarChartRodData(
                                    toY: 0,
                                    color: Colors.grey,
                                    width: 20,
                                  ),
                                ],
                              ),
                            ],
                      titlesData: FlTitlesData(
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: true),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (value, meta) {
                              if (value.toInt() < monthlyData.length) {
                                return Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    monthlyData[value.toInt()]['month']
                                        as String,
                                    style: const TextStyle(fontSize: 10),
                                  ),
                                );
                              }
                              return const Text('');
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> _getMonthlySalesData(
    AppDatabase db,
  ) async {
    try {
      final now = DateTime.now();
      final months = <String, DateTime>{};

      // Generate last 6 months
      for (int i = 5; i >= 0; i--) {
        final month = DateTime(now.year, now.month - i, 1);
        final monthName = DateFormat('MMM', 'ar').format(month);
        months[monthName] = month;
      }

      final result = <Map<String, dynamic>>[];

      for (final entry in months.entries) {
        final month = entry.value;
        final start = DateTime(month.year, month.month, 1);
        final end = DateTime(month.year, month.month + 1, 0, 23, 59, 59);

        final invoices = await db.invoiceDao.getInvoicesByDateRange(start, end);
        final total = invoices.fold<double>(
          0,
          (sum, invoice) => sum + invoice.totalAmount,
        );

        result.add({'month': entry.key, 'total': total});
      }

      return result;
    } catch (e) {
      return [];
    }
  }
}

// ════════════════════════════════════════════════════════════════════════
// 4. صفحات أخرى (يمكن تطويرها لاحقاً)
// ════════════════════════════════════════════════════════════════════════

class InventoryPage extends ConsumerWidget {
  const InventoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(appDatabaseProvider);

    return _InventoryPageContent(db: db);
  }
}

class _InventoryPageContent extends StatefulWidget {
  final AppDatabase db;

  const _InventoryPageContent({required this.db});

  @override
  State<_InventoryPageContent> createState() => _InventoryPageContentState();
}

class _InventoryPageContentState extends State<_InventoryPageContent> {
  String _searchQuery = '';
  String _selectedCategory = 'الكل';
  final List<String> _categories = [
    'الكل',
    'إلكترونيات',
    'ملابس',
    'أطعمة',
    'أخرى',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'إدارة المخزون',
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 24),

                // Search and Filter Row
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: 'البحث عن منتج...',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onChanged: (value) {
                          setState(() {
                            _searchQuery = value;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        // ignore: deprecated_member_use
                        value: _selectedCategory,
                        decoration: InputDecoration(
                          labelText: 'الفئة',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        items: _categories.map((category) {
                          return DropdownMenuItem(
                            value: category,
                            child: Text(category),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedCategory = value!;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton.icon(
                      onPressed: () => _addNewProduct(),
                      icon: const Icon(Icons.add),
                      label: const Text('منتج جديد'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Products Table
          Expanded(
            child: FutureBuilder<List<Product>>(
              future: _getFilteredProducts(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final products = snapshot.data ?? [];

                return Container(
                  margin: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // Table Header
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(12),
                            topRight: Radius.circular(12),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: const Text(
                                'اسم المنتج',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            Expanded(
                              child: const Text(
                                'الباركود',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            Expanded(
                              child: const Text(
                                'الفئة',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            Expanded(
                              child: const Text(
                                'السعر',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            Expanded(
                              child: const Text(
                                'الكمية',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            Expanded(
                              child: const Text(
                                'الحالة',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 100, child: Text('')),
                          ],
                        ),
                      ),

                      const Divider(height: 1),

                      // Products List
                      Expanded(
                        child: products.isEmpty
                            ? const Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.inventory_2_outlined,
                                      size: 64,
                                      color: Colors.grey,
                                    ),
                                    SizedBox(height: 16),
                                    Text(
                                      'لا توجد منتجات',
                                      style: TextStyle(
                                        fontSize: 18,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                itemCount: products.length,
                                itemBuilder: (context, index) {
                                  final product = products[index];
                                  return _buildProductRow(product);
                                },
                              ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<List<Product>> _getFilteredProducts() async {
    try {
      final allProducts = await widget.db.productDao.filterProducts();

      // Filter by category
      var filteredProducts = _selectedCategory == 'الكل'
          ? allProducts
          : allProducts.where((p) => p.category == _selectedCategory).toList();

      // Filter by search query
      if (_searchQuery.isNotEmpty) {
        filteredProducts = filteredProducts
            .where(
              (p) => p.name.toLowerCase().contains(_searchQuery.toLowerCase()),
            )
            .toList();
      }

      return filteredProducts;
    } catch (e) {
      return [];
    }
  }

  Widget _buildProductRow(Product product) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              product.name,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(child: Text(product.barcode ?? '-')),
          Expanded(child: Text(product.category ?? '-')),
          Expanded(
            child: Text(
              '${product.price.toStringAsFixed(2)} ج.م',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(
              '${product.quantity}',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: product.quantity > 10 ? Colors.green : Colors.orange,
              ),
            ),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: product.quantity > 0
                    ? Colors.green.withValues(alpha: 0.1)
                    : Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                product.quantity > 0 ? 'متوفر' : 'نفذ',
                style: TextStyle(
                  color: product.quantity > 0 ? Colors.green : Colors.red,
                  fontWeight: FontWeight.w500,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          SizedBox(
            width: 100,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit, size: 20),
                  onPressed: () => _editProduct(product),
                  tooltip: 'تعديل',
                ),
                IconButton(
                  icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                  onPressed: () => _deleteProduct(product),
                  tooltip: 'حذف',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _addNewProduct() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ProductForm(db: widget.db),
      ),
    ).then((_) => setState(() {}));
  }

  void _editProduct(Product product) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ProductForm(db: widget.db, product: product),
      ),
    ).then((_) => setState(() {}));
  }

  void _deleteProduct(Product product) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل أنت متأكد من حذف المنتج "${product.name}"؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              try {
                await widget.db.productDao.deleteProduct(product);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم حذف المنتج بنجاح')),
                  );
                }
                setState(() {}); // Refresh the list
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('خطأ في الحذف: $e')));
                }
              }
            },
            child: const Text('حذف', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

class CustomersPage extends ConsumerWidget {
  const CustomersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(appDatabaseProvider);

    return _CustomersPageContent(db: db);
  }
}

class _CustomersPageContent extends StatefulWidget {
  final AppDatabase db;

  const _CustomersPageContent({required this.db});

  @override
  State<_CustomersPageContent> createState() => _CustomersPageContentState();
}

class _CustomersPageContentState extends State<_CustomersPageContent> {
  String _searchQuery = '';
  String _selectedFilter = 'الكل';
  final List<String> _filters = ['الكل', 'نشط', 'غير نشط', 'مدين'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'إدارة العملاء',
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 24),

                // Search and Filter Row
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: 'البحث عن عميل...',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onChanged: (value) {
                          setState(() {
                            _searchQuery = value;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        // ignore: deprecated_member_use
                        value: _selectedFilter,
                        decoration: InputDecoration(
                          labelText: 'الحالة',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        items: _filters.map((filter) {
                          return DropdownMenuItem(
                            value: filter,
                            child: Text(filter),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedFilter = value!;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton.icon(
                      onPressed: () => _addNewCustomer(),
                      icon: const Icon(Icons.person_add),
                      label: const Text('عميل جديد'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Customers Table
          Expanded(
            child: FutureBuilder<List<Customer>>(
              future: _getFilteredCustomers(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final customers = snapshot.data ?? [];

                return Container(
                  margin: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // Stats Cards
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Expanded(
                              child: _buildStatCard(
                                'إجمالي العملاء',
                                '${customers.length}',
                                Icons.people,
                                Colors.blue,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _buildStatCard(
                                'العملاء النشطون',
                                '${customers.where((c) => c.isActive).length}',
                                Icons.person,
                                Colors.green,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const Divider(height: 1),

                      // Table Header
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(12),
                            topRight: Radius.circular(12),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: const Text(
                                'اسم العميل',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            Expanded(
                              child: const Text(
                                'الهاتف',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            Expanded(
                              child: const Text(
                                'الرصيد',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            Expanded(
                              child: const Text(
                                'الحالة',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 120, child: Text('')),
                          ],
                        ),
                      ),

                      const Divider(height: 1),

                      // Customers List
                      Expanded(
                        child: customers.isEmpty
                            ? const Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.people_outline,
                                      size: 64,
                                      color: Colors.grey,
                                    ),
                                    SizedBox(height: 16),
                                    Text(
                                      'لا توجد عملاء',
                                      style: TextStyle(
                                        fontSize: 18,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                itemCount: customers.length,
                                itemBuilder: (context, index) {
                                  final customer = customers[index];
                                  return _buildCustomerRow(customer);
                                },
                              ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<List<Customer>> _getFilteredCustomers() async {
    try {
      final allCustomers = await widget.db.customerDao.getAllActiveCustomers();

      // Filter by status
      var filteredCustomers = _selectedFilter == 'الكل'
          ? allCustomers
          : allCustomers.where((c) {
              switch (_selectedFilter) {
                case 'نشط':
                  return c.isActive == true;
                case 'غير نشط':
                  return c.isActive == false;
                case 'مدين':
                  return (c.openingBalance + c.totalDebt - c.totalPaid) < 0;
                default:
                  return true;
              }
            }).toList();
      // Filter by search query
      if (_searchQuery.isNotEmpty) {
        filteredCustomers = filteredCustomers
            .where(
              (c) => c.name.toLowerCase().contains(_searchQuery.toLowerCase()),
            )
            .toList();
      }

      return filteredCustomers;
    } catch (e) {
      return [];
    }
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerRow(Customer customer) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  customer.name,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                if (customer.address?.isNotEmpty == true)
                  Text(
                    customer.address!,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
              ],
            ),
          ),
          Expanded(child: Text(customer.phone ?? '-')),
          Expanded(
            child: Text(
              '${customer.openingBalance.toStringAsFixed(2)} ج.م',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: customer.openingBalance >= 0 ? Colors.green : Colors.red,
              ),
            ),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: customer.isActive == true
                    ? Colors.green.withValues(alpha: 0.1)
                    : Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                customer.isActive == true ? 'نشط' : 'غير نشط',
                style: TextStyle(
                  color: customer.isActive == true ? Colors.green : Colors.red,
                  fontWeight: FontWeight.w500,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          SizedBox(
            width: 120,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.visibility, size: 20),
                  onPressed: () => _viewCustomerDetails(customer),
                  tooltip: 'عرض التفاصيل',
                ),
                IconButton(
                  icon: const Icon(Icons.edit, size: 20),
                  onPressed: () => _editCustomer(customer),
                  tooltip: 'تعديل',
                ),
                IconButton(
                  icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                  onPressed: () => _deleteCustomer(customer),
                  tooltip: 'حذف',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _addNewCustomer() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const AddEditCustomerPage(),
      ),
    ).then((_) => setState(() {}));
  }

  void _viewCustomerDetails(Customer customer) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('تفاصيل العميل: ${customer.name}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('الهاتف: ${customer.phone ?? '-'}'),
              Text('العنوان: ${customer.address ?? '-'}'),
              Text('الرصيد: ${customer.openingBalance.toStringAsFixed(2)} ج.م'),
              Text('الحالة: ${customer.isActive ? 'نشط' : 'غير نشط'}'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  void _editCustomer(Customer customer) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => AddEditCustomerPage(customer: customer),
      ),
    ).then((_) => setState(() {}));
  }

  void _deleteCustomer(Customer customer) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل أنت متأكد من حذف العميل "${customer.name}"؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              try {
                await widget.db.customerDao.deleteCustomer(customer.id);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم حذف العميل بنجاح')),
                  );
                }
                setState(() {}); // Refresh the list
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('خطأ في الحذف: $e')));
                }
              }
            },
            child: const Text('حذف', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

class UsersPage extends ConsumerWidget {
  const UsersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(appDatabaseProvider);

    return _UsersPageContent(db: db);
  }
}

class _UsersPageContent extends StatefulWidget {
  final AppDatabase db;

  const _UsersPageContent({required this.db});

  @override
  State<_UsersPageContent> createState() => _UsersPageContentState();
}

class _UsersPageContentState extends State<_UsersPageContent> {
  String _searchQuery = '';
  String _selectedRole = 'الكل';
  String _selectedStatus = 'الكل';
  final List<String> _roles = ['الكل', 'مدير', 'كاشير', 'مستخدم عادي'];
  final List<String> _statuses = ['الكل', 'نشط', 'غير نشط'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'إدارة المستخدمين',
                  style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 24),

                // Search and Filter Row
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: 'البحث عن مستخدم...',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onChanged: (value) {
                          setState(() {
                            _searchQuery = value;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        // ignore: deprecated_member_use
                        value: _selectedRole,
                        decoration: InputDecoration(
                          labelText: 'الصلاحية',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        items: _roles.map((role) {
                          return DropdownMenuItem(
                            value: role,
                            child: Text(role),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedRole = value!;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        // ignore: deprecated_member_use
                        value: _selectedStatus,
                        decoration: InputDecoration(
                          labelText: 'الحالة',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        items: _statuses.map((status) {
                          return DropdownMenuItem(
                            value: status,
                            child: Text(status),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedStatus = value!;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton.icon(
                      onPressed: () => _addNewUser(),
                      icon: const Icon(Icons.person_add),
                      label: const Text('مستخدم جديد'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Users Table
          Expanded(
            child: FutureBuilder<List<models.User>>(
              future: _getFilteredUsers(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final List<models.User> users = snapshot.data ?? [];

                return Container(
                  margin: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // Stats Cards
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Expanded(
                              child: _buildStatCard(
                                'إجمالي المستخدمين',
                                '${users.length}',
                                Icons.people,
                                Colors.blue,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _buildStatCard(
                                'المستخدمون النشطون',
                                '${users.where((u) => u.isActive).length}',
                                Icons.person,
                                Colors.green,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const Divider(height: 1),

                      // Table Header
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(12),
                            topRight: Radius.circular(12),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: const Text(
                                'اسم المستخدم',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            Expanded(
                              child: const Text(
                                'البريد الإلكتروني',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            Expanded(
                              child: const Text(
                                'الصلاحية',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            Expanded(
                              child: const Text(
                                'الحالة',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            Expanded(
                              child: const Text(
                                'آخر تسجيل دخول',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 120, child: Text('')),
                          ],
                        ),
                      ),

                      const Divider(height: 1),

                      // Users List
                      Expanded(
                        child: users.isEmpty
                            ? const Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.person_outline,
                                      size: 64,
                                      color: Colors.grey,
                                    ),
                                    SizedBox(height: 16),
                                    Text(
                                      'لا توجد مستخدمين',
                                      style: TextStyle(
                                        fontSize: 18,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                itemCount: users.length,
                                itemBuilder: (context, index) {
                                  final user = users[index];
                                  return _buildUserRow(user);
                                },
                              ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<List<models.User>> _getFilteredUsers() async {
    try {
      final allUsers = await widget.db.userDao.getAllUsers();

      // Filter by role
      var filteredUsers = _selectedRole == 'الكل'
          ? allUsers
          : allUsers.where((u) => u.role == _selectedRole).toList();

      // Filter by status
      if (_selectedStatus != 'الكل') {
        filteredUsers = filteredUsers.where((u) {
          switch (_selectedStatus) {
            case 'نشط':
              return u.isActive == true;
            case 'غير نشط':
              return u.isActive == false;
            default:
              return true;
          }
        }).toList();
      }

      // Filter by search query
      if (_searchQuery.isNotEmpty) {
        filteredUsers = filteredUsers
            .where(
              (u) =>
                  u.username.toLowerCase().contains(_searchQuery.toLowerCase()),
            )
            .toList();
      }

      return filteredUsers as List<models.User>;
    } catch (e) {
      return [];
    }
  }

  Widget _buildUserRow(models.User user) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.grey[200]!)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.username,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                if (user.email?.isNotEmpty == true)
                  Text(
                    user.email!,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Text(models.PermissionMatrix.getRoleDisplayName(user.role)),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: user.isActive == true
                    ? Colors.green.withValues(alpha: 0.1)
                    : Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                user.isActive == true ? 'نشط' : 'غير نشط',
                style: TextStyle(
                  color: user.isActive == true ? Colors.green : Colors.red,
                  fontWeight: FontWeight.w500,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          Expanded(
            child: Text(
              user.lastLogin != null
                  ? DateFormat('yyyy-MM-dd HH:mm').format(user.lastLogin!)
                  : 'لم يسجل دخول',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ),
          SizedBox(
            width: 120,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.visibility, size: 20),
                  onPressed: () => _viewUserDetails(user),
                  tooltip: 'عرض التفاصيل',
                ),
                IconButton(
                  icon: const Icon(Icons.edit, size: 20),
                  onPressed: () => _editUser(user),
                  tooltip: 'تعديل',
                ),
                IconButton(
                  icon: Icon(
                    user.isActive == true ? Icons.block : Icons.check_circle,
                    size: 20,
                    color: user.isActive == true ? Colors.orange : Colors.green,
                  ),
                  onPressed: () => _toggleUserStatus(user),
                  tooltip: user.isActive == true ? 'تعطيل' : 'تفعيل',
                ),
                IconButton(
                  icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                  onPressed: () => _deleteUser(user),
                  tooltip: 'حذف',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _addNewUser() {
    final usernameCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    final fullNameCtrl = TextEditingController();
    String selectedRole = 'cashier';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Text('إضافة مستخدم جديد'),
          content: SizedBox(
            width: 350,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: usernameCtrl, decoration: const InputDecoration(labelText: 'اسم المستخدم', border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  TextField(controller: fullNameCtrl, decoration: const InputDecoration(labelText: 'الاسم الكامل', border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  TextField(controller: passwordCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'كلمة المرور', border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedRole,
                    decoration: const InputDecoration(labelText: 'الدور', border: OutlineInputBorder()),
                    items: ['admin', 'manager', 'cashier', 'accountant', 'viewer'].map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                    onChanged: (v) => setDlgState(() => selectedRole = v!),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () async {
                if (usernameCtrl.text.isEmpty || passwordCtrl.text.isEmpty) return;
                try {
                  await widget.db.userDao.createUser(usernameCtrl.text.trim(), passwordCtrl.text, selectedRole, fullNameCtrl.text.trim());
                  if (ctx.mounted) Navigator.pop(ctx);
                  setState(() {});
                } catch (e) {
                  if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('خطأ: $e')));
                }
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  void _viewUserDetails(models.User user) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('تفاصيل المستخدم: ${user.username}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('اسم المستخدم: ${user.username}'),
              Text('البريد الإلكتروني: ${user.email ?? '-'}'),
              Text(
                'الصلاحية: ${models.PermissionMatrix.getRoleDisplayName(user.role)}',
              ),
              Text('الحالة: ${user.isActive ? 'نشط' : 'غير نشط'}'),
              if (user.lastLogin != null)
                Text(
                  'آخر تسجيل دخول: ${DateFormat('yyyy-MM-dd HH:mm').format(user.lastLogin!)}',
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  void _editUser(models.User user) {
    final usernameCtrl = TextEditingController(text: user.username);
    final fullNameCtrl = TextEditingController(text: user.fullName);
    final passwordCtrl = TextEditingController();
    String selectedRole = user.role.name;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: Text('تعديل المستخدم: ${user.username}'),
          content: SizedBox(
            width: 350,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: usernameCtrl, decoration: const InputDecoration(labelText: 'اسم المستخدم', border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  TextField(controller: fullNameCtrl, decoration: const InputDecoration(labelText: 'الاسم الكامل', border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  TextField(controller: passwordCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'كلمة المرور (اتركه فارغًا إذا لم يتغير)', border: OutlineInputBorder())),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedRole,
                    decoration: const InputDecoration(labelText: 'الدور', border: OutlineInputBorder()),
                    items: ['admin', 'manager', 'cashier', 'accountant', 'viewer'].map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                    onChanged: (v) => setDlgState(() => selectedRole = v!),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () async {
                if (usernameCtrl.text.isEmpty) return;
                try {
                  final existing = await widget.db.userDao.getUserById(user.id!);
                  if (existing == null) {
                    if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('المستخدم غير موجود')));
                    return;
                  }
                  final updated = existing.copyWith(
                    username: usernameCtrl.text.trim(),
                    fullName: fullNameCtrl.text.trim().isEmpty ? existing.fullName : fullNameCtrl.text.trim(),
                    role: selectedRole,
                  );
                  await widget.db.userDao.updateUser(updated);
                  if (passwordCtrl.text.isNotEmpty) {
                    await widget.db.userDao.changePassword(user.id!, passwordCtrl.text);
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                  setState(() {});
                } catch (e) {
                  if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('خطأ: $e')));
                }
              },
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }

  void _toggleUserStatus(models.User user) async {
    try {
      final appUser = await widget.db.userDao.getUserById(user.id!);
      if (appUser == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('المستخدم غير موجود'), backgroundColor: Colors.red),
          );
        }
        return;
      }
      await widget.db.userDao.toggleUserStatus(user.id!, !appUser.isActive);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم ${appUser.isActive ? 'تعطيل' : 'تفعيل'} المستخدم بنجاح',
            ),
          ),
        );
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('خطأ في تحديث الحالة: $e')));
      }
    }
  }

  void _deleteUser(models.User user) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل أنت متأكد من حذف المستخدم "${user.username}"؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              try {
                await widget.db.userDao.deleteUser(user.id!);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم حذف المستخدم بنجاح')),
                  );
                }
                setState(() {}); // Refresh the list
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('خطأ في الحذف: $e')));
                }
              }
            },
            child: const Text('حذف', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
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
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    color: color.withValues(alpha: 0.8),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bar_chart, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'صفحة التقارير',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              'تقارير مفصلة وتحليلات',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.settings, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'صفحة الإعدادات',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              'إعدادات النظام والتكوين',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
