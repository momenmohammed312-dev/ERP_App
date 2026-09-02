import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/provider/app_database_provider.dart';
import 'package:pos_offline_desktop/core/models/user_model.dart';
import 'package:pos_offline_desktop/core/provider/auth_provider.dart';
import 'package:pos_offline_desktop/core/services/validation/permission_validator.dart';
import 'package:pos_offline_desktop/core/services/reports/equity_statement_service.dart';
import 'package:pos_offline_desktop/core/services/reports/equity_statement_pdf_generator.dart';

class EquityStatementScreen extends ConsumerStatefulWidget {
  final AppDatabase db;
  const EquityStatementScreen({super.key, required this.db});

  @override
  ConsumerState<EquityStatementScreen> createState() => _EquityStatementScreenState();
}

class _EquityStatementScreenState extends ConsumerState<EquityStatementScreen> {
  DateTime _from = DateTime.now().subtract(const Duration(days: 30));
  DateTime _to = DateTime.now();
  EquityStatementData? _data;
  bool _isLoading = true;
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _checkAndLoad();
  }

  Future<void> _checkAndLoad() async {
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
    final svc = EquityStatementService(ref.read(appDatabaseProvider));
    final data = await svc.getStatement(from: _from, to: _to);
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
      await EquityStatementPdfGenerator.generate(_data!);
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
        title: const Text('كشف حقوق الملكية'),
        actions: [
          IconButton(icon: const Icon(Icons.date_range), onPressed: _pickRange),
          IconButton(icon: _isExporting ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.picture_as_pdf), onPressed: _isExporting ? null : _export),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _data == null
              ? const Center(child: Text('لا توجد بيانات'))
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(label: Text('الشريك')),
                      DataColumn(label: Text('افتتاحي')),
                      DataColumn(label: Text('مساهمات')),
                      DataColumn(label: Text('أرباح')),
                      DataColumn(label: Text('مسحوبات')),
                      DataColumn(label: Text('ختامي')),
                    ],
                    rows: [
                      ..._data!.partners.map((p) => DataRow(cells: [
                            DataCell(Text(p.partner.name)),
                            DataCell(Text(p.opening.toStringAsFixed(2))),
                            DataCell(Text(p.contributions.toStringAsFixed(2))),
                            DataCell(Text(p.profitAllocations.toStringAsFixed(2))),
                            DataCell(Text(p.withdrawals.toStringAsFixed(2))),
                            DataCell(Text(p.closing.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.bold))),
                          ])),
                      DataRow(
                        color: WidgetStateProperty.all(Colors.grey.shade200),
                        cells: [
                          const DataCell(Text('الإجمالي', style: TextStyle(fontWeight: FontWeight.bold))),
                          DataCell(Text(_data!.totalOpening.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.bold))),
                          DataCell(Text(_data!.totalContributions.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.bold))),
                          DataCell(Text(_data!.totalProfitAllocations.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.bold))),
                          DataCell(Text(_data!.totalWithdrawals.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.bold))),
                          DataCell(Text(_data!.totalClosing.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.bold))),
                        ],
                      ),
                    ],
                  ),
                ),
    );
  }
}
