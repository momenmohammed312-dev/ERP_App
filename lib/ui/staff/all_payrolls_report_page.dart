import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_offline_desktop/core/provider/app_database_provider.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/dao/staff_management_dao.dart';
import 'package:pos_offline_desktop/services/staff_management_service.dart';
import 'package:pos_offline_desktop/ui/staff/services/staff_payroll_statement_generator.dart';
import 'package:pos_offline_desktop/services/payroll_display.dart';

class AllPayrollsReportPage extends ConsumerStatefulWidget {
  const AllPayrollsReportPage({super.key});
  @override
  ConsumerState<AllPayrollsReportPage> createState() => _AllPayrollsReportPageState();
}

class _AllPayrollsReportPageState extends ConsumerState<AllPayrollsReportPage> {
  String _period = "${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2,'0')}";
  List<Payroll> _payrolls = [];
  Map<String,Staff> _staffMap = {};
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(()=>_loading=true);
    final db = ref.read(appDatabaseProvider);
    final all = await db.select(db.payrollTable).get();
    final filtered = all.where((p)=>p.payrollPeriod==_period).toList();
    final staffList = await db.select(db.staffTable).get();
    final map = {for(var s in staffList) s.staffId: s};
    setState((){_payrolls=filtered; _staffMap=map; _loading=false;});
  }

  Future<void> _pickPeriod() async {
    final picked = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2030), helpText: 'اختر شهر الكشف');
    if(picked==null) return;
    final y = picked.year, m = picked.month;
    final monthly = "$y-${m.toString().padLeft(2,'0')}";
    // اعرض الشهري + الأسابيع الصالحة (الخميس في نفس الشهر)
    final db = ref.read(appDatabaseProvider);
    final svc = StaffManagementService(StaffManagementDao(db), db);
    final weeks = <int>[];
    for (var w = 1; w <= 5; w++) {
      try { svc.weekBounds(y, m, w); weeks.add(w); } catch (_) {}
    }
    if (!mounted) return;
    final chosen = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('اختر الفترة'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, monthly),
            child: Text('شهري $monthly'),
          ),
          for (final w in weeks)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, '$monthly-W$w'),
              child: Text('أسبوع $w ($monthly-W$w)'),
            ),
        ],
      ),
    );
    if (chosen != null) {
      setState(()=>_period=chosen);
      _load();
    }
  }

  @override
  Widget build(BuildContext context){
    return Scaffold(
      appBar: AppBar(title: Text('كشف حساب كلي - $_period'), actions: [
        IconButton(icon: Icon(Icons.calendar_month), onPressed: _pickPeriod),
        IconButton(icon: Icon(Icons.print), onPressed: _payrolls.isEmpty?null:() async {
          final db = ref.read(appDatabaseProvider);
          // build a dummy staff for header (not used for all)
          final dummy = _staffMap.values.isNotEmpty ? _staffMap.values.first : null;
          if(dummy==null) return;
          await StaffPayrollStatementGenerator.generateAndPrintAll(context: context, db: db, payrolls: _payrolls, staffMap: _staffMap, period: _period);
        }),
      ]),
      body: _loading ? Center(child: CircularProgressIndicator()) :
      _payrolls.isEmpty ? Center(child: Text('لا توجد مرتبات لـ $_period')) :
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('الإسم')),
            DataColumn(label: Text('الأساسي')),
            DataColumn(label: Text('إضافي')),
            DataColumn(label: Text('انتظام')),
            DataColumn(label: Text('تأخير')),
            DataColumn(label: Text('غياب')),
            DataColumn(label: Text('سلف')),
            DataColumn(label: Text('إذن')),
            DataColumn(label: Text('إجمالي')),
          ],
          rows: _payrolls.map((p){
            final s = _staffMap[p.staffId];
            // الغياب من القيم المخزنة (تشمل ×mult) بدل إعادة الحساب بدونها
            var absentDed = PayrollDisplay.absenceDeduction(
                p, weekly: s?.payFrequency == 'weekly');
            return DataRow(cells: [
              DataCell(Text(s?.name ?? p.staffId)),
              DataCell(Text(p.basicSalary.toStringAsFixed(0))),
              DataCell(Text(p.overtimePay.toStringAsFixed(0))),
              DataCell(Text(p.bonus.toStringAsFixed(0))),
              DataCell(Text(p.lateDeduction.toStringAsFixed(0))),
              DataCell(Text(absentDed.toStringAsFixed(0))),
              DataCell(Text(p.advances.toStringAsFixed(0))),
              DataCell(Text(p.permissionDeduction.toStringAsFixed(0))),
              DataCell(Text(p.netSalary.toStringAsFixed(0), style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green))),
            ]);
          }).toList(),
        ),
      ),
    );
  }
}
