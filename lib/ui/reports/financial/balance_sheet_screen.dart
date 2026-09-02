import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/provider/app_database_provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:pos_offline_desktop/core/models/user_model.dart';
import 'package:pos_offline_desktop/core/provider/auth_provider.dart';
import 'package:pos_offline_desktop/core/services/validation/permission_validator.dart';
import 'package:pos_offline_desktop/core/services/reports/balance_sheet_service.dart';
import 'package:pos_offline_desktop/core/services/reports/balance_sheet_pdf_generator.dart';

class BalanceSheetScreen extends ConsumerStatefulWidget {
  final AppDatabase db;
  const BalanceSheetScreen({super.key, required this.db});

  @override
  ConsumerState<BalanceSheetScreen> createState() => _BalanceSheetScreenState();
}

class _BalanceSheetScreenState extends ConsumerState<BalanceSheetScreen> {
  DateTime _asOf = DateTime.now();
  BalanceSheetData? _data;
  bool _isLoading = true;
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _checkPermissionAndLoad();
  }

  Future<void> _checkPermissionAndLoad() async {
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
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final svc = BalanceSheetService(ref.read(appDatabaseProvider));
    final data = await svc.getBalanceSheet(asOf: _asOf);
    setState(() {
      _data = data;
      _isLoading = false;
    });
  }

  Future<void> _export() async {
    if (_data == null) return;
    setState(() => _isExporting = true);
    try {
      await BalanceSheetPdfGenerator.generate(_data!);
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
        title: const Text('الميزانية العمومية'),
        actions: [
          IconButton(icon: const Icon(Icons.calendar_today), onPressed: () async {
            final picked = await showDatePicker(context: context, initialDate: _asOf, firstDate: DateTime(2020), lastDate: DateTime.now());
            if (picked != null) setState(() => _asOf = picked);
            _load();
          }),
          IconButton(icon: _isExporting ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.picture_as_pdf), onPressed: _isExporting ? null : _export),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _data == null
              ? const Center(child: Text('لا توجد بيانات'))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('كما في ${DateFormat('yyyy/MM/dd').format(_asOf)}', style: Theme.of(context).textTheme.titleMedium),
                      const Gap(12),
                      if (!_data!.isBalanced)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.red)),
                          child: Text('⚠ الميزانية غير متوازنة — الفرق: ${_data!.delta.toStringAsFixed(2)}', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                        ),
                      if (!_data!.isBalanced) const Gap(12),
                      _section('الأصول', _data!.assets, _data!.totalAssets, Colors.green),
                      const Gap(12),
                      _section('الالتزامات', _data!.liabilities, _data!.totalLiabilities, Colors.orange),
                      const Gap(12),
                      _section('حقوق الملكية', _data!.equity, _data!.totalEquity, Colors.blue),
                      const Divider(height: 24),
                      _totalRow('إجمالي الأصول', _data!.totalAssets, Colors.green),
                      _totalRow('إجمالي الالتزامات وحقوق الملكية', _data!.totalLiabilitiesEquity, Colors.blue),
                    ],
                  ),
                ),
    );
  }

  Widget _section(String title, List<BalanceSheetAccountRow> rows, double total, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            color: color.withValues(alpha: 0.1),
            child: Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
          ),
          ...rows.map((r) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('${r.account.code} - ${r.account.name}', style: const TextStyle(fontSize: 12)),
                  Text(r.balance.toStringAsFixed(2), style: const TextStyle(fontSize: 12)),
                ]),
              )),
          const Divider(),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('الإجمالي', style: TextStyle(fontWeight: FontWeight.bold)),
            Text(total.toStringAsFixed(2), style: TextStyle(fontWeight: FontWeight.bold, color: color)),
          ]),
        ]),
      ),
    );
  }

  Widget _totalRow(String label, double value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        Text(value.toStringAsFixed(2), style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 16)),
      ]),
    );
  }
}
