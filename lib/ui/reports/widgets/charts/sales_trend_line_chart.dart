import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

class SalesTrendLineChart extends StatelessWidget {
  final List<Map<String, dynamic>> comparisonData;

  const SalesTrendLineChart({
    super.key,
    required this.comparisonData,
  });

  @override
  Widget build(BuildContext context) {
    final spots = comparisonData.asMap().entries.map((entry) {
      final i = entry.key;
      final sales = (entry.value['total_sales'] as double?) ?? 0.0;
      return FlSpot(i.toDouble(), sales);
    }).toList();

    if (spots.isEmpty || spots.every((s) => s.y == 0)) {
      return const SizedBox(
        height: 300,
        child: Center(child: Text('لا توجد بيانات مبيعات')),
      );
    }

    final minY = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
    final maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    final yRange = maxY - minY;
    final adjustedMinY = (yRange < 100 ? (minY - 50).clamp(0.0, double.infinity) : (minY > 0 ? minY * 0.9 : 0)).toDouble();
    final adjustedMaxY = (yRange < 100 ? maxY + 50 : maxY * 1.1).toDouble();

    return SizedBox(
      height: 300,
      child: LineChart(
        LineChartData(
          lineTouchData: LineTouchData(
            enabled: true,
            touchTooltipData: LineTouchTooltipData(
              getTooltipItems: (touchedSpots) {
                return touchedSpots.map((spot) {
                  final date = comparisonData[spot.spotIndex]['date'] as String;
                  return LineTooltipItem(
                    '$date\nالمبيعات: ${spot.y.toStringAsFixed(0)} ج.م',
                    const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  );
                }).toList();
              },
            ),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: true,
            horizontalInterval: ((adjustedMaxY - adjustedMinY) / 4).clamp(1.0, double.infinity).toDouble(),
            getDrawingHorizontalLine: (value) => FlLine(
              color: Colors.grey.withValues(alpha: 0.2),
              strokeWidth: 1,
            ),
            getDrawingVerticalLine: (value) => FlLine(
              color: Colors.grey.withValues(alpha: 0.2),
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                interval: 1,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= comparisonData.length) return const SizedBox.shrink();
                  final parts = (comparisonData[i]['date'] as String).split('-');
                  final label = parts.length >= 3 ? '${parts[2]}/${parts[1]}' : '';
                  return SideTitleWidget(
                    axisSide: meta.axisSide,
                    child: Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500)),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: ((adjustedMaxY - adjustedMinY) / 4).clamp(1.0, double.infinity).toDouble(),
                getTitlesWidget: (value, meta) {
                  return Text(
                    '${(value / 1000).toStringAsFixed(0)}K',
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
                  );
                },
                reservedSize: 42,
              ),
            ),
          ),
          borderData: FlBorderData(
            show: true,
            border: Border.all(color: Colors.grey.withValues(alpha: 0.3), width: 1),
          ),
          minX: 0,
          maxX: (comparisonData.length - 1).toDouble(),
          minY: adjustedMinY,
          maxY: adjustedMaxY,
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              gradient: LinearGradient(
                colors: [
                  Colors.blue.withValues(alpha: 0.8),
                  Colors.blue.withValues(alpha: 0.4),
                ],
              ),
              barWidth: 3,
              isStrokeCapRound: true,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
                  radius: 4,
                  color: Colors.blue,
                  strokeWidth: 2,
                  strokeColor: Colors.white,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  colors: [
                    Colors.blue.withValues(alpha: 0.3),
                    Colors.blue.withValues(alpha: 0.05),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}