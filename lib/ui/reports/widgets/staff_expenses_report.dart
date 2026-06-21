import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';

class StaffExpensesReport extends StatefulWidget {
  final AppDatabase db;

  const StaffExpensesReport({super.key, required this.db});

  @override
  State<StaffExpensesReport> createState() => _StaffExpensesReportState();
}

class _StaffExpensesReportState extends State<StaffExpensesReport> {
  bool _isLoading = false;
  List<StaffAdvance> _advances = [];
  List<_SalaryEntry> _salaryEntries = [];
  Map<String, String> _staffMap = {};
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final advances = await widget.db.select(widget.db.staffAdvances).get();
      final staffList = await widget.db.select(widget.db.staffTable).get();

      final salaryExpenses = await (widget.db.select(widget.db.expenses)
        ..where((t) => t.category.equals('salaries'))
      ).get();

      final paidPayrolls = await (widget.db.select(widget.db.payrollTable)
        ..where((t) => t.status.equals('paid'))
      ).get();

      final staffMap = <String, String>{
        for (final s in staffList) s.staffId: s.name,
      };

      final entries = <_SalaryEntry>[];

      for (final exp in salaryExpenses) {
        entries.add(_SalaryEntry(
          staffId: _extractStaffIdFromDesc(exp.description, staffMap),
          staffName: _extractStaffNameFromDesc(exp.description, staffMap),
          amount: exp.amount,
          date: exp.date,
          period: '',
          source: 'expense',
        ));
      }

      for (final p in paidPayrolls) {
        final alreadyExists = entries.any((e) =>
            e.source == 'expense' &&
            (e.amount - p.netSalary).abs() < 0.01 &&
            e.date.difference(p.paymentDate ?? p.updatedAt).inMinutes.abs() < 2);
        if (!alreadyExists) {
          entries.add(_SalaryEntry(
            staffId: p.staffId,
            staffName: staffMap[p.staffId] ?? 'غير معروف',
            amount: p.netSalary,
            date: p.paymentDate ?? p.updatedAt,
            period: p.payrollPeriod,
            source: 'payroll',
          ));
        }
      }

      entries.sort((a, b) => b.date.compareTo(a.date));

