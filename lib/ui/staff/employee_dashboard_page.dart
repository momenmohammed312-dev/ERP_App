import '../../core/platform/platform_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import '../../core/database/app_database.dart';
import '../../core/provider/app_database_provider.dart';
import '../../core/database/dao/staff_management_dao.dart';
import '../../core/theme/madar_colors.dart';
import 'staff_list_page.dart';
import 'staff_form_page.dart';
import 'device_management_page.dart';
import 'unmatched_attendance_page.dart';
import 'attendance_settings_page.dart';
import 'batch_payroll_slips_page.dart';

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
  int _excusedToday = 0;
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
    // تصفير العدادات قبل إعادة التحميل — عشان لو اليوم مفيش حالات "حاضر" مثلاً مايفضلش رقم قديم
    _presentToday = 0;
    _absentToday = 0;
    _lateToday = 0;
    _excusedToday = 0;
    _onLeaveToday = 0;
    _pendingVacations = 0;
    _pendingAdvancesTotal = 0;
    try {
      final allStaff = await _dao.getAllStaff();
      _activeStaff = allStaff.where((s) => s.isActive).length;
      _totalSalary = allStaff.fold<double>(0, (s, e) => s + e.basicSalary);

      final today = DateTime.now();
      final todayStart = DateTime(today.year, today.month, today.day);

      final attendanceRows = await _db.customSelect('''
        SELECT status, COUNT(*) as cnt FROM attendance_table
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
            _presentToday += cnt;
            break;
          case 'excused':
          case 'excused_late':
            _excusedToday += cnt;
            _presentToday += cnt;
            break;
          case 'absent':
            _absentToday = cnt;
            break;
          case 'late':
            _lateToday = cnt;
            break;
          case 'leave':
            _onLeaveToday = cnt;
            break;
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
        final rawTotal = advanceRows.first.data['total'];
        _pendingAdvancesTotal = rawTotal is num ? rawTotal.toDouble() : 0.0;
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
    final isDark = context.isDarkMode;
    final bgColor = context.bgCanvas;
    final cardBg = context.bgCard;
    final textColor = context.textPrimary;
    final subTextColor = context.textSecondary;
    final accentColor = context.primaryColor;
    final borderColor = context.borderColor;

    return Scaffold(
      backgroundColor: bgColor,
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: accentColor))
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                children: [
                  // Modern integrated header replacing redundant AppBar
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? cardBg
                                  : MadarColors.lightBabyBlueContainer,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isDark
                                    ? borderColor
                                    : MadarColors.lightBorder,
                              ),
                            ),
                            child: Icon(
                              Icons.badge_outlined,
                              size: 20,
                              color: isDark ? accentColor : MadarColors.lightPrimary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'لوحة متابعة الموظفين',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: textColor,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        color: subTextColor,
                        onPressed: _loadData,
                        tooltip: 'تحديث البيانات',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildSectionHeader(textColor, 'ملخص عام', Icons.dashboard_outlined),
                  const SizedBox(height: 12),
                  _buildSummaryGrid(
                    textColor, subTextColor, accentColor, cardBg, borderColor, isDark),
                  const SizedBox(height: 20),
                  _buildSectionHeader(
                    textColor, 'حضور اليوم', Icons.calendar_today_outlined),
                  const SizedBox(height: 12),
                  _buildAttendanceCards(cardBg, borderColor, isDark),
                  const SizedBox(height: 20),
                  _buildSectionHeader(
                    textColor, 'إجراءات سريعة', Icons.bolt_outlined),
                  const SizedBox(height: 12),
                  _buildQuickActions(
                    textColor, accentColor, subTextColor, cardBg, borderColor),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionHeader(Color textColor, String title, IconData icon) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = isDark ? MadarColors.gold : MadarColors.lightPrimary;

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: primary.withValues(alpha: 0.25),
              width: 1,
            ),
          ),
          child: Icon(icon, size: 18, color: primary),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: textColor,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryGrid(
    Color textColor,
    Color subTextColor,
    Color accentColor,
    Color cardBg,
    Color borderColor,
    bool isDark,
  ) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                '$_activeStaff',
                'موظفين نشطين',
                Colors.green,
                Icons.people_alt_outlined,
                cardBg,
                borderColor,
                textColor,
                subTextColor,
                isDark,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricCard(
                '$_pendingVacations',
                'إجازات معلقة',
                Colors.orange,
                Icons.beach_access_outlined,
                cardBg,
                borderColor,
                textColor,
                subTextColor,
                isDark,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                '${_pendingAdvancesTotal.toStringAsFixed(0)} ج.م',
                'سلف معلقة',
                Colors.redAccent,
                Icons.payments_outlined,
                cardBg,
                borderColor,
                textColor,
                subTextColor,
                isDark,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricCard(
                '${_totalSalary.toStringAsFixed(0)} ج.م',
                'إجمالي المرتبات',
                accentColor,
                Icons.account_balance_wallet_outlined,
                cardBg,
                borderColor,
                textColor,
                subTextColor,
                isDark,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMetricCard(
    String value,
    String label,
    Color color,
    IconData icon,
    Color cardBg,
    Color borderColor,
    Color textColor,
    Color subTextColor,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? borderColor.withValues(alpha: 0.6)
              : MadarColors.lightBorder,
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.15)
                : const Color(0x0A0066FF),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: subTextColor,
                  ),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: textColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceCards(Color cardBg, Color borderColor, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? borderColor.withValues(alpha: 0.6)
              : MadarColors.lightBorder,
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.15)
                : const Color(0x0A0066FF),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          _buildAttendanceStat('$_presentToday', 'حاضر', const Color(0xFF0284C7), Icons.check_circle_outline),
          const SizedBox(width: 6),
          _buildAttendanceStat('$_absentToday', 'غائب', const Color(0xFFEF4444), Icons.cancel_outlined),
          const SizedBox(width: 6),
          _buildAttendanceStat('$_lateToday', 'متأخر', const Color(0xFFF59E0B), Icons.access_time),
          const SizedBox(width: 6),
          _buildAttendanceStat('$_excusedToday', 'إذن', const Color(0xFF10B981), Icons.assignment_outlined),
          const SizedBox(width: 6),
          _buildAttendanceStat('$_onLeaveToday', 'إجازة', const Color(0xFF0066FF), Icons.beach_access_outlined),
        ],
      ),
    );
  }

  Widget _buildAttendanceStat(String count, String label, Color color, IconData icon) {
    final isMobile = PlatformUtils.isMobile;
    return Expanded(
      child: Container(
        padding: EdgeInsets.symmetric(vertical: isMobile ? 5 : 8, horizontal: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(isMobile ? 8 : 10),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: isMobile ? 13 : 16, color: color),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                count,
                style: TextStyle(
                  fontSize: isMobile ? 13 : 16,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: isMobile ? 9.5 : 10,
                fontWeight: FontWeight.w600,
                color: color.withValues(alpha: 0.9),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions(Color textColor, Color goldColor,
      Color subTextColor, Color cardBg, Color borderColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildActionBtn(
                  'الموظفين',
                  Icons.people_alt_outlined,
                  goldColor,
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const StaffListPage(),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildActionBtn(
                  'إضافة موظف',
                  Icons.person_add_alt_1_outlined,
                  const Color(0xFF238636),
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
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildActionBtn(
                  'الإجازات ($_pendingVacations)',
                  Icons.beach_access_outlined,
                  const Color(0xFFD29922),
                  () => _showSectionList('إجازات معلقة', 'vacations'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildActionBtn(
                  'السلف',
                  Icons.payments_outlined,
                  const Color(0xFFF85149),
                  () => _showSectionList('سلف معلقة', 'advances'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildActionBtn(
                  'أجهزة البصمة',
                  Icons.fingerprint_rounded,
                  const Color(0xFF388BFD),
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const DeviceManagementPage(),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildActionBtn(
                  'حركات معلقة',
                  Icons.warning_amber_rounded,
                  Colors.orangeAccent,
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const UnmatchedAttendancePage(),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildActionBtn(
                  'إعدادات الحضور',
                  Icons.settings_outlined,
                  const Color(0xFF10B981),
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AttendanceSettingsPage(),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildActionBtn(
                  'المرتبات',
                  Icons.receipt_long_outlined,
                  const Color(0xFF8B5CF6),
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const BatchPayrollSlipsPage(),
                    ),
                  ),
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
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
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
          LEFT JOIN staff_table s ON v.staff_id = s.staff_id
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
          LEFT JOIN staff_table s ON a.staff_id = s.staff_id
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
