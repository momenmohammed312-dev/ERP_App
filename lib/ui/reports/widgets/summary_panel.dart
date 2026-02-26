import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/export_service_simple.dart';

class SummaryPanel extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  final String reportType;
  final VoidCallback onExport;
  final VoidCallback onPrint;

  const SummaryPanel({
    super.key,
    required this.data,
    required this.reportType,
    required this.onExport,
    required this.onPrint,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(
                  Icons.summarize,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'ملخص النتائج',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const Spacer(),
                Text(
                  'الإجمالي: ${data.length}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Summary statistics
            _buildSummaryStatistics(context),

            const SizedBox(height: 16),

            // Charts section
            if (_shouldShowCharts()) _buildChartsSection(context),

            const SizedBox(height: 16),

            // Action buttons
            _buildActionButtons(context),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryStatistics(BuildContext context) {
    final summary = _calculateSummary();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildSummaryItem(
                  title: _getMainTitle(),
                  value: _getMainValue(summary),
                  color: _getMainColor(context),
                  icon: _getMainIcon(),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildSummaryItem(
                  title: _getSecondaryTitle(),
                  value: _getSecondaryValue(summary),
                  color: _getSecondaryColor(context),
                  icon: _getSecondaryIcon(),
                ),
              ),
            ],
          ),

          if (_showTertiaryItem()) ...[
            const SizedBox(height: 16),
            _buildSummaryItem(
              title: _getTertiaryTitle(),
              value: _getTertiaryValue(summary),
              color: _getTertiaryColor(context),
              icon: _getTertiaryIcon(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSummaryItem({
    required String title,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: color,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () async {
              try {
                await ExportService.exportToCSV(
                  data: data,
                  reportType: reportType,
                  fileName: 'تقرير_$reportType',
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('تم تصدير البيانات بنجاح')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('فشل في التصدير: $e')));
                }
              }
            },
            icon: const Icon(Icons.download),
            label: const Text('تصدير'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () async {
              try {
                await ExportService.exportToCSV(
                  data: data,
                  reportType: reportType,
                  fileName: 'تقرير_$reportType',
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('جاري إعداد الطباعة...')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('فشل في الطباعة: $e')));
                }
              }
            },
            icon: const Icon(Icons.print),
            label: const Text('طباعة'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  Map<String, dynamic> _calculateSummary() {
    if (data.isEmpty) return {};

    switch (reportType) {
      case 'sales':
        final totalAmount = data.fold<double>(
          0.0,
          (sum, item) => sum + (item['totalAmount'] as double? ?? 0.0),
        );
        final paidAmount = data.fold<double>(
          0.0,
          (sum, item) => sum + (item['paidAmount'] as double? ?? 0.0),
        );
        final unpaidAmount = totalAmount - paidAmount;

        return {
          'totalAmount': totalAmount,
          'paidAmount': paidAmount,
          'unpaidAmount': unpaidAmount,
          'count': data.length,
        };

      case 'customers':
        final totalBalance = data.fold<double>(
          0.0,
          (sum, item) => sum + (item['balance'] as double? ?? 0.0),
        );
        final positiveBalance = data
            .where((item) => (item['balance'] as double? ?? 0.0) > 0)
            .length;
        final negativeBalance = data
            .where((item) => (item['balance'] as double? ?? 0.0) < 0)
            .length;

        return {
          'totalBalance': totalBalance,
          'positiveCount': positiveBalance,
          'negativeCount': negativeBalance,
          'count': data.length,
        };

      case 'suppliers':
        final totalBalance = data.fold<double>(
          0.0,
          (sum, item) => sum + (item['balance'] as double? ?? 0.0),
        );

        return {'totalBalance': totalBalance, 'count': data.length};

      case 'products':
        final totalQuantity = data.fold<int>(
          0,
          (sum, item) => sum + (item['quantity'] as int? ?? 0),
        );
        final totalSold = data.fold<int>(
          0,
          (sum, item) => sum + (item['totalSold'] as int? ?? 0),
        );
        final totalValue = data.fold<double>(
          0.0,
          (sum, item) =>
              sum +
              ((item['quantity'] as int? ?? 0) *
                  (item['price'] as double? ?? 0.0)),
        );

        return {
          'totalQuantity': totalQuantity,
          'totalSold': totalSold,
          'totalValue': totalValue,
          'count': data.length,
        };

      case 'financial':
        final totalIncome = data
            .where((item) => (item['type'] as String? ?? '') == 'دخل')
            .fold<double>(
              0.0,
              (sum, item) => sum + (item['amount'] as double? ?? 0.0),
            );
        final totalExpenses = data
            .where((item) => (item['type'] as String? ?? '') == 'مصروف')
            .fold<double>(
              0.0,
              (sum, item) => sum + (item['amount'] as double? ?? 0.0).abs(),
            );
        final netAmount = totalIncome - totalExpenses;

        return {
          'totalIncome': totalIncome,
          'totalExpenses': totalExpenses,
          'netAmount': netAmount,
          'count': data.length,
        };

      default:
        return {'count': data.length};
    }
  }

  String _getMainTitle() {
    switch (reportType) {
      case 'sales':
        return 'إجمالي المبيعات';
      case 'customers':
        return 'إجمالي الرصيد';
      case 'suppliers':
        return 'إجمالي المستحقات';
      case 'products':
        return 'قيمة المخزون';
      case 'financial':
        return 'صافي الإيرادات';
      default:
        return 'الإجمالي';
    }
  }

  String _getMainValue(Map<String, dynamic> summary) {
    switch (reportType) {
      case 'sales':
        return (summary['totalAmount'] as double? ?? 0.0).toStringAsFixed(2);
      case 'customers':
        return (summary['totalBalance'] as double? ?? 0.0).toStringAsFixed(2);
      case 'suppliers':
        return (summary['totalBalance'] as double? ?? 0.0).toStringAsFixed(2);
      case 'products':
        return (summary['totalValue'] as double? ?? 0.0).toStringAsFixed(2);
      case 'financial':
        return (summary['netAmount'] as double? ?? 0.0).toStringAsFixed(2);
      default:
        return (summary['count'] ?? 0).toString();
    }
  }

  Color _getMainColor(BuildContext context) {
    switch (reportType) {
      case 'sales':
        return Colors.blue;
      case 'customers':
        return Colors.orange;
      case 'suppliers':
        return Colors.purple;
      case 'products':
        return Colors.teal;
      case 'financial':
        return Colors.green;
      default:
        return Theme.of(context).colorScheme.primary;
    }
  }

  IconData _getMainIcon() {
    switch (reportType) {
      case 'sales':
        return Icons.shopping_cart;
      case 'customers':
        return Icons.people;
      case 'suppliers':
        return Icons.business;
      case 'products':
        return Icons.inventory;
      case 'financial':
        return Icons.account_balance;
      default:
        return Icons.summarize;
    }
  }

  String _getSecondaryTitle() {
    switch (reportType) {
      case 'sales':
        return 'المبلغ المدفوع';
      case 'customers':
        return 'العملاء المدينون';
      case 'suppliers':
        return 'عدد الموردين';
      case 'products':
        return 'الكمية الكلية';
      case 'financial':
        return 'إجمالي الإيرادات';
      default:
        return 'العدد';
    }
  }

  String _getSecondaryValue(Map<String, dynamic> summary) {
    switch (reportType) {
      case 'sales':
        return (summary['paidAmount'] as double? ?? 0.0).toStringAsFixed(2);
      case 'customers':
        return (summary['positiveCount'] ?? 0).toString();
      case 'suppliers':
        return (summary['count'] ?? 0).toString();
      case 'products':
        return (summary['totalQuantity'] ?? 0).toString();
      case 'financial':
        return (summary['totalIncome'] as double? ?? 0.0).toStringAsFixed(2);
      default:
        return (summary['count'] ?? 0).toString();
    }
  }

  Color _getSecondaryColor(BuildContext context) {
    switch (reportType) {
      case 'sales':
        return Colors.green;
      case 'customers':
        return Colors.red;
      case 'suppliers':
        return Colors.blue;
      case 'products':
        return Colors.orange;
      case 'financial':
        return Colors.blue;
      default:
        return Theme.of(context).colorScheme.secondary;
    }
  }

  IconData _getSecondaryIcon() {
    switch (reportType) {
      case 'sales':
        return Icons.payments;
      case 'customers':
        return Icons.trending_up;
      case 'suppliers':
        return Icons.store;
      case 'products':
        return Icons.category;
      case 'financial':
        return Icons.trending_up;
      default:
        return Icons.info;
    }
  }

  bool _showTertiaryItem() {
    return ['sales', 'customers', 'products', 'financial'].contains(reportType);
  }

  String _getTertiaryTitle() {
    switch (reportType) {
      case 'sales':
        return 'المبلغ غير المدفوع';
      case 'customers':
        return 'العملاء الدائنون';
      case 'products':
        return 'الكمية المباعة';
      case 'financial':
        return 'إجمالي المصروفات';
      default:
        return '';
    }
  }

  String _getTertiaryValue(Map<String, dynamic> summary) {
    switch (reportType) {
      case 'sales':
        return (summary['unpaidAmount'] as double? ?? 0.0).toStringAsFixed(2);
      case 'customers':
        return (summary['negativeCount'] ?? 0).toString();
      case 'products':
        return (summary['totalSold'] ?? 0).toString();
      case 'financial':
        return (summary['totalExpenses'] as double? ?? 0.0).toStringAsFixed(2);
      default:
        return '0';
    }
  }

  Color _getTertiaryColor(BuildContext context) {
    switch (reportType) {
      case 'sales':
        return Colors.red;
      case 'customers':
        return Colors.green;
      case 'products':
        return Colors.purple;
      case 'financial':
        return Colors.red;
      default:
        return Theme.of(context).colorScheme.outline;
    }
  }

  IconData _getTertiaryIcon() {
    switch (reportType) {
      case 'sales':
        return Icons.money_off;
      case 'customers':
        return Icons.trending_down;
      case 'products':
        return Icons.sell;
      case 'financial':
        return Icons.trending_down;
      default:
        return Icons.info_outline;
    }
  }

  bool _shouldShowCharts() {
    return data.isNotEmpty &&
        ['sales', 'customers', 'products', 'financial'].contains(reportType);
  }

  Widget _buildChartsSection(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'الرسوم البيانية',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(height: 250, child: _buildChart()),
        ],
      ),
    );
  }

  Widget _buildChart() {
    switch (reportType) {
      case 'sales':
        return _buildSalesChart();
      case 'customers':
        return _buildCustomersChart();
      case 'products':
        return _buildProductsChart();
      case 'financial':
        return _buildFinancialChart();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildSalesChart() {
    // Simple bar chart showing top sales amounts
    final topSales = data.take(5).toList();

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: topSales.isNotEmpty
            ? topSales
                      .map((e) => e['totalAmount'] as double? ?? 0.0)
                      .reduce((a, b) => a > b ? a : b) *
                  1.2
            : 1000,
        barGroups: topSales.asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value;
          final amount = item['totalAmount'] as double? ?? 0.0;

          return BarChartGroupData(
            x: index,
            barRods: [
              BarChartRodData(toY: amount, color: Colors.blue, width: 20),
            ],
          );
        }).toList(),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                if (value.toInt() < topSales.length) {
                  return Text(
                    topSales[value.toInt()]['invoiceNumber']?.toString() ?? '',
                    style: const TextStyle(fontSize: 10),
                  );
                }
                return const Text('');
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 40),
          ),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        gridData: FlGridData(show: true),
      ),
    );
  }

  Widget _buildCustomersChart() {
    // Pie chart showing customer balance distribution
    final positiveBalance = data
        .where((item) => (item['balance'] as double? ?? 0.0) > 0)
        .length;
    final negativeBalance = data
        .where((item) => (item['balance'] as double? ?? 0.0) < 0)
        .length;
    final zeroBalance = data.length - positiveBalance - negativeBalance;

    final sections = <PieChartSectionData>[];

    if (positiveBalance > 0) {
      sections.add(
        PieChartSectionData(
          value: positiveBalance.toDouble(),
          title: '$positiveBalance',
          color: Colors.red,
          radius: 60,
        ),
      );
    }

    if (negativeBalance > 0) {
      sections.add(
        PieChartSectionData(
          value: negativeBalance.toDouble(),
          title: '$negativeBalance',
          color: Colors.green,
          radius: 60,
        ),
      );
    }

    if (zeroBalance > 0) {
      sections.add(
        PieChartSectionData(
          value: zeroBalance.toDouble(),
          title: '$zeroBalance',
          color: Colors.grey,
          radius: 60,
        ),
      );
    }

    return PieChart(
      PieChartData(sections: sections, sectionsSpace: 2, centerSpaceRadius: 40),
    );
  }

  Widget _buildProductsChart() {
    // Bar chart showing inventory levels
    final topProducts = data.take(5).toList();

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: topProducts.isNotEmpty
            ? topProducts
                      .map((e) => e['quantity'] as int? ?? 0)
                      .reduce((a, b) => a > b ? a : b) *
                  1.2
            : 100,
        barGroups: topProducts.asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value;
          final quantity = item['quantity'] as int? ?? 0;

          return BarChartGroupData(
            x: index,
            barRods: [
              BarChartRodData(
                toY: quantity.toDouble(),
                color: Colors.teal,
                width: 20,
              ),
            ],
          );
        }).toList(),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                if (value.toInt() < topProducts.length) {
                  return Text(
                    topProducts[value.toInt()]['name']?.toString().substring(
                          0,
                          5,
                        ) ??
                        '',
                    style: const TextStyle(fontSize: 8),
                  );
                }
                return const Text('');
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 40),
          ),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        gridData: FlGridData(show: true),
      ),
    );
  }

  Widget _buildFinancialChart() {
    // Pie chart showing income vs expenses
    final summary = _calculateSummary();
    final income = summary['totalIncome'] as double? ?? 0.0;
    final expenses = summary['totalExpenses'] as double? ?? 0.0;

    final sections = <PieChartSectionData>[];

    if (income > 0) {
      sections.add(
        PieChartSectionData(
          value: income,
          title: income.toStringAsFixed(0),
          color: Colors.green,
          radius: 60,
        ),
      );
    }

    if (expenses > 0) {
      sections.add(
        PieChartSectionData(
          value: expenses,
          title: expenses.toStringAsFixed(0),
          color: Colors.red,
          radius: 60,
        ),
      );
    }

    return PieChart(
      PieChartData(sections: sections, sectionsSpace: 2, centerSpaceRadius: 40),
    );
  }
}
