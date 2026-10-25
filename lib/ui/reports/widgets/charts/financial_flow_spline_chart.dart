import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:pos_offline_desktop/core/theme/madar_colors.dart';

class FinancialFlowSplineChart extends StatefulWidget {
  final List<Map<String, dynamic>> dailyFlow;

  const FinancialFlowSplineChart({super.key, required this.dailyFlow});

  @override
  State<FinancialFlowSplineChart> createState() => _FinancialFlowSplineChartState();
}

class _FinancialFlowSplineChartState extends State<FinancialFlowSplineChart> {
  int? _hoveredIndex;

  @override
  Widget build(BuildContext context) {
    if (widget.dailyFlow.isEmpty) {
      return Center(
        child: Text(
          'لا توجد تدفقات مالية في الفترة المحددة',
          style: TextStyle(
            fontFamily: 'NotoSansArabic',
            fontSize: 13,
            color: Colors.white.withValues(alpha: 0.5),
          ),
        ),
      );
    }

    final currencyFormatter = NumberFormat.currency(locale: 'en_EG', symbol: 'ج.م', decimalDigits: 0);

    final salesSpots = <FlSpot>[];
    final purchaseSpots = <FlSpot>[];
    final profitSpots = <FlSpot>[];

    double maxY = 100;
    double minY = 0;

    for (int i = 0; i < widget.dailyFlow.length; i++) {
      final item = widget.dailyFlow[i];
      final s = (item['sales'] as num?)?.toDouble() ?? 0.0;
      final p = (item['purchases'] as num?)?.toDouble() ?? 0.0;
      final net = s - p;

      salesSpots.add(FlSpot(i.toDouble(), s));
      purchaseSpots.add(FlSpot(i.toDouble(), p));
      profitSpots.add(FlSpot(i.toDouble(), net));

      if (s > maxY) maxY = s;
      if (p > maxY) maxY = p;
      if (net < minY) minY = net;
    }

    final activeItem = (_hoveredIndex != null &&
            _hoveredIndex! >= 0 &&
            _hoveredIndex! < widget.dailyFlow.length)
        ? widget.dailyFlow[_hoveredIndex!]
        : (widget.dailyFlow.isNotEmpty ? widget.dailyFlow.last : null);

    final activeSales = (activeItem?['sales'] as num?)?.toDouble() ?? 0.0;
    final activePurchases = (activeItem?['purchases'] as num?)?.toDouble() ?? 0.0;
    final activeNet = activeSales - activePurchases;
    final activeDate = activeItem?['date'] as String? ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Telemetry Ribbon
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 6,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.calendar_today_rounded, size: 13, color: MadarColors.gold),
                  const SizedBox(width: 6),
                  Text(
                    activeDate.isNotEmpty ? activeDate : 'التدفق المالي',
                    style: const TextStyle(
                      fontFamily: 'NotoSansArabic',
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildTelemetryBadge('المبيعات', activeSales, MadarColors.gold),
                  const SizedBox(width: 12),
                  _buildTelemetryBadge('المشتريات', activePurchases, const Color(0xFFD29922)),
                  const SizedBox(width: 12),
                  _buildTelemetryBadge(
                    'الصافي',
                    activeNet,
                    activeNet >= 0 ? const Color(0xFF238636) : const Color(0xFFF85149),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // Spline Chart
        Expanded(
          child: LineChart(
            LineChartData(
              lineTouchData: LineTouchData(
                enabled: true,
                handleBuiltInTouches: true,
                touchCallback: (FlTouchEvent event, LineTouchResponse? touchResponse) {
                  setState(() {
                    if (!event.isInterestedForInteractions ||
                        touchResponse == null ||
                        touchResponse.lineBarSpots == null ||
                        touchResponse.lineBarSpots!.isEmpty) {
                      _hoveredIndex = null;
                      return;
                    }
                    _hoveredIndex = touchResponse.lineBarSpots!.first.x.toInt();
                  });
                },
                touchTooltipData: LineTouchTooltipData(
                  getTooltipItems: (touchedSpots) {
                    return touchedSpots.map((spot) {
                      final isSales = spot.barIndex == 0;
                      final isPurchases = spot.barIndex == 1;
                      final label = isSales
                          ? 'مبيعات'
                          : (isPurchases ? 'مشتريات' : 'صافي');
                      final color = isSales
                          ? MadarColors.gold
                          : (isPurchases ? const Color(0xFFD29922) : const Color(0xFF388BFD));

                      return LineTooltipItem(
                        '$label: ${currencyFormatter.format(spot.y)}',
                        TextStyle(
                          fontFamily: 'NotoSansArabic',
                          color: color,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      );
                    }).toList();
                  },
                ),
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (value) => FlLine(
                  color: Colors.white.withValues(alpha: 0.06),
                  strokeWidth: 1,
                  dashArray: [4, 4],
                ),
              ),
              titlesData: FlTitlesData(
                leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 48,
                    getTitlesWidget: (value, meta) {
                      if (value == meta.max || value == meta.min) {
                        return const SizedBox.shrink();
                      }
                      return Text(
                        '${(value / 1000).toStringAsFixed(0)}k',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.white.withValues(alpha: 0.4),
                          fontWeight: FontWeight.w600,
                        ),
                      );
                    },
                  ),
                ),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    interval: (widget.dailyFlow.length / 5).clamp(1.0, 10.0).toDouble(),
                    getTitlesWidget: (value, meta) {
                      final i = value.toInt();
                      if (i < 0 || i >= widget.dailyFlow.length) {
                        return const SizedBox.shrink();
                      }
                      final d = widget.dailyFlow[i]['date'] as String? ?? '';
                      final parts = d.split('-');
                      final label = parts.length >= 3 ? '${parts[2]}/${parts[1]}' : d;

                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.white.withValues(alpha: 0.45),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              borderData: FlBorderData(show: false),
              minX: 0,
              maxX: (widget.dailyFlow.length - 1).toDouble(),
              minY: minY * 1.1,
              maxY: maxY * 1.15,
              lineBarsData: [
                // Sales Spline (Gold)
                LineChartBarData(
                  spots: salesSpots,
                  isCurved: true,
                  curveSmoothness: 0.35,
                  color: MadarColors.gold,
                  barWidth: 2.8,
                  isStrokeCapRound: true,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      colors: [
                        MadarColors.gold.withValues(alpha: 0.22),
                        MadarColors.gold.withValues(alpha: 0.0),
                      ],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
                // Purchases Spline (Amber)
                LineChartBarData(
                  spots: purchaseSpots,
                  isCurved: true,
                  curveSmoothness: 0.35,
                  color: const Color(0xFFD29922),
                  barWidth: 2.2,
                  isStrokeCapRound: true,
                  dotData: const FlDotData(show: false),
                ),
                // Net Profit Spline (Blue)
                LineChartBarData(
                  spots: profitSpots,
                  isCurved: true,
                  curveSmoothness: 0.35,
                  color: const Color(0xFF388BFD),
                  barWidth: 1.8,
                  dashArray: [5, 4],
                  dotData: const FlDotData(show: false),
                ),
              ],
            ),
            duration: const Duration(milliseconds: 250),
          ),
        ),
      ],
    );
  }

  Widget _buildTelemetryBadge(String label, double value, Color color) {
    final formatter = NumberFormat.compact(locale: 'ar');

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          '$label: ',
          style: TextStyle(
            fontFamily: 'NotoSansArabic',
            fontSize: 11,
            color: Colors.white.withValues(alpha: 0.6),
          ),
        ),
        Text(
          '${formatter.format(value)} ج.م',
          style: TextStyle(
            fontFamily: 'NotoSansArabic',
            fontSize: 11.5,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}
