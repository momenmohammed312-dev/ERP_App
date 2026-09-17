import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:drift/drift.dart' as drift;
import 'package:uuid/uuid.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/provider/auth_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// شاشة إدخال الرصيد الافتتاحي لأرصدة أول المدة.
/// تسمح بإدخال رصيد افتتاحي لكل حساب أصل/التزام/حقوق،
/// وعند الحفظ تنشئ قيداً محاسبياً متوازناً (مدين الأصول / دائن الخصوم والحقوق).
/// الفرق يتم توازينه تلقائياً عبر حساب رأس المال (3000).
class OpeningBalanceScreen extends ConsumerStatefulWidget {
  final AppDatabase db;
  const OpeningBalanceScreen({super.key, required this.db});

  @override
  ConsumerState<OpeningBalanceScreen> createState() => _OpeningBalanceScreenState();
}

class _OpeningBalanceScreenState extends ConsumerState<OpeningBalanceScreen> {
  final Map<String, TextEditingController> _controllers = {};
  bool _isLoading = true;
  bool _saving = false;
  List<Account> _accounts = [];
  String? _capitalAccountId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final all = await widget.db.accountsDao.getAllAccounts();
      final capital = await widget.db.accountsDao.getByCode('3000');
      setState(() {
        _accounts = all
            .where((a) => a.type == 'asset' || a.type == 'liability' || a.type == 'equity')
            .toList()
          ..sort((a, b) => a.code.compareTo(b.code));
        _capitalAccountId = capital?.id;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  double _parse(String? text) => double.tryParse((text ?? '').trim()) ?? 0;

  Future<void> _save() async {
    // الأصول = مدين (debit) ، الخصوم والحقوق = دائن (credit)
    double assetsDr = 0;
    double liabEqCr = 0;
    final lines = <JournalLinesCompanion>[];
    final uid = const Uuid();

    for (final a in _accounts) {
      final val = _parse(_controllers[a.id]?.text);
      if (val <= 0) continue;
      if (a.type == 'asset') {
        assetsDr += val;
        lines.add(JournalLinesCompanion.insert(
          id: uid.v4(),
          journalEntryId: '',
          accountId: a.id,
          debit: drift.Value(val),
          credit: const drift.Value(0),
          memo: const drift.Value('رصيد افتتاحي'),
        ));
      } else {
        liabEqCr += val;
        lines.add(JournalLinesCompanion.insert(
          id: uid.v4(),
          journalEntryId: '',
          accountId: a.id,
          debit: const drift.Value(0),
          credit: drift.Value(val),
          memo: const drift.Value('رصيد افتتاحي'),
        ));
      }
    }

    final total = assetsDr + liabEqCr;
    if (total <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل رصيداً افتتاحياً واحداً على الأقل'), backgroundColor: Colors.orange),
      );
      return;
    }

    // فرق التوازن يُحسم عبر حساب رأس المال (3000)
    final delta = assetsDr - liabEqCr;
    if (delta > 0) {
      // مدين (أصول) أكثر من دائن → نحتاج دائن إضافي لرأس المال
      lines.add(JournalLinesCompanion.insert(
        id: uid.v4(),
        journalEntryId: '',
        accountId: _capitalAccountId!,
        debit: const drift.Value(0),
        credit: drift.Value(delta),
        memo: const drift.Value('رصيد افتتاحي (فرق التوازن)'),
      ));
    } else if (delta < 0) {
      // دائن أكثر → مدين إضافي لرأس المال
      lines.add(JournalLinesCompanion.insert(
        id: uid.v4(),
        journalEntryId: '',
        accountId: _capitalAccountId!,
        debit: drift.Value(-delta),
        credit: const drift.Value(0),
        memo: const drift.Value('رصيد افتتاحي (فرق التوازن)'),
      ));
    }

    setState(() => _saving = true);
    try {
      final user = ref.read(authProvider);
      final createdBy = user?.username ?? user?.email ?? 'admin';
      final postingKey = 'opening_balance:${const Uuid().v4()}';
      await widget.db.transaction(() async {
        await widget.db.journalDao.insertBalancedEntry(
          postingKey: postingKey,
          date: DateTime.now(),
          description: 'رصيد افتتاحي (أرصدة أول المدة)',
          sourceType: 'opening_balance',
          sourceId: postingKey,
          lines: lines,
          createdBy: createdBy,
        );
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تسجيل الرصيد الافتتاحي بقيد متوازن'), backgroundColor: Colors.green),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل الحفظ: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'asset':
        return Colors.teal;
      case 'liability':
        return Colors.orange;
      case 'equity':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'asset':
        return 'أصل';
      case 'liability':
        return 'التزام';
      case 'equity':
        return 'حقوق ملكية';
      default:
        return type;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(appBar: AppBar(title: const Text('الرصيد الافتتاحي')), body: const Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('الرصيد الافتتاحي'),
        actions: [
          TextButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.check),
            label: const Text('حفظ'),
            style: TextButton.styleFrom(foregroundColor: Colors.white, backgroundColor: Colors.green),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.teal.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.teal.withValues(alpha: 0.3)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.info_outline, color: Colors.teal, size: 18),
                Gap(8),
                Text('إدخال أرصدة أول المدة', style: TextStyle(fontWeight: FontWeight.bold)),
              ]),
              const Gap(4),
              Text(
                'أدخل أرصدة الأصول (مدين) والخصوم والحقوق (دائن). أي فرق يتم تسويته تلقائياً على حساب رأس المال 3000.',
                style: const TextStyle(fontSize: 12, color: Colors.teal),
              ),
            ]),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              itemCount: _accounts.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final a = _accounts[i];
                final color = _typeColor(a.type);
                final ctrl = _controllers.putIfAbsent(a.id, () => TextEditingController());
                return ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    backgroundColor: color.withValues(alpha: 0.15),
                    child: Text(a.code, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                  title: Text(a.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  subtitle: Text('${_typeLabel(a.type)} • ${a.normalBalance == 'credit' ? 'دائن' : 'مدين'}', style: const TextStyle(fontSize: 11)),
                  trailing: SizedBox(
                    width: 150,
                    child: TextField(
                      controller: ctrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      textAlign: TextAlign.end,
                      decoration: InputDecoration(
                        hintText: '0.00',
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                        suffixText: a.type == 'asset' ? 'مدين' : 'دائن',
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
