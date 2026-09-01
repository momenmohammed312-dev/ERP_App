import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/database/app_database.dart';
import '../../core/provider/app_database_provider.dart';
import '../../core/provider/auth_provider.dart';
import '../../core/database/dao/staff_management_dao.dart';
import '../../core/models/user_model.dart';
import '../../widgets/permission_guard.dart';
import 'package:intl/intl.dart';
import 'manual_override_dialog.dart';
import 'services/staff_attendance_report_generator.dart';

class AttendancePage extends ConsumerStatefulWidget {
  final Staff staff;

  const AttendancePage({super.key, required this.staff});

  @override
  ConsumerState<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends ConsumerState<AttendancePage> {
  List<Attendance> _attendanceList = [];
  bool _isLoading = true;
  DateTime? _filterStart;
  DateTime? _filterEnd;
  double _latePerHour = 0; // مضاعف
  double _earlyPerHour = 0; // مضاعف
  double _absencePerDay = 0;
  int _grace = 15;
  String _workStart = '09:00';
  String _workEnd = '17:00';

  List<Attendance> get _filteredList {
    final base = (_filterStart == null || _filterEnd == null)
        ? _attendanceList
        : _attendanceList.where((r) {
            final d = DateTime(r.date.year, r.date.month, r.date.day);
            final s = DateTime(_filterStart!.year, _filterStart!.month, _filterStart!.day);
            final e = DateTime(_filterEnd!.year, _filterEnd!.month, _filterEnd!.day);
            return !d.isBefore(s) && !d.isAfter(e);
          }).toList();
    base.sort((a, b) => b.date.compareTo(a.date));
    return base;
  }

  @override
  void initState() {
    super.initState();
    _loadAttendance();
  }

  Future<void> _loadAttendance() async {
    setState(() => _isLoading = true);
    final db = ref.read(appDatabaseProvider);
    final dao = StaffManagementDao(db);
    try {
      final attendance = await dao.getAttendanceByStaff(widget.staff.staffId);
      // تحميل إعدادات الخصم للملخص
      try {
        final settings = await db.select(db.attendanceSettings).get();
        for (final s in settings) {
          if (s.settingKey == 'late_penalty_per_hour') _latePerHour = double.tryParse(s.settingValue) ?? 0;
          if (s.settingKey == 'early_leave_penalty_per_hour') _earlyPerHour = double.tryParse(s.settingValue) ?? 0;
          if (s.settingKey == 'absence_penalty_amount') _absencePerDay = double.tryParse(s.settingValue) ?? 0;
          if (s.settingKey == 'grace_period_minutes') _grace = int.tryParse(s.settingValue) ?? 15;
          if (s.settingKey == 'default_work_start') _workStart = s.settingValue;
          if (s.settingKey == 'default_work_end') _workEnd = s.settingValue;
        }
      } catch (_) {}
      attendance.sort((a, b) => b.date.compareTo(a.date));
      setState(() {
        _attendanceList = attendance;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('خطأ في تحميل سجل الحضور')));
    }
  }

  Future<void> _pickFilterRange() async {
    final now = DateTime.now();
    final first = await showDatePicker(context: context, initialDate: _filterStart ?? now, firstDate: DateTime(2020), lastDate: DateTime(2030));
    if (first == null) return;
    if (!mounted) return;
    final last = await showDatePicker(context: context, initialDate: _filterEnd ?? first, firstDate: first, lastDate: DateTime(2030));
    if (last == null) return;
    setState(() {
      _filterStart = first;
      _filterEnd = last;
    });
  }

  Future<void> _editRecord(Attendance record) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => ManualOverrideDialog(staff: widget.staff),
    );
    if (result == true) _loadAttendance();
  }

  Future<void> _deleteAllImported() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف كل الحضور المستورد'),
        content: Text('متأكد تحذف كل سجلات ${widget.staff.name} المستوردة (source=import)؟ سيتم حذف أغسطس كله المستورد فقط.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white), child: const Text('حذف الكل')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _isChecking = true);
    try {
      final service = ref.read(staffManagementServiceProvider);
      final user = ref.read(authProvider);
      final count = await service.deleteImportedForStaff(user, widget.staff.staffId);
      await _loadAttendance();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم حذف $count سجل مستورد'), backgroundColor: Colors.green));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل الحذف: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  Future<void> _deleteDayRecord(Attendance record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف سجل الحضور'),
        content: Text(
          'متأكد إنك عايز تمسح سجل يوم ${DateFormat('yyyy/MM/dd', 'ar').format(record.date)} كلّه؟',
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
    if (confirmed != true || !mounted) return;
    setState(() => _isChecking = true);
    try {
      final service = ref.read(staffManagementServiceProvider);
      final user = ref.read(authProvider);
      await service.deleteAttendanceDay(
        user,
        widget.staff.staffId,
        record.date,
      );
      await _loadAttendance();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حذف سجل اليوم'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل حذف السجل: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  Future<void> _printReport() async {
    final db = ref.read(appDatabaseProvider);
    final list = _filteredList;
    if (list.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا يوجد بيانات للطباعة')));
      return;
    }
    try {
      await StaffAttendanceReportGenerator.generateAndPrint(db: db, staff: widget.staff, records: list, startDate: _filterStart, endDate: _filterEnd);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ طباعة: $e')));
    }
  }

  bool _isChecking = false;

  Future<void> _showManualEntryDialog() async {
    DateTime selectedDate = DateTime.now();
    TimeOfDay checkInTime = TimeOfDay.now();
    TimeOfDay? checkOutTime;
    String status = 'present';
    String notes = '';
    final statusOptions = ['present', 'absent', 'late', 'leave'];
    final statusLabels = ['حاضر', 'غائب', 'متأخر', 'إجازة'];

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) {
        DateTime date = selectedDate;
        TimeOfDay inTime = checkInTime;
        TimeOfDay? outTime = checkOutTime;
        String selStatus = status;
        final noteCtrl = TextEditingController(text: notes);
        final formKey = GlobalKey<FormState>();

        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('تسجيل حضور يدوي'),
            content: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      title: const Text('التاريخ'),
                      subtitle: Text(
                        DateFormat('yyyy/MM/dd - EEEE', 'ar').format(date),
                      ),
                      trailing: const Icon(Icons.calendar_today),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: date,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2030),
                        );
                        if (picked != null) {
                          setDialogState(() => date = picked);
                        }
                      },
                    ),
                    const Divider(),
                    ListTile(
                      title: const Text('وقت الحضور'),
                      subtitle: Text(inTime.format(context)),
                      trailing: const Icon(Icons.access_time),
                      onTap: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: inTime,
                        );
                        if (picked != null) {
                          setDialogState(() => inTime = picked);
                        }
                      },
                    ),
                    const Divider(),
                    ListTile(
                      title: const Text('وقت الانصراف (اختياري)'),
                      subtitle: Text(
                        outTime?.format(context) ?? 'لم يتم التسجيل',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (outTime != null)
                            IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () =>
                                  setDialogState(() => outTime = null),
                            ),
                          const Icon(Icons.access_time),
                        ],
                      ),
                      onTap: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: outTime ?? TimeOfDay.now(),
                        );
                        if (picked != null) {
                          setDialogState(() => outTime = picked);
                        }
                      },
                    ),
                    const Divider(),
                    DropdownButtonFormField<String>(
                      initialValue: selStatus,
                      decoration: const InputDecoration(
                        labelText: 'الحالة',
                        border: OutlineInputBorder(),
                      ),
                      items: List.generate(statusOptions.length, (i) {
                        return DropdownMenuItem(
                          value: statusOptions[i],
                          child: Text(statusLabels[i]),
                        );
                      }),
                      onChanged: (v) {
                        if (v != null) setDialogState(() => selStatus = v);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: noteCtrl,
                      decoration: const InputDecoration(
                        labelText: 'ملاحظات',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 8),
                    if (outTime != null)
                      Text(
                        'إجمالي ساعات العمل: ${_calcHours(inTime, outTime!)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blueGrey,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (formKey.currentState!.validate()) {
                    final service = ref.read(staffManagementServiceProvider);
                    final alreadyRecorded = await service.hasAttendanceOnDate(
                      widget.staff.staffId,
                      date,
                    );
                    if (!ctx.mounted) return;
                    if (alreadyRecorded) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'مينفعش تسجيل يدوي مكرر لنفس اليوم — عشان تعدّل يوم متسجل استخدم (تعديل مراقب)',
                          ),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }
                    Navigator.pop(ctx, {
                      'date': date,
                      'checkIn': inTime,
                      'checkOut': outTime,
                      'status': selStatus,
                      'notes': noteCtrl.text.trim(),
                    });
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueGrey,
                  foregroundColor: Colors.white,
                ),
                child: const Text('حفظ'),
              ),
            ],
          ),
        );
      },
    );

    if (result != null) {
      setState(() => _isChecking = true);
      try {
        final dt = result['date'] as DateTime;
        final ci = result['checkIn'] as TimeOfDay;
        final co = result['checkOut'] as TimeOfDay?;
        final st = result['status'] as String;
        final nt = result['notes'] as String;

        final checkInDateTime = DateTime(
          dt.year, dt.month, dt.day, ci.hour, ci.minute,
        );
        DateTime? checkOutDateTime;
        double? workingHours;

        if (co != null) {
          checkOutDateTime = DateTime(
            dt.year, dt.month, dt.day, co.hour, co.minute,
          );
          if (checkOutDateTime.isBefore(checkInDateTime)) {
            checkOutDateTime = checkOutDateTime.add(const Duration(days: 1));
          }
          workingHours =
              checkOutDateTime.difference(checkInDateTime).inMinutes / 60.0;
        }

        final service = ref.read(staffManagementServiceProvider);
        await service.recordManualAttendance(
          widget.staff.staffId,
          date: dt,
          status: st,
          checkInTime: checkInDateTime,
          checkOutTime: checkOutDateTime,
          workingHours: workingHours,
          notes: nt.isNotEmpty ? nt : null,
          source: 'manual',
        );
        await _loadAttendance();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم تسجيل الحضور يدوياً'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('خطأ في حفظ الحضور'), backgroundColor: Colors.red),
          );
        }
      } finally {
        if (mounted) setState(() => _isChecking = false);
      }
    }
  }

  String _calcHours(TimeOfDay start, TimeOfDay end) {
    final startMin = start.hour * 60 + start.minute;
    final endMin = end.hour * 60 + end.minute;
    final diff = endMin >= startMin ? endMin - startMin : endMin + 1440 - startMin;
    final h = diff ~/ 60;
    final m = diff % 60;
    return '${h}h ${m.toString().padLeft(2, '0')}m';
  }

  Future<void> _checkIn() async {
    setState(() => _isChecking = true);
    try {
      final service = ref.read(staffManagementServiceProvider);
      final recorded = await service.recordCheckInTodayOnce(
        widget.staff.staffId,
      );
      if (!mounted) return;
      if (!recorded) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('مينفعش تسجيل حضور تاني لنفس اليوم، اتسجل من قبل'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      await _loadAttendance();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم تسجيل الحضور'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('فشل تسجيل الحضور'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  Future<void> _checkOut() async {
    setState(() => _isChecking = true);
    try {
      final service = ref.read(staffManagementServiceProvider);
      final success = await service.recordCheckOut(widget.staff.staffId, source: 'manual');
      if (!mounted) return;
      if (!success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('لم يتم العثور على سجل حضور اليوم'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      await _loadAttendance();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم تسجيل الانصراف'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('فشل تسجيل الانصراف'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGuard(
      permission: Permission.viewAttendance,
      child: Scaffold(
        appBar: AppBar(
          title: Text('سجل الحضور: ${widget.staff.name}'),
        actions: [
          ElevatedButton.icon(
            onPressed: _isChecking ? null : _checkIn,
            icon: const Icon(Icons.login, size: 18),
            label: const Text('تسجيل حضور'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
          const SizedBox(width: 4),
          ElevatedButton.icon(
            onPressed: _isChecking ? null : _checkOut,
            icon: const Icon(Icons.logout, size: 18),
            label: const Text('تسجيل انصراف'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
          const SizedBox(width: 4),
          ElevatedButton.icon(
            onPressed: _isChecking ? null : _showManualEntryDialog,
            icon: const Icon(Icons.edit_calendar, size: 18),
            label: const Text('تسجيل يدوي'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueGrey,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
          const SizedBox(width: 4),
          ElevatedButton.icon(
            onPressed: _isChecking ? null : () async {
              final result = await showDialog<bool>(
                context: context,
                builder: (_) => ManualOverrideDialog(staff: widget.staff),
              );
              if (result == true) {
                _loadAttendance();
              }
            },
            icon: const Icon(Icons.admin_panel_settings, size: 18),
            label: const Text('تعديل مراقب'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
          const SizedBox(width: 4),
          ElevatedButton.icon(
            onPressed: _printReport,
            icon: const Icon(Icons.print, size: 18),
            label: const Text('طباعة التقرير'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 12)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              _buildFilterBar(),
              _buildSummaryCards(),
              Expanded(child: _filteredList.isEmpty ? _buildEmptyState() : _buildAttendanceList()),
            ]),
      ),
    );
  }

  Widget _buildFilterBar() {
    final hasFilter = _filterStart != null && _filterEnd != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(children: [
        ElevatedButton.icon(onPressed: _pickFilterRange, icon: const Icon(Icons.date_range, size: 16), label: Text(hasFilter ? '${DateFormat('yyyy/MM/dd').format(_filterStart!)} - ${DateFormat('yyyy/MM/dd').format(_filterEnd!)}' : 'اختيار الفترة')),
        const SizedBox(width: 8),
        if (hasFilter) TextButton(onPressed: () => setState(() { _filterStart = null; _filterEnd = null; }), child: const Text('مسح الفلتر')),
        const Spacer(),
        IconButton(icon: const Icon(Icons.delete_sweep, color: Colors.red), tooltip: 'حذف كل المستورد لهذا الموظف', onPressed: _deleteAllImported),
        Text('${_filteredList.length} سجل', style: TextStyle(color: Colors.grey[600])),
      ]),
    );
  }

  Widget _buildSummaryCards() {
    final list = _filteredList;
    final absent = list.where((r) => r.status == 'absent').length;
    final lateCount = list.where((r) => r.status == 'late').length;
    int totalLateMin = 0;
    int totalEarlyMin = 0;
    int sMin = 540; int eMin = 1020;
    try { final p = _workStart.split(':'); sMin = (int.tryParse(p[0]) ?? 9)*60 + (int.tryParse(p[1]) ?? 0); } catch(_){}
    try { final p = _workEnd.split(':'); eMin = (int.tryParse(p[0]) ?? 17)*60 + (int.tryParse(p[1]) ?? 0); } catch(_){}
    final gEnd = sMin + _grace;
    for (final r in list) {
      if (r.status == 'late' && r.checkInTime != null) { final ci = r.checkInTime!.hour*60 + r.checkInTime!.minute; if (ci > gEnd) totalLateMin += ci - gEnd; }
      if (r.checkOutTime != null) { final co = r.checkOutTime!.hour*60 + r.checkOutTime!.minute; if (co < eMin) totalEarlyMin += eMin - co; }
    }
    final hourly = widget.staff.hourlyRate ?? (widget.staff.basicSalary / 160.0);
    double lateDed = _latePerHour > 0 ? (totalLateMin/60.0) * hourly * _latePerHour : 0;
    double earlyDed = _earlyPerHour > 0 ? (totalEarlyMin/60.0) * hourly * _earlyPerHour : 0;
    double absDed = absent * _absencePerDay;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(children: [
        Expanded(child: _summaryCard('غياب', '$absent يوم', Icons.person_off, Colors.red)),
        const SizedBox(width: 8),
        Expanded(child: _summaryCard('تأخير', '${totalLateMin ~/ 60}س ${totalLateMin % 60}د ($lateCount)', Icons.timer, Colors.amber)),
        const SizedBox(width: 8),
        Expanded(child: _summaryCard('بدري', '${totalEarlyMin ~/ 60}س ${totalEarlyMin % 60}د', Icons.logout, Colors.deepOrange)),
        const SizedBox(width: 8),
        Expanded(child: _summaryCard('خصومات', '${(lateDed+earlyDed+absDed).toStringAsFixed(0)} ج.م', Icons.money_off, Colors.orange)),
      ]),
    );
  }
  Widget _summaryCard(String t, String v, IconData ic, Color c) => Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(children: [Icon(ic, color: c, size: 20), const SizedBox(height: 4), Text(t, style: TextStyle(color: Colors.grey[600], fontSize: 12)), Text(v, style: const TextStyle(fontWeight: FontWeight.bold))])));

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.schedule, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            'لا يوجد سجل حضور لهذا الموظف',
            style: TextStyle(fontSize: 18, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceList() {
    final list = _filteredList;
    return ListView.builder(
      padding: const EdgeInsets.all(16.0),
      itemCount: list.length,
      itemBuilder: (context, index) {
        final record = list[index];
        return _buildAttendanceCard(record);
      },
    );
  }

  Widget _buildAttendanceCard(Attendance record) {
    final theme = Theme.of(context);
    final statusColor = _getStatusColor(record.status);

    return Card(
      margin: const EdgeInsets.only(bottom: 12.0),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DateFormat('EEEE, d MMMM yyyy', 'ar').format(record.date),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: statusColor),
                      ),
                      child: Text(
                        _getStatusText(record.status),
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                if (record.workingHours != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${record.workingHours!.toStringAsFixed(1)} ساعة',
                        style: TextStyle(
                          color: Colors.blue[700],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Text(
                        'ساعات العمل',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
              ],
            ),
            const Divider(height: 24),
            Row(
              children: [
                _buildTimeInfo(Icons.login, 'حضور', record.checkInTime),
                const Spacer(),
                _buildTimeInfo(Icons.logout, 'انصراف', record.checkOutTime),
                IconButton(icon: const Icon(Icons.edit, size: 18), tooltip: 'تعديل', onPressed: () => _editRecord(record)),
                PermissionGuard(
                  permission: Permission.manageAttendance,
                  showUpgradePrompt: false,
                  child: IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    tooltip: 'حذف سجل اليوم',
                    onPressed: () => _deleteDayRecord(record),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeInfo(IconData icon, String label, DateTime? time) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            Text(
              time != null ? DateFormat('hh:mm a').format(time) : '--:--',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ],
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'present':
        return Colors.green;
      case 'absent':
        return Colors.red;
      case 'leave':
        return Colors.orange;
      case 'late':
        return Colors.amber;
      default:
        return Colors.grey;
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'present':
        return 'حاضر';
      case 'absent':
        return 'غائب';
      case 'leave':
        return 'إجازة';
      case 'late':
        return 'متأخر';
      default:
        return status;
    }
  }
}
