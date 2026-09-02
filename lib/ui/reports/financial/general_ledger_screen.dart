import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/provider/app_database_provider.dart';
import 'package:pos_offline_desktop/core/models/user_model.dart';
import 'package:pos_offline_desktop/core/provider/auth_provider.dart';
import 'package:pos_offline_desktop/core/services/validation/permission_validator.dart';
import 'package:pos_offline_desktop/core/services/reports/general_ledger_service.dart';
import 'package:pos_offline_desktop/core/services/reports/general_ledger_pdf_generator.dart';

class GeneralLedgerScreen extends ConsumerStatefulWidget {
  final AppDatabase db;
  const GeneralLedgerScreen({super.key, required this.db});

  @override
  ConsumerState<GeneralLedgerScreen> createState() => _GeneralLedgerScreenState();
}

class _GeneralLedgerScreenState extends ConsumerState<GeneralLedgerScreen> {
  DateTime _from = DateTime.now().subtract(const Duration(days: 30));
  DateTime _to = DateTime.now();
  String? _selectedAccountId;
  List<Account> _accounts = [];
  GeneralLedgerData? _data;
  bool _isLoading = true;
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _loadAccountsAndCheck();
  }

  Future<void> _loadAccountsAndCheck() async {
    final user = ref.read(authProvider);
    if (user != null) {
      try {
        PermissionValidator.requirePermission(user, Permission.viewFinancialReports, 'عرض التقارير المالية');
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: Colors.red));
          Navigator.pop(context);
        }
        return;
      }
    }
    final accs = await ref.read(appDatabaseProvider).accountsDao.getAllAccounts();
    setState(() => _accounts = accs);
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final svc = GeneralLedgerService(ref.read(appDatabaseProvider));
    final data = await svc.getLedger(accountId: _selectedAccountId, from: _from, to: _to);
    setState(() {
      _data = data;
      _isLoading = false;
    });
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime.now(), initialDateRange: DateTimeRange(start: _from, end: _to));
    if (picked != null) setState(() { _from = picked.start; _to = picked.end; });
    _load();
  }

  Future<void> _export() async {
    if (_data == null) return;
    setState(() => _isExporting = true);
    try {
      await GeneralLedgerPdfGenerator.generate(_data!);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e')));
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('دفتر الأستاذ العام'),
        actions: [
          IconButton(icon: const Icon(Icons.date_range), onPressed: _pickRange),
          IconButton(icon: _isExporting ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.picture_as_pdf), onPressed: _isExporting ? null : _export),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedAccountId,
                    decoration: const InputDecoration(labelText: 'الحساب', border: OutlineInputBorder()),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('كل الحسابات')),
                      ..._accounts.map((a) => DropdownMenuItem(value: a.id, child: Text('${a.code} - ${a.name}'))),
                    ],
                    onChanged: (v) {
                      setState(() => _selectedAccountId = v);
                      _load();
                    },
                  ),
                ),
                const Gap(12),
                Text('افتتاحي: ${_data?.openingBalance.toStringAsFixed(2) ?? '-'}', style: const TextStyle(fontWeight: FontWeight.bold)),
                const Gap(12),
                Text('ختامي: ${_data?.closingBalance.toStringAsFixed(2) ?? '-'}', style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _data == null || _data!.lines.isEmpty
                    ? const Center(child: Text('لا توجد حركات في هذه الفترة'))
                    : SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: const [
                            DataColumn(label: Text('التاريخ')),
                            DataColumn(label: Text('البيان')),
                            DataColumn(label: Text('مدين')),
                            DataColumn(label: Text('دائن')),
                            DataColumn(label: Text('الرصيد')),
                          ],
                          rows: _data!.lines
                              .map((gl) => DataRow(cells: [
                                    DataCell(Text(DateFormat('yyyy/MM/dd').format(gl.entry.date), style: const TextStyle(fontSize: 12))),
                                    DataCell(Text(gl.entry.description, style: const TextStyle(fontSize: 12))),
                                    DataCell(Text(gl.line.debit > 0 ? gl.line.debit.toStringAsFixed(2) : '-', style: const TextStyle(fontSize: 12))),
                                    DataCell(Text(gl.line.credit > 0 ? gl.line.credit.toStringAsFixed(2) : '-', style: const TextStyle(fontSize: 12))),
                                    DataCell(Text(gl.runningBalance.toStringAsFixed(2), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                                  ]))
                              .toList(),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