      setState(() {
        _advances = advances;
        _salaryEntries = entries;
        _staffMap = staffMap;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'خطأ في تحميل البيانات: $e';
      });
    }
  }

  String _extractStaffIdFromDesc(String desc, Map<String, String> staffMap) {
    for (final entry in staffMap.entries) {
      if (desc.contains(entry.value) || desc.contains(entry.key)) {
        return entry.key;
      }
    }
    return '';
  }

  String _extractStaffNameFromDesc(String desc, Map<String, String> staffMap) {
    for (final entry in staffMap.entries) {
      if (desc.contains(entry.value)) {
        return entry.value;
      }
      if (desc.contains(entry.key)) {
        return entry.value;
      }
    }
    return desc;
  }

  double get _totalAdvances => _advances
      .where((a) => a.status == 'paid')
      .fold(0.0, (sum, a) => sum + a.amount);
  double get _totalSalaries =>
      _salaryEntries.fold(0.0, (sum, e) => sum + e.amount);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF121212) : Colors.grey.shade50;
    final cardBg = isDark ? const Color(0xFF1E1E2C) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text('تقرير مصروفات الموظفين'),
        backgroundColor: bgColor,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'تحديث',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 64,
                    color: Colors.red.shade300,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _errorMessage!,
                    style: TextStyle(color: textColor),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _loadData,
                    icon: const Icon(Icons.refresh),
                    label: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Card(
                        color: cardBg,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: Colors.red.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.red.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.payments,
                                  color: Colors.red,
                                  size: 28,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'إجمالي السلف',
                                      style: TextStyle(
                                        color: Colors.red.shade400,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${_totalAdvances.toStringAsFixed(2)} ج.م',
                                      style: TextStyle(
                                        color: textColor,
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    'عدد السلف',
                                    style: TextStyle(
                                      color: textColor.withValues(alpha: 0.6),
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(
                                    '${_advances.length}',
                                    style: TextStyle(
                                      color: textColor,
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Card(
                        color: cardBg,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: Colors.orange.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.receipt_long,
                                  color: Colors.orange,
                                  size: 28,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'المرتبات المصروفة',
                                      style: TextStyle(
                                        color: Colors.orange.shade400,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${_totalSalaries.toStringAsFixed(2)} ج.م',
                                      style: TextStyle(
                                        color: textColor,
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    'عدد المرتبات',
                                    style: TextStyle(
                                      color: textColor.withValues(alpha: 0.6),
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(
                                    '${_salaryEntries.length}',
                                    style: TextStyle(
                                      color: textColor,
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                DefaultTabController(
                  length: 2,
                  child: Expanded(
                    child: Column(
                      children: [
                      TabBar(
                        labelColor: Colors.orange,
                        unselectedLabelColor: textColor.withValues(alpha: 0.5),
                        indicatorColor: Colors.orange,
                        tabs: const [
                          Tab(text: 'السلف', icon: Icon(Icons.payments, size: 18)),
                          Tab(text: 'المرتبات', icon: Icon(Icons.receipt_long, size: 18)),
                        ],
                      ),
                      Expanded(
                        child: TabBarView(
                          children: [
                            _advances.isEmpty
                                ? Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.inbox_outlined, size: 64, color: textColor.withValues(alpha: 0.3)),
                                        const SizedBox(height: 16),
                                        Text('لا توجد سلف مسجلة', style: TextStyle(color: textColor.withValues(alpha: 0.6), fontSize: 16)),
                                      ],
                                    ),
                                  )
                                : ListView.builder(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    itemCount: _advances.length,
                                    itemBuilder: (context, index) {
                                      final advance = _advances[index];
                                      final staffName = _staffMap[advance.staffId] ?? 'غير معروف';
                                      final statusColor = advance.status == 'paid'
                                          ? Colors.green
                                          : advance.status == 'approved'
                                          ? Colors.blue
                                          : advance.status == 'rejected'
                                          ? Colors.red
                                          : Colors.orange;
                                      final statusText = advance.status == 'paid'
                                          ? 'مدفوع'
                                          : advance.status == 'approved'
                                          ? 'موافق عليه'
                                          : advance.status == 'rejected'
                                          ? 'مرفوض'
                                          : 'معلق';
                                      return Card(
                                        color: cardBg,
                                        margin: const EdgeInsets.only(bottom: 8),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                        child: ListTile(
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                          leading: CircleAvatar(
                                            backgroundColor: Colors.blueGrey.withValues(alpha: 0.2),
                                            child: Text(staffName.isNotEmpty ? staffName[0] : '?', style: const TextStyle(fontWeight: FontWeight.bold)),
                                          ),
                                          title: Text('سلفة - $staffName', style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
                                          subtitle: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const SizedBox(height: 4),
                                              Text(DateFormat('yyyy/MM/dd').format(advance.requestDate), style: TextStyle(color: textColor.withValues(alpha: 0.6), fontSize: 12)),
                                              if (advance.reason != null && advance.reason!.isNotEmpty)
                                                Text(advance.reason!, style: TextStyle(color: textColor.withValues(alpha: 0.5), fontSize: 11)),
                                            ],
                                          ),
                                          trailing: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            crossAxisAlignment: CrossAxisAlignment.end,
                                            children: [
                                              Text('${advance.amount.toStringAsFixed(2)} ج.م', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 15)),
                                              const SizedBox(height: 4),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                                                child: Text(statusText, style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold)),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),

                            _salaryEntries.isEmpty
                                ? Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.receipt_long_outlined, size: 64, color: textColor.withValues(alpha: 0.3)),
                                        const SizedBox(height: 16),
                                        Text('لا توجد مرتبات مصروفة', style: TextStyle(color: textColor.withValues(alpha: 0.6), fontSize: 16)),
                                      ],
                                    ),
                                  )
                                : ListView.builder(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    itemCount: _salaryEntries.length,
                                    itemBuilder: (context, index) {
                                      final entry = _salaryEntries[index];
                                      return Card(
                                        color: cardBg,
                                        margin: const EdgeInsets.only(bottom: 8),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                        child: ListTile(
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                          leading: CircleAvatar(
                                            backgroundColor: Colors.orange.withValues(alpha: 0.2),
                                            child: Text(
                                              entry.staffName.isNotEmpty ? entry.staffName[0] : '?',
                                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange),
                                            ),
                                          ),
                                          title: Text(entry.staffName, style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 14)),
                                          subtitle: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(DateFormat('yyyy/MM/dd').format(entry.date), style: TextStyle(color: textColor.withValues(alpha: 0.6), fontSize: 12)),
                                              if (entry.period.isNotEmpty)
                                                Text('الفترة: ${entry.period}', style: TextStyle(color: textColor.withValues(alpha: 0.4), fontSize: 11)),
                                            ],
                                          ),
                                          trailing: Text('${entry.amount.toStringAsFixed(2)} ج.م', style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 15)),
                                        ),
                                      );
                                    },
                                  ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
    );
  }
}

class _SalaryEntry {
  final String staffId;
  final String staffName;
  final double amount;
  final DateTime date;
  final String period;
  final String source;

  _SalaryEntry({
    required this.staffId,
    required this.staffName,
    required this.amount,
    required this.date,
    required this.period,
    required this.source,
  });
}
