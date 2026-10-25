import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:intl/intl.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/theme/madar_colors.dart';
import 'package:pos_offline_desktop/core/services/export_service.dart';
import 'package:pos_offline_desktop/core/utils/app_utils.dart';
import 'package:pos_offline_desktop/core/provider/auth_provider.dart';
import 'package:pos_offline_desktop/ui/purchase/widgets/purchase_detail_dialog.dart';
import 'package:pos_offline_desktop/ui/purchase/widgets/void_purchase_dialog.dart';
import 'package:pos_offline_desktop/ui/supplier/widgets/edit_supplier_transaction_dialog.dart';
import 'package:pos_offline_desktop/l10n/app_localizations.dart';

/// List filter for the suppliers screen. Defaults to active only so that
/// deactivated (soft-deleted) suppliers disappear while their financial
/// history stays intact in the ledger.
final supplierStatusFilterProvider = StateProvider<String>((_) => 'active');
final supplierSearchQueryProvider = StateProvider<String>((_) => '');

class SuppliersWidget extends ConsumerWidget {
  final AppDatabase db;

  const SuppliersWidget({super.key, required this.db});

  Future<Map<String, dynamic>> _getSuppliersSummary() async {
    try {
      final suppliers = await db.select(db.suppliers).get();
      final supplierMap = {for (final s in suppliers) s.id: s.openingBalance};

      final ledgerRows = await db.customSelect('''
        SELECT ref_id, COALESCE(SUM(credit - debit), 0) as net
        FROM ledger_transactions
        WHERE entity_type = 'Supplier'
        GROUP BY ref_id
      ''').get();

      final balances = Map<String, double>.from(supplierMap);
      for (final row in ledgerRows) {
        final refId = row.data['ref_id']?.toString() ?? '';
        final net = (row.data['net'] as num?)?.toDouble() ?? 0.0;
        balances[refId] = (balances[refId] ?? 0.0) + net;
      }

      double totalOutstandingDebt = 0.0;
      int activeSuppliers = 0;
      for (final b in balances.values) {
        if (b > 0) {
          totalOutstandingDebt += b;
          activeSuppliers++;
        }
      }

      final now = DateTime.now();
      final currentMonthStart = DateTime(now.year, now.month, 1);
      final paidResult = await db.customSelect(
        '''
        SELECT COALESCE(SUM(debit), 0) as paid
        FROM ledger_transactions
        WHERE entity_type = 'Supplier' AND debit > 0 AND date BETWEEN ? AND ?
      ''',
        variables: [
          Variable.withDateTime(currentMonthStart),
          Variable.withDateTime(now),
        ],
      ).get();

      final paidThisMonth =
          (paidResult.first.data['paid'] as num?)?.toDouble() ?? 0.0;

      return {
        'totalSuppliers': suppliers.length,
        'outstandingDebt': totalOutstandingDebt,
        'paidThisMonth': paidThisMonth,
        'activeSuppliers': activeSuppliers,
      };
    } catch (e) {
      debugPrint('Error in supplier summary: $e');
      return {
        'totalSuppliers': 0,
        'outstandingDebt': 0.0,
        'paidThisMonth': 0.0,
        'activeSuppliers': 0,
      };
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final statusFilter = ref.watch(supplierStatusFilterProvider);
    final searchQuery = ref.watch(supplierSearchQueryProvider);
    final isWide = MediaQuery.of(context).size.width >= 700;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Suppliers Summary KPI Bar
          FutureBuilder<Map<String, dynamic>>(
            future: _getSuppliersSummary(),
            builder: (context, snapshot) {
              final data = snapshot.data ?? {
                'totalSuppliers': 0,
                'outstandingDebt': 0.0,
                'paidThisMonth': 0.0,
                'activeSuppliers': 0,
              };

              final items = [
                _SupplierSummaryItem(
                  title: l10n.total_suppliers,
                  value: '${data['totalSuppliers']}',
                  icon: Icons.people_alt_rounded,
                  color: const Color(0xFF388BFD),
                ),
                _SupplierSummaryItem(
                  title: 'مستحقات الموردين (علينا)',
                  value:
                      '${(data['outstandingDebt'] as double).toStringAsFixed(2)} ${l10n.currency}',
                  icon: Icons.trending_up_rounded,
                  color: const Color(0xFFF85149),
                ),
                _SupplierSummaryItem(
                  title: 'سدادات هذا الشهر',
                  value:
                      '${(data['paidThisMonth'] as double).toStringAsFixed(2)} ${l10n.currency}',
                  icon: Icons.payments_rounded,
                  color: const Color(0xFF238636),
                ),
                _SupplierSummaryItem(
                  title: 'موردين لهم حساب',
                  value: '${data['activeSuppliers']}',
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
                    color: Theme.of(context)
                        .colorScheme
                        .outline
                        .withValues(alpha: 0.15),
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
                        Text(
                          l10n.suppliers_summary,
                          style: const TextStyle(
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
          ),

          const Gap(16),

          // Search and Actions Bar
          Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(context)
                          .colorScheme
                          .outline
                          .withValues(alpha: 0.15),
                    ),
                  ),
                  child: TextField(
                    onChanged: (val) => ref
                        .read(supplierSearchQueryProvider.notifier)
                        .state = val,
                    decoration: InputDecoration(
                      hintText: l10n.search_supplier_hint,
                      hintStyle: TextStyle(
                        fontFamily: 'NotoSansArabic',
                        fontSize: 13,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.5),
                      ),
                      prefixIcon: const Icon(Icons.search, size: 20),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
              ),
              const Gap(12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(context)
                        .colorScheme
                        .outline
                        .withValues(alpha: 0.15),
                  ),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: statusFilter,
                    icon: const Icon(Icons.filter_list_rounded, size: 18),
                    items: [
                      DropdownMenuItem(value: 'all', child: Text(l10n.all)),
                      DropdownMenuItem(
                        value: 'active',
                        child: Text(l10n.active),
                      ),
                      DropdownMenuItem(
                        value: 'inactive',
                        child: Text(l10n.inactive),
                      ),
                      DropdownMenuItem(
                        value: 'debt',
                        child: Text(l10n.has_debt),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        ref.read(supplierStatusFilterProvider.notifier).state =
                            value;
                      }
                    },
                  ),
                ),
              ),
              const Gap(12),
              FilledButton.icon(
                onPressed: () {
                  _showAddSupplierDialog(context);
                },
                icon: const Icon(Icons.add_business_rounded, size: 18),
                label: Text(
                  l10n.add_supplier,
                  style: const TextStyle(
                    fontFamily: 'NotoSansArabic',
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),

          const Gap(16),

          // Suppliers List
          StreamBuilder<List<Supplier>>(
            stream: statusFilter == 'debt'
                ? db.supplierDao.watchSuppliersWithDebt()
                : db.supplierDao.watchSuppliersByStatus(statusFilter),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(),
                  ),
                );
              }
              final allSuppliers = snapshot.data ?? [];
              final q = searchQuery.toLowerCase().trim();
              final suppliers = q.isEmpty
                  ? allSuppliers
                  : allSuppliers.where((s) {
                      final name = s.name.toLowerCase();
                      final phone = (s.phone ?? '').toLowerCase();
                      return name.contains(q) || phone.contains(q);
                    }).toList();

              if (suppliers.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.business_outlined,
                          size: 64,
                          color: Colors.grey,
                        ),
                        const Gap(16),
                        Text(l10n.no_suppliers_currently),
                        Text(
                          l10n.add_new_suppliers_to_start,
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: suppliers.length,
                itemBuilder: (context, index) {
                  final supplier = suppliers[index];
                  return FutureBuilder<double>(
                    future: db.ledgerDao.getSupplierBalance(supplier.id),
                    builder: (context, balanceSnapshot) {
                      final balance = balanceSnapshot.data ?? 0.0;
                      return _SupplierCard(
                        supplier: supplier,
                        totalPurchases: balance > 0 ? balance : 0.0,
                        totalPaid: balance < 0 ? -balance : 0.0,
                        db: db,
                        context: context,
                        lastPurchaseDate: DateTime.now().subtract(
                          Duration(days: index * 2),
                        ),
                        getSupplierPurchases: _getSupplierPurchases,
                      );
                    },
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _getSupplierPurchases(
    String supplierId,
  ) async {
    try {
      final purchasesResult = await db
          .customSelect(
            '''
        SELECT p.id, p.invoice_number, p.purchase_date, p.total_amount, 
               p.paid_amount, p.payment_method, p.status, p.is_deleted
        FROM purchases p
        WHERE p.supplier_id = ?
        ORDER BY p.purchase_date DESC
        LIMIT 30
        ''',
            variables: [Variable.withString(supplierId)],
          )
          .get();

      final purchaseItems = purchasesResult.map((row) {
        final d = row.data;
        final pDate = parseDate(d['purchase_date']);
        return {
          'id': d['id']?.toString() ?? '',
          'type': 'purchase',
          'invoice_number': d['invoice_number']?.toString(),
          'purchase_date': pDate.toIso8601String(),
          'date': pDate,
          'total_amount': (d['total_amount'] as num?)?.toDouble() ?? 0.0,
          'paid_amount': (d['paid_amount'] as num?)?.toDouble() ?? 0.0,
          'payment_method': d['payment_method']?.toString() ?? 'cash',
          'status': d['status']?.toString() ?? 'pending',
          'is_deleted': d['is_deleted'] == 1 || d['is_deleted'] == true,
          'description': 'فاتورة ${d['invoice_number'] ?? 'غير محدد'}',
        };
      }).toList();

      final paymentsResult = await db
          .customSelect(
            '''
        SELECT id, date, description, debit, credit, origin, payment_method, receipt_number
        FROM ledger_transactions
        WHERE entity_type = 'Supplier' AND ref_id = ? AND (debit > 0 OR origin = 'payment' OR origin = 'reversal')
        ORDER BY date DESC
        LIMIT 100
        ''',
            variables: [Variable.withString(supplierId)],
          )
          .get();

      final paymentItems = paymentsResult.map((row) {
        final d = row.data;
        final debit = (d['debit'] as num?)?.toDouble() ?? 0.0;
        final credit = (d['credit'] as num?)?.toDouble() ?? 0.0;
        final amount = debit > 0 ? debit : credit;
        final pDate = parseDate(d['date']);
        final desc = (d['description']?.toString().isNotEmpty ?? false)
            ? d['description'].toString()
            : 'سداد دفعة للمورد';

        return {
          'id': d['id']?.toString() ?? '',
          'type': 'payment',
          'invoice_number': d['receipt_number']?.toString(),
          'purchase_date': pDate.toIso8601String(),
          'date': pDate,
          'total_amount': amount,
          'paid_amount': amount,
          'payment_method': d['payment_method']?.toString() ?? 'cash',
          'status': 'paid',
          'is_deleted': false,
          'description': desc,
        };
      }).toList();

      final combined = [...purchaseItems, ...paymentItems];
      combined.sort((a, b) => (b['date'] as DateTime).compareTo(a['date'] as DateTime));
      return combined;
    } catch (e) {
      debugPrint('Error fetching supplier purchases: $e');
      return [];
    }
  }

  void _showAddSupplierDialog(BuildContext context) {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final addressController = TextEditingController();
    final emailController = TextEditingController();
    final balanceController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) {
        final l10n = AppLocalizations.of(dialogContext);
        return AlertDialog(
          title: Text(l10n.add_new_supplier),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: l10n.supplier_name,
                  border: const OutlineInputBorder(),
                ),
              ),
              const Gap(16),
              TextField(
                controller: phoneController,
                decoration: InputDecoration(
                  labelText: l10n.phone_number,
                  border: const OutlineInputBorder(),
                ),
                keyboardType: TextInputType.phone,
              ),
              const Gap(16),
              TextField(
                controller: addressController,
                decoration: InputDecoration(
                  labelText: l10n.address,
                  border: const OutlineInputBorder(),
                ),
              ),
              const Gap(16),
              TextField(
                controller: emailController,
                decoration: InputDecoration(
                  labelText: l10n.email,
                  border: const OutlineInputBorder(),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const Gap(16),
              TextField(
                controller: balanceController,
                decoration: InputDecoration(
                  labelText: l10n.opening_balance,
                  border: const OutlineInputBorder(),
                  prefixText: l10n.currency,
                ),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(l10n.cancel),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.isNotEmpty) {
                  try {
                    // Duplicate guard: same normalized name (+phone when both
                    // present) blocks the insert with a conflict message.
                    // Never auto-merges; the user picks use-existing vs edit.
                    final conflicts =
                        await db.supplierDao.findDuplicateSuppliers(
                      name: nameController.text,
                      phone: phoneController.text.isNotEmpty
                          ? phoneController.text
                          : null,
                    );
                    if (conflicts.isNotEmpty) {
                      if (dialogContext.mounted) {
                        Navigator.pop(dialogContext);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'المورد موجود بالفعل: ${conflicts.first.name} — استخدم الموجود أو عدّله بدل التكرار',
                            ),
                            backgroundColor: Colors.orange,
                          ),
                        );
                      }
                      return;
                    }
                    // Add supplier to database
                    await db.supplierDao.insertSupplier(
                      SuppliersCompanion.insert(
                        id: DateTime.now().millisecondsSinceEpoch.toString(),
                        name: nameController.text,
                        phone: phoneController.text.isNotEmpty
                            ? Value(phoneController.text)
                            : const Value.absent(),
                        address: addressController.text.isNotEmpty
                            ? Value(addressController.text)
                            : const Value.absent(),
                        openingBalance: Value(
                          double.tryParse(balanceController.text) ?? 0.0,
                        ),
                        status: const Value('Active'),
                      ),
                    );

                    if (dialogContext.mounted) {
                      Navigator.pop(dialogContext);
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        SnackBar(
                          content: Text(l10n.supplier_added_successfully),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  } catch (e) {
                    if (dialogContext.mounted) {
                      Navigator.pop(dialogContext);
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        SnackBar(
                          content: Text('${l10n.error}: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                }
              },
              child: Text(l10n.save),
            ),
          ],
        );
      },
    );
  }
}

class _SupplierSummaryItem extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _SupplierSummaryItem({
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

class _SupplierCard extends ConsumerWidget {
  final Supplier supplier;
  final double totalPurchases;
  final double totalPaid;
  final AppDatabase db;
  final BuildContext context;
  final DateTime lastPurchaseDate;
  final Future<List<Map<String, dynamic>>> Function(String)
  getSupplierPurchases;

  const _SupplierCard({
    required this.supplier,
    required this.totalPurchases,
    required this.totalPaid,
    required this.db,
    required this.context,
    required this.lastPurchaseDate,
    required this.getSupplierPurchases,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remainingDebt = totalPurchases - totalPaid;
    final isCreditor = remainingDebt > 0.001;
    final isDebtor = remainingDebt < -0.001;

    final badgeColor = isCreditor
        ? const Color(0xFFF85149)
        : (isDebtor ? const Color(0xFF388BFD) : const Color(0xFF238636));

    final badgeLabel = isCreditor
        ? AppLocalizations.of(context).debtor
        : (isDebtor ? AppLocalizations.of(context).entitled : 'خالص الحساب');

    final badgeAmount = isCreditor
        ? '${remainingDebt.toStringAsFixed(2)} ${AppLocalizations.of(context).currency}'
        : (isDebtor
            ? '${(-remainingDebt).toStringAsFixed(2)} ${AppLocalizations.of(context).currency}'
            : '0.00 ${AppLocalizations.of(context).currency}');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.15),
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          shape: const Border(),
          collapsedShape: const Border(),
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.purple.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Center(
              child:
                  Icon(Icons.business_rounded, color: Colors.purple, size: 20),
            ),
          ),
          title: Text(
            supplier.name,
            style: const TextStyle(
              fontFamily: 'NotoSansArabic',
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (supplier.phone != null && supplier.phone!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Row(
                    children: [
                      Icon(
                        Icons.phone_rounded,
                        size: 13,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.5),
                      ),
                      const Gap(4),
                      Text(
                        supplier.phone!,
                        style: TextStyle(
                          fontFamily: 'NotoSansArabic',
                          fontSize: 12.5,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              const Gap(2),
              Text(
                '${AppLocalizations.of(context).last_purchase_colon} ${lastPurchaseDate.day}/${lastPurchaseDate.month}/${lastPurchaseDate.year}',
                style: TextStyle(
                  fontFamily: 'NotoSansArabic',
                  fontSize: 11.5,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: badgeColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: badgeColor.withValues(alpha: 0.3)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  badgeLabel,
                  style: TextStyle(
                    fontFamily: 'NotoSansArabic',
                    color: badgeColor,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  badgeAmount,
                  style: TextStyle(
                    fontFamily: 'NotoSansArabic',
                    color: badgeColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                // Contact Information
                if (supplier.address != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Theme.of(
                          context,
                        ).colorScheme.outline.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppLocalizations.of(context).contact_information,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        if (supplier.address != null) ...[
                          const Gap(4),
                          Row(
                            children: [
                              const Icon(Icons.location_on, size: 16),
                              const Gap(4),
                              Text(supplier.address ?? ''),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),

                const Gap(16),

                // Financial Summary
                Row(
                  children: [
                    Expanded(
                      child: _FinancialCard(
                        title: AppLocalizations.of(context).total_purchases,
                        value: totalPurchases,
                        color: Colors.blue,
                      ),
                    ),
                    const Gap(16),
                    Expanded(
                      child: _FinancialCard(
                        title: AppLocalizations.of(context).paid,
                        value: totalPaid,
                        color: Colors.green,
                      ),
                    ),
                    const Gap(16),
                    Expanded(
                      child: _FinancialCard(
                        title: AppLocalizations.of(context).remaining,
                        value: remainingDebt,
                        color: remainingDebt > 0 ? Colors.red : Colors.green,
                      ),
                    ),
                  ],
                ),

                const Gap(16),

                // Recent Purchases
                FutureBuilder<List<Map<String, dynamic>>>(
                  future: getSupplierPurchases(supplier.id),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return Container(
                        padding: const EdgeInsets.all(20),
                        child: const Text('لا توجد مشتريات لهذا المورد'),
                      );
                    }
                    final purchases = snapshot.data!;
                    return Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(
                            context,
                          ).colorScheme.outline.withValues(alpha: 0.2),
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.purple.withValues(alpha: 0.1),
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(8),
                                topRight: Radius.circular(8),
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    AppLocalizations.of(context).date,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    AppLocalizations.of(context).description,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    AppLocalizations.of(context).amount,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    AppLocalizations.of(context).status,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 44),
                              ],
                            ),
                          ),
                          ...purchases.map((purchase) {
                            final isPayment = purchase['type'] == 'payment';
                            final date = DateTime.parse(
                              purchase['purchase_date'],
                            );
                            final amount = purchase['total_amount'] as double;
                            final paidAmount =
                                purchase['paid_amount'] as double;
                            final remaining = amount - paidAmount;
                            final isPaid = remaining <= 0;
                            final isVoided = purchase['status'] == 'Voided' ||
                                purchase['is_deleted'] == 1 ||
                                purchase['is_deleted'] == true;
                            return InkWell(
                              onTap: () async {
                                if (isPayment) {
                                  final ledgerTx = await db.ledgerDao
                                      .getTransactionById(purchase['id']);
                                  if (ledgerTx != null && context.mounted) {
                                    final updated = await showDialog<bool>(
                                      context: context,
                                      builder: (_) =>
                                          EditSupplierTransactionDialog(
                                        db: db,
                                        transaction: ledgerTx,
                                        onSaved: () {
                                          if (context.mounted) {
                                            (context as Element)
                                                .markNeedsBuild();
                                          }
                                        },
                                      ),
                                    );
                                    if (updated == true && context.mounted) {
                                      (context as Element).markNeedsBuild();
                                    }
                                  }
                                } else {
                                  await showDialog(
                                    context: context,
                                    builder: (_) => PurchaseDetailDialog(
                                      db: db,
                                      purchaseId:
                                          purchase['id']?.toString() ?? '',
                                    ),
                                  );
                                  if (context.mounted) {
                                    (context as Element).markNeedsBuild();
                                  }
                                }
                              },
                              child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(
                                    color: Theme.of(context).colorScheme.outline
                                        .withValues(alpha: 0.1),
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${date.day}/${date.month}/${date.year}',
                                    ),
                                  ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                isPayment
                                                    ? (purchase['description'] ??
                                                        'سداد دفعة')
                                                    : 'فاتورة ${purchase['invoice_number'] ?? 'غير محدد'}',
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            if (isVoided) ...[
                                              const Gap(4),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 6,
                                                  vertical: 1,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Colors.red
                                                      .withValues(alpha: 0.1),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                  border: Border.all(
                                                      color: Colors.redAccent),
                                                ),
                                                child: const Text(
                                                  'ملغاة',
                                                  style: TextStyle(
                                                    color: Colors.red,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        const Gap(2),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isPayment
                                                ? Colors.green.withValues(
                                                    alpha: 0.15,
                                                  )
                                                : Colors.blue.withValues(
                                                    alpha: 0.1,
                                                  ),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            isPayment ? 'سداد' : 'شراء',
                                            style: TextStyle(
                                              color: isPayment
                                                  ? Colors.green
                                                  : Colors.blue,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      '${amount.toStringAsFixed(2)} ${AppLocalizations.of(context).currency}',
                                      style: TextStyle(
                                        color: isPayment ? Colors.green : null,
                                        fontWeight: isPayment
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isPayment
                                            ? Colors.green.withValues(
                                                alpha: 0.15,
                                              )
                                            : (isVoided
                                                ? Colors.grey.withValues(
                                                    alpha: 0.1,
                                                  )
                                                : (isPaid
                                                    ? Colors.green.withValues(
                                                        alpha: 0.1,
                                                      )
                                                    : Colors.orange.withValues(
                                                        alpha: 0.1,
                                                      ))),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        isPayment
                                            ? 'سند صرف'
                                            : (isVoided
                                                ? 'ملغاة'
                                                : (isPaid
                                                    ? AppLocalizations.of(
                                                        context,
                                                      ).paid_status
                                                    : 'متبقي ${remaining.toStringAsFixed(2)}')),
                                        style: TextStyle(
                                          color: isPayment
                                              ? Colors.green
                                              : (isVoided
                                                  ? Colors.grey
                                                  : (isPaid
                                                      ? Colors.green
                                                      : Colors.orange)),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 44,
                                    child: isVoided
                                        ? const SizedBox.shrink()
                                        : IconButton(
                                            icon: const Icon(
                                              Icons.delete_outline,
                                              color: Colors.red,
                                              size: 20,
                                            ),
                                            tooltip: isPayment
                                                ? 'حذف سند السداد'
                                                : 'حذف الفاتورة',
                                            onPressed: () async {
                                              if (isPayment) {
                                                final confirm =
                                                    await showDialog<bool>(
                                                  context: context,
                                                  builder: (ctx) => AlertDialog(
                                                    title: const Text(
                                                        'تأكيد حذف سند السداد'),
                                                    content: Text(
                                                      'هل أنت متأكد من حذف حركة السداد بمبلغ ${amount.toStringAsFixed(2)} ج.م؟\nسيتم استرجاع المبلغ لمديونية المورد.',
                                                    ),
                                                    actions: [
                                                      TextButton(
                                                        onPressed: () =>
                                                            Navigator.pop(
                                                                ctx, false),
                                                        child: const Text('إلغاء'),
                                                      ),
                                                      ElevatedButton(
                                                        onPressed: () =>
                                                            Navigator.pop(
                                                                ctx, true),
                                                        style:
                                                            ElevatedButton.styleFrom(
                                                          backgroundColor:
                                                              Colors.red,
                                                          foregroundColor:
                                                              Colors.white,
                                                        ),
                                                        child: const Text(
                                                            'تأكيد الحذف'),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                                if (confirm == true) {
                                                  await db.ledgerDao
                                                      .deleteTransaction(
                                                          purchase['id']);
                                                  if (context.mounted) {
                                                    (context as Element)
                                                        .markNeedsBuild();
                                                    ScaffoldMessenger.of(context)
                                                        .showSnackBar(
                                                      const SnackBar(
                                                        content: Text(
                                                            'تم حذف حركة السداد واسترجاع الرصيد بنجاح'),
                                                        backgroundColor:
                                                            Colors.green,
                                                      ),
                                                    );
                                                  }
                                                }
                                              } else {
                                                final username = ref
                                                        .read(authProvider)
                                                        ?.username ??
                                                    'admin';
                                                final done =
                                                    await showDialog<bool>(
                                                  context: context,
                                                  builder: (_) =>
                                                      VoidPurchaseDialog(
                                                    db: db,
                                                    purchaseId: purchase['id']
                                                            ?.toString() ??
                                                        '',
                                                    voidedBy: username,
                                                  ),
                                                );
                                                if (done == true &&
                                                    context.mounted) {
                                                  (context as Element)
                                                      .markNeedsBuild();
                                                }
                                              }
                                            },
                                          ),
                                  ),
                                ],
                              ),
                            ),
                            );
                          }),
                        ],
                      ),
                    );
                  },
                ),

                const Gap(16),

                // Action Buttons (supplier quick-purchase removed permanently:
                // it posted debit-side ledger rows with no purchase, items or
                // stock — see Item 3; purchases are created from the supply
                // invoice page only).
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () async {
                          await _showPaymentDialog(supplier);
                          if (context.mounted) {
                            (context as Element).markNeedsBuild();
                          }
                        },
                        icon: const Icon(Icons.payments_rounded, size: 17),
                        label: Text(
                          AppLocalizations.of(context).settle_payment,
                        ),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                    const Gap(10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          _exportSupplierReport(supplier);
                        },
                        icon: const Icon(Icons.picture_as_pdf_outlined, size: 17),
                        label: const Text('كشف حساب PDF'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                    const Gap(10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          _showEditSupplierDialog(supplier);
                        },
                        icon: const Icon(Icons.edit_outlined, size: 17),
                        label: const Text('تعديل البيانات'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                    const Gap(10),
                    OutlinedButton.icon(
                      onPressed: () {
                        _showDeleteSupplierDialog(supplier);
                      },
                      icon: const Icon(Icons.delete_outline_rounded, size: 17),
                      label: const Text('حذف'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFF85149),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }

  void _showEditSupplierDialog(Supplier supplier) {
    final nameController = TextEditingController(text: supplier.name);
    final phoneController = TextEditingController(text: supplier.phone ?? '');
    final addressController = TextEditingController(
      text: supplier.address ?? '',
    );
    final balanceController = TextEditingController(
      text: supplier.openingBalance.toString(),
    );

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('تعديل بيانات المورد'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: 'اسم المورد',
                  border: const OutlineInputBorder(),
                ),
              ),
              const Gap(16),
              TextField(
                controller: phoneController,
                decoration: InputDecoration(
                  labelText: 'رقم الهاتف',
                  border: const OutlineInputBorder(),
                ),
                keyboardType: TextInputType.phone,
              ),
              const Gap(16),
              TextField(
                controller: addressController,
                decoration: InputDecoration(
                  labelText: 'العنوان',
                  border: const OutlineInputBorder(),
                ),
              ),
              const Gap(16),
              TextField(
                controller: balanceController,
                decoration: InputDecoration(
                  labelText: 'الرصيد الافتتاحي',
                  border: const OutlineInputBorder(),
                  prefixText: 'ج.م',
                ),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.isNotEmpty) {
                  try {
                    final conflicts =
                        await db.supplierDao.findDuplicateSuppliers(
                      name: nameController.text,
                      phone: phoneController.text.isNotEmpty
                          ? phoneController.text
                          : null,
                      excludeId: supplier.id,
                    );
                    if (conflicts.isNotEmpty) {
                      if (dialogContext.mounted) {
                        Navigator.pop(dialogContext);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'الاسم/الهاتف يطابق موردًا آخر: ${conflicts.first.name} — راجع البيانات بدل التكرار',
                            ),
                            backgroundColor: Colors.orange,
                          ),
                        );
                      }
                      return;
                    }
                    await db.supplierDao.updateSupplier(
                      SuppliersCompanion(
                        id: Value(supplier.id),
                        name: Value(nameController.text),
                        phone: phoneController.text.isNotEmpty
                            ? Value(phoneController.text)
                            : const Value.absent(),
                        address: addressController.text.isNotEmpty
                            ? Value(addressController.text)
                            : const Value.absent(),
                        openingBalance: Value(
                          double.tryParse(balanceController.text) ?? 0.0,
                        ),
                        // Preserve lifecycle status: editing must never
                        // resurrect a deactivated supplier.
                        status: Value(supplier.status),
                      ),
                    );

                    if (dialogContext.mounted) {
                      Navigator.pop(dialogContext);
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        SnackBar(
                          content: Text('تم تحديث بيانات المورد بنجاح'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  } catch (e) {
                    if (dialogContext.mounted) {
                      Navigator.pop(dialogContext);
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        SnackBar(
                          content: Text('خطأ: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                }
              },
              child: Text('حفظ'),
            ),
          ],
        );
      },
    );
  }

  void _showDeleteSupplierDialog(Supplier supplier) {
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('حذف المورد'),
          content: Text(
            'سيتم إخفاء "${supplier.name}" من القوائم مع الاحتفاظ الكامل '
            'بسجل فواتيره ومدفوعاته في الدفتر.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () async {
                try {
                  // Soft delete: deactivate so history (purchases, ledger)
                  // is never orphaned. The default list shows Active only.
                  await db.supplierDao.deactivateSupplier(supplier.id);

                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('تم حذف المورد مع الاحتفاظ بالسجلات'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('خطأ: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: Text('حذف'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showPaymentDialog(Supplier supplier) async {
    final amountController = TextEditingController();
    final descriptionController = TextEditingController();

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('سداد دفعة لـ ${supplier.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountController,
                decoration: InputDecoration(
                  labelText: 'المبلغ',
                  border: const OutlineInputBorder(),
                  prefixText: 'ج.م',
                ),
                keyboardType: TextInputType.number,
              ),
              const Gap(16),
              TextField(
                controller: descriptionController,
                decoration: InputDecoration(
                  labelText: 'الوصف',
                  border: const OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (amountController.text.isNotEmpty) {
                  try {
                    // Add payment transaction: paying a supplier REDUCES what
                    // we owe, so it is a DEBIT (credit would increase the
                    // debt — the old code had this backwards and each
                    // payment grew the balance instead of shrinking it).
                    await db.ledgerDao.insertTransaction(
                      LedgerTransactionsCompanion.insert(
                        id: DateTime.now().millisecondsSinceEpoch.toString(),
                        entityType: 'Supplier',
                        refId: supplier.id,
                        date: DateTime.now(),
                        description: descriptionController.text.isNotEmpty
                            ? descriptionController.text
                            : 'سداد دفعة للمورد',
                        debit: Value(
                          double.tryParse(amountController.text) ?? 0.0,
                        ),
                        credit: const Value(0.0),
                        origin: 'payment',
                        paymentMethod: const Value('cash'),
                        createdAt: Value(DateTime.now()),
                      ),
                    );

                    if (dialogContext.mounted) {
                      Navigator.pop(dialogContext);
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        SnackBar(
                          content: Text('تم تسديد الدفعة بنجاح'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  } catch (e) {
                    if (dialogContext.mounted) {
                      Navigator.pop(dialogContext);
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        SnackBar(
                          content: Text('خطأ: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                }
              },
              child: Text('سداد'),
            ),
          ],
        );
      },
    );
  }

  void _exportSupplierReport(Supplier supplier) async {
    try {
      final exportService = ExportService();

      // Get supplier transactions
      final transactions = await db.ledgerDao.getTransactionsByEntity(
        'Supplier',
        supplier.id,
      );

      // Convert to data for export
      final data = transactions.map((transaction) {
        return {
          'التاريخ': DateFormat('yyyy/MM/dd HH:mm').format(transaction.date),
          'الوصف': transaction.description,
          'المبلغ': '${transaction.debit.toStringAsFixed(2)} ج.م',
          'النوع': transaction.debit > 0 ? 'مدين' : 'دائن',
          'طريقة الدفع': transaction.paymentMethod ?? 'غير محدد',
        };
      }).toList();

      await exportService.exportToPDF(
        title: 'كشف حساب مختصر - ${supplier.name}',
        data: data,
        headers: ['التاريخ', 'الوصف', 'المبلغ', 'النوع', 'طريقة الدفع'],
        columns: ['التاريخ', 'الوصف', 'المبلغ', 'النوع', 'طريقة الدفع'],
        fileName:
            'supplier_${supplier.id}_${DateTime.now().millisecondsSinceEpoch}.pdf',
      );

      // Check if context is still valid before using it
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم تصدير تقرير المورد بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      // Check if context is still valid before using it
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في التصدير: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

class _FinancialCard extends StatelessWidget {
  final String title;
  final double value;
  final Color color;

  const _FinancialCard({
    required this.title,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: color),
          ),
          const Gap(4),
          Text(
            '${value.toStringAsFixed(2)} ${AppLocalizations.of(context).currency}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
