import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import 'package:drift/drift.dart' hide Column;

import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/ui/customer/customer_statement_screen.dart';

enum DebtFilter { all, dueToday, overdue }

class CustomerDebtListScreen extends StatefulWidget {
  final AppDatabase db;

  const CustomerDebtListScreen({super.key, required this.db});

  @override
  State<CustomerDebtListScreen> createState() => _CustomerDebtListScreenState();
}

class _CustomerDebtListScreenState extends State<CustomerDebtListScreen> {
  DebtFilter _filter = DebtFilter.all;
  String _search = '';
  bool _loading = true;
  List<_CustomerDebt> _debts = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final balances = await widget.db.ledgerDao.getAllCustomerBalances();
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final todayEnd = todayStart.add(const Duration(days: 1));

      final debts = <_CustomerDebt>[];
      for (final row in balances) {
        final id = row['id'] as String;
        final name = row['name'] as String;
        final phone = row['phone'] as String?;
        final balance = (row['balance'] as num?)?.toDouble() ?? 0.0;

        if (balance <= 0) continue; // only show debtors

        // Check if has due today / overdue invoices
        final hasDueToday = await _hasInvoicesDue(id, todayStart, todayEnd);
        final hasOverdue = await _hasOverdueInvoices(id, todayStart);

        debts.add(_CustomerDebt(
          id: id,
          name: name,
          phone: phone,
          balance: balance,
          hasDueToday: hasDueToday,
          hasOverdue: hasOverdue,
        ));
      }

      if (mounted) {
        setState(() {
          _debts = debts;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _hasInvoicesDue(String customerId, DateTime start, DateTime end) async {
    final invoices = await widget.db.invoiceDao.getInvoicesByDateRange(start, end);
    return invoices.any((inv) => inv.customerId == customerId && inv.paymentMethod == 'credit');
  }

  Future<bool> _hasOverdueInvoices(String customerId, DateTime todayStart) async {
    final oldInvoices = await widget.db.invoiceDao.getInvoicesByDateRange(
      DateTime(2000), todayStart.subtract(const Duration(days: 1)));
    return oldInvoices.any((inv) => inv.customerId == customerId && inv.paymentMethod == 'credit');
  }

  List<_CustomerDebt> get _filtered {
    var list = _debts.where((d) => d.name.toLowerCase().contains(_search.toLowerCase())).toList();
    if (_filter == DebtFilter.dueToday) {
      list = list.where((d) => d.hasDueToday).toList();
    } else if (_filter == DebtFilter.overdue) {
      list = list.where((d) => d.hasOverdue).toList();
    }
    return list;
  }

  Future<void> _recordPayment(_CustomerDebt debt) async {
    final ctrl = TextEditingController();
    final noteCtrl = TextEditingController();
    final amount = await showDialog<double>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('سداد للعميل: ${debt.name}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('المديونية الحالية: ${debt.balance.toStringAsFixed(2)} ج.م'),
          const Gap(12),
          TextField(controller: ctrl, decoration: const InputDecoration(labelText: 'المبلغ', prefixText: 'ج.م ', border: OutlineInputBorder()), keyboardType: TextInputType.number),
          const Gap(12),
          TextField(controller: noteCtrl, decoration: const InputDecoration(labelText: 'ملاحظة', border: OutlineInputBorder())),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
          ElevatedButton(onPressed: () {
            final amt = double.tryParse(ctrl.text);
            if (amt == null || amt <= 0) return;
            Navigator.pop(context, amt);
          }, child: const Text('تأكيد')),
        ],
      ),
    );
    if (amount == null || amount <= 0 || !mounted) return;
    try {
      await widget.db.ledgerDao.insertTransaction(
        LedgerTransactionsCompanion.insert(
          id: '${DateTime.now().millisecondsSinceEpoch}_pay_${debt.id}',
          entityType: 'Customer',
          refId: debt.id,
          date: DateTime.now(),
          description: noteCtrl.text.isNotEmpty ? noteCtrl.text : 'سداد آجل',
          debit: const Value(0.0),
          credit: Value(amount),
          origin: 'payment',
          paymentMethod: Value('cash'),
        ),
      );
      _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تسجيل السداد'), backgroundColor: Colors.green));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('مديونيات العملاء'),
        actions: [
          PopupMenuButton<DebtFilter>(
            initialValue: _filter,
            onSelected: (f) => setState(() => _filter = f),
            itemBuilder: (_) => [
              const PopupMenuItem(value: DebtFilter.all, child: Text('الكل')),
              const PopupMenuItem(value: DebtFilter.dueToday, child: Text('مستحق اليوم')),
              const PopupMenuItem(value: DebtFilter.overdue, child: Text('متأخر')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: InputDecoration(
                labelText: 'بحث بالاسم/الهاتف',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                suffixIcon: _search.isNotEmpty ? IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() => _search = '')) : null,
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_filtered.isEmpty)
            Expanded(child: Center(child: Text(_filter == DebtFilter.all ? 'لا توجد مديونيات' : 'لا توجد نتائج للفلتر', style: theme.textTheme.bodyLarge?.copyWith(color: Colors.grey))))
          else
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: _filtered.length,
                itemBuilder: (_, i) {
                  final d = _filtered[i];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: d.hasOverdue ? Colors.red.shade100 : (d.hasDueToday ? Colors.orange.shade100 : Colors.blue.shade100),
                        child: Icon(d.hasOverdue ? Icons.warning : (d.hasDueToday ? Icons.today : Icons.person), color: d.hasOverdue ? Colors.red : (d.hasDueToday ? Colors.orange : Colors.blue)),
                      ),
                      title: Text(d.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (d.phone != null) Text(d.phone!, style: const TextStyle(fontSize: 12)),
                          Row(
                            children: [
                              Icon(d.hasOverdue ? Icons.warning : (d.hasDueToday ? Icons.today : Icons.check_circle), size: 14, color: d.hasOverdue ? Colors.red : (d.hasDueToday ? Colors.orange : Colors.green)),
                              const Gap(4),
                              Text(
                                d.hasOverdue ? 'متأخر' : (d.hasDueToday ? 'مستحق اليوم' : 'عادي'),
                                style: TextStyle(fontSize: 12, color: d.hasOverdue ? Colors.red : (d.hasDueToday ? Colors.orange : Colors.green)),
                              ),
                            ],
                          ),
                        ],
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('${d.balance.toStringAsFixed(2)} ج.م', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: d.balance > 0 ? Colors.red : Colors.green)),
                          const Gap(4),
                          SizedBox(
                            width: 100,
                            child: ElevatedButton(
                              onPressed: () => _recordPayment(d),
                              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 6), backgroundColor: Colors.teal, foregroundColor: Colors.white),
                              child: const Text('سداد', style: TextStyle(fontSize: 12)),
                            ),
                          ),
                        ],
                      ),
                      onTap: () async {
                        final customer = await widget.db.customerDao.getCustomerById(d.id);
                        if (customer != null && mounted) {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerStatementScreen(customer: customer)));
                        }
                      },
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _CustomerDebt {
  final String id;
  final String name;
  final String? phone;
  final double balance;
  final bool hasDueToday;
  final bool hasOverdue;

  const _CustomerDebt({required this.id, required this.name, required this.phone, required this.balance, required this.hasDueToday, required this.hasOverdue});
}