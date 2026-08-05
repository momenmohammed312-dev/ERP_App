import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import 'package:pos_offline_desktop/core/provider/app_database_provider.dart';

class ProductSalesPieChart extends ConsumerWidget {
  final DateTimeRange? dateRange;

  const ProductSalesPieChart({super.key, required this.dateRange});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<Map<String, double>>(
      future: _loadProductSalesData(ref, dateRange),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final productSales = snapshot.data!;
        if (productSales.isEmpty) {
          return const Center(child: Text('لا توجد بيانات منتجات'));
        }

        final total = productSales.values.reduce((a, b) => a + b);
        final entries = productSales.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));

        // Top 6 products
        final topProducts = entries.take(6).toList();
        final otherValue = entries.length > 6
            ? entries.skip(6).fold<double>(0, (s, e) => s + e.value)
            : 0.0;
        if (otherValue > 0) {
          topProducts.add(MapEntry('أخرى', otherValue));
        }

        final colors = [
          Colors.blue,
          Colors.green,
          Colors.orange,
          Colors.purple,
          Colors.red,
          Colors.teal,
          Colors.cyan,
          Colors.pink,
        ];

        return SizedBox(
          height: 250,
          child: PieChart(
            PieChartData(
              pieTouchData: PieTouchData(touchCallback: (event, response) {}),
              borderData: FlBorderData(show: false),
              sectionsSpace: 2,
              centerSpaceRadius: 50,
              sections: topProducts.asMap().entries.map((entry) {
                final i = entry.key;
                final product = entry.value.key;
                final value = entry.value.value;
                final pct = (value / total * 100);
                return PieChartSectionData(
                  color: colors[i % colors.length],
                  value: value,
                  title: '${pct.toStringAsFixed(1)}%',
                  radius: 80,
                  titleStyle: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  titlePositionPercentageOffset: 0.55,
                  badgeWidget: pct > 5
                      ? Text(
                          product,
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w500,
                            color: Colors.white,
                          ),
                          textAlign: TextAlign.center,
                        )
                      : null,
                  badgePositionPercentageOffset: 1.15,
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  Future<Map<String, double>> _loadProductSalesData(
    WidgetRef ref,
    DateTimeRange? dateRange,
  ) async {
    try {
      if (dateRange == null) return {};
      final db = ref.read(appDatabaseProvider);
      final result = await db.customSelect('''
        SELECT p.name, SUM(ii.price * ii.quantity - ii.discount) as total_sales
        FROM invoice_items ii
        JOIN products p ON ii.product_id = p.id
        JOIN invoices i ON ii.invoice_id = i.id
        WHERE i.date >= ? AND i.date <= ? AND i.status != 'voided'
        GROUP BY p.id, p.name
        ORDER BY total_sales DESC
        LIMIT 10
      ''', variables: [
        drift.Variable.withDateTime(dateRange.start),
        drift.Variable.withDateTime(dateRange.end),
      ]).get();

      return {for (var row in result) row.data['name'] as String: (row.data['total_sales'] as num).toDouble()};
    } catch (e) {
      return {};
    }
  }
}