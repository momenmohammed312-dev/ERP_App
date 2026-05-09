import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:drift/drift.dart' as drift hide Column;
import 'package:pos_offline_desktop/core/database/app_database.dart';

class CustomersSummaryWidget extends ConsumerWidget {
  final AppDatabase db;

  const CustomersSummaryWidget({super.key, required this.db});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _getCustomerSummary(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        final data =
            snapshot.data ??
            {
              'totalCustomers': 0,
              'outstandingDebt': 0.0,
              'paidThisMonth': 0.0,
              'activeCustomers': 0,
            };

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'ملخص العملاء',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Gap(12),
                Row(
                  children: [
                    Expanded(
                      child: _CustomerSummaryItem(
                        title: 'إجمالي العملاء',
                        value: '${data['totalCustomers']}',
                        icon: Icons.people,
                        color: Colors.blue,
                      ),
                    ),
                    const Gap(12),
                    Expanded(
                      child: _CustomerSummaryItem(
                        title: 'الديون المستحقة',
                        value:
                            '${(data['outstandingDebt'] as double).toStringAsFixed(2)} ج.م',
                        icon: Icons.money_off,
                        color: Colors.red,
                      ),
                    ),
                  ],
                ),
                const Gap(12),
                Row(
                  children: [
                    Expanded(
                      child: _CustomerSummaryItem(
                        title: 'المدفوع هذا الشهر',
                        value:
                            '${(data['paidThisMonth'] as double).toStringAsFixed(2)} ج.م',
                        icon: Icons.payment,
                        color: Colors.green,
                      ),
                    ),
                    const Gap(12),
                    Expanded(
                      child: _CustomerSummaryItem(
                        title: 'العملاء النشطين',
                        value: '${data['activeCustomers']}',
                        icon: Icons.check_circle,
                        color: Colors.orange,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<Map<String, dynamic>> _getCustomerSummary() async {
    try {
      // Get all customers
      final customers = await db.select(db.customers).get();

      // Calculate totals
      double totalOutstandingDebt = 0.0;
      double paidThisMonth = 0.0;
      int activeCustomers = 0;

      final now = DateTime.now();
      final currentMonthStart = DateTime(now.year, now.month, 1);

      for (final customer in customers) {
        try {
          final balance = await db.ledgerDao.getRunningBalance(
            'Customer',
            customer.id,
          );

          if (balance > 0) {
            totalOutstandingDebt += balance;
            activeCustomers++;
          }

          // Get transactions for this month to calculate paid amount
          final monthlyTransactions =
              await (db.select(db.ledgerTransactions)
                    ..where((t) => t.entityType.equals('Customer'))
                    ..where((t) => t.refId.equals(customer.id))
                    ..where(
                      (t) => t.date.isBetween(
                        drift.Constant(currentMonthStart),
                        drift.Constant(now),
                      ),
                    )
                    ..where((t) => t.credit.isBiggerThan(drift.Constant(0.0))))
                  .get();

          for (final transaction in monthlyTransactions) {
            paidThisMonth += transaction.credit;
          }
        } catch (e) {
          // Skip if there's an error with this customer
          debugPrint('Error processing customer ${customer.id}: $e');
          continue;
        }
      }

      return {
        'totalCustomers': customers.length,
        'outstandingDebt': totalOutstandingDebt,
        'paidThisMonth': paidThisMonth,
        'activeCustomers': activeCustomers,
      };
    } catch (e) {
      debugPrint('Error in customer summary: $e');
      return {
        'totalCustomers': 0,
        'outstandingDebt': 0.0,
        'paidThisMonth': 0.0,
        'activeCustomers': 0,
      };
    }
  }
}

class _CustomerSummaryItem extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _CustomerSummaryItem({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const Gap(8),
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: color),
          ),
          const Gap(4),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
