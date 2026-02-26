import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../services/data_service.dart';
import '../utils/constants.dart';
// ignore: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:convert';

class DashboardOverview extends StatefulWidget {
  const DashboardOverview({super.key});

  @override
  State<DashboardOverview> createState() => _DashboardOverviewState();
}

class _DashboardOverviewState extends State<DashboardOverview> {
  WebBrowserInfo? _webInfo;
  final DataService _dataService = DataService();

  @override
  void initState() {
    super.initState();
    _loadSystemInfo();
    _dataService.init().then((_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _loadSystemInfo() async {
    final deviceInfo = DeviceInfoPlugin();
    _webInfo = await deviceInfo.webBrowserInfo;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // Header — Wrap for responsive
          _buildHeader(),

          const SizedBox(height: 32),

          // Stats Cards — responsive
          _buildStatsCards(),

          const SizedBox(height: 32),

          // Charts Section — responsive
          _buildChartsSection(),

          const SizedBox(height: 32),

          // Recent Transactions
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'آخر التراخيص',
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

  // ════════════════════════════════════════════════════════════════════
  // Header — Wrap for responsive
  // ════════════════════════════════════════════════════════════════════

  Widget _buildHeader() {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 12,
      children: [
        const Text(
          'لوحة التحكم',
          style: TextStyle(
            fontSize: 28,
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
    );
  }

  // ════════════════════════════════════════════════════════════════════
  // Stats Cards — LayoutBuilder for responsive
  // ════════════════════════════════════════════════════════════════════

  Widget _buildStatsCards() {
    final clients = _dataService.getClients();
    final licenses = _dataService.getLicenses();

    final cards = <Widget>[
      _buildStatCard(
        'إجمالي الإيرادات',
        '${_dataService.totalRevenue.toStringAsFixed(0)} ج.م',
        Icons.trending_up,
        AppColors.successColor,
        _getRevenueGrowth(),
        true,
      ),
      _buildStatCard(
        'عدد العملاء',
        clients.length.toString(),
        Icons.people,
        AppColors.primaryColor,
        '${clients.length} عميل',
        true,
      ),
      _buildStatCard(
        'عدد التراخيص',
        licenses.length.toString(),
        Icons.inventory,
        AppColors.warningColor,
        '${_dataService.activeLicensesCount} نشط',
        true,
      ),
      _buildStatCard(
        'التراخيص النشطة',
        _dataService.activeLicensesCount.toString(),
        Icons.inventory_2,
        AppColors.accentColor,
        'ترخيص فعّال',
        true,
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

  // ════════════════════════════════════════════════════════════════════
  // Charts Section — LayoutBuilder for responsive
  // ════════════════════════════════════════════════════════════════════

  Widget _buildChartsSection() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 800;

        final pieCard = Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'العملاء حسب الباقة',
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
        );

        final barCard = Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'الإيرادات الشهرية',
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
        );

        if (isWide) {
          return Row(
            children: [
              Expanded(child: pieCard),
              const SizedBox(width: 16),
              Expanded(child: barCard),
            ],
          );
        } else {
          return Column(
            children: [
              pieCard,
              const SizedBox(height: 16),
              barCard,
            ],
          );
        }
      },
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
                    fontSize: 12,
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
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════
  // Pie Chart — real data from DataService
  // ════════════════════════════════════════════════════════════════════

  Widget _buildPieChart() {
    final packageCounts = _dataService.getClientsCountByPackage();
    final total = packageCounts.values.fold(0, (a, b) => a + b);

    if (total == 0) {
      return const Center(
        child: Text(
          'لا توجد بيانات بعد',
          style: TextStyle(color: Colors.grey, fontSize: 16),
        ),
      );
    }

    final basicPct = (packageCounts['basic'] ?? 0) / total * 100;
    final standardPct = (packageCounts['standard'] ?? 0) / total * 100;
    final professionalPct = (packageCounts['professional'] ?? 0) / total * 100;

    return PieChart(
      PieChartData(
        sectionsSpace: 2,
        centerSpaceRadius: 60,
        sections: [
          if (basicPct > 0)
            PieChartSectionData(
              color: AppColors.primaryColor,
              value: basicPct,
              title: '${basicPct.toStringAsFixed(0)}%',
              radius: 50,
              titleStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          if (standardPct > 0)
            PieChartSectionData(
              color: AppColors.warningColor,
              value: standardPct,
              title: '${standardPct.toStringAsFixed(0)}%',
              radius: 50,
              titleStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          if (professionalPct > 0)
            PieChartSectionData(
              color: AppColors.successColor,
              value: professionalPct,
              title: '${professionalPct.toStringAsFixed(0)}%',
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

  // ════════════════════════════════════════════════════════════════════
  // Bar Chart — real monthly revenue from DataService
  // ════════════════════════════════════════════════════════════════════

  Widget _buildBarChart() {
    final monthlyRevenue = _dataService.getMonthlyRevenue();

    if (monthlyRevenue.isEmpty || monthlyRevenue.values.every((v) => v == 0)) {
      return const Center(
        child: Text(
          'لا توجد إيرادات بعد',
          style: TextStyle(color: Colors.grey, fontSize: 16),
        ),
      );
    }

    final entries = monthlyRevenue.entries.toList();
    // Take last 6 months
    final recent =
        entries.length > 6 ? entries.sublist(entries.length - 6) : entries;

    return BarChart(
      BarChartData(
        barGroups: recent.asMap().entries.map((entry) {
          return BarChartGroupData(
            x: entry.key,
            barRods: [
              BarChartRodData(
                toY: entry.value.value,
                color: AppColors.primaryColor,
                width: 20,
              ),
            ],
          );
        }).toList(),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 50),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                if (idx < 0 || idx >= recent.length) {
                  return SideTitleWidget(
                    axisSide: meta.axisSide,
                    child: const Text(''),
                  );
                }
                // Extract month from key like "2026-02"
                final parts = recent[idx].key.split('-');
                final monthNum =
                    parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
                return SideTitleWidget(
                  axisSide: meta.axisSide,
                  child: Text(
                    _getMonthName(monthNum),
                    style: const TextStyle(fontSize: 11),
                  ),
                );
              },
            ),
          ),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        gridData: FlGridData(show: false),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════
  // Recent Transactions — real data from DataService
  // ════════════════════════════════════════════════════════════════════

  Widget _buildRecentTransactions() {
    final allLicenses = _dataService.getLicenses();
    if (allLicenses.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'لا توجد تراخيص بعد',
            style: TextStyle(color: Colors.grey, fontSize: 16),
          ),
        ),
      );
    }

    // Sort by createdAt descending
    final sorted = List.of(allLicenses)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final recent = sorted.take(5).toList();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('مفتاح الترخيص')),
          DataColumn(label: Text('العميل')),
          DataColumn(label: Text('المبلغ')),
          DataColumn(label: Text('التاريخ')),
          DataColumn(label: Text('الحالة')),
        ],
        rows: recent.map((license) {
          final statusColor =
              license.isExpired ? AppColors.errorColor : AppColors.successColor;
          final statusLabel = license.isExpired ? 'منتهي' : 'نشط';

          return DataRow(
            cells: [
              DataCell(Text(
                license.licenseKey.length > 16
                    ? '${license.licenseKey.substring(0, 16)}...'
                    : license.licenseKey,
              )),
              DataCell(Text(license.clientName)),
              DataCell(Text('${license.price.toStringAsFixed(0)} ج.م')),
              DataCell(Text(_formatDate(license.createdAt))),
              DataCell(
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w500,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ],
          );
        }).toList(),
      ),
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
    try {
      final licenses = _dataService.getLicenses();
      String csv = 'License Key,Client Name,Price,Status,Created At\n';

      for (var l in licenses) {
        csv +=
            '${l.licenseKey},${l.clientName},${l.price},${l.isExpired ? "Expired" : "Active"},${l.createdAt}\n';
      }

      final bytes = utf8.encode(csv);
      final blob = html.Blob([bytes], 'text/csv');
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: url)
        ..setAttribute('download',
            'dashboard_report_${DateTime.now().millisecondsSinceEpoch}.csv')
        ..click();
      html.Url.revokeObjectUrl(url);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم تصدير التقرير بنجاح'),
          backgroundColor: AppColors.successColor,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('فشل تصدير التقرير: $e'),
          backgroundColor: AppColors.errorColor,
        ),
      );
    }
  }

  // ════════════════════════════════════════════════════════════════════
  // Helper methods
  // ════════════════════════════════════════════════════════════════════

  String _getRevenueGrowth() {
    final monthly = _dataService.getMonthlyRevenue();
    if (monthly.length < 2) return 'لا توجد بيانات كافية';
    final entries = monthly.entries.toList();
    final current = entries.last.value;
    final previous = entries[entries.length - 2].value;
    if (previous == 0) return current > 0 ? '+100%' : '0%';
    final growth = ((current - previous) / previous * 100).toStringAsFixed(1);
    return '${double.parse(growth) >= 0 ? '+' : ''}$growth%';
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  String _getMonthName(int month) {
    const months = [
      '',
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
      'ديسمبر',
    ];
    if (month >= 1 && month <= 12) return months[month];
    return '';
  }
}
