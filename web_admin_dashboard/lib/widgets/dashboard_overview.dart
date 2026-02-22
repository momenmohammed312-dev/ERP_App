import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../utils/constants.dart';

class DashboardOverview extends StatefulWidget {
  const DashboardOverview({super.key});

  @override
  State<DashboardOverview> createState() => _DashboardOverviewState();
}

class _DashboardOverviewState extends State<DashboardOverview> {
  WebBrowserInfo? _webInfo;

  @override
  void initState() {
    super.initState();
    _loadSystemInfo();
  }

  Future<void> _loadSystemInfo() async {
    final deviceInfo = DeviceInfoPlugin();
    _webInfo = await deviceInfo.webBrowserInfo;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'لوحة التحكم',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primaryColor,
                ),
              ),
              ElevatedButton.icon(
                onPressed: _exportReport,
                icon: const Icon(Icons.download),
                label: const Text('تصدير التقرير'),
              ),
            ],
          ),

          const SizedBox(height: 32),

          // Stats Cards
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'إجمالي المبيعات',
                  '45,678.90 ج.م',
                  Icons.trending_up,
                  AppColors.successColor,
                  '+12.5%',
                  true,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildStatCard(
                  'عدد العملاء',
                  '1,234',
                  Icons.people,
                  AppColors.primaryColor,
                  '+8.2%',
                  true,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildStatCard(
                  'عدد المنتجات',
                  '567',
                  Icons.inventory,
                  AppColors.warningColor,
                  '-2.1%',
                  false,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildStatCard(
                  'المخزون',
                  '23,456 ج.م',
                  Icons.inventory_2,
                  AppColors.accentColor,
                  '+5.7%',
                  true,
                ),
              ),
            ],
          ),

          const SizedBox(height: 32),

          // Charts Section
          Row(
            children: [
              // Pie Chart
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'المبيعات حسب الفئة',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          height: 300,
                          child: _buildPieChart(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),

              // Bar Chart
              Expanded(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'المبيعات الشهرية',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          height: 300,
                          child: _buildBarChart(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 32),

          // Recent Transactions
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'آخر المعاملات',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildRecentTransactions(),
                ],
              ),
            ),
          ),

          const SizedBox(height: 32),

          // System Information
          _buildSystemInfoCard(),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color,
      String change, bool isPositive) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const Spacer(),
                Icon(
                  isPositive ? Icons.trending_up : Icons.trending_down,
                  color: isPositive
                      ? AppColors.successColor
                      : AppColors.errorColor,
                  size: 16,
                ),
                const SizedBox(width: 4),
                Text(
                  change,
                  style: TextStyle(
                    color: isPositive
                        ? AppColors.successColor
                        : AppColors.errorColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPieChart() {
    return PieChart(
      PieChartData(
        sectionsSpace: 2,
        centerSpaceRadius: 60,
        sections: [
          PieChartSectionData(
            color: AppColors.primaryColor,
            value: 35,
            title: '35%',
            radius: 50,
            titleStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          PieChartSectionData(
            color: AppColors.warningColor,
            value: 25,
            title: '25%',
            radius: 50,
            titleStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          PieChartSectionData(
            color: AppColors.successColor,
            value: 20,
            title: '20%',
            radius: 50,
            titleStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          PieChartSectionData(
            color: AppColors.accentColor,
            value: 20,
            title: '20%',
            radius: 50,
            titleStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBarChart() {
    return BarChart(
      BarChartData(
        barGroups: [
          BarChartGroupData(
            x: 0,
            barRods: [
              BarChartRodData(
                toY: 12000,
                color: AppColors.primaryColor,
                width: 20,
              ),
            ],
          ),
          BarChartGroupData(
            x: 1,
            barRods: [
              BarChartRodData(
                toY: 15000,
                color: AppColors.primaryColor,
                width: 20,
              ),
            ],
          ),
          BarChartGroupData(
            x: 2,
            barRods: [
              BarChartRodData(
                toY: 18000,
                color: AppColors.primaryColor,
                width: 20,
              ),
            ],
          ),
          BarChartGroupData(
            x: 3,
            barRods: [
              BarChartRodData(
                toY: 14000,
                color: AppColors.primaryColor,
                width: 20,
              ),
            ],
          ),
          BarChartGroupData(
            x: 4,
            barRods: [
              BarChartRodData(
                toY: 16000,
                color: AppColors.primaryColor,
                width: 20,
              ),
            ],
          ),
          BarChartGroupData(
            x: 5,
            barRods: [
              BarChartRodData(
                toY: 20000,
                color: AppColors.primaryColor,
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
                const months = [
                  'يناير',
                  'فبراير',
                  'مارس',
                  'أبريل',
                  'مايو',
                  'يونيو'
                ];
                if (value.toInt() < months.length) {
                  return SideTitleWidget(
                    axisSide: meta.axisSide,
                    child: Text(months[value.toInt()]),
                  );
                }
                return SideTitleWidget(
                  axisSide: meta.axisSide,
                  child: Text(''),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        gridData: FlGridData(show: false),
      ),
    );
  }

  Widget _buildRecentTransactions() {
    final transactions = [
      {
        'id': 'INV-001',
        'customer': 'أحمد محمد',
        'amount': '1,234.50',
        'date': '2024-01-15',
        'status': 'مدفوع'
      },
      {
        'id': 'INV-002',
        'customer': 'فاطمة علي',
        'amount': '890.00',
        'date': '2024-01-15',
        'status': 'مدفوع'
      },
      {
        'id': 'INV-003',
        'customer': 'محمد سعيد',
        'amount': '2,456.75',
        'date': '2024-01-14',
        'status': 'مدفوع'
      },
      {
        'id': 'INV-004',
        'customer': 'خالد أحمد',
        'amount': '567.25',
        'date': '2024-01-14',
        'status': 'مدفوع'
      },
      {
        'id': 'INV-005',
        'customer': 'عمر خالد',
        'amount': '3,234.00',
        'date': '2024-01-13',
        'status': 'مدفوع'
      },
    ];

    return DataTable(
      columns: const [
        DataColumn(
          label: Text('رقم الفاتورة'),
        ),
        DataColumn(
          label: Text('العميل'),
        ),
        DataColumn(
          label: Text('المبلغ'),
        ),
        DataColumn(
          label: Text('التاريخ'),
        ),
        DataColumn(
          label: Text('الحالة'),
        ),
      ],
      rows: transactions.map((transaction) {
        return DataRow(
          cells: [
            DataCell(Text(transaction['id']!)),
            DataCell(Text(transaction['customer']!)),
            DataCell(Text(transaction['amount']!)),
            DataCell(Text(transaction['date']!)),
            DataCell(
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.successColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  transaction['status']!,
                  style: TextStyle(
                    color: AppColors.successColor,
                    fontWeight: FontWeight.w500,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildSystemInfoCard() {
    if (_webInfo == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'معلومات النظام',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Text('المتصفح: ${_webInfo!.browserName}'),
            Text('إصدار المتصفح: ${_webInfo!.appVersion}'),
            Text('نظام التشغيل: ${_webInfo!.platform}'),
            Text('اللغة: ${_webInfo!.language}'),
            Text('المنصة: ${_webInfo!.product}'),
          ],
        ),
      ),
    );
  }

  void _exportReport() {
    // محاكاة تصدير التقرير
    // في التطبيق الحقيقي، سيتم الاتصال بالـ API وتصدير البيانات
    // ignore: avoid_print
    print('تصدير التقرير...');
  }
}
