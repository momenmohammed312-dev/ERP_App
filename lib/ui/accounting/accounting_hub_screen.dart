import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/models/user_model.dart';
import 'package:pos_offline_desktop/core/provider/auth_provider.dart';
import 'package:pos_offline_desktop/core/services/validation/permission_validator.dart';
import 'package:pos_offline_desktop/ui/reports/financial/balance_sheet_screen.dart';
import 'package:pos_offline_desktop/ui/reports/financial/profit_loss_screen.dart';
import 'package:pos_offline_desktop/ui/reports/financial/equity_statement_screen.dart';
import 'package:pos_offline_desktop/ui/reports/financial/general_ledger_screen.dart';
import 'package:pos_offline_desktop/ui/equity/equity_management_screen.dart';
import 'package:pos_offline_desktop/ui/analytics/consolidated_accounts_screen.dart';
import 'package:pos_offline_desktop/ui/accounting/opening_balance_screen.dart';

class AccountingHubScreen extends ConsumerStatefulWidget {
  final AppDatabase db;
  const AccountingHubScreen({super.key, required this.db});

  @override
  ConsumerState<AccountingHubScreen> createState() => _AccountingHubScreenState();
}

class _AccountingHubScreenState extends ConsumerState<AccountingHubScreen> {
  bool _hasAccess = false;
  bool _checking = true;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final user = ref.read(authProvider);
    if (user == null) {
      setState(() { _hasAccess = true; _checking = false; });
      return;
    }
    try {
      PermissionValidator.requirePermission(user, Permission.viewFinancialReports, 'المركز المحاسبي');
      setState(() { _hasAccess = true; _checking = false; });
    } catch (_) {
      setState(() { _hasAccess = false; _checking = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_checking) {
      return Scaffold(appBar: AppBar(title: const Text('المركز المحاسبي')), body: const Center(child: CircularProgressIndicator()));
    }
    if (!_hasAccess) {
      return Scaffold(
        appBar: AppBar(title: const Text('المركز المحاسبي')),
        body: Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.lock, size: 64, color: Colors.grey.shade400),
            const Gap(16),
            const Text('ليس لديك صلاحية عرض التقارير المالية', style: TextStyle(fontSize: 16)),
            const Gap(8),
            Text('مطلوب صلاحية: عرض التقارير المالية (محاسب/مدير)', style: TextStyle(color: Colors.grey.shade600)),
          ]),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('المركز المحاسبي — كل التفاصيل في مكان واحد')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Quick stats
            _QuickStats(db: widget.db),
            const Gap(12),
            // Prominent opening balance banner
            Material(
              color: Colors.teal.shade50,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => OpeningBalanceScreen(db: widget.db)),
                ),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.teal, width: 1.2),
                  ),
                  child: Row(children: [
                    Icon(Icons.playlist_add_check_circle, color: Colors.teal.shade700, size: 30),
                    const Gap(12),
                    const Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('إدخال الرصيد الافتتاحي', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.teal)),
                        Gap(2),
                        Text('سجّل أرصدة أول المدة للأصول والخصوم ورأس المال', style: TextStyle(fontSize: 12, color: Colors.teal)),
                      ]),
                    ),
                    Icon(Icons.chevron_left, color: Colors.teal.shade700),
                  ]),
                ),
              ),
            ),
            const Gap(20),
            Text('الحسابات واليومية', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const Gap(12),
            Row(children: [
              Expanded(child: _HubCard(icon: Icons.account_tree, color: Colors.teal, title: 'دليل الحسابات', subtitle: '12 حساب نظام + أرصدة حية', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _ChartOfAccountsScreen(db: widget.db))))),
              const Gap(12),
              Expanded(child: _HubCard(icon: Icons.menu_book, color: Colors.brown, title: 'دفتر الأستاذ العام', subtitle: 'حركة كل حساب بالتفصيل', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GeneralLedgerScreen(db: widget.db))))),
            ]),
            const Gap(12),
            Row(children: [
              Expanded(child: _HubCard(icon: Icons.receipt_long, color: Colors.indigo, title: 'دفتر اليومية', subtitle: 'كل القيود المحاسبية', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _JournalScreen(db: widget.db))))),
              const Gap(12),
              Expanded(child: _HubCard(icon: Icons.account_balance_wallet, color: Colors.blue, title: 'الأرصدة الموحدة', subtitle: 'عملاء + موردين', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ConsolidatedAccountsScreen())))),
            ]),
            const Gap(20),
            Text('القوائم المالية', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const Gap(12),
            Row(children: [
              Expanded(child: _HubCard(icon: Icons.balance, color: Colors.teal, title: 'الميزانية العمومية', subtitle: 'أصول = خصوم + حقوق', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BalanceSheetScreen(db: widget.db))))),
              const Gap(12),
              Expanded(child: _HubCard(icon: Icons.trending_up, color: Colors.green, title: 'الأرباح والخسائر', subtitle: 'إيراد - تكلفة - مصروف', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProfitLossScreen(db: widget.db))))),
            ]),
            const Gap(12),
            Row(children: [
              Expanded(child: _HubCard(icon: Icons.pie_chart, color: Colors.purple, title: 'كشف حقوق الملكية', subtitle: 'لكل شريك', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EquityStatementScreen(db: widget.db))))),
              const Gap(12),
              Expanded(child: _HubCard(icon: Icons.people, color: Colors.green.shade700, title: 'رأس المال والشركاء', subtitle: 'مساهمات/مسحوبات', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EquityManagementScreen(db: widget.db))))),
            ]),
            const Gap(20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                Icon(Icons.info_outline, color: theme.colorScheme.primary, size: 18),
                const Gap(8),
                Expanded(child: Text('كل القيود تُنشأ تلقائياً من المبيعات/المشتريات/المصروفات/المرتجعات داخل نفس الـ transaction — لا إدخال يدوي مطلوب.', style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.7)))),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _HubCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _HubCard({required this.icon, required this.color, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.2)), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2))]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color, size: 28),
          const Gap(10),
          Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 14)),
          const Gap(4),
          Text(subtitle, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
        ]),
      ),
    );
  }
}

