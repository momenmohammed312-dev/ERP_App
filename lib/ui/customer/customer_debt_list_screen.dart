import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:pos_offline_desktop/core/config/app_features.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/services/customer_collection_service.dart';
import 'package:pos_offline_desktop/core/utils/arabic_name_normalizer.dart';
import 'package:pos_offline_desktop/ui/customer/customer_statement_screen.dart';
import 'package:pos_offline_desktop/ui/empty_barnika/empty_barnika_screen.dart';

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

        if (balance <= 0.005) continue;

        final hasDueToday = await _hasInvoicesDue(id, todayStart, todayEnd);
        final hasOverdue = await _hasOverdueInvoices(id, todayStart);
        final barnikaBalance = AppFeatures.hasEmptyContainerTracking
            ? await widget.db.emptyBarnikaTrackingDao
                .getCustomerOutstandingBalance(id)
            : 0;

        debts.add(
          _CustomerDebt(
            id: id,
            name: name,
            phone: phone,
            balance: balance,
            barnikaBalance: barnikaBalance,
            hasDueToday: hasDueToday,
            hasOverdue: hasOverdue,
          ),
        );
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

  Future<bool> _hasInvoicesDue(
    String customerId,
    DateTime start,
    DateTime end,
  ) async {
    final invoices = await widget.db.invoiceDao.getInvoicesByDateRange(start, end);
    return invoices.any(
      (inv) => inv.customerId == customerId && inv.paymentMethod == 'credit',
    );
  }

  Future<bool> _hasOverdueInvoices(String customerId, DateTime todayStart) async {
    final oldInvoices = await widget.db.invoiceDao.getInvoicesByDateRange(
      DateTime(2000),
      todayStart.subtract(const Duration(days: 1)),
    );
    return oldInvoices.any(
      (inv) => inv.customerId == customerId && inv.paymentMethod == 'credit',
    );
  }

  List<_CustomerDebt> get _filtered {
    var list = _debts
        .where(
          (d) => ArabicNameNormalizer.matchesQuery(
            candidate: d.name,
            query: _search,
            candidatePhone: d.phone,
          ),
        )
        .toList();
    if (_filter == DebtFilter.dueToday) {
      list = list.where((d) => d.hasDueToday).toList();
    } else if (_filter == DebtFilter.overdue) {
      list = list.where((d) => d.hasOverdue).toList();
    }
    return list;
  }

  Future<void> _recordPayment(_CustomerDebt debt) async {
    final dialogResult = await showDialog<_CollectDialogResult>(
      context: context,
      builder: (_) => _CollectPaymentDialog(debt: debt),
    );

    if (dialogResult == null || !mounted) {
      return;
    }

    final paidAmount = dialogResult.paidAmount;
    final discountAmount = dialogResult.discountAmount;
    final paymentMethod = dialogResult.paymentMethod;
    final notes = dialogResult.notes;

    try {
      final result = await CustomerCollectionService(widget.db).collectPayment(
        customerId: debt.id,
        paidAmount: paidAmount,
        discountAmount: discountAmount,
        paymentMethod: paymentMethod,
        notes: notes.isEmpty ? null : notes,
      );
      await _load();
      if (mounted) {
        final allocMsg = result.allocations.isNotEmpty
            ? ' (وُزّع FIFO على ${result.allocations.length} فواتير)'
            : '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تم تحصيل ${result.totalCredited.toStringAsFixed(2)} ج.م$allocMsg • المتبقي: ${result.newCustomerBalance.toStringAsFixed(2)} ج.م',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('مديونيات العملاء والتحصيل'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
            tooltip: 'تحديث',
          ),
          PopupMenuButton<DebtFilter>(
            initialValue: _filter,
            onSelected: (f) => setState(() => _filter = f),
            itemBuilder: (_) => const [
              PopupMenuItem(value: DebtFilter.all, child: Text('الكل')),
              PopupMenuItem(value: DebtFilter.dueToday, child: Text('مستحق اليوم')),
              PopupMenuItem(value: DebtFilter.overdue, child: Text('متأخر')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: TextField(
              decoration: InputDecoration(
                labelText: 'بحث ذكي بالاسم أو الهاتف',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                suffixIcon: _search.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() => _search = ''),
                      )
                    : null,
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_filtered.isEmpty)
            Expanded(
              child: Center(
                child: Text(
                  _filter == DebtFilter.all
                      ? 'لا توجد مديونيات'
                      : 'لا توجد نتائج للفلتر',
                  style: theme.textTheme.bodyLarge?.copyWith(color: Colors.grey),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                itemCount: _filtered.length,
                itemBuilder: (_, i) {
                  final d = _filtered[i];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () async {
                        final customer =
                            await widget.db.customerDao.getCustomerById(d.id);
                        if (customer != null && context.mounted) {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  CustomerStatementScreen(customer: customer),
                            ),
                          );
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: d.hasOverdue
                                  ? Colors.red.shade100
                                  : (d.hasDueToday
                                      ? Colors.orange.shade100
                                      : Colors.blue.shade100),
                              child: Icon(
                                d.hasOverdue
                                    ? Icons.warning
                                    : (d.hasDueToday
                                        ? Icons.today
                                        : Icons.person),
                                color: d.hasOverdue
                                    ? Colors.red
                                    : (d.hasDueToday
                                        ? Colors.orange
                                        : Colors.blue),
                              ),
                            ),
                            const Gap(12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    d.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                  if (d.phone != null && d.phone!.isNotEmpty)
                                    Text(
                                      d.phone!,
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  const Gap(4),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 4,
                                    children: [
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            d.hasOverdue
                                                ? Icons.warning
                                                : (d.hasDueToday
                                                    ? Icons.today
                                                    : Icons.check_circle),
                                            size: 14,
                                            color: d.hasOverdue
                                                ? Colors.red
                                                : (d.hasDueToday
                                                    ? Colors.orange
                                                    : Colors.green),
                                          ),
                                          const Gap(4),
                                          Flexible(
                                            child: Text(
                                              d.hasOverdue
                                                  ? 'متأخر'
                                                  : (d.hasDueToday
                                                      ? 'مستحق اليوم'
                                                      : 'عادي'),
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: d.hasOverdue
                                                    ? Colors.red
                                                    : (d.hasDueToday
                                                        ? Colors.orange
                                                        : Colors.green),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (d.barnikaBalance > 0)
                                        InkWell(
                                          onTap: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    EmptyBarnikaCustomerScreen(
                                                  db: widget.db,
                                                  customerId: d.id,
                                                  customerName: d.name,
                                                ),
                                              ),
                                            ).then((_) => _load());
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.orange.shade50,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              border: Border.all(
                                                color: Colors.orange.shade300,
                                              ),
                                            ),
                                            child: Text(
                                              'برانيك: ${d.barnikaBalance}',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.orange.shade900,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const Gap(8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '${d.balance.toStringAsFixed(2)} ج.م',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    color:
                                        d.balance > 0 ? Colors.red : Colors.green,
                                  ),
                                ),
                                const Gap(6),
                                ElevatedButton(
                                  onPressed: () => _recordPayment(d),
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 6,
                                    ),
                                    backgroundColor: Colors.teal,
                                    foregroundColor: Colors.white,
                                  ),
                                  child: const Text(
                                    'تحصيل',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
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
  final int barnikaBalance;
  final bool hasDueToday;
  final bool hasOverdue;

  const _CustomerDebt({
    required this.id,
    required this.name,
    required this.phone,
    required this.balance,
    this.barnikaBalance = 0,
    required this.hasDueToday,
    required this.hasOverdue,
  });
}

class _CollectDialogResult {
  final double paidAmount;
  final double discountAmount;
  final String paymentMethod;
  final String notes;

  const _CollectDialogResult({
    required this.paidAmount,
    required this.discountAmount,
    required this.paymentMethod,
    required this.notes,
  });
}

class _CollectPaymentDialog extends StatefulWidget {
  final _CustomerDebt debt;

  const _CollectPaymentDialog({required this.debt});

  @override
  State<_CollectPaymentDialog> createState() => _CollectPaymentDialogState();
}

class _CollectPaymentDialogState extends State<_CollectPaymentDialog> {
  final _paidCtrl = TextEditingController();
  final _discountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  String _paymentMethod = 'cash';

  @override
  void dispose() {
    _paidCtrl.dispose();
    _discountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('تحصيل من العميل: ${widget.debt.name}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'المديونية الحالية: ${widget.debt.balance.toStringAsFixed(2)} ج.م',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const Gap(12),
            TextFormField(
              controller: _paidCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'المبلغ المحصّل',
                prefixText: 'ج.م ',
                border: OutlineInputBorder(),
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            const Gap(10),
            TextFormField(
              controller: _discountCtrl,
              decoration: const InputDecoration(
                labelText: 'خصم عند التحصيل (اختياري)',
                prefixText: 'ج.م ',
                border: OutlineInputBorder(),
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            const Gap(10),
            DropdownButtonFormField<String>(
              initialValue: _paymentMethod,
              decoration: const InputDecoration(
                labelText: 'طريقة التحصيل',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'cash', child: Text('نقدي (كاش)')),
                DropdownMenuItem(value: 'bank', child: Text('تحويل بنكي')),
                DropdownMenuItem(value: 'card', child: Text('بطاقة')),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _paymentMethod = v);
              },
            ),
            const Gap(10),
            TextField(
              controller: _noteCtrl,
              decoration: const InputDecoration(
                labelText: 'ملاحظة (اختياري)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          onPressed: () {
            final paid = double.tryParse(_paidCtrl.text.trim()) ?? 0.0;
            final disc = double.tryParse(_discountCtrl.text.trim()) ?? 0.0;
            if (paid < 0 || disc < 0 || (paid + disc) <= 0) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('أدخل مبلغ تحصيل أو خصم أكبر من صفر'),
                  backgroundColor: Colors.orange,
                ),
              );
              return;
            }
            Navigator.pop(
              context,
              _CollectDialogResult(
                paidAmount: paid,
                discountAmount: disc,
                paymentMethod: _paymentMethod,
                notes: _noteCtrl.text.trim(),
              ),
            );
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.teal,
            foregroundColor: Colors.white,
          ),
          child: const Text('تأكيد التحصيل'),
        ),
      ],
    );
  }
}