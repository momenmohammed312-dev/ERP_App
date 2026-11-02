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
    final isLight = Theme.of(context).brightness == Brightness.light;
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
                color: isLight ? MadarColors.lightDeepCobalt.withValues(alpha: 0.6) : Colors.white.withValues(alpha: 0.5),
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

        final donutWidget = Stack(
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
                centerSpaceRadius: 46,
                sections: topProducts.asMap().entries.map((entry) {
                  final i = entry.key;
                  final value = entry.value.value;
                  final isTouched = i == _touchedIndex;
                  final radius = isTouched ? 40.0 : 32.0;
                  final pct = total > 0 ? (value / total * 100) : 0.0;

                  return PieChartSectionData(
                    color: _palette[i % _palette.length],
                    value: value,
                    title: isTouched ? '%' : '',
                    radius: radius,
                    titleStyle: const TextStyle(
                      fontFamily: 'NotoSansArabic',
                      fontSize: 11,
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
                      fontSize: activeEntry != null ? 11 : 10,
                      fontWeight: FontWeight.w700,
                      color: activeEntry != null
                          ? _palette[_touchedIndex % _palette.length]
                          : (isLight ? MadarColors.lightDeepCobalt : Colors.white70),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    activeEntry != null
                        ? ' ج.م'
                        : ' ج.م',
                    style: TextStyle(
                      fontFamily: 'NotoSansArabic',
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: isLight ? MadarColors.lightDeepCobalt : Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );

        final legendWidget = SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: topProducts.asMap().entries.map((entry) {
              final i = entry.key;
              final product = entry.value.key;
              final value = entry.value.value;
              final pct = total > 0 ? (value / total * 100) : 0.0;
              final isTouched = i == _touchedIndex;

              return InkWell(
                onTap: () {
                  setState(() {
                    _touchedIndex = isTouched ? -1 : i;
                  });
                },
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3.5),
                  decoration: BoxDecoration(
                    color: isTouched
                        ? _palette[i % _palette.length].withValues(alpha: 0.15)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _palette[i % _palette.length],
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          product,
                          style: TextStyle(
                            fontFamily: 'NotoSansArabic',
                            fontSize: 11,
                            fontWeight: isTouched ? FontWeight.bold : FontWeight.w500,
                            color: isLight ? MadarColors.lightDeepCobalt : Colors.white.withValues(alpha: 0.85),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '%',
                        style: TextStyle(
                          fontFamily: 'NotoSansArabic',
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: isLight ? MadarColors.lightDeepCobalt : Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        );

        return LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= 320) {
              return Row(
                children: [
                  Expanded(flex: 6, child: donutWidget),
                  const SizedBox(width: 10),
                  Expanded(flex: 5, child: legendWidget),
                ],
              );
            } else {
              return Column(
                children: [
                  Expanded(flex: 6, child: donutWidget),
                  const SizedBox(height: 8),
                  Expanded(flex: 4, child: legendWidget),
                ],
              );
            }
          },
        );
      },
    );
  }
}
