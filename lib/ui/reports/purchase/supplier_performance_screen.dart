import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/database/dao/enhanced_purchase_dao.dart';
import '../../../../core/provider/app_database_provider.dart';
import '../../../../core/database/app_database.dart';

class SupplierPerformanceScreen extends ConsumerStatefulWidget {
  const SupplierPerformanceScreen({super.key});

  @override
  ConsumerState<SupplierPerformanceScreen> createState() =>
      _SupplierPerformanceScreenState();
}

class _SupplierPerformanceScreenState
    extends ConsumerState<SupplierPerformanceScreen> {
  bool _isLoading = true;
  List<SupplierMetrics> _metrics = [];
  late final EnhancedPurchaseDao _purchaseDao;

  @override
  void initState() {
    super.initState();
    _purchaseDao = EnhancedPurchaseDao(ref.read(appDatabaseProvider));
    _loadPerformanceData();
  }

  Future<void> _loadPerformanceData() async {
    setState(() => _isLoading = true);
    try {
      final suppliers = await _purchaseDao.getAllSuppliers();
      final allPurchases = await _purchaseDao.getAllPurchases();

      final List<SupplierMetrics> metricsList = [];

      for (final supplier in suppliers) {
        final supplierPurchases = allPurchases
            .where((p) => p.supplierId == supplier.id)
            .toList();

        final totalSpent = supplierPurchases.fold(
          0.0,
          (sum, p) => sum + p.totalAmount,
        );
        final purchaseCount = supplierPurchases.length;
        final lastPurchaseDate = supplierPurchases.isNotEmpty
            ? supplierPurchases
                  .map((p) => p.purchaseDate)
                  .reduce((a, b) => a.isAfter(b) ? a : b)
            : null;

        metricsList.add(
          SupplierMetrics(
            supplier: supplier,
            totalSpent: totalSpent,
            purchaseCount: purchaseCount,
            lastPurchaseDate: lastPurchaseDate,
            currentBalance: supplier.currentBalance,
          ),
        );
      }

      // Sort by total spent by default
      metricsList.sort((a, b) => b.totalSpent.compareTo(a.totalSpent));

      setState(() {
        _metrics = metricsList;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading performance data: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E2E),
      appBar: AppBar(
        title: const Text('تحليلات أداء الموردين'),
        backgroundColor: const Color(0xFF2D2D3D),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadPerformanceData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.purple))
          : Column(
              children: [
                _buildHighlights(),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _metrics.length,
                    itemBuilder: (context, index) {
                      return _SupplierMetricCard(metrics: _metrics[index]);
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildHighlights() {
    final double totalDues = _metrics.fold(
      0,
      (sum, m) => sum + m.currentBalance,
    );
    final topSupplier = _metrics.isNotEmpty ? _metrics.first : null;

    return Container(
      padding: const EdgeInsets.all(20),
      color: const Color(0xFF2D2D3D),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildHighlightItem(
            'إجمالي المديونية',
            '${totalDues.toStringAsFixed(2)} ج.م',
            Icons.account_balance_wallet,
            Colors.redAccent,
          ),
          if (topSupplier != null)
            _buildHighlightItem(
              'أكبر مورد',
              topSupplier.supplier.businessName,
              Icons.star,
              Colors.amber,
              subtitle: '${topSupplier.totalSpent.toStringAsFixed(0)} ج.م',
            ),
        ],
      ),
    );
  }

  Widget _buildHighlightItem(
    String label,
    String value,
    IconData icon,
    Color color, {
    String? subtitle,
  }) {
    return Column(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        if (subtitle != null)
          Text(
            subtitle,
            style: TextStyle(color: color.withValues(alpha: 0.8), fontSize: 10),
          ),
      ],
    );
  }
}

class SupplierMetrics {
  final EnhancedSupplier supplier;
  final double totalSpent;
  final int purchaseCount;
  final DateTime? lastPurchaseDate;
  final double currentBalance;

  SupplierMetrics({
    required this.supplier,
    required this.totalSpent,
    required this.purchaseCount,
    this.lastPurchaseDate,
    required this.currentBalance,
  });
}

class _SupplierMetricCard extends StatelessWidget {
  final SupplierMetrics metrics;

  const _SupplierMetricCard({required this.metrics});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF2D2D3D),
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.purple.withValues(alpha: 0.2),
                  child: Text(
                    metrics.supplier.businessName.substring(0, 1),
                    style: const TextStyle(
                      color: Colors.purple,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        metrics.supplier.businessName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        metrics.supplier.phone,
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: metrics.currentBalance > 0
                        ? Colors.red.withValues(alpha: 0.1)
                        : Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    metrics.currentBalance > 0 ? 'مدين' : 'مسدد',
                    style: TextStyle(
                      color: metrics.currentBalance > 0
                          ? Colors.redAccent
                          : Colors.greenAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(color: Colors.white12, height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildSubMetric(
                  'إجمالي المشتريات',
                  '${metrics.totalSpent.toStringAsFixed(2)} ج.م',
                ),
                _buildSubMetric('عدد الفواتير', '${metrics.purchaseCount}'),
                _buildSubMetric(
                  'الرصيد الحالي',
                  '${metrics.currentBalance.toStringAsFixed(2)} ج.م',
                  color: metrics.currentBalance > 0
                      ? Colors.redAccent
                      : Colors.greenAccent,
                ),
              ],
            ),
            if (metrics.lastPurchaseDate != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.history, color: Colors.grey, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    'آخر عملية: ${DateFormat('yyyy-MM-dd').format(metrics.lastPurchaseDate!)}',
                    style: const TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSubMetric(
    String label,
    String value, {
    Color color = Colors.white,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10)),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
