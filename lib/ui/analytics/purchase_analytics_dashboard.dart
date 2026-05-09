import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/dao/enhanced_purchase_dao.dart';
import 'package:pos_offline_desktop/core/provider/app_database_provider.dart';

class PurchaseAnalyticsDashboard extends ConsumerStatefulWidget {
  const PurchaseAnalyticsDashboard({super.key});

  @override
  ConsumerState<PurchaseAnalyticsDashboard> createState() =>
      _PurchaseAnalyticsDashboardScreenState();
}

class _PurchaseAnalyticsDashboardScreenState
    extends ConsumerState<PurchaseAnalyticsDashboard> {
  late final EnhancedPurchaseDao _purchaseDao;
  Map<String, dynamic> _analyticsData = {};
  bool _isLoading = true;
  String _selectedPeriod = 'month'; // week, month, quarter, year

  @override
  void initState() {
    super.initState();
    _purchaseDao = EnhancedPurchaseDao(ref.read(appDatabaseProvider));
    _loadAnalyticsData();
  }

  Future<void> _loadAnalyticsData() async {
    setState(() => _isLoading = true);

    try {
      final allPurchases = await _purchaseDao.getAllPurchases();
      final analytics = await _calculateAnalytics(allPurchases);

      setState(() {
        _analyticsData = analytics;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ في تحميل البيانات: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<Map<String, dynamic>> _calculateAnalytics(
    List<EnhancedPurchase> purchases,
  ) async {
    final now = DateTime.now();
    DateTime startDate;

    switch (_selectedPeriod) {
      case 'week':
        startDate = now.subtract(Duration(days: 7));
        break;
      case 'month':
        startDate = DateTime(now.year, now.month - 1, now.day);
        break;
      case 'quarter':
        startDate = DateTime(now.year, now.month - 3, now.day);
        break;
      case 'year':
        startDate = DateTime(now.year - 1, now.month, now.day);
        break;
      default:
        startDate = DateTime(now.year, now.month - 1, now.day);
    }

    final filteredPurchases = purchases
        .where((p) => p.purchaseDate.isAfter(startDate))
        .toList();

    // Calculate basic metrics
    final totalAmount = filteredPurchases.fold(
      0.0,
      (sum, p) => sum + p.totalAmount,
    );
    final averageOrderValue = filteredPurchases.isNotEmpty
        ? totalAmount / filteredPurchases.length
        : 0.0;

    final creditPurchases = filteredPurchases
        .where((p) => p.isCreditPurchase)
        .toList();
    final cashPurchases = filteredPurchases
        .where((p) => !p.isCreditPurchase)
        .toList();

    final creditAmount = creditPurchases.fold(
      0.0,
      (sum, p) => sum + p.totalAmount,
    );
    final cashAmount = cashPurchases.fold(0.0, (sum, p) => sum + p.totalAmount);

    // Calculate daily averages
    final days = now.difference(startDate).inDays;
    final dailyAverage = days > 0 ? totalAmount / days : 0.0;

    // Calculate supplier metrics
    final supplierStats = <String, Map<String, dynamic>>{};
    for (final purchase in filteredPurchases) {
      final supplierName = purchase.supplierName;
      if (!supplierStats.containsKey(supplierName)) {
        supplierStats[supplierName] = {
          'count': 0,
          'total': 0.0,
          'average': 0.0,
        };
      }
      supplierStats[supplierName]!['count']++;
      supplierStats[supplierName]!['total'] += purchase.totalAmount;
    }

    // Calculate averages for each supplier
    supplierStats.forEach((supplier, stats) {
      stats['average'] = stats['count'] > 0
          ? stats['total'] / stats['count']
          : 0.0;
    });

    // Sort suppliers by total amount
    final topSuppliers = supplierStats.entries.toList()
      ..sort((a, b) => b.value['total'].compareTo(a.value['total']));

    // Calculate monthly trend
    final monthlyTrend = <String, double>{};
    for (int i = 5; i >= 0; i--) {
      final month = DateTime(now.year, now.month - i, 1);
      final nextMonth = DateTime(now.year, now.month - i + 1, 1);

      final monthPurchases = filteredPurchases
          .where(
            (p) =>
                p.purchaseDate.isAfter(month.subtract(Duration(days: 1))) &&
                p.purchaseDate.isBefore(nextMonth),
          )
          .toList();

      final monthKey = DateFormat('MMM yyyy').format(month);
      monthlyTrend[monthKey] = monthPurchases.fold(
        0.0,
        (sum, p) => sum + p.totalAmount,
      );
    }

    // Calculate payment method distribution
    final paymentDistribution = {'credit': creditAmount, 'cash': cashAmount};

    return {
      'totalPurchases': totalAmount,
      'purchaseCount': filteredPurchases.length,
      'averageOrderValue': averageOrderValue,
      'dailyAverage': dailyAverage,
      'creditAmount': creditAmount,
      'cashAmount': cashAmount,
      'creditCount': creditPurchases.length,
      'cashCount': cashPurchases.length,
      'creditPercentage': totalAmount > 0
          ? (creditAmount / totalAmount) * 100
          : 0.0,
      'cashPercentage': totalAmount > 0
          ? (cashAmount / totalAmount) * 100
          : 0.0,
      'supplierStats': supplierStats,
      'topSuppliers': topSuppliers.take(5).toList(),
      'monthlyTrend': monthlyTrend,
      'paymentDistribution': paymentDistribution,
      'period': _selectedPeriod,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF1E1E2E),
      appBar: AppBar(
        title: Text('لوحة تحليلات المشتريات'),
        backgroundColor: Color(0xFF2D2D3D),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadAnalyticsData,
            tooltip: 'تحديث البيانات',
          ),
          IconButton(
            icon: Icon(Icons.download),
            onPressed: _exportAnalytics,
            tooltip: 'تصدير التحليلات',
          ),
        ],
      ),
      body: Column(
        children: [
          // Period Selector
          _buildPeriodSelector(),
          SizedBox(height: 16),

          // Analytics Content
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator(color: Colors.purple))
                : SingleChildScrollView(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Key Metrics Cards
                        _buildKeyMetricsCards(),
                        SizedBox(height: 24),

                        // Charts Section
                        _buildChartsSection(),
                        SizedBox(height: 24),

                        // Top Suppliers Section
                        _buildTopSuppliersSection(),
                        SizedBox(height: 24),

                        // Payment Distribution Section
                        _buildPaymentDistributionSection(),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPeriodSelector() {
    return Container(
      padding: EdgeInsets.all(16),
      child: Row(
        children: [
          Text('الفترة:', style: TextStyle(color: Colors.white, fontSize: 16)),
          SizedBox(width: 16),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildPeriodChip('week', 'أسبوع'),
                  SizedBox(width: 8),
                  _buildPeriodChip('month', 'شهر'),
                  SizedBox(width: 8),
                  _buildPeriodChip('quarter', 'ربع سنة'),
                  SizedBox(width: 8),
                  _buildPeriodChip('year', 'سنة'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPeriodChip(String period, String label) {
    final isSelected = _selectedPeriod == period;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _selectedPeriod = period;
        });
        _loadAnalyticsData();
      },
      backgroundColor: Color(0xFF2D2D3D),
      selectedColor: Colors.purple.withValues(alpha: 0.3),
      labelStyle: TextStyle(color: isSelected ? Colors.purple : Colors.white),
    );
  }

  Widget _buildKeyMetricsCards() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'المقاييس الرئيسية',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        SizedBox(height: 16),

        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                'إجمالي المشتريات',
                '${_analyticsData['totalPurchases']?.toStringAsFixed(0) ?? '0'} ج.م',
                Icons.shopping_cart,
                Colors.purple,
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: _buildMetricCard(
                'عدد الفواتير',
                '${_analyticsData['purchaseCount'] ?? 0}',
                Icons.receipt,
                Colors.blue,
              ),
            ),
          ],
        ),
        SizedBox(height: 12),

        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                'متوسط الفاتورة',
                '${_analyticsData['averageOrderValue']?.toStringAsFixed(0) ?? '0'} ج.م',
                Icons.calculate,
                Colors.green,
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: _buildMetricCard(
                'متوسط يومي',
                '${_analyticsData['dailyAverage']?.toStringAsFixed(0) ?? '0'} ج.م',
                Icons.trending_up,
                Colors.orange,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMetricCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Color(0xFF2D2D3D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Color(0xFF3D3D4D)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 4),
          Text(title, style: TextStyle(color: Colors.grey[400], fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildChartsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'الرسوم البيانية',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        SizedBox(height: 16),

        // Monthly Trend Chart
        _buildMonthlyTrendChart(),
        SizedBox(height: 16),

        // Payment Method Distribution
        _buildPaymentMethodChart(),
      ],
    );
  }

  Widget _buildMonthlyTrendChart() {
    final monthlyTrend =
        _analyticsData['monthlyTrend'] as Map<String, double>? ?? {};

    return Container(
      height: 200,
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Color(0xFF2D2D3D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Color(0xFF3D3D4D)),
      ),
      child: Column(
        children: [
          Text(
            'اتجاه المشتريات الشهري',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 16),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: monthlyTrend.entries.map((entry) {
                final maxValue = monthlyTrend.values.isNotEmpty
                    ? monthlyTrend.values.reduce((a, b) => a > b ? a : b)
                    : 1.0;
                final height = maxValue > 0
                    ? (entry.value / maxValue) * 120
                    : 0.0;

                return Column(
                  children: [
                    Container(
                      width: 30,
                      height: height,
                      decoration: BoxDecoration(
                        color: Colors.purple,
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(4),
                        ),
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      entry.key.substring(0, 3),
                      style: TextStyle(color: Colors.grey[400], fontSize: 10),
                    ),
                    Text(
                      entry.value.toStringAsFixed(0),
                      style: TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentMethodChart() {
    final paymentDistribution =
        _analyticsData['paymentDistribution'] as Map<String, double>? ?? {};
    final creditAmount = paymentDistribution['credit'] ?? 0.0;
    final cashAmount = paymentDistribution['cash'] ?? 0.0;
    final total = creditAmount + cashAmount;

    return Container(
      height: 200,
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Color(0xFF2D2D3D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Color(0xFF3D3D4D)),
      ),
      child: Column(
        children: [
          Text(
            'توزيع طرق الدفع',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 16),
          Expanded(
            child: Row(
              children: [
                // Credit
                Expanded(
                  child: Column(
                    children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(4),
                            ),
                          ),
                          child: Center(
                            child: Text(
                              '${total > 0 ? (creditAmount / total * 100).toStringAsFixed(1) : '0.0'}%',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: 8),
                      Text('الآجل', style: TextStyle(color: Colors.grey[400])),
                      Text(
                        '${creditAmount.toStringAsFixed(0)} ج.م',
                        style: TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 16),
                // Cash
                Expanded(
                  child: Column(
                    children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.teal,
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(4),
                            ),
                          ),
                          child: Center(
                            child: Text(
                              '${total > 0 ? (cashAmount / total * 100).toStringAsFixed(1) : '0.0'}%',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: 8),
                      Text('النقدي', style: TextStyle(color: Colors.grey[400])),
                      Text(
                        '${cashAmount.toStringAsFixed(0)} ج.م',
                        style: TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopSuppliersSection() {
    final topSuppliers = _analyticsData['topSuppliers'] as List? ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'أعلى 5 موردين',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        SizedBox(height: 16),

        Container(
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Color(0xFF2D2D3D),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Color(0xFF3D3D4D)),
          ),
          child: Column(
            children: topSuppliers.isEmpty
                ? [
                    Center(
                      child: Text(
                        'لا توجد بيانات',
                        style: TextStyle(color: Colors.grey[400]),
                      ),
                    ),
                  ]
                : topSuppliers
                      .whereType<MapEntry<String, Map<String, dynamic>>>()
                      .toList()
                      .asMap()
                      .entries
                      .map((entry) {
                        final index = entry.key;
                        final supplier = entry.value;
                        final stats = supplier.value;

                        return Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: Row(
                            children: [
                              // Rank
                              Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  color: _getRankColor(index),
                                  borderRadius: BorderRadius.circular(15),
                                ),
                                child: Center(
                                  child: Text(
                                    '${index + 1}',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(width: 12),

                              // Supplier Name
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      supplier.key,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      '${stats['count']} فواتير',
                                      style: TextStyle(
                                        color: Colors.grey[400],
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // Total Amount
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '${stats['total'].toStringAsFixed(0)} ج.م',
                                    style: TextStyle(
                                      color: Colors.purple,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    'متوسط: ${stats['average'].toStringAsFixed(0)} ج.م',
                                    style: TextStyle(
                                      color: Colors.grey[400],
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      })
                      .toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentDistributionSection() {
    final creditPercentage = _analyticsData['creditPercentage'] ?? 0.0;
    final cashPercentage = _analyticsData['cashPercentage'] ?? 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'تحليل الدفع',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        SizedBox(height: 16),

        Row(
          children: [
            Expanded(
              child: _buildPaymentCard(
                'المشتريات الآجلة',
                creditPercentage,
                '${_analyticsData['creditCount'] ?? 0}',
                Colors.red,
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: _buildPaymentCard(
                'المشتريات النقدية',
                cashPercentage,
                '${_analyticsData['cashCount'] ?? 0}',
                Colors.teal,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPaymentCard(
    String title,
    double percentage,
    String count,
    Color color,
  ) {
    final safePercent = percentage.isNaN || percentage.isInfinite
        ? 0.0
        : (percentage.clamp(0.0, 100.0));
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Color(0xFF2D2D3D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Color(0xFF3D3D4D)),
      ),
      child: Column(
        children: [
          Text(
            title,
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 12),
          CircularPercentIndicator(
            radius: 40.0,
            lineWidth: 8.0,
            percent: safePercent / 100,
            center: Text(
              '${safePercent.toStringAsFixed(1)}%',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            progressColor: color,
          ),
          SizedBox(height: 12),
          Text('$count فاتورة', style: TextStyle(color: Colors.grey[400])),
        ],
      ),
    );
  }

  Color _getRankColor(int index) {
    switch (index) {
      case 0:
        return Colors.amber;
      case 1:
        return Colors.grey;
      case 2:
        return Colors.brown;
      default:
        return Colors.blueGrey;
    }
  }

  void _exportAnalytics() {
    // Export analytics to CSV or PDF
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('سيتم تصدير تحليلات المشتريات'),
        backgroundColor: Colors.green,
      ),
    );
  }
}

// Simple circular percent indicator widget
class CircularPercentIndicator extends StatelessWidget {
  final double radius;
  final double lineWidth;
  final double percent;
  final Widget center;
  final Color progressColor;

  const CircularPercentIndicator({
    super.key,
    required this.radius,
    required this.lineWidth,
    required this.percent,
    required this.center,
    required this.progressColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: radius * 2,
      height: radius * 2,
      child: Stack(
        children: [
          // Background circle
          Container(
            width: radius * 2,
            height: radius * 2,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Color(0xFF3D3D4D), width: lineWidth),
            ),
          ),
          // Progress circle
          SizedBox(
            width: radius * 2,
            height: radius * 2,
            child: CircularProgressIndicator(
              value: percent,
              strokeWidth: lineWidth,
              backgroundColor: Color(0xFF3D3D4D),
              valueColor: AlwaysStoppedAnimation<Color>(progressColor),
            ),
          ),
          // Center content
          Center(child: center),
        ],
      ),
    );
  }
}