class _QuickStats extends ConsumerWidget {
  final AppDatabase db;
  const _QuickStats({required this.db});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<List<Account>>(
      future: db.accountsDao.getAllAccounts(),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox(height: 60, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
        final accounts = snap.data!;
        return FutureBuilder<List<double>>(
          future: Future.wait(accounts.map((a) async {
            final raw = await db.journalDao.getAccountBalance(a.id);
            return a.normalBalance == 'credit' ? -raw : raw;
          })),
          builder: (context, balSnap) {
            if (!balSnap.hasData) return const SizedBox(height: 40, child: LinearProgressIndicator());
            final balances = balSnap.data!;
            double assets = 0, liab = 0, equity = 0, revenue = 0, expenses = 0;
            for (var i = 0; i < accounts.length; i++) {
              final a = accounts[i];
              final b = balances[i];
              if (a.type == 'asset') assets += b;
              if (a.type == 'liability') liab += b;
              if (a.type == 'equity') equity += b;
              if (a.type == 'revenue') revenue += b;
              if (a.type == 'expense') expenses += b;
            }
            return Row(
              children: [
                Expanded(child: _StatChip(label: 'أصول', value: assets, color: Colors.teal)),
                const Gap(8),
                Expanded(child: _StatChip(label: 'خصوم', value: liab, color: Colors.orange)),
                const Gap(8),
                Expanded(child: _StatChip(label: 'حقوق', value: equity, color: Colors.blue)),
                const Gap(8),
                Expanded(child: _StatChip(label: 'صافي ربح', value: revenue - expenses, color: (revenue - expenses) >= 0 ? Colors.green : Colors.red)),
              ],
            );
          },
        );
      },
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  const _StatChip({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withValues(alpha: 0.3))),
      child: Column(children: [
        Text(label, style: TextStyle(fontSize: 11, color: color)),
        const Gap(4),
        Text(value.toStringAsFixed(2), style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 13)),
      ]),
    );
  }
}

