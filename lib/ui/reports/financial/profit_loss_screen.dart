import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/provider/app_database_provider.dart';
import 'package:pos_offline_desktop/core/models/user_model.dart';
import 'package:pos_offline_desktop/core/provider/auth_provider.dart';
import 'package:pos_offline_desktop/core/services/validation/permission_validator.dart';
import 'package:pos_offline_desktop/core/services/reports/profit_loss_service.dart';
import 'package:pos_offline_desktop/core/services/reports/profit_loss_pdf_generator.dart';

class ProfitLossScreen extends ConsumerStatefulWidget {
  final AppDatabase db;
  const ProfitLossScreen({super.key, required this.db});

  @override
  ConsumerState<ProfitLossScreen> createState() => _ProfitLossScreenState();
}

class _ProfitLossScreenState extends ConsumerState<ProfitLossScreen> {
  DateTime _from = DateTime.now().subtract(const Duration(days: 30));
  DateTime _to = DateTime.now();
  ProfitLossData? _data;
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
    final svc = ProfitLossService(ref.read(appDatabaseProvider));
    final data = await svc.getProfitLoss(from: _from, to: _to);
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
      await ProfitLossPdfGenerator.generate(_data!);
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
        title: const Text('قائمة الأرباح والخسائر'),
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
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Text('الفترة: ${DateFormat('yyyy/MM/dd').format(_from)} - ${DateFormat('yyyy/MM/dd').format(_to)}'),
                      const Gap(12),
                      _row('إيرادات المبيعات', _data!.revenue, bold: true),
                      _row('(-) مردودات المبيعات', _data!.salesReturns),
                      _row('صافي الإيرادات', _data!.netRevenue, bold: true, bg: Colors.grey.shade200),
                      _row('(-) تكلفة البضاعة المباعة', _data!.cogs),
                      _row('مجمل الربح', _data!.grossProfit, bold: true, bg: Colors.grey.shade200, color: _data!.grossProfit >= 0 ? Colors.green : Colors.red),
                      _row('(-) مصروفات تشغيلية', _data!.operatingExpenses),
                      _row('صافي الربح', _data!.netProfit, bold: true, bg: Colors.grey.shade300, color: _data!.netProfit >= 0 ? Colors.green : Colors.red),
                    ],
                  ),
                ),
    );
  }

  Widget _row(String label, double value, {bool bold = false, Color? bg, Color? color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: bg, border: Border(bottom: BorderSide(color: Colors.grey.shade300))),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
        Text(value.toStringAsFixed(2), style: TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal, color: color)),
      ]),
    );
  }
}
