import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/data_service.dart';
import '../utils/constants.dart';

/// Revenue Dashboard - لوحة الإيرادات
class RevenueDashboard extends StatefulWidget {
  const RevenueDashboard({super.key});

  @override
  State<RevenueDashboard> createState() => _RevenueDashboardState();
}

class _RevenueDashboardState extends State<RevenueDashboard> {
  final DataService _dataService = DataService();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _dataService.addListener(_onDataChanged);
    _loadData();
  }

  void _onDataChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    await _dataService.init();
    setState(() => _isLoading = false);
  }

  @override
  void dispose() {
    _dataService.removeListener(_onDataChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        color: AppColors.backgroundColor,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 24),
                    _buildStatsCards(),
                    const SizedBox(height: 24),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isMobile = constraints.maxWidth < 600;
                        if (isMobile) {
                          return Column(
                            children: [
                              _buildMonthlyRevenueChart(),
                              const SizedBox(height: 24),
                              _buildPackageDistribution(),
                            ],
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                                flex: 2, child: _buildMonthlyRevenueChart()),
                            const SizedBox(width: 24),
                            Expanded(child: _buildPackageDistribution()),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                    _buildPricingTable(),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'الإيرادات',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: AppColors.primaryColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'تتبع إيرادات مبيعات التراخيص',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.successColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: AppColors.successColor.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.trending_up,
                  color: AppColors.successColor, size: 20),
              const SizedBox(width: 8),
              Text(
                'إجمالي: ${_dataService.totalRevenue.toInt()} ج.م',
                style: const TextStyle(
                  color: AppColors.successColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatsCards() {
    final totalClients = _dataService.getClients().length;

    final cards = <Widget>[
      _buildStatCard(
        'إجمالي العملاء',
        totalClients.toString(),
        Icons.people,
        AppColors.accentColor,
        'عميل مسجل',
      ),
      _buildStatCard(
        'إيرادات هذا الشهر',
        '${_getThisMonthRevenue().toInt()} ج',
        Icons.calendar_today,
        AppColors.successColor,
        _getRevenueGrowth(),
      ),
      _buildStatCard(
        'التراخيص النشطة',
        _dataService.activeLicensesCount.toString(),
        Icons.verified,
        AppColors.professionalColor,
        'ترخيص نشط',
      ),
      _buildStatCard(
        'معدل التجديد',
        '${_getRenewalRate().toStringAsFixed(0)}%',
        Icons.refresh,
        AppColors.warningColor,
        'من العملاء',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 900;
        if (isWide) {
          return Row(
            children: [
              Expanded(child: cards[0]),
              const SizedBox(width: 16),
              Expanded(child: cards[1]),
              const SizedBox(width: 16),
              Expanded(child: cards[2]),
              const SizedBox(width: 16),
              Expanded(child: cards[3]),
            ],
          );
        }

        final width = constraints.maxWidth;
        final crossAxisCount = width >= 600 ? 2 : 1;
        const spacing = 16.0;
        final cardWidth = crossAxisCount == 1
            ? width
            : (width - (spacing * (crossAxisCount - 1))) / crossAxisCount;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children:
              cards.map((c) => SizedBox(width: cardWidth, child: c)).toList(),
        );
      },
    );
  }

  Widget _buildStatCard(
      String title, String value, IconData icon, Color color, String subtitle) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            value,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthlyRevenueChart() {
    final monthlyRevenue = _dataService.getMonthlyRevenue();
    final entries = monthlyRevenue.entries.toList();

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'الإيرادات الشهرية',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.primaryColor,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 300,
            child: entries.isEmpty || entries.every((e) => e.value == 0)
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.bar_chart,
                            size: 60, color: Colors.grey[300]),
                        const SizedBox(height: 16),
                        Text(
                          'لا توجد إيرادات بعد',
                          style: TextStyle(color: Colors.grey[500]),
                        ),
                      ],
                    ),
                  )
                : BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      maxY: entries
                              .map((e) => e.value)
                              .reduce((a, b) => a > b ? a : b) *
                          1.2,
                      barTouchData: BarTouchData(
                        enabled: true,
                        touchTooltipData: BarTouchTooltipData(
                          getTooltipItem: (group, groupIndex, rod, rodIndex) {
                            return BarTooltipItem(
                              '${rod.toY.toInt()} ج.م',
                              const TextStyle(color: Colors.white),
                            );
                          },
                        ),
                      ),
                      titlesData: FlTitlesData(
                        show: true,
                        rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (value, meta) {
                              final index = value.toInt();
                              if (index >= 0 && index < entries.length) {
                                final month =
                                    entries[index].key.split('-').last;
                                return Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(
                                    _getMonthName(int.parse(month)),
                                    style: TextStyle(
                                        fontSize: 10, color: Colors.grey[600]),
                                  ),
                                );
                              }
                              return const Text('');
                            },
                          ),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 40,
                            getTitlesWidget: (value, meta) {
                              return Text(
                                '${value.toInt()}',
                                style: TextStyle(
                                    fontSize: 10, color: Colors.grey[600]),
                              );
                            },
                          ),
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      gridData: FlGridData(
                        show: true,
                        drawHorizontalLine: true,
                        drawVerticalLine: false,
                        horizontalInterval: entries
                                .map((e) => e.value)
                                .reduce((a, b) => a > b ? a : b) /
                            5,
                        getDrawingHorizontalLine: (value) => FlLine(
                          color: Colors.grey[200]!,
                          strokeWidth: 1,
                        ),
                      ),
                      barGroups: entries.asMap().entries.map((entry) {
                        return BarChartGroupData(
                          x: entry.key,
                          barRods: [
                            BarChartRodData(
                              toY: entry.value.value,
                              color: AppColors.accentColor,
                              width: 20,
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(6)),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPackageDistribution() {
    final stats = _dataService.getClientsCountByPackage();
    final total = stats.values.fold(0, (sum, count) => sum + count);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'توزيع الباقات',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.primaryColor,
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 200,
            child: total == 0
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.pie_chart,
                            size: 60, color: Colors.grey[300]),
                        const SizedBox(height: 16),
                        Text(
                          'لا توجد بيانات',
                          style: TextStyle(color: Colors.grey[500]),
                        ),
                      ],
                    ),
                  )
                : PieChart(
                    PieChartData(
                      sectionsSpace: 2,
                      centerSpaceRadius: 40,
                      sections: [
                        PieChartSectionData(
                          value: (stats['basic'] ?? 0).toDouble(),
                          color: AppColors.basicColor,
                          title: '${stats['basic'] ?? 0}',
                          titleStyle: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold),
                          radius: 50,
                        ),
                        PieChartSectionData(
                          value: (stats['standard'] ?? 0).toDouble(),
                          color: AppColors.standardColor,
                          title: '${stats['standard'] ?? 0}',
                          titleStyle: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold),
                          radius: 50,
                        ),
                        PieChartSectionData(
                          value: (stats['professional'] ?? 0).toDouble(),
                          color: AppColors.professionalColor,
                          title: '${stats['professional'] ?? 0}',
                          titleStyle: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold),
                          radius: 50,
                        ),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 24),
          _buildLegendItem('أساسي', AppColors.basicColor, stats['basic'] ?? 0),
          const SizedBox(height: 8),
          _buildLegendItem(
              'قياسي', AppColors.standardColor, stats['standard'] ?? 0),
          const SizedBox(height: 8),
          _buildLegendItem('احترافي', AppColors.professionalColor,
              stats['professional'] ?? 0),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color, int count) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(label)),
        Text('$count', style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildPricingTable() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'جدول الأسعار',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.primaryColor,
            ),
          ),
          const SizedBox(height: 16),
          Table(
            columnWidths: const {
              0: FlexColumnWidth(2),
              1: FlexColumnWidth(1),
              2: FlexColumnWidth(1),
              3: FlexColumnWidth(1),
              4: FlexColumnWidth(1),
            },
            children: [
              TableRow(
                decoration: BoxDecoration(
                  color: AppColors.primaryColor.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                children: const [
                  Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('الباقة',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('شهري',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('سنوي',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('مدى الحياة',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('المميزات',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              _buildPricingRow(
                  'أساسي', 250, 'عمليات البيع فقط', AppColors.basicColor),
              _buildPricingRow('قياسي', 400, 'البيع + العملاء والموردين',
                  AppColors.standardColor),
              _buildPricingRow('احترافي', 600, 'كل المميزات + الموظفين',
                  AppColors.professionalColor),
            ],
          ),
        ],
      ),
    );
  }

  TableRow _buildPricingRow(
      String name, double monthlyPrice, String features, Color color) {
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 8),
              Text(name,
                  style: TextStyle(color: color, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text('${monthlyPrice.toInt()} ج'),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text('${(monthlyPrice * 10).toInt()} ج'),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text('${(monthlyPrice * 24).toInt()} ج'),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(features,
              style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        ),
      ],
    );
  }

  double _getThisMonthRevenue() {
    final now = DateTime.now();
    final monthKey = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final monthlyRevenue = _dataService.getMonthlyRevenue();
    return monthlyRevenue[monthKey] ?? 0.0;
  }

  String _getRevenueGrowth() {
    // Simplified growth calculation
    final thisMonth = _getThisMonthRevenue();
    if (thisMonth > 0) {
      return '↑ إيرادات جديدة';
    }
    return 'ابدأ البيع';
  }

  double _getRenewalRate() {
    final total = _dataService.getLicenses().length;
    if (total == 0) return 0;
    final active = _dataService.activeLicensesCount;
    return (active / total) * 100;
  }

  String _getMonthName(int month) {
    const months = [
      'يناير',
      'فبراير',
      'مارس',
      'أبريل',
      'مايو',
      'يونيو',
      'يوليو',
      'أغسطس',
      'سبتمبر',
      'أكتوبر',
      'نوفمبر',
      'ديسمبر'
    ];
    return months[month - 1];
  }
}
