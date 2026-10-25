import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import 'package:intl/intl.dart';
import 'package:pos_offline_desktop/core/provider/app_database_provider.dart';
import 'package:pos_offline_desktop/core/theme/madar_colors.dart';

class ProductSalesPieChart extends ConsumerStatefulWidget {
  final DateTimeRange? dateRange;

  const ProductSalesPieChart({super.key, required this.dateRange});

  @override
  ConsumerState<ProductSalesPieChart> createState() => _ProductSalesPieChartState();
}

class _ProductSalesPieChartState extends ConsumerState<ProductSalesPieChart> {
  Future<Map<String, double>>? _cachedFuture;
  int _touchedIndex = -1;

  static const List<Color> _palette = [
    MadarColors.gold,             // #C9A84C
    Color(0xFF238636),            // Emerald
    Color(0xFF388BFD),            // Blue
    Color(0xFFA371F7),            // Purple
    Color(0xFFD29922),            // Amber
    Color(0xFFF85149),            // Coral
    Color(0xFF39C5CF),            // Cyan
    Color(0xFF8B949E),            // Gray / Other
  ];

  @override
  void initState() {
    super.initState();
    _cachedFuture = _loadProductSalesData(widget.dateRange);
  }

  @override
  void didUpdateWidget(covariant ProductSalesPieChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dateRange != widget.dateRange) {
      setState(() {
        _touchedIndex = -1;
        _cachedFuture = _loadProductSalesData(widget.dateRange);
      });
    }
  }

  Future<Map<String, double>> _loadProductSalesData(DateTimeRange? dateRange) async {
    try {
      if (dateRange == null) return {};
      final db = ref.read(appDatabaseProvider);
      final result = await db.customSelect(
        '''
        SELECT p.name, SUM(ii.price * ii.quantity - ii.discount) as total_sales
        FROM invoice_items ii
        JOIN products p ON ii.product_id = p.id
        JOIN invoices i ON ii.invoice_id = i.id
        WHERE i.date >= ? AND i.date <= ? AND i.status != 'voided'
        GROUP BY p.id, p.name
        ORDER BY total_sales DESC
        LIMIT 10
        ''',
        variables: [
          drift.Variable.withDateTime(dateRange.start),
          drift.Variable.withDateTime(dateRange.end),
        ],
      ).get();

      return {
        for (var row in result)
          row.data['name'] as String: (row.data['total_sales'] as num).toDouble(),
      };
    } catch (e) {
      return {};
    }
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormatter = NumberFormat.compact(locale: 'ar');

    return FutureBuilder<Map<String, double>>(
      future: _cachedFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: MadarColors.gold),
            ),
          );
        }

        final productSales = snapshot.data ?? {};
        if (productSales.isEmpty) {
          return Center(
            child: Text(
              'لا توجد بيانات مبيعات في الفترة المحددة',
              style: TextStyle(
                fontFamily: 'NotoSansArabic',
                fontSize: 13,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
          );
        }

        final total = productSales.values.fold<double>(0, (a, b) => a + b);
        final entries = productSales.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));

        // Top 6 products + others
        final topProducts = entries.take(6).toList();
        final otherValue = entries.length > 6
            ? entries.skip(6).fold<double>(0, (s, e) => s + e.value)
            : 0.0;
        if (otherValue > 0) {
          topProducts.add(MapEntry('أخرى', otherValue));
        }

        final activeEntry = (_touchedIndex >= 0 && _touchedIndex < topProducts.length)
            ? topProducts[_touchedIndex]
            : null;

        return Stack(
          alignment: Alignment.center,
          children: [
            PieChart(
              PieChartData(
                pieTouchData: PieTouchData(
                  touchCallback: (FlTouchEvent event, pieTouchResponse) {
                    setState(() {
                      if (!event.isInterestedForInteractions ||
                          pieTouchResponse == null ||
                          pieTouchResponse.touchedSection == null) {
                        _touchedIndex = -1;
                        return;
                      }
                      _touchedIndex = pieTouchResponse
                          .touchedSection!
                          .touchedSectionIndex;
                    });
                  },
                ),
                borderData: FlBorderData(show: false),
                sectionsSpace: 3,
                centerSpaceRadius: 56,
                sections: topProducts.asMap().entries.map((entry) {
                  final i = entry.key;
                  final product = entry.value.key;
                  final value = entry.value.value;
                  final isTouched = i == _touchedIndex;
                  final radius = isTouched ? 48.0 : 40.0;
                  final pct = total > 0 ? (value / total * 100) : 0.0;

                  return PieChartSectionData(
                    color: _palette[i % _palette.length],
                    value: value,
                    title: isTouched ? '${pct.toStringAsFixed(1)}%' : '',
                    radius: radius,
                    titleStyle: const TextStyle(
                      fontFamily: 'NotoSansArabic',
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    titlePositionPercentageOffset: 0.55,
                  );
                }).toList(),
              ),
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOutCubic,
            ),

            // In-donut Telemetry Badge
            IgnorePointer(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    activeEntry != null ? activeEntry.key : 'إجمالي المبيعات',
                    style: TextStyle(
                      fontFamily: 'NotoSansArabic',
                      fontSize: activeEntry != null ? 12 : 11,
                      fontWeight: FontWeight.w600,
                      color: activeEntry != null
                          ? _palette[_touchedIndex % _palette.length]
                          : Colors.white.withValues(alpha: 0.65),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    activeEntry != null
                        ? '${currencyFormatter.format(activeEntry.value)} ج.م'
                        : '${currencyFormatter.format(total)} ج.م',
                    style: const TextStyle(
                      fontFamily: 'NotoSansArabic',
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
