import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import '../../../core/database/dao/enhanced_purchase_dao.dart';
import '../../../core/provider/app_database_provider.dart';
import '../../../widgets/license/feature_guard.dart';
import 'widgets/inventory_report_tab.dart';
import 'purchase/purchase_reports_screen.dart';
import 'purchase/supplier_performance_screen.dart';
import 'purchase/purchase_budget_screen.dart';
import 'purchase/purchase_orders_screen.dart';

class EnhancedReportsScreen extends ConsumerStatefulWidget {
  const EnhancedReportsScreen({super.key});

  @override
  ConsumerState<EnhancedReportsScreen> createState() =>
      _EnhancedReportsScreenState();
}

class _EnhancedReportsScreenState extends ConsumerState<EnhancedReportsScreen> {
  late final EnhancedPurchaseDao _purchaseDao;
  Map<String, dynamic> _purchaseStats = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _purchaseDao = EnhancedPurchaseDao(ref.read(appDatabaseProvider));
    _loadPurchaseStatistics();
  }

  Future<void> _loadPurchaseStatistics() async {
    try {
      final allPurchases = await _purchaseDao.getAllPurchases();
      final now = DateTime.now();
      final thisMonth = DateTime(now.year, now.month, 1);
      final lastMonth = DateTime(now.year, now.month - 1, 1);

      final thisMonthPurchases = allPurchases
          .where((p) => p.purchaseDate.isAfter(thisMonth))
          .toList();
      final lastMonthPurchases = allPurchases
          .where(
            (p) =>
                p.purchaseDate.isAfter(lastMonth) &&
                p.purchaseDate.isBefore(thisMonth),
          )
          .toList();

      final totalPurchases = allPurchases.fold(
        0.0,
        (sum, p) => sum + p.totalAmount,
      );
      final thisMonthTotal = thisMonthPurchases.fold(
        0.0,
        (sum, p) => sum + p.totalAmount,
      );
      final lastMonthTotal = lastMonthPurchases.fold(
        0.0,
        (sum, p) => sum + p.totalAmount,
      );

      final creditPurchases = allPurchases
          .where((p) => p.isCreditPurchase)
          .toList();
      final cashPurchases = allPurchases
          .where((p) => !p.isCreditPurchase)
          .toList();

      final creditTotal = creditPurchases.fold(
        0.0,
        (sum, p) => sum + p.totalAmount,
      );
      final cashTotal = cashPurchases.fold(
        0.0,
        (sum, p) => sum + p.totalAmount,
      );

      setState(() {
        _purchaseStats = {
          'totalPurchases': totalPurchases,
          'purchaseCount': allPurchases.length,
          'thisMonthTotal': thisMonthTotal,
          'thisMonthCount': thisMonthPurchases.length,
          'lastMonthTotal': lastMonthTotal,
          'lastMonthCount': lastMonthPurchases.length,
          'creditTotal': creditTotal,
          'creditCount': creditPurchases.length,
          'cashTotal': cashTotal,
          'cashCount': cashPurchases.length,
          'averagePurchase': allPurchases.isNotEmpty
              ? totalPurchases / allPurchases.length
              : 0.0,
          'growth': lastMonthTotal > 0
              ? ((thisMonthTotal - lastMonthTotal) / lastMonthTotal) * 100
              : 0.0,
        };
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FeatureGuard(
      featureName: 'reports',
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          backgroundColor: const Color(0xFF1E1E2E),
          appBar: AppBar(
            title: const Text('التقارير المحسّنة'),
            backgroundColor: const Color(0xFF2D2D3D),
            bottom: const TabBar(
              tabs: [
                Tab(icon: Icon(Icons.shopping_cart), text: 'المشتريات'),
                Tab(icon: Icon(Icons.inventory_2), text: 'المخزون'),
              ],
              indicatorColor: Colors.purple,
              labelColor: Colors.purple,
              unselectedLabelColor: Colors.grey,
            ),
          ),
          body: TabBarView(
            children: [
              // Purchases Tab
              _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.purple),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadPurchaseStatistics,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Purchase Statistics Section
                            _buildPurchaseStatistics(),
                            const SizedBox(height: 24),

                            // Quick Actions
                            _buildQuickActions(),
                            const SizedBox(height: 24),

                            // Charts Section
                            _buildChartsSection(),
                          ],
                        ),
                      ),
                    ),

              // Inventory Tab
              const InventoryReportTab(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPurchaseStatistics() {
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Color(0xFF2D2D3D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Color(0xFF3D3D4D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.analytics, color: Colors.purple, size: 28),
              SizedBox(width: 12),
              Text(
                'إحصائيات المشتريات',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          SizedBox(height: 20),

          // Main Stats Cards
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'إجمالي المشتريات',
                  '${_purchaseStats['totalPurchases']?.toStringAsFixed(0) ?? '0'} ج.م',
                  Icons.shopping_cart,
                  Colors.purple,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  'عدد الفواتير',
                  '${_purchaseStats['purchaseCount'] ?? 0}',
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
                child: _buildStatCard(
                  'هذا الشهر',
                  '${_purchaseStats['thisMonthTotal']?.toStringAsFixed(0) ?? '0'} ج.م',
                  Icons.calendar_today,
                  Colors.green,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  'متوسط الفاتورة',
                  '${_purchaseStats['averagePurchase']?.toStringAsFixed(0) ?? '0'} ج.m',
                  Icons.calculate,
                  Colors.orange,
                ),
              ),
            ],
          ),
          SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'الآجل',
                  '${_purchaseStats['creditTotal']?.toStringAsFixed(0) ?? '0'} ج.م',
                  Icons.account_balance,
                  Colors.red,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  'النقدي',
                  '${_purchaseStats['cashTotal']?.toStringAsFixed(0) ?? '0'} ج.م',
                  Icons.attach_money,
                  Colors.teal,
                ),
              ),
            ],
          ),

          // Growth Indicator
          SizedBox(height: 16),
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Color(0xFF3D3D4D),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  _purchaseStats['growth'] >= 0
                      ? Icons.trending_up
                      : Icons.trending_down,
                  color: _purchaseStats['growth'] >= 0
                      ? Colors.green
                      : Colors.red,
                ),
                SizedBox(width: 8),
                Text(
                  'نمو الشهر: ${_purchaseStats['growth']?.toStringAsFixed(1) ?? '0.0'}%',
                  style: TextStyle(
                    color: _purchaseStats['growth'] >= 0
                        ? Colors.green
                        : Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Color(0xFF3D3D4D),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(color: Colors.grey[400], fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Color(0xFF2D2D3D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Color(0xFF3D3D4D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'إجراءات سريعة',
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
                child: ElevatedButton.icon(
                  onPressed: () => _navigateToPurchaseReports(),
                  icon: Icon(Icons.description),
                  label: Text('تقارير المشتريات'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple,
                    padding: EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _navigateToSupplierAnalytics(),
                  icon: Icon(Icons.people),
                  label: Text('تحليلات الموردين'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    padding: EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _navigateToBudgetManagement(),
                  icon: Icon(Icons.account_balance_wallet),
                  label: Text('إدارة الميزانية'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _navigateToPurchaseOrders(),
                  icon: Icon(Icons.shopping_cart),
                  label: Text('أوامر الشراء'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    padding: EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChartsSection() {
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Color(0xFF2D2D3D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Color(0xFF3D3D4D)),
      ),
      child: Column(
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

          // Simple Bar Chart for Purchase Types
          _buildPurchaseTypeChart(),
          SizedBox(height: 16),

          // Simple Pie Chart for Payment Methods
          _buildPaymentMethodChart(),
        ],
      ),
    );
  }

  Widget _buildPurchaseTypeChart() {
    final creditTotal = _purchaseStats['creditTotal'] ?? 0.0;
    final cashTotal = _purchaseStats['cashTotal'] ?? 0.0;
    final total = creditTotal + cashTotal;

    return Container(
      height: 200,
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Color(0xFF3D3D4D),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            'أنواع المشتريات',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 16),
          Expanded(
            child: Row(
              children: [
                // Credit Purchases Bar
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
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: Padding(
                              padding: EdgeInsets.all(8),
                              child: Text(
                                '${creditTotal > 0 ? (creditTotal / total * 100).toStringAsFixed(1) : '0.0'}%',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'الآجل',
                        style: TextStyle(color: Colors.grey[400], fontSize: 12),
                      ),
                      Text(
                        '${creditTotal.toStringAsFixed(0)} ج.م',
                        style: TextStyle(color: Colors.white, fontSize: 10),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 16),
                // Cash Purchases Bar
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
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: Padding(
                              padding: EdgeInsets.all(8),
                              child: Text(
                                '${cashTotal > 0 ? (cashTotal / total * 100).toStringAsFixed(1) : '0.0'}%',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'النقدي',
                        style: TextStyle(color: Colors.grey[400], fontSize: 12),
                      ),
                      Text(
                        '${cashTotal.toStringAsFixed(0)} ج.م',
                        style: TextStyle(color: Colors.white, fontSize: 10),
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

  Widget _buildPaymentMethodChart() {
    final creditCount = _purchaseStats['creditCount'] ?? 0;
    final cashCount = _purchaseStats['cashCount'] ?? 0;

    return Container(
      height: 200,
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Color(0xFF3D3D4D),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(
            'طرق الدفع',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 16),
          Expanded(
            child: Row(
              children: [
                // Credit Count
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
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: Padding(
                              padding: EdgeInsets.all(8),
                              child: Text(
                                '$creditCount',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'فواتير آجلة',
                        style: TextStyle(color: Colors.grey[400], fontSize: 12),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 16),
                // Cash Count
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
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: Padding(
                              padding: EdgeInsets.all(8),
                              child: Text(
                                '$cashCount',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'فواتير نقدية',
                        style: TextStyle(color: Colors.grey[400], fontSize: 12),
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

  void _navigateToPurchaseReports() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const PurchaseReportsScreen()),
    );
  }

  void _navigateToSupplierAnalytics() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const SupplierPerformanceScreen(),
      ),
    );
  }

  void _navigateToBudgetManagement() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const PurchaseBudgetScreen()),
    );
  }

  void _navigateToPurchaseOrders() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const PurchaseOrdersScreen()),
    );
  }
}
