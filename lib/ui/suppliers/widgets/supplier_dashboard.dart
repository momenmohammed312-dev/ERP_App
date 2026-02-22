import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';

class SupplierDashboard extends ConsumerStatefulWidget {
  final AppDatabase db;
  final Function(EnhancedSupplier)? onSupplierSelected;
  final VoidCallback? onRefresh;

  const SupplierDashboard({
    super.key,
    required this.db,
    this.onSupplierSelected,
    this.onRefresh,
  });

  @override
  ConsumerState<SupplierDashboard> createState() => _SupplierDashboardState();
}

class _SupplierDashboardState extends ConsumerState<SupplierDashboard> {
  int _totalSuppliers = 0;
  double _totalSupplierBalances = 0.0;
  double _averageBalance = 0.0;
  List<EnhancedSupplier> _topSuppliers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    setState(() => _isLoading = true);

    try {
      // Get suppliers
      final suppliers = await widget.db.enhancedPurchaseDao.getAllSuppliers();

      // Calculate metrics
      final totalBalances = suppliers.fold<double>(
        0.0,
        (sum, supplier) => sum + supplier.currentBalance,
      );

      setState(() {
        _totalSuppliers = suppliers.length;
        _totalSupplierBalances = totalBalances;
        _averageBalance = suppliers.isNotEmpty
            ? totalBalances / suppliers.length
            : 0.0;
        _topSuppliers = suppliers.where((s) => s.currentBalance != 0).toList()
          ..sort(
            (a, b) => b.currentBalance.abs().compareTo(a.currentBalance.abs()),
          );
        _topSuppliers = _topSuppliers.take(5).toList();
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading supplier dashboard data: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'لوحة تحكم الموردين',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                if (widget.onRefresh != null)
                  IconButton(
                    onPressed: () {
                      widget.onRefresh?.call();
                      _loadDashboardData();
                    },
                    icon: const Icon(Icons.refresh),
                    tooltip: 'تحديث لوحة التحكم',
                  ),
              ],
            ),
            const Gap(24),

            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else ...[
              // Metrics Row
              Row(
                children: [
                  Expanded(
                    child: _buildMetricCard(
                      'إجمالي الموردين',
                      _totalSuppliers.toString(),
                      Icons.business,
                      Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const Gap(16),
                  Expanded(
                    child: _buildMetricCard(
                      'إجمالي الأرصدة',
                      '${_totalSupplierBalances.toStringAsFixed(2)} ج.م',
                      Icons.account_balance,
                      Colors.orange.shade600,
                    ),
                  ),
                  const Gap(16),
                  Expanded(
                    child: _buildMetricCard(
                      'متوسط الرصيد',
                      '${_averageBalance.toStringAsFixed(2)} ج.م',
                      Icons.analytics,
                      Colors.teal.shade600,
                    ),
                  ),
                ],
              ),

              const Gap(24),

              // Charts Row
              Row(
                children: [
                  Expanded(child: _buildBalanceChart()),
                  const Gap(16),
                  Expanded(child: _buildSupplierStatusChart()),
                ],
              ),

              const Gap(24),

              // Top Suppliers Section
              Text(
                'أعلى الموردين (بالرصيد)',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const Gap(12),

              if (_topSuppliers.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).dividerColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    'لا توجد معاملات للموردين',
                    style: TextStyle(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _topSuppliers.length,
                  itemBuilder: (context, index) {
                    final supplier = _topSuppliers[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.1),
                        child: Text(
                          supplier.businessName.isNotEmpty
                              ? supplier.businessName[0].toUpperCase()
                              : 'م',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ),
                      title: Text(
                        supplier.businessName,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      subtitle: Text(
                        supplier.phone,
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                      trailing: Text(
                        '${supplier.currentBalance.toStringAsFixed(2)} ج.م',
                        style: TextStyle(
                          color: supplier.currentBalance > 0
                              ? Colors.red
                              : supplier.currentBalance < 0
                              ? Colors.green
                              : Colors.grey,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onTap: () => widget.onSupplierSelected?.call(supplier),
                    );
                  },
                ),
            ],
          ],
        ),
      ),
    );
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
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const Gap(8),
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

  Widget _buildBalanceChart() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'توزيع الأرصدة',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const Gap(16),
          SizedBox(
            height: 150,
            child: _topSuppliers.isNotEmpty
                ? BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      maxY: _topSuppliers.isNotEmpty
                          ? _topSuppliers
                                    .map((e) => e.currentBalance.abs())
                                    .reduce((a, b) => a > b ? a : b) *
                                1.2
                          : 1000,
                      barGroups: _topSuppliers
                          .take(5)
                          .toList()
                          .asMap()
                          .entries
                          .map((entry) {
                            final index = entry.key;
                            final supplier = entry.value;
                            return BarChartGroupData(
                              x: index,
                              barRods: [
                                BarChartRodData(
                                  toY: supplier.currentBalance.abs(),
                                  color: supplier.currentBalance > 0
                                      ? Colors.red
                                      : Colors.green,
                                  width: 15,
                                ),
                              ],
                            );
                          })
                          .toList(),
                      titlesData: FlTitlesData(
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (value, meta) {
                              if (value.toInt() < _topSuppliers.length) {
                                return Text(
                                  _topSuppliers[value.toInt()].businessName
                                      .substring(0, 3),
                                  style: const TextStyle(fontSize: 8),
                                );
                              }
                              return const Text('');
                            },
                          ),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 30,
                          ),
                        ),
                        topTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      gridData: FlGridData(show: true),
                    ),
                  )
                : const Center(child: Text('لا توجد بيانات')),
          ),
        ],
      ),
    );
  }

  Widget _buildSupplierStatusChart() {
    final positiveBalance = _topSuppliers
        .where((s) => s.currentBalance > 0)
        .length;
    final negativeBalance = _topSuppliers
        .where((s) => s.currentBalance < 0)
        .length;
    final zeroBalance = _totalSuppliers - positiveBalance - negativeBalance;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'حالة الموردين',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const Gap(16),
          SizedBox(
            height: 150,
            child: PieChart(
              PieChartData(
                sections: [
                  if (positiveBalance > 0)
                    PieChartSectionData(
                      value: positiveBalance.toDouble(),
                      title: '$positiveBalance',
                      color: Colors.red,
                      radius: 50,
                    ),
                  if (negativeBalance > 0)
                    PieChartSectionData(
                      value: negativeBalance.toDouble(),
                      title: '$negativeBalance',
                      color: Colors.green,
                      radius: 50,
                    ),
                  if (zeroBalance > 0)
                    PieChartSectionData(
                      value: zeroBalance.toDouble(),
                      title: '$zeroBalance',
                      color: Colors.grey,
                      radius: 50,
                    ),
                ],
                sectionsSpace: 2,
                centerSpaceRadius: 30,
              ),
            ),
          ),
          const Gap(8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildLegendItem('مستحق لهم', Colors.red),
              const Gap(16),
              _buildLegendItem('دائنون', Colors.green),
              const Gap(16),
              _buildLegendItem('متوازن', Colors.grey),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const Gap(4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}