class _ChartOfAccountsScreen extends StatelessWidget {
  final AppDatabase db;
  const _ChartOfAccountsScreen({required this.db});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('دليل الحسابات')),
      body: FutureBuilder<List<Account>>(
        future: db.accountsDao.getAllAccounts(),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final accounts = snap.data!..sort((a, b) => a.code.compareTo(b.code));
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: accounts.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final a = accounts[i];
              Color typeColor;
              switch (a.type) {
                case 'asset':
                  typeColor = Colors.teal;
                  break;
                case 'liability':
                  typeColor = Colors.orange;
                  break;
                case 'equity':
                  typeColor = Colors.blue;
                  break;
                case 'revenue':
                  typeColor = Colors.green;
                  break;
                case 'expense':
                  typeColor = Colors.red;
                  break;
                default:
                  typeColor = Colors.grey;
              }
              return FutureBuilder<double>(
                future: db.journalDao.getAccountBalance(a.id).then((raw) => a.normalBalance == 'credit' ? -raw : raw),
                builder: (context, balSnap) {
                  final bal = balSnap.data ?? 0;
                  return ListTile(
                    leading: CircleAvatar(backgroundColor: typeColor.withValues(alpha: 0.15), child: Text(a.code, style: TextStyle(color: typeColor, fontSize: 10, fontWeight: FontWeight.bold))),
                    title: Text(a.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    subtitle: Text('${a.type} • ${a.normalBalance} • ${a.isSystem ? 'نظام' : 'مخصص'}', style: const TextStyle(fontSize: 11)),
                    trailing: Text(bal.toStringAsFixed(2), style: TextStyle(fontWeight: FontWeight.bold, color: typeColor)),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _AccountLedgerScreen(db: db, account: a))),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _AccountLedgerScreen extends StatelessWidget {
  final AppDatabase db;
  final Account account;
  const _AccountLedgerScreen({required this.db, required this.account});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${account.code} - ${account.name}')),
      body: FutureBuilder<List<JournalLine>>(
        future: db.journalDao.getLinesForAccount(account.id),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final lines = snap.data!;
          if (lines.isEmpty) return const Center(child: Text('لا توجد حركات'));
          return ListView.builder(
            itemCount: lines.length,
            itemBuilder: (context, i) {
              final l = lines[i];
              return FutureBuilder<JournalEntry?>(
                future: db.journalDao.getById(l.journalEntryId),
                builder: (context, eSnap) {
                  final e = eSnap.data;
                  return ListTile(
                    title: Text(e?.description ?? '-', style: const TextStyle(fontSize: 13)),
                    subtitle: Text(e != null ? '${e.date.toString().split(' ')[0]} • ${e.sourceType}' : '', style: const TextStyle(fontSize: 11)),
                    trailing: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text(l.debit > 0 ? l.debit.toStringAsFixed(2) : '-', style: const TextStyle(color: Colors.green)),
                      Text(l.credit > 0 ? l.credit.toStringAsFixed(2) : '-', style: const TextStyle(color: Colors.red)),
                    ]),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _JournalScreen extends StatelessWidget {
  final AppDatabase db;
  const _JournalScreen({required this.db});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('دفتر اليومية')),
      body: StreamBuilder<List<JournalEntry>>(
        stream: db.journalDao.watchAllEntries(),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final entries = snap.data!;
          if (entries.isEmpty) return const Center(child: Text('لا توجد قيود'));
          return ListView.builder(
            itemCount: entries.length,
            itemBuilder: (context, i) {
              final e = entries[i];
              return FutureBuilder<List<JournalLine>>(
                future: db.journalDao.getLinesForEntry(e.id),
                builder: (context, lineSnap) {
                  final lines = lineSnap.data ?? [];
                  final totalDebit = lines.fold<double>(0, (s, l) => s + l.debit);
                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: ExpansionTile(
                      title: Text(e.description, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                      subtitle: Text('${e.postingKey} • ${e.date.toString().split(' ')[0]} • ${e.status}', style: const TextStyle(fontSize: 11)),
                      trailing: Text(totalDebit.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.bold)),
                      children: lines
                          .map((l) => FutureBuilder<Account?>(
                                future: db.accountsDao.getById(l.accountId),
                                builder: (context, aSnap) => ListTile(
                                  dense: true,
                                  title: Text(aSnap.data != null ? '${aSnap.data!.code} - ${aSnap.data!.name}' : l.accountId, style: const TextStyle(fontSize: 12)),
                                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                    Text(l.debit > 0 ? l.debit.toStringAsFixed(2) : '-', style: const TextStyle(color: Colors.green, fontSize: 12)),
                                    const Gap(12),
                                    Text(l.credit > 0 ? l.credit.toStringAsFixed(2) : '-', style: const TextStyle(color: Colors.red, fontSize: 12)),
                                  ]),
                                ),
                              ))
                          .toList(),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
