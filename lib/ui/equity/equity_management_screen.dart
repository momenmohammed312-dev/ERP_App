import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/services/equity_service.dart';

class EquityManagementScreen extends StatefulWidget {
  final AppDatabase db;
  const EquityManagementScreen({super.key, required this.db});

  @override
  State<EquityManagementScreen> createState() => _EquityManagementScreenState();
}

class _EquityManagementScreenState extends State<EquityManagementScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('إدارة رأس المال والشركاء'),
          bottom: const TabBar(tabs: [
            Tab(icon: Icon(Icons.people), text: 'الشركاء'),
            Tab(icon: Icon(Icons.account_balance_wallet), text: 'الحركات'),
          ]),
        ),
        body: TabBarView(
          children: [
            _PartnersTab(db: widget.db),
            _EquityTransactionsTab(db: widget.db),
          ],
        ),
      ),
    );
  }
}

class _PartnersTab extends StatefulWidget {
  final AppDatabase db;
  const _PartnersTab({required this.db});
  @override
  State<_PartnersTab> createState() => _PartnersTabState();
}

class _PartnersTabState extends State<_PartnersTab> {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _addPartner,
              icon: const Icon(Icons.person_add),
              label: const Text('إضافة شريك'),
            ),
          ),
        ),
        Expanded(
          child: StreamBuilder<List<Partner>>(
            stream: widget.db.equityDao.watchAllPartners(),
            builder: (context, snap) {
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final partners = snap.data!;
              if (partners.isEmpty) {
                return Center(child: Text('لا يوجد شركاء — أضف شريكاً للبدء', style: TextStyle(color: Colors.grey.shade600)));
              }
              return ListView.builder(
                itemCount: partners.length,
                itemBuilder: (context, i) {
                  final p = partners[i];
                  return FutureBuilder<double>(
                    future: widget.db.equityDao.getPartnerBalance(p.id),
                    builder: (context, balSnap) {
                      final bal = balSnap.data ?? 0;
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        child: ListTile(
                          leading: CircleAvatar(child: Text(p.name[0].toUpperCase())),
                          title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(p.phone ?? '—'),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('${bal.toStringAsFixed(2)} ج.م', style: TextStyle(fontWeight: FontWeight.bold, color: bal >= 0 ? Colors.green : Colors.red)),
                              Text(p.isActive ? 'نشط' : 'غير نشط', style: const TextStyle(fontSize: 11)),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _addPartner() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final res = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('إضافة شريك'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'اسم الشريك *', border: OutlineInputBorder())),
            const Gap(12),
            TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: 'هاتف', border: OutlineInputBorder())),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(
            onPressed: () {
              if (nameCtrl.text.trim().isEmpty) return;
              Navigator.pop(c, true);
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    if (res == true && nameCtrl.text.trim().isNotEmpty) {
      await EquityService(widget.db).createPartner(name: nameCtrl.text.trim(), phone: phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim());
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تمت إضافة الشريك')));
    }
  }
}

class _EquityTransactionsTab extends StatefulWidget {
  final AppDatabase db;
  const _EquityTransactionsTab({required this.db});
  @override
  State<_EquityTransactionsTab> createState() => _EquityTransactionsTabState();
}

class _EquityTransactionsTabState extends State<_EquityTransactionsTab> {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              FilledButton.icon(onPressed: () => _addTransaction('capital_contribution'), icon: const Icon(Icons.add), label: const Text('مساهمة')),
              const Gap(8),
              FilledButton.icon(onPressed: () => _addTransaction('withdrawal'), icon: const Icon(Icons.remove), label: const Text('مسحوبات'), style: FilledButton.styleFrom(backgroundColor: Colors.orange)),
              const Gap(8),
              OutlinedButton.icon(onPressed: () => _addTransaction('profit_allocation'), icon: const Icon(Icons.pie_chart), label: const Text('توزيع ربح (يدوي)')),
              const Spacer(),
              FutureBuilder<double>(
                future: widget.db.equityDao.getTotalEquity(),
                builder: (context, snap) => Text('إجمالي حقوق الملكية: ${(snap.data ?? 0).toStringAsFixed(2)} ج.م', style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<List<EquityTransaction>>(
            stream: widget.db.equityDao.watchAllEquityTransactions(),
            builder: (context, snap) {
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final txs = snap.data!;
              if (txs.isEmpty) return Center(child: Text('لا توجد حركات رأس مال', style: TextStyle(color: Colors.grey.shade600)));
              return ListView.builder(
                itemCount: txs.length,
                itemBuilder: (context, i) {
                  final t = txs[i];
                  Color color;
                  IconData icon;
                  switch (t.type) {
                    case 'opening_capital':
                    case 'capital_contribution':
                      color = Colors.green;
                      icon = Icons.arrow_downward;
                      break;
                    case 'withdrawal':
                      color = Colors.red;
                      icon = Icons.arrow_upward;
                      break;
                    case 'profit_allocation':
                      color = Colors.blue;
                      icon = Icons.pie_chart;
                      break;
                    default:
                      color = Colors.grey;
                      icon = Icons.circle;
                  }
                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: ListTile(
                      leading: CircleAvatar(backgroundColor: color.withValues(alpha: 0.15), child: Icon(icon, color: color, size: 18)),
                      title: Text(t.description ?? t.type, style: const TextStyle(fontSize: 13)),
                      subtitle: Text(DateFormat('yyyy/MM/dd HH:mm').format(t.date), style: const TextStyle(fontSize: 11)),
                      trailing: Text('${t.amount.toStringAsFixed(2)} ج.م', style: TextStyle(fontWeight: FontWeight.bold, color: color)),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _addTransaction(String type) async {
    final partners = await widget.db.equityDao.getActivePartners();
    if (partners.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أضف شريكاً أولاً')));
      return;
    }
    String? selectedPartnerId = partners.first.id;
    final amountCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String paymentMethod = 'cash';
    DateTime date = DateTime.now();

    final res = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(type == 'capital_contribution' ? 'مساهمة رأس مال' : type == 'withdrawal' ? 'مسحوبات' : 'توزيع ربح يدوي'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedPartnerId,
                  decoration: const InputDecoration(labelText: 'الشريك', border: OutlineInputBorder()),
                  items: partners.map((p) => DropdownMenuItem(value: p.id, child: Text(p.name))).toList(),
                  onChanged: (v) => setState(() => selectedPartnerId = v),
                ),
                const Gap(12),
                TextField(controller: amountCtrl, decoration: const InputDecoration(labelText: 'المبلغ *', border: OutlineInputBorder(), prefixText: 'ج.م '), keyboardType: const TextInputType.numberWithOptions(decimal: true)),
                const Gap(12),
                if (type != 'profit_allocation')
                  DropdownButtonFormField<String>(
                    initialValue: paymentMethod,
                    decoration: const InputDecoration(labelText: 'طريقة الدفع', border: OutlineInputBorder()),
                    items: const [DropdownMenuItem(value: 'cash', child: Text('نقدي')), DropdownMenuItem(value: 'bank', child: Text('بنك'))],
                    onChanged: (v) => setState(() => paymentMethod = v!),
                  ),
                if (type != 'profit_allocation') const Gap(12),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(context: ctx, initialDate: date, firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 365)));
                    if (picked != null) setState(() => date = DateTime(picked.year, picked.month, picked.day, date.hour, date.minute));
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'التاريخ', border: OutlineInputBorder()),
                    child: Text(DateFormat('yyyy/MM/dd').format(date)),
                  ),
                ),
                const Gap(12),
                TextField(controller: descCtrl, decoration: const InputDecoration(labelText: 'البيان', border: OutlineInputBorder())),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('حفظ')),
          ],
        ),
      ),
    );
    if (res != true) return;
    final amount = double.tryParse(amountCtrl.text.trim());
    if (amount == null || amount <= 0) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('مبلغ غير صحيح')));
      return;
    }
    try {
      final svc = EquityService(widget.db);
      switch (type) {
        case 'capital_contribution':
          await svc.recordCapitalContribution(partnerId: selectedPartnerId!, amount: amount, date: date, description: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(), paymentMethod: paymentMethod);
          break;
        case 'withdrawal':
          await svc.recordWithdrawal(partnerId: selectedPartnerId!, amount: amount, date: date, description: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(), paymentMethod: paymentMethod);
          break;
        case 'profit_allocation':
          await svc.recordProfitAllocation(partnerId: selectedPartnerId!, amount: amount, date: date, description: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim());
          break;
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ الحركة'), backgroundColor: Colors.green));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red));
    }
  }
}
