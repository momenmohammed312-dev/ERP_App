import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:drift/drift.dart' as drift hide Column;
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/theme/madar_colors.dart';

class CustomersSummaryWidget extends ConsumerWidget {
  final AppDatabase db;

  const CustomersSummaryWidget({super.key, required this.db});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _getCustomerSummary(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            height: 96,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.15),
              ),
            ),
            child: const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }

        final data = snapshot.data ?? {
          'totalCustomers': 0,
          'outstandingDebt': 0.0,
          'paidThisMonth': 0.0,
          'activeCustomers': 0,
        };

        final isWide = MediaQuery.of(context).size.width >= 700;

        final items = [
          _CustomerSummaryItem(
            title: 'إجمالي العملاء',
            value: '${data['totalCustomers']}',
            icon: Icons.people_alt_rounded,
            color: const Color(0xFF388BFD),
          ),
          _CustomerSummaryItem(
            title: 'الديون المستحقة (لنا)',
            value: '${(data['outstandingDebt'] as double).toStringAsFixed(2)} ج.م',
            icon: Icons.trending_up_rounded,
            color: const Color(0xFFF85149),
          ),
          _CustomerSummaryItem(
            title: 'تحصيلات هذا الشهر',
            value: '${(data['paidThisMonth'] as double).toStringAsFixed(2)} ج.م',
            icon: Icons.payments_rounded,
            color: const Color(0xFF238636),
          ),
          _CustomerSummaryItem(
            title: 'عملاء عليهم حساب',
            value: '${data['activeCustomers']}',
            icon: Icons.account_balance_wallet_rounded,
            color: MadarColors.gold,
          ),
        ];

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.15),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: MadarColors.gold.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(
                      Icons.analytics_rounded,
                      size: 15,
                      color: MadarColors.gold,
                    ),
                  ),
                  const Gap(8),
                  const Text(
                    'ملخص العملاء والمديونيات',
                    style: TextStyle(
                      fontFamily: 'NotoSansArabic',
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const Gap(12),
              if (isWide)
                Row(
                  children: [
                    for (int i = 0; i < items.length; i++) ...[
                      if (i > 0) const Gap(10),
                      Expanded(child: items[i]),
                    ],
                  ],
                )
              else
                Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: items[0]),
                        const Gap(10),
                        Expanded(child: items[1]),
                      ],
                    ),
                    const Gap(10),
                    Row(
                      children: [
                        Expanded(child: items[2]),
                        const Gap(10),
                        Expanded(child: items[3]),
                      ],
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }

  Future<Map<String, dynamic>> _getCustomerSummary() async {
    try {
      final customers = await db.select(db.customers).get();
      final customerMap = {for (final c in customers) c.id: c.openingBalance};

      // Aggregate ledger balances in a single query
      final ledgerRows = await db.customSelect('''
        SELECT ref_id, COALESCE(SUM(debit - credit), 0) as net
        FROM ledger_transactions
        WHERE entity_type = 'Customer'
        GROUP BY ref_id
      ''').get();

      final balances = Map<String, double>.from(customerMap);
      for (final row in ledgerRows) {
        final refId = row.data['ref_id']?.toString() ?? '';
        final net = (row.data['net'] as num?)?.toDouble() ?? 0.0;
        balances[refId] = (balances[refId] ?? 0.0) + net;
      }

      double totalOutstandingDebt = 0.0;
      int activeCustomers = 0;
      for (final b in balances.values) {
        if (b > 0) {
          totalOutstandingDebt += b;
          activeCustomers++;
        }
      }

      final now = DateTime.now();
      final currentMonthStart = DateTime(now.year, now.month, 1);
      final paidResult = await db.customSelect(
        '''
        SELECT COALESCE(SUM(credit), 0) as paid
        FROM ledger_transactions
        WHERE entity_type = 'Customer' AND credit > 0 AND date BETWEEN ? AND ?
      ''',
        variables: [
          drift.Variable.withDateTime(currentMonthStart),
          drift.Variable.withDateTime(now),
        ],
      ).get();

      final paidThisMonth =
          (paidResult.first.data['paid'] as num?)?.toDouble() ?? 0.0;

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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, color: color, size: 14),
              ),
              const Gap(8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'NotoSansArabic',
                    fontSize: 11.5,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.7),
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const Gap(8),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'NotoSansArabic',
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }
}
