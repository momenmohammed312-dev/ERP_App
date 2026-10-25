import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:intl/intl.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
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

class SuppliersWidget extends ConsumerWidget {
  final AppDatabase db;

  const SuppliersWidget({super.key, required this.db});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final statusFilter = ref.watch(supplierStatusFilterProvider);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Suppliers Summary - Use Flexible to prevent overflow
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16), // Reduced padding
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.suppliers_summary,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Gap(12), // Reduced gap
                  Row(
                    children: [
                      Expanded(
                        child: StreamBuilder<int>(
                          stream: db.supplierDao.watchSuppliersCount(),
                          builder: (context, snapshot) {
                            final count = snapshot.data ?? 0;
                            return _SupplierSummaryItem(
                              title: l10n.total_suppliers,
                              value: count.toString(),
                              icon: Icons.people,
                              color: Colors.blue,
                            );
                          },
                        ),
                      ),
                      const Gap(12), // Reduced gap
                      Expanded(
                        child: _SupplierSummaryItem(
                          title: l10n.outstanding_debt,
                          value: '0.00 ${l10n.currency}',
                          icon: Icons.money_off,
                          color: Colors.red,
                        ),
                      ),
                    ],
                  ),
                  const Gap(12), // Reduced gap
                  Row(
                    children: [
                      Expanded(
                        child: _SupplierSummaryItem(
                          title: l10n.paid_this_month,
                          value: '0.00 ${l10n.currency}',
                          icon: Icons.payment,
                          color: Colors.green,
                        ),
                      ),
                      const Gap(12), // Reduced gap
                      Expanded(
                        child: _SupplierSummaryItem(
                          title: l10n.active_suppliers,
                          value: '0',
                          icon: Icons.check_circle,
                          color: Colors.orange,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const Gap(16), // Reduced gap
          // Search and Actions - Use Flexible to prevent overflow
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    labelText: l10n.search_supplier_hint,
                    prefixIcon: const Icon(Icons.search),
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8, // Reduced vertical padding
                    ),
                  ),
                ),
              ),
              const Gap(12), // Reduced gap
              DropdownButton<String>(
                value: statusFilter,
                items: [
                  DropdownMenuItem(value: 'all', child: Text(l10n.all)),
                  DropdownMenuItem(value: 'active', child: Text(l10n.active)),
                  DropdownMenuItem(
                    value: 'inactive',
                    child: Text(l10n.inactive),
                  ),
                  DropdownMenuItem(value: 'debt', child: Text(l10n.has_debt)),
                ],
                onChanged: (value) {
                  if (value != null) {
                    ref.read(supplierStatusFilterProvider.notifier).state =
                        value;
                  }
                },
              ),
              const Gap(12), // Reduced gap
              ElevatedButton.icon(
                onPressed: () {
                  _showAddSupplierDialog(context);
                },
                icon: const Icon(Icons.add),
                label: Text(l10n.add_supplier),
              ),
            ],
          ),

          const Gap(16), // Reduced gap
          // Suppliers List - Use ConstrainedBox to limit height
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 600),
            child: StreamBuilder<List<Supplier>>(
              stream: statusFilter == 'debt'
                  ? db.supplierDao.watchSuppliersWithDebt()
                  : db.supplierDao.watchSuppliersByStatus(statusFilter),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return Center(
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
                  );
                }

                return ListView.builder(
                  shrinkWrap: true,
                  itemCount: snapshot.data!.length,
                  itemBuilder: (context, index) {
                    final supplier = snapshot.data![index];
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
        WHERE entity_type = 'Supplier' AND ref_id = ? AND (origin = 'payment' OR origin = 'reversal')
        ORDER BY date DESC
        LIMIT 30
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

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: Colors.purple.withValues(alpha: 0.1),
          child: Icon(Icons.business, color: Colors.purple),
        ),
        title: Text(
          supplier.name,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (supplier.phone != null)
              Text(
                supplier.phone ?? '',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
            const Gap(4),
            Text(
              '${AppLocalizations.of(context).last_purchase_colon} ${lastPurchaseDate.day}/${lastPurchaseDate.month}/${lastPurchaseDate.year}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${remainingDebt.toStringAsFixed(2)} ${AppLocalizations.of(context).currency}',
              style: TextStyle(
                color: remainingDebt > 0 ? Colors.red : Colors.green,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              remainingDebt > 0
                  ? AppLocalizations.of(context).debtor
                  : AppLocalizations.of(context).entitled,
              style: TextStyle(
                color: remainingDebt > 0 ? Colors.red : Colors.green,
                fontSize: 12,
              ),
            ),
          ],
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
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          await _showPaymentDialog(supplier);
                          if (context.mounted) {
                            (context as Element).markNeedsBuild();
                          }
                        },
                        icon: const Icon(Icons.payment),
                        label: Text(
                          AppLocalizations.of(context).settle_payment,
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                        ),
                      ),
                    ),
                    const Gap(16),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          _showEditSupplierDialog(supplier);
                        },
                        icon: const Icon(Icons.edit),
                        label: Text('تعديل'),
                      ),
                    ),
                    const Gap(16),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          _showDeleteSupplierDialog(supplier);
                        },
                        icon: const Icon(Icons.delete),
                        label: Text('حذف'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                        ),
                      ),
                    ),
                    const Gap(16),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          _exportSupplierReport(supplier);
                        },
                        icon: const Icon(Icons.picture_as_pdf),
                        label: Text(AppLocalizations.of(context).export),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
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
