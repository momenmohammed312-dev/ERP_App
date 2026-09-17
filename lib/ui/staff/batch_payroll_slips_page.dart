import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/provider/app_database_provider.dart';
import 'package:pos_offline_desktop/core/provider/auth_provider.dart';
import 'package:pos_offline_desktop/services/payroll_display.dart';
import 'package:pos_offline_desktop/ui/staff/services/staff_payroll_statement_generator.dart';
import 'package:pos_offline_desktop/ui/staff/payroll_disbursement_sheet.dart';

/// صفحة المرتبات المجمعة: تقرير لكل الموظفين لفترة (شهر/أسبوع)
/// مع حساب تلقائي للناقص وطباعة 3 قسائم في ورقة A4 (توفير ورق + قص).
class BatchPayrollSlipsPage extends ConsumerStatefulWidget {
  const BatchPayrollSlipsPage({super.key});

  @override
  ConsumerState<BatchPayrollSlipsPage> createState() =>
      _BatchPayrollSlipsPageState();
}

class _BatchPayrollSlipsPageState extends ConsumerState<BatchPayrollSlipsPage> {
  bool _isMonthly = true;
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month, 1);
  int _week = 1;

  List<Payroll> _payrolls = [];
  Map<String, Staff> _staffMap = {};
  List<Staff> _activeStaff = [];
  List<String> _failures = [];
  bool _loading = true;
  bool _calculating = false;
  String _calcProgress = '';
  // قسائم مختارة للطباعة: فاضي = طباعة الكل
  final Set<int> _selectedPayrollIds = {};

  String get _period {
    final ym = '${_month.year}-${_month.month.toString().padLeft(2, '0')}';
    return _isMonthly ? ym : '$ym-W$_week';
  }

  // حدود الفترة من نفس قواعد الخدمة (الأسبوع: سبت–خميس لشهر الخميس)
  DateTime get _periodStart {
    if (_isMonthly) return DateTime(_month.year, _month.month, 1);
    return ref
        .read(staffManagementServiceProvider)
        .weekBounds(_month.year, _month.month, _week)
        .$1;
  }

  DateTime get _periodEnd {
    if (_isMonthly) return DateTime(_month.year, _month.month + 1, 0);
    return ref
        .read(staffManagementServiceProvider)
        .weekBounds(_month.year, _month.month, _week)
        .$2;
  }

  /// الأسابيع الصالحة لشهر مختار (الخميس داخل نفس الشهر)
  List<int> _validWeeks() {
    final svc = ref.read(staffManagementServiceProvider);
    final out = <int>[];
    for (var w = 1; w <= 5; w++) {
      try {
        svc.weekBounds(_month.year, _month.month, w);
        out.add(w);
      } catch (_) {}
    }
    return out;
  }

  void _clampWeek() {
    final valid = _validWeeks();
    if (valid.isEmpty) return;
    if (!valid.contains(_week)) _week = valid.last;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failures = [];
    });
    try {
      final db = ref.read(appDatabaseProvider);
      final staffList = await db.select(db.staffTable).get();
      final allPayrolls = await db.select(db.payrollTable).get();
      final filtered = allPayrolls
          .where((p) => p.payrollPeriod == _period)
          .toList();
      final active = staffList
          .where((s) => s.isActive && s.status == 'active')
          .toList();
      if (mounted) {
        setState(() {
          _staffMap = {for (final s in staffList) s.staffId: s};
          _activeStaff = active;
          _payrolls = filtered;
          _selectedPayrollIds.removeWhere(
            (id) => !filtered.any((p) => p.id == id),
          );
          _loading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('خطأ في التحميل: $e')));
    }
  }

  List<Staff> get _missingStaff {
    final ids = _payrolls.map((p) => p.staffId).toSet();
    // كل دورة تحسب موظفيها فقط: الشهري يتخطى الأسبوعيين والعكس
    return _activeStaff.where((s) {
      if (ids.contains(s.staffId)) return false;
      final weekly = s.payFrequency == 'weekly';
      return _isMonthly ? !weekly : weekly;
    }).toList();
  }

  int get _skippedByMode => _activeStaff
      .where(
        (s) => _isMonthly
            ? s.payFrequency == 'weekly'
            : s.payFrequency != 'weekly',
      )
      .length;

  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _month,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      helpText: 'اختر شهر الفترة',
    );
    if (picked != null) {
      setState(() {
        _month = DateTime(picked.year, picked.month, 1);
        _clampWeek();
      });
      await _load();
    }
  }

  /// حساب تلقائي للموظفين الناقصين — كل موظف مستقل، فشل واحد لا يوقف الباقي.
  Future<void> _autoCalculateMissing() async {
    final missing = _missingStaff;
    if (missing.isEmpty) return;
    final user = ref.read(authProvider);
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('سجل دخول أولاً لحساب المرتبات')),
        );
      }
      return;
    }
    setState(() {
      _calculating = true;
      _failures = [];
    });
    final service = ref.read(staffManagementServiceProvider);
    final failures = <String>[];
    for (int i = 0; i < missing.length; i++) {
      final s = missing[i];
      if (mounted) {
        setState(
          () =>
              _calcProgress = 'جاري حساب ${i + 1}/${missing.length}: ${s.name}',
        );
      }
      try {
        // التوجيه حسب دورة الموظف: الأسبوعي بمعادلته (÷6، بدون 200، سقف سلفة)
        if (_isMonthly) {
          // commitmentBonus = 0 → الخدمة تطبق مكافأة الالتزام تلقائياً لو الشروط متحققة
          await service.calculatePayroll(user, s.staffId, _period);
        } else {
          await service.calculateWeeklyPay(
            user,
            s.staffId,
            _month.year,
            _month.month,
            _week,
          );
        }
      } catch (e) {
        failures.add('${s.name}: $e');
      }
    }
    await _load();
    if (!mounted) return;
    setState(() {
      _calculating = false;
      _calcProgress = '';
      _failures = failures;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failures.isEmpty
              ? 'تم حساب ${missing.length} مرتب بنجاح${_skippedByMode > 0 ? ' (تخطي $_skippedByMode بدورة مختلفة)' : ''}'
              : 'تم حساب ${missing.length - failures.length} - فشل ${failures.length}',
        ),
        backgroundColor: failures.isEmpty ? Colors.green : Colors.orange,
      ),
    );
  }

  void _openDisbursementSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => PayrollDisbursementSheet(
        period: _period,
        staffMap: _staffMap,
        selectedIds: Set<int>.of(_selectedPayrollIds),
        onChanged: () {
          Navigator.pop(context);
          _load();
        },
        onPrintSlips: _printBatch,
      ),
    );
  }

  Future<void> _printBatch() async {
    if (_payrolls.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('لا توجد مرتبات محسوبة للطباعة — احسب الناقص أولاً'),
        ),
      );
      return;
    }
    // طباعة المختار فقط إن وُجد، وإلا الكل
    final toPrint = _visiblePayrolls;
    if (toPrint.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اختر مرتباً واحداً على الأقل للطباعة')),
      );
      return;
    }
    try {
      final db = ref.read(appDatabaseProvider);
      await StaffPayrollStatementGenerator.generateAndPrintBatchSlips(
        context: context,
        db: db,
        payrolls: toPrint,
        staffMap: _staffMap,
        period: _period,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('خطأ في الطباعة: $e')));
      }
    }
  }

  /// مرتبات نطاق العرض الحالي: المحدد بالشيك بوكس، أو الكل إن لا تحديد.
  List<Payroll> get _visiblePayrolls => _selectedPayrollIds.isEmpty
      ? _payrolls
      : _payrolls.where((p) => _selectedPayrollIds.contains(p.id)).toList();

  // C3: page header total uses the ONE shared fold over stored rows —
  // identical rules to voucher + service + batch-pay by construction.
  double get _visibleTotal => PayrollDisplay.totalsOf(_visiblePayrolls).net;

  @override
  Widget build(BuildContext context) {
    final missing = _missingStaff;
    final dateFmt = DateFormat('yyyy/MM/dd');
    return Scaffold(
      appBar: AppBar(
        title: Text('المرتبات المجمعة - $_period'),
        actions: [
          IconButton(
            icon: const Icon(Icons.print),
            tooltip: 'ملخص واعتماد الصرف (الكل أو المحدد بالشيك بوكس)',
            onPressed: (_payrolls.isEmpty || _calculating)
                ? null
                : _openDisbursementSheet,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildPeriodCard(dateFmt),
          if (_calculating)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  const LinearProgressIndicator(),
                  const SizedBox(height: 4),
                  Text(_calcProgress, style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
          _buildSummaryChips(missing.length),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _selectedPayrollIds.isEmpty
                      ? 'إجمالي الكل (${_payrolls.length}): ${_visibleTotal.toStringAsFixed(0)}'
                      : 'إجمالي المحدد (${_visiblePayrolls.length}): ${_visibleTotal.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
          ),
          if (_failures.isNotEmpty)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'تعذر حساب:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  for (final f in _failures.take(3)) Text(f),
                  if (_failures.length > 3)
                    Text('... و ${_failures.length - 3} آخرين'),
                ],
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : (_payrolls.isEmpty && missing.isEmpty)
                ? const Center(child: Text('لا يوجد موظفون نشطون'))
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (_payrolls.isNotEmpty) ...[
                        Row(
                          children: [
                            const Text(
                              'مرتبات محسوبة',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            const Spacer(),
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  if (_selectedPayrollIds.length ==
                                      _payrolls.length) {
                                    _selectedPayrollIds.clear();
                                  } else {
                                    _selectedPayrollIds
                                      ..clear()
                                      ..addAll(_payrolls.map((p) => p.id));
                                  }
                                });
                              },
                              child: Text(
                                _selectedPayrollIds.length == _payrolls.length
                                    ? 'إلغاء تحديد الكل'
                                    : 'تحديد الكل للطباعة',
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        for (final p in _payrolls) _buildPayrollTile(p),
                      ],
                      if (missing.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          'ناقص (${missing.length}) — يحتاج حساب',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: Colors.orange,
                          ),
                        ),
                        const SizedBox(height: 8),
                        for (final s in missing) _buildMissingTile(s),
                      ],
                    ],
                  ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: (missing.isEmpty || _calculating)
                      ? null
                      : _autoCalculateMissing,
                  icon: const Icon(Icons.calculate),
                  label: Text('حساب الناقص (${missing.length})'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: (_payrolls.isEmpty || _calculating)
                      ? null
                      : _printBatch,
                  icon: const Icon(Icons.print, color: Colors.white),
                  label: Text(
                    _selectedPayrollIds.isEmpty
                        ? 'طباعة 3 / صفحة'
                        : 'طباعة المختار (${_selectedPayrollIds.length})',
                    style: const TextStyle(color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPeriodCard(DateFormat dateFmt) {
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: true,
                  label: Text('شهري'),
                  icon: Icon(Icons.calendar_month),
                ),
                ButtonSegment(
                  value: false,
                  label: Text('أسبوعي'),
                  icon: Icon(Icons.date_range),
                ),
              ],
              selected: {_isMonthly},
              onSelectionChanged: (s) {
                setState(() {
                  _isMonthly = s.first;
                  _clampWeek();
                });
                _load();
              },
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'الفترة: $_period\n${dateFmt.format(_periodStart)} → ${dateFmt.format(_periodEnd)}',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                TextButton.icon(
                  onPressed: _pickMonth,
                  icon: const Icon(Icons.edit_calendar),
                  label: const Text('تغيير الشهر'),
                ),
                if (!_isMonthly)
                  Builder(
                    builder: (context) {
                      final valid = _validWeeks();
                      if (valid.isEmpty) return const Text('لا أسابيع');
                      final svc = ref.read(staffManagementServiceProvider);
                      return DropdownButton<int>(
                        value: valid.contains(_week) ? _week : valid.last,
                        items: valid.map((w) {
                          final b = svc.weekBounds(
                            _month.year,
                            _month.month,
                            w,
                          );
                          return DropdownMenuItem(
                            value: w,
                            child: Text(
                              'أسبوع $w (${b.$1.day}/${b.$1.month}→${b.$2.day}/${b.$2.month})',
                            ),
                          );
                        }).toList(),
                        onChanged: (w) {
                          if (w != null) {
                            setState(() => _week = w);
                            _load();
                          }
                        },
                      );
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryChips(int missingCount) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Chip(
            label: Text('محسوب: ${_payrolls.length}'),
            backgroundColor: Colors.green.withValues(alpha: 0.15),
          ),
          const SizedBox(width: 8),
          Chip(
            label: Text('ناقص: $missingCount'),
            backgroundColor: Colors.orange.withValues(alpha: 0.15),
          ),
          const SizedBox(width: 8),
          Chip(label: Text('إجمالي: ${_activeStaff.length}')),
        ],
      ),
    );
  }

  Widget _buildPayrollTile(Payroll p) {
    final s = _staffMap[p.staffId];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.teal.withValues(alpha: 0.15),
          child: const Icon(Icons.person, color: Colors.teal),
        ),
        title: Text(
          s?.name ?? p.staffId,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(s?.staffId ?? p.staffId),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              p.netSalary.toStringAsFixed(0),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.green,
                fontSize: 16,
              ),
            ),
            if (p.status == 'calculated')
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                tooltip: 'حذف المرتب وإعادة الحساب',
                onPressed: () => _deletePayroll(p),
              ),
            Checkbox(
              value: _selectedPayrollIds.contains(p.id),
              onChanged: (v) {
                setState(() {
                  if (v == true) {
                    _selectedPayrollIds.add(p.id);
                  } else {
                    _selectedPayrollIds.remove(p.id);
                  }
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deletePayroll(Payroll payroll) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف المرتب'),
        content: Text(
          'هل أنت متأكد من حذف مرتب ${payroll.payrollPeriod} قبل الاعتماد؟ '
          'سيتم إعادة حسابه من جديد.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final db = ref.read(appDatabaseProvider);
      await (db.delete(
        db.payrollTable,
      )..where((t) => t.id.equals(payroll.id))).go();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم حذف المرتب — يمكنك إعادة احتسابه'),
          backgroundColor: Colors.green,
        ),
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ في الحذف: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildMissingTile(Staff s) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: Colors.orange.withValues(alpha: 0.05),
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: Colors.orange,
          child: Icon(Icons.warning, color: Colors.white, size: 18),
        ),
        title: Text(s.name),
        subtitle: Text(s.staffId),
        trailing: const Text(
          'ناقص',
          style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
