import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import '../../core/database/app_database.dart';
import '../../core/provider/app_database_provider.dart';
import '../../core/database/dao/staff_management_dao.dart';
import 'staff_list_page.dart';
import 'staff_form_page.dart';

class EmployeeDashboardPage extends ConsumerStatefulWidget {
  const EmployeeDashboardPage({super.key});

  @override
  ConsumerState<EmployeeDashboardPage> createState() =>
      _EmployeeDashboardPageState();
}

class _EmployeeDashboardPageState
    extends ConsumerState<EmployeeDashboardPage>
    with SingleTickerProviderStateMixin {
  late StaffManagementDao _dao;
  late AppDatabase _db;
  bool _isLoading = true;

  int _activeStaff = 0;
  int _presentToday = 0;
  int _absentToday = 0;
  int _lateToday = 0;
  int _onLeaveToday = 0;
  int _pendingVacations = 0;
  double _pendingAdvancesTotal = 0.0;
  double _totalSalary = 0.0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _db = ref.read(appDatabaseProvider);
    _dao = StaffManagementDao(_db);
    await _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final allStaff = await _dao.getAllStaff();
      _activeStaff = allStaff.where((s) => s.isActive).length;
      _totalSalary = allStaff.fold<double>(0, (s, e) => s + e.basicSalary);

      final today = DateTime.now();
      final todayStart = DateTime(today.year, today.month, today.day);

      final attendanceRows = await _db.customSelect('''
        SELECT status, COUNT(*) as cnt FROM attendance
        WHERE date >= ? AND date < ?
        GROUP BY status
      ''', variables: [
        drift.Variable.withDateTime(todayStart),
        drift.Variable.withDateTime(
          todayStart.add(const Duration(days: 1)),
        ),
      ]).get();

      for (final row in attendanceRows) {
        final status = row.read<String>('status');
        final cnt = row.read<int>('cnt');
        switch (status) {
          case 'present':
            _presentToday = cnt;
          case 'absent':
            _absentToday = cnt;
          case 'late':
            _lateToday = cnt;
          case 'leave':
            _onLeaveToday = cnt;
        }
      }

      final vacationRows = await _db.customSelect('''
        SELECT status, COUNT(*) as cnt FROM vacations
        GROUP BY status
      ''').get();
      for (final row in vacationRows) {
        if (row.read<String>('status') == 'pending') {
          _pendingVacations = row.read<int>('cnt');
        }
      }

      final advanceRows = await _db.customSelect('''
        SELECT COALESCE(SUM(amount), 0) as total FROM staff_advances
        WHERE status IN ('pending', 'approved')
      ''').get();
      if (advanceRows.isNotEmpty) {
        _pendingAdvancesTotal = advanceRows.first.read<num>('total').toDouble();
      }

      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في تحميل البيانات: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0D1117) : Colors.grey.shade50;
    final cardBg = isDark ? const Color(0xFF161B22) : Colors.white;
    final textColor = isDark ? const Color(0xFFE6EDF3) : Colors.black87;
    final subTextColor = isDark ? const Color(0xFF8B949E) : Colors.black54;
    final goldColor = const Color(0xFFC9A84C);
    final borderColor =
        isDark ? const Color(0xFF30363D) : Colors.grey.shade300;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text('لوحة الموظفين'),
        backgroundColor: bgColor,
        foregroundColor: textColor,
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
          ? Center(child: CircularProgressIndicator(color: goldColor))
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildSectionHeader(textColor, 'ملخص عام', Icons.dashboard),
                  const SizedBox(height: 12),
                  _buildSummaryGrid(
                    textColor, goldColor, cardBg, borderColor),
                  const SizedBox(height: 20),
                  _buildSectionHeader(
                    textColor, 'حضور اليوم', Icons.calendar_today),
                  const SizedBox(height: 12),
                  _buildAttendanceCards(cardBg, borderColor),
                  const SizedBox(height: 20),
                  _buildSectionHeader(
                    textColor, 'إجراءات سريعة', Icons.flash_on),
                  const SizedBox(height: 12),
                  _buildQuickActions(
                    textColor, goldColor, subTextColor, cardBg, borderColor),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionHeader(Color textColor, String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: textColor.withValues(alpha: 0.7)),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryGrid(
    Color textColor, Color goldColor, Color cardBg, Color borderColor) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                '$_activeStaff', 'موظفين نشطين', Colors.green,
                Icons.person, cardBg, borderColor,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildMetricCard(
                '$_pendingVacations', 'إجازات معلقة', Colors.orange,
                Icons.beach_access, cardBg, borderColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                '${_pendingAdvancesTotal.toStringAsFixed(0)} ج.م',
                'سلف معلقة', Colors.redAccent,
                Icons.money_off, cardBg, borderColor,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildMetricCard(
                '${_totalSalary.toStringAsFixed(0)} ج.م',
                'إجمالي المرتبات', goldColor,
                Icons.attach_money, cardBg, borderColor,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMetricCard(
    String value, String label, Color color, IconData icon,
    Color cardBg, Color borderColor,
  ) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 600),
      curve: Curves.elasticOut,
      builder: (context, scale, child) {
        return Transform.scale(scale: scale, child: child);
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: color.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttendanceCards(Color cardBg, Color borderColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          _buildAttendanceStat('$_presentToday', 'حاضر', Colors.green),
          const SizedBox(width: 8),
          _buildAttendanceStat('$_absentToday', 'غائب', Colors.red),
          const SizedBox(width: 8),
          _buildAttendanceStat('$_lateToday', 'متأخر', Colors.orange),
          const SizedBox(width: 8),
          _buildAttendanceStat('$_onLeaveToday', 'إجازة', Colors.blue),
        ],
      ),
    );
  }

  Widget _buildAttendanceStat(String count, String label, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(
            count,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: color.withValues(alpha: 0.8)),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions(Color textColor, Color goldColor,
      Color subTextColor, Color cardBg, Color borderColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildActionBtn(
                  'الموظفين',
                  Icons.people,
                  goldColor,
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const StaffListPage(),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildActionBtn(
                  'إضافة موظف',
                  Icons.person_add,
                  Colors.green,
                  () async {
                    final result = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const StaffFormPage(),
                      ),
                    );
                    if (result == true) _loadData();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildActionBtn(
                  'الإجازات ($_pendingVacations)',
                  Icons.beach_access,
                  Colors.orange,
                  () => _showSectionList('إجازات معلقة', 'vacations'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildActionBtn(
                  'السلف',
                  Icons.money_off,
                  Colors.redAccent,
                  () => _showSectionList('سلف معلقة', 'advances'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionBtn(
      String label, IconData icon, Color color, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSectionList(String title, String type) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.85,
        minChildSize: 0.3,
        expand: false,
        builder: (_, scrollCtrl) => _SectionListSheet(
          db: _db,
          title: title,
          type: type,
          scrollController: scrollCtrl,
        ),
      ),
    ).then((_) => _loadData());
  }
}

class _SectionListSheet extends StatefulWidget {
  final AppDatabase db;
  final String title;
  final String type;
  final ScrollController scrollController;
  const _SectionListSheet({
    required this.db,
    required this.title,
    required this.type,
    required this.scrollController,
  });

  @override
  State<_SectionListSheet> createState() => _SectionListSheetState();
}

class _SectionListSheetState extends State<_SectionListSheet> {
  List<Map<String, dynamic>> _items = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      if (widget.type == 'vacations') {
        final rows = await widget.db.customSelect('''
          SELECT v.id, v.staff_id, v.vacation_type, v.start_date, v.end_date,
                 v.total_days, v.status, s.name as staff_name
          FROM vacations v
          LEFT JOIN staff s ON v.staff_id = s.staff_id
          WHERE v.status = 'pending'
          ORDER BY v.created_at DESC
        ''').get();
        _items = rows.map((r) => {
          'id': r.read<int>('id'),
          'staff_name': r.read<String?>('staff_name') ?? '',
          'details':
              '${r.read<String>('vacation_type')} - ${r.read<int>('total_days')} يوم',
        }).toList();
      } else {
        final rows = await widget.db.customSelect('''
          SELECT a.id, a.staff_id, a.amount, a.status, a.request_date,
                 s.name as staff_name
          FROM staff_advances a
          LEFT JOIN staff s ON a.staff_id = s.staff_id
          WHERE a.status IN ('pending', 'approved')
          ORDER BY a.created_at DESC
        ''').get();
        _items = rows.map((r) => {
          'id': r.read<int>('id'),
          'staff_name': r.read<String?>('staff_name') ?? '',
          'details': '${r.read<double>('amount').toStringAsFixed(0)} ج.م',
        }).toList();
      }
      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Icon(
                widget.type == 'vacations'
                    ? Icons.beach_access
                    : Icons.money_off,
                color: widget.type == 'vacations'
                    ? Colors.orange
                    : Colors.redAccent,
              ),
              const SizedBox(width: 8),
              Text(
                widget.title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _items.isEmpty
                  ? const Center(child: Text('لا توجد بيانات'))
                  : ListView.separated(
                      controller: widget.scrollController,
                      itemCount: _items.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final item = _items[i];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: widget.type == 'vacations'
                                ? Colors.orange.withValues(alpha: 0.2)
                                : Colors.redAccent.withValues(alpha: 0.2),
                            child: Icon(
                              widget.type == 'vacations'
                                  ? Icons.beach_access
                                  : Icons.money_off,
                              color: widget.type == 'vacations'
                                  ? Colors.orange
                                  : Colors.redAccent,
                              size: 20,
                            ),
                          ),
                          title: Text(item['staff_name'] as String),
                          subtitle: Text(item['details'] as String),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}
