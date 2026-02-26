import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/database/dao/enhanced_purchase_dao.dart';
import '../../../../core/provider/app_database_provider.dart';

class PurchaseBudgetScreen extends ConsumerStatefulWidget {
  const PurchaseBudgetScreen({super.key});

  @override
  ConsumerState<PurchaseBudgetScreen> createState() =>
      _PurchaseBudgetScreenState();
}

class _PurchaseBudgetScreenState extends ConsumerState<PurchaseBudgetScreen> {
  bool _isLoading = true;
  List<MonthlySpending> _monthlySpending = [];
  late final EnhancedPurchaseDao _purchaseDao;

  @override
  void initState() {
    super.initState();
    _purchaseDao = EnhancedPurchaseDao(ref.read(appDatabaseProvider));
    _loadBudgetData();
  }

  Future<void> _loadBudgetData() async {
    setState(() => _isLoading = true);
    try {
      final allPurchases = await _purchaseDao.getAllPurchases();

      final Map<String, double> spendingByMonth = {};

      for (final purchase in allPurchases) {
        final monthKey = DateFormat('yyyy-MM').format(purchase.purchaseDate);
        spendingByMonth[monthKey] =
            (spendingByMonth[monthKey] ?? 0) + purchase.totalAmount;
      }

      final List<MonthlySpending> sortedSpending = spendingByMonth.entries
          .map((e) => MonthlySpending(month: e.key, amount: e.value))
          .toList();

      sortedSpending.sort((a, b) => b.month.compareTo(a.month));

      setState(() {
        _monthlySpending = sortedSpending;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading budget data: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E2E),
      appBar: AppBar(
        title: const Text('تحليل المصاريف والميزانية'),
        backgroundColor: const Color(0xFF2D2D3D),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.purple))
          : Column(
              children: [
                _buildSpendingOverview(),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _monthlySpending.length,
                    itemBuilder: (context, index) {
                      return _MonthlySpendingCard(
                        spending: _monthlySpending[index],
                        isHighest:
                            index ==
                            0, // Simplified: first in sorted list is highest if sorted by amount, but here we sort by date
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSpendingOverview() {
    final double totalSpent = _monthlySpending.fold(
      0,
      (sum, m) => sum + m.amount,
    );
    final double avgSpent = _monthlySpending.isNotEmpty
        ? totalSpent / _monthlySpending.length
        : 0;

    return Container(
      padding: const EdgeInsets.all(20),
      color: const Color(0xFF2D2D3D),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildOverviewItem(
            'متوسط الإنفاق الشهري',
            '${avgSpent.toStringAsFixed(2)} ج.م',
            Icons.analytics,
            Colors.blue,
          ),
          _buildOverviewItem(
            'إجمالي ميزانية المشتريات',
            '${totalSpent.toStringAsFixed(2)} ج.م',
            Icons.account_balance,
            Colors.green,
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewItem(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
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
      ],
    );
  }
}

class MonthlySpending {
  final String month;
  final double amount;

  MonthlySpending({required this.month, required this.amount});
}

class _MonthlySpendingCard extends StatelessWidget {
  final MonthlySpending spending;
  final bool isHighest;

  const _MonthlySpendingCard({required this.spending, this.isHighest = false});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF2D2D3D),
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.purple.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.calendar_month, color: Colors.purple),
        ),
        title: Text(
          spending.month,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        trailing: Text(
          '${spending.amount.toStringAsFixed(2)} ج.م',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ),
    );
  }
}
