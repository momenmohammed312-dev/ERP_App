import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/database/app_database.dart';
import '../../core/provider/app_database_provider.dart';
import '../../core/database/dao/staff_management_dao.dart';
import '../../core/models/user_model.dart';
import '../../core/provider/auth_provider.dart';
import '../../widgets/permission_guard.dart';
import 'package:intl/intl.dart';
import 'manual_override_dialog.dart';

class AttendancePage extends ConsumerStatefulWidget {
  final Staff staff;

  const AttendancePage({super.key, required this.staff});

  @override
  ConsumerState<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends ConsumerState<AttendancePage> {
  List<Attendance> _attendanceList = [];
  bool _isLoading = true;

  double _absencePenalty = 0.0;

  // ── restored from 81ad48a: schedule snapshot for late-minutes math ──
  int _graceMinutes = 15;
  String _workStart = '09:00';
  String _workEnd = '17:00';

  // ── restored from 81ad48a: active rewards/penalties affect deductions ──
  double _penaltiesTotal = 0.0;
  List<String> _penaltyTitles = [];

  // ── restored from 81ad48a: absence multiplier setting ──
  double _absenceMultiplier = 1.0;

  String _dateFilter = 'all'; // 'all', 'today', 'this_week', 'this_month', 'custom'
  DateTimeRange? _customDateRange;
  String _statusFilter = 'all'; // 'all', 'present', 'late', 'excused', 'absent', 'leave'

  List<Attendance> get _filteredAttendanceList {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return _attendanceList.where((r) {
      // 1. Date filter
      final rDate = DateTime(r.date.year, r.date.month, r.date.day);
      if (_dateFilter == 'today') {
        if (!rDate.isAtSameMomentAs(today)) return false;
      } else if (_dateFilter == 'this_week') {
        final startOfWeek = today.subtract(Duration(days: today.weekday % 7));
        final endOfWeek = startOfWeek.add(const Duration(days: 6));
        if (rDate.isBefore(startOfWeek) || rDate.isAfter(endOfWeek)) return false;
      } else if (_dateFilter == 'this_month') {
        if (rDate.year != now.year || rDate.month != now.month) return false;
      } else if (_dateFilter == 'custom' && _customDateRange != null) {
        final start = DateTime(
          _customDateRange!.start.year,
          _customDateRange!.start.month,
          _customDateRange!.start.day,
        );
        final end = DateTime(
          _customDateRange!.end.year,
          _customDateRange!.end.month,
          _customDateRange!.end.day,
        );
        if (rDate.isBefore(start) || rDate.isAfter(end)) return false;
      }

      // 2. Status filter
      if (_statusFilter != 'all') {
        if (_statusFilter == 'excused') {
          if (r.status != 'excused' && r.status != 'excused_late') return false;
        } else if (r.status != _statusFilter) {
          return false;
        }
      }

      return true;
    }).toList();
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

      double absPen = 0.0;
      int grace = 15;
      String workStart = '09:00';
      String workEnd = '17:00';
      double absenceMult = 1.0;
      try {
        final absRow = await (db.select(db.attendanceSettings)
              ..where((t) => t.settingKey.equals('absence_penalty_amount')))
            .getSingleOrNull();
        if (absRow != null) {
          absPen = double.tryParse(absRow.settingValue) ?? 0.0;
        }
        // restored from 81ad48a: schedule snapshot (defaults → staff override)
        final settings = await db.select(db.attendanceSettings).get();
        for (final s in settings) {
          if (s.settingKey == 'grace_period_minutes') {
            grace = int.tryParse(s.settingValue) ?? 15;
          } else if (s.settingKey == 'default_work_start' &&
              s.settingValue.isNotEmpty) {
            workStart = s.settingValue;
          } else if (s.settingKey == 'default_work_end' &&
              s.settingValue.isNotEmpty) {
            workEnd = s.settingValue;
          } else if (s.settingKey == 'absence_penalty_days_multiplier') {
            absenceMult = double.tryParse(s.settingValue) ?? 1.0;
          }
        }
      } catch (_) {}

      if (!widget.staff.useDefaultSchedule) {
        if (widget.staff.workScheduleStart != null &&
            widget.staff.workScheduleStart!.isNotEmpty) {
          workStart = widget.staff.workScheduleStart!;
        }
        if (widget.staff.workScheduleEnd != null &&
            widget.staff.workScheduleEnd!.isNotEmpty) {
          workEnd = widget.staff.workScheduleEnd!;
        }
      }

      // restored from 81ad48a: active penalties feed the deductions card
      double penaltiesTotal = 0.0;
      List<String> penaltyTitles = [];
      try {
        final rows = await (db.select(db.rewardsPenalties)
              ..where((t) => t.staffId.equals(widget.staff.staffId))
              ..where((t) => t.status.equals('active'))
              ..where((t) => t.type.equals('penalty')))
            .get();
        for (final r in rows) {
          penaltiesTotal += r.amount ?? 0.0;
          penaltyTitles.add(
            '${r.title} (${((r.amount ?? 0.0)).toStringAsFixed(0)} ج.م)',
          );
        }
      } catch (_) {}

      setState(() {
        _attendanceList = attendance.reversed.toList();
        _absencePenalty = absPen;
        _graceMinutes = grace;
        _workStart = workStart;
        _workEnd = workEnd;
        _absenceMultiplier = absenceMult;
        _penaltiesTotal = penaltiesTotal;
        _penaltyTitles = penaltyTitles;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('خطأ في تحميل سجل الحضور: $e')));
    }
  }

  bool _isChecking = false;

  Future<void> _showManualEntryDialog([Attendance? initialRecord]) async {
    final statusOptions = [
      'present',
      'absent',
      'late',
      'leave',
      'excused',
      'excused_late',
    ];
    final statusLabels = [
      'حاضر',
      'غائب',
      'متأخر',
      'إجازة',
      'إذن (معفي)',
      'متأخر بإذن',
    ];

    DateTime selectedDate = initialRecord?.date ?? DateTime.now();
    TimeOfDay? checkInTime = initialRecord != null
        ? (initialRecord.checkInTime != null
            ? TimeOfDay.fromDateTime(initialRecord.checkInTime!)
            : null)
        : TimeOfDay.now();
    TimeOfDay? checkOutTime = initialRecord?.checkOutTime != null
        ? TimeOfDay.fromDateTime(initialRecord!.checkOutTime!)
        : null;
    String status = (initialRecord != null &&
            statusOptions.contains(initialRecord.status))
        ? initialRecord.status
        : 'present';
    String notes = initialRecord?.notes ?? '';
    String? initialLeaveType = initialRecord?.leaveType;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) {
        DateTime date = selectedDate;
        TimeOfDay? inTime = checkInTime;
        TimeOfDay? outTime = checkOutTime;
        String selStatus = status;
        String selLeaveType = initialLeaveType ?? 'personal';
        bool isHourlyExcuse = false;
        TimeOfDay? excuseFromTime;
        TimeOfDay? excuseToTime;
        final noteCtrl = TextEditingController(text: notes);
        final formKey = GlobalKey<FormState>();

        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(initialRecord != null ? 'تعديل سجل حضور / إذن' : 'تسجيل حضور يدوي'),
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
                          lastDate: DateTime(2035),
                        );
                        if (picked != null) {
                          setDialogState(() => date = picked);
                        }
                      },
                    ),
                    const Divider(),
                    ListTile(
                      title: const Text('وقت الحضور'),
                      subtitle: Text(
                        inTime?.format(context) ?? 'لم يتم التسجيل (اختياري للإذن)',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (inTime != null)
                            IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              tooltip: 'مسح وقت الحضور',
                              onPressed: () =>
                                  setDialogState(() => inTime = null),
                            ),
                          const Icon(Icons.access_time),
                        ],
                      ),
                      onTap: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: inTime ?? TimeOfDay.now(),
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
                              tooltip: 'مسح وقت الانصراف',
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
                      value: selStatus,
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
                    if (selStatus == 'excused' || selStatus == 'excused_late') ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: (selStatus == 'excused' ? Colors.teal : Colors.deepOrange).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: (selStatus == 'excused' ? Colors.teal : Colors.deepOrange).withValues(alpha: 0.3),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  selStatus == 'excused' ? Icons.verified_user : Icons.schedule_outlined,
                                  size: 18,
                                  color: selStatus == 'excused' ? Colors.teal : Colors.deepOrange,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'تفاصيل الإذن والتصريح',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: selStatus == 'excused' ? Colors.teal : Colors.deepOrange,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            DropdownButtonFormField<String>(
                              value: selLeaveType,
                              decoration: const InputDecoration(
                                labelText: 'نوع الإذن',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              items: const [
                                DropdownMenuItem(value: 'personal', child: Text('إذن شخصي')),
                                DropdownMenuItem(value: 'mission', child: Text('مأمورية عمل رسمية')),
                                DropdownMenuItem(value: 'medical', child: Text('عذر طبي / كشف')),
                                DropdownMenuItem(value: 'emergency', child: Text('ظرف طارئ / عائلي')),
                                DropdownMenuItem(value: 'study', child: Text('دراسة / امتحانات')),
                                DropdownMenuItem(value: 'other', child: Text('إذن عام')),
                              ],
                              onChanged: (v) {
                                if (v != null) setDialogState(() => selLeaveType = v);
                              },
                            ),
                            const SizedBox(height: 10),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('إذن بساعات محددة', style: TextStyle(fontSize: 14)),
                              subtitle: Text(
                                isHourlyExcuse ? 'تحديد فترة الإذن بالوقت' : 'إذن يوم كامل معفي',
                                style: const TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                              value: isHourlyExcuse,
                              onChanged: (v) => setDialogState(() => isHourlyExcuse = v),
                            ),
                            if (isHourlyExcuse) ...[
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () async {
                                        final picked = await showTimePicker(
                                          context: context,
                                          initialTime: excuseFromTime ?? const TimeOfDay(hour: 9, minute: 0),
                                        );
                                        if (picked != null) setDialogState(() => excuseFromTime = picked);
                                      },
                                      icon: const Icon(Icons.access_time, size: 16),
                                      label: Text(
                                        excuseFromTime != null ? 'من: ${excuseFromTime!.format(context)}' : 'من الساعة',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () async {
                                        final picked = await showTimePicker(
                                          context: context,
                                          initialTime: excuseToTime ?? const TimeOfDay(hour: 12, minute: 0),
                                        );
                                        if (picked != null) setDialogState(() => excuseToTime = picked);
                                      },
                                      icon: const Icon(Icons.access_time_filled, size: 16),
                                      label: Text(
                                        excuseToTime != null ? 'إلى: ${excuseToTime!.format(context)}' : 'إلى الساعة',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (excuseFromTime != null && excuseToTime != null) ...[
                                const SizedBox(height: 6),
                                Text(
                                  'مدة الإذن: ${_calcHours(excuseFromTime!, excuseToTime!)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: selStatus == 'excused' ? Colors.teal : Colors.deepOrange,
                                  ),
                                ),
                              ],
                            ],
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: noteCtrl,
                      decoration: InputDecoration(
                        labelText: (selStatus == 'excused' || selStatus == 'excused_late')
                            ? 'سبب / ملاحظات الإذن'
                            : 'ملاحظات',
                        border: const OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 8),
                    if (inTime != null && outTime != null)
                      Text(
                        'إجمالي ساعات العمل: ${_calcHours(inTime!, outTime!)}',
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
                onPressed: () {
                  if (formKey.currentState!.validate()) {
                    String userNotes = noteCtrl.text.trim();
                    String? excuseType;
                    if (selStatus == 'excused' || selStatus == 'excused_late') {
                      excuseType = selLeaveType;
                      final typeName = _getExcuseTypeTitle(selLeaveType);
                      String timing = '';
                      if (isHourlyExcuse && excuseFromTime != null && excuseToTime != null) {
                        timing = 'من ${excuseFromTime!.format(context)} إلى ${excuseToTime!.format(context)}';
                      } else if (!isHourlyExcuse) {
                        timing = 'يوم كامل معفي';
                      }
                      if (timing.isNotEmpty) {
                        userNotes = userNotes.isNotEmpty ? '[$typeName - $timing] $userNotes' : '[$typeName - $timing]';
                      } else {
                        userNotes = userNotes.isNotEmpty ? '[$typeName] $userNotes' : '[$typeName]';
                      }
                    }

                    Navigator.pop(ctx, {
                      'date': date,
                      'checkIn': inTime,
                      'checkOut': outTime,
                      'status': selStatus,
                      'notes': userNotes,
                      'leaveType': excuseType,
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
        final ci = result['checkIn'] as TimeOfDay?;
        final co = result['checkOut'] as TimeOfDay?;
        final st = result['status'] as String;
        final nt = result['notes'] as String;
        final lt = result['leaveType'] as String?;

        DateTime? checkInDateTime;
        if (ci != null) {
          checkInDateTime = DateTime(
            dt.year, dt.month, dt.day, ci.hour, ci.minute,
          );
        }

        DateTime? checkOutDateTime;
        double? workingHours;

        if (co != null) {
          checkOutDateTime = DateTime(
            dt.year, dt.month, dt.day, co.hour, co.minute,
          );
          if (checkInDateTime != null) {
            if (checkOutDateTime.isBefore(checkInDateTime)) {
              checkOutDateTime = checkOutDateTime.add(const Duration(days: 1));
            }
            workingHours =
                checkOutDateTime.difference(checkInDateTime).inMinutes / 60.0;
          }
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
          leaveType: lt,
          source: 'manual',
        );
        await _loadAttendance();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(initialRecord != null
                  ? 'تم تحديث السجل بنجاح'
                  : 'تم تسجيل الحضور يدوياً'),
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

  Future<void> _editRecord(Attendance record) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'تعديل سجل: ${DateFormat('yyyy/MM/dd - EEEE', 'ar').format(record.date)}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.blueGrey,
                  child: Icon(Icons.edit_calendar, color: Colors.white),
                ),
                title: const Text('تعديل يدوي / تسجيل إذن'),
                subtitle: const Text('تغيير الحالة إلى إذن، متأخر بإذن، حاضر، إلخ'),
                onTap: () => Navigator.pop(ctx, 'manual'),
              ),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.redAccent,
                  child: Icon(Icons.admin_panel_settings, color: Colors.white),
                ),
                title: const Text('تعديل مراقب رسمي'),
                subtitle: const Text('تعديل إداري مع توثيق سبب التعديل للمراقبين'),
                onTap: () => Navigator.pop(ctx, 'override'),
              ),
            ],
          ),
        ),
      ),
    );

    if (action == 'manual') {
      await _showManualEntryDialog(record);
    } else if (action == 'override') {
      if (!mounted) return;
      final result = await showDialog<bool>(
        context: context,
        builder: (_) => ManualOverrideDialog(
          staff: widget.staff,
          initialDate: record.date,
          initialStatus: record.status,
          initialCheckInTime: record.checkInTime,
          initialCheckOutTime: record.checkOutTime,
          initialNotes: record.notes,
          initialLeaveType: record.leaveType,
        ),
      );
      if (result == true) {
        _loadAttendance();
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
      await service.recordCheckIn(widget.staff.staffId, source: 'manual');
      if (!mounted) return;
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

  /// Restored from 81ad48a: recompute worked/overtime hours for the currently
  /// filtered range (fixes old rows whose overtime stayed zero). Skips
  /// admin overrides and days inside paid payroll periods — with confirm.
  Future<void> _recomputeOvertime() async {
    final list = _filteredAttendanceList
        .where((r) => r.checkInTime != null && r.checkOutTime != null)
        .toList();
    if (list.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد سجلات بأوقات في الفترة المعروضة')),
      );
      return;
    }
    final dates = list.map((r) => r.date).toList()..sort();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إعادة حساب الإضافي؟'),
        content: Text(
          'سيُعاد حساب ساعات العمل والإضافي لـ ${list.length} سجل\n'
          'من ${DateFormat('yyyy/MM/dd').format(dates.first)} إلى ${DateFormat('yyyy/MM/dd').format(dates.last)}\n'
          'حسب بداية/نهاية الدوام.\n\n'
          'تُستثنى التعديلات الإدارية وأيام المرتبات المدفوعة.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('إعادة حساب وتحديث'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _isChecking = true);
    try {
      final user = ref.read(authProvider);
      final service = ref.read(staffManagementServiceProvider);
      final result = await service.recomputeOvertimeForPeriod(
        user,
        widget.staff.staffId,
        dates.first,
        dates.last,
      );
      await _loadAttendance();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تمت إعادة حساب ${result.recomputed} سجل (تُخطي ${result.skipped})',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
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
            onPressed: _isChecking ? null : _recomputeOvertime,
            icon: const Icon(Icons.more_time, size: 18),
            label: const Text('إعادة حساب الإضافي'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildSummaryCards(),
                _buildFilterBar(),
                Expanded(
                  child: _filteredAttendanceList.isEmpty
                      ? _buildEmptyState()
                      : _buildAttendanceList(),
                ),
              ],
            ),
      ),
    );
  }

  // ── restored from 81ad48a: late math against schedule snapshot ──
  int _scheduleStartMinutes() {
    try {
      final p = _workStart.split(':');
      return (int.tryParse(p[0]) ?? 9) * 60 + (int.tryParse(p[1]) ?? 0);
    } catch (_) {
      return 9 * 60;
    }
  }

  int _scheduleEndMinutes() {
    try {
      final p = _workEnd.split(':');
      return (int.tryParse(p[0]) ?? 17) * 60 + (int.tryParse(p[1]) ?? 0);
    } catch (_) {
      return 17 * 60;
    }
  }

  bool _isLateEffective(Attendance r) {
    if (r.status == 'excused' || r.status == 'excused_late') return false;
    if (r.checkInTime == null) return r.status == 'late';
    final ci = r.checkInTime!.hour * 60 + r.checkInTime!.minute;
    final gEnd = _scheduleStartMinutes() + _graceMinutes;
    if (r.status == 'late') return true;
    if (r.status != 'present') return false;
    return ci > gEnd;
  }

  int _lateMinutesOf(Attendance r) {
    if (!_isLateEffective(r) || r.checkInTime == null) return 0;
    final ci = r.checkInTime!.hour * 60 + r.checkInTime!.minute;
    final gEnd = _scheduleStartMinutes() + _graceMinutes;
    if (ci <= gEnd) return 0;
    // القاعدة القديمة: التأخير من بداية الدوام شاملاً السماح
    return ci - _scheduleStartMinutes();
  }

  bool _isPermissionRecord(Attendance r) {
    if (r.status == 'excused' || r.status == 'excused_late') return true;
    // أذونات محفوظة كإجازة مع نوع إذن (شخصي/مأمورية/طبي/طارئ/...) تُحتسب إذناً
    if (r.status == 'leave' &&
        r.leaveType != null &&
        r.leaveType!.trim().isNotEmpty) {
      return true;
    }
    if (r.checkOutTime != null) {
      final co = r.checkOutTime!.hour * 60 + r.checkOutTime!.minute;
      if (co < _scheduleEndMinutes() &&
          (r.status == 'present' || r.status == 'late')) {
        return true;
      }
    }
    return false;
  }

  String _formatHM(int totalMinutes) {
    return '${totalMinutes ~/ 60}س ${totalMinutes % 60}د';
  }

  // Restored from 81ad48a (via PayrollDisplay): hourly rate for deduction
  // previews — explicit hourlyRate first, else base ÷ divisor ÷ 8 where the
  // divisor is 6 for weekly staff and 30 otherwise.
  double _hourlyRate() {
    if (widget.staff.hourlyRate != null) return widget.staff.hourlyRate!;
    final divisor = widget.staff.employmentType == 'weekly' ? 6.0 : 30.0;
    if (divisor <= 0) return 0.0;
    return widget.staff.basicSalary / divisor / 8.0;
  }

  // Restored from 81ad48a: early-leave minutes (checkout before schedule
  // end). Fully excused rows (excused/excused_late/leave-with-type) are
  // exempt and accrue nothing.
  int _earlyMinutesOf(Attendance r) {
    if (r.checkOutTime == null) return 0;
    if (r.status == 'excused' ||
        r.status == 'excused_late' ||
        r.status == 'leave' ||
        r.status == 'absent') {
      return 0;
    }
    final co = r.checkOutTime!.hour * 60 + r.checkOutTime!.minute;
    final end = _scheduleEndMinutes();
    if (co >= end) return 0;
    return end - co;
  }

  Widget _buildSummaryCards() {
    final list = _filteredAttendanceList;
    final absentDays = list.where((r) => r.status == 'absent').length;
    final lateRecords = list.where(_isLateEffective).toList();
    final lateDays = lateRecords.length;
    final totalLateMinutes =
        lateRecords.fold<int>(0, (s, r) => s + _lateMinutesOf(r));
    final permissionRecords = list.where(_isPermissionRecord).toList();
    final excusedDays = list
        .where((r) => r.status == 'excused' || r.status == 'excused_late')
        .length;
    final totalOvertime = list.fold<double>(0.0, (s, r) => s + r.overtimeHours);
    // Restored old deduction model (81ad48a): hourly-based —
    // late ×1.5, early/permission ×1.0, absence × amount × multiplier —
    // plus active penalties. Never silently zero while lateness exists.
    final hourly = _hourlyRate();
    final totalEarlyMinutes =
        list.fold<int>(0, (s, r) => s + _earlyMinutesOf(r));
    final lateDed = (totalLateMinutes / 60.0) * hourly * 1.5;
    final permDed = (totalEarlyMinutes / 60.0) * hourly * 1.0;
    final absDed = absentDays * _absencePenalty * _absenceMultiplier;
    final totalDeductions = lateDed + permDed + absDed + _penaltiesTotal;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: _summaryCard(
              'غياب',
              '$absentDays يوم',
              Icons.person_off,
              Colors.red,
              () {
                setState(() => _statusFilter = 'absent');
              },
              () => _showAbsenceDetails(
                list.where((r) => r.status == 'absent').toList(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _summaryCard(
              'تأخير',
              '${_formatHM(totalLateMinutes)} ($lateDays يوم)',
              Icons.timer,
              Colors.amber,
              () {
                setState(() => _statusFilter = 'late');
              },
              () => _showLateDetails(lateRecords),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _summaryCard(
              'إذن',
              '$excusedDays يوم',
              Icons.assignment_turned_in,
              Colors.teal,
              () {
                setState(() => _statusFilter = 'excused');
              },
              () => _showPermissionDetails(permissionRecords),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _summaryCard(
              'إضافي',
              '${totalOvertime.toStringAsFixed(1)}س',
              Icons.more_time,
              Colors.blue,
              () => _showOvertimeDetails(
                list.where((r) => r.overtimeHours > 0).toList(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _summaryCard(
              'خصومات',
              '${totalDeductions.toStringAsFixed(0)} ج.م',
              Icons.money_off,
              Colors.deepOrange,
              () => _showDeductionsDetails(
                lateDed: lateDed,
                permDed: permDed,
                absDed: absDed,
                hourly: hourly,
                totalLateMinutes: totalLateMinutes,
                totalEarlyMinutes: totalEarlyMinutes,
                absentDays: absentDays,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showAbsenceDetails(List<Attendance> absents) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.person_off, color: Colors.red),
            SizedBox(width: 8),
            Text('تفاصيل أيام الغياب'),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: absents.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                    'لا يوجد أيام غياب مسجلة في هذه الفترة',
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: absents.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (c, i) {
                    final r = absents[i];
                    return ListTile(
                      dense: true,
                      leading: const CircleAvatar(
                        radius: 12,
                        backgroundColor: Colors.red,
                        child: Text(
                          'غ',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      title: Text(
                        DateFormat('EEEE, yyyy/MM/dd', 'ar').format(r.date),
                      ),
                      subtitle: Text(
                        (r.notes != null && r.notes!.trim().isNotEmpty)
                            ? r.notes!
                            : 'غياب بدون إذن',
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  void _showLateDetails(List<Attendance> lates) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.timer, color: Colors.amber),
            SizedBox(width: 8),
            Text('تفاصيل أيام التأخير'),
          ],
        ),
        content: SizedBox(
          width: 450,
          child: lates.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                    'لا يوجد تأخير مسجل في هذه الفترة',
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: lates.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (c, i) {
                    final r = lates[i];
                    final lateM = _lateMinutesOf(r);
                    final lateStr = lateM > 0 ? _formatHM(lateM) : '-';
                    final checkInStr = r.checkInTime != null
                        ? DateFormat('hh:mm a', 'ar').format(r.checkInTime!)
                        : '--:--';
                    return ListTile(
                      dense: true,
                      leading: const CircleAvatar(
                        radius: 12,
                        backgroundColor: Colors.amber,
                        child: Icon(
                          Icons.access_time,
                          size: 14,
                          color: Colors.black87,
                        ),
                      ),
                      title: Text(
                        DateFormat('EEEE, yyyy/MM/dd', 'ar').format(r.date),
                      ),
                      subtitle: Text('حضور: $checkInStr'),
                      trailing: Text(
                        lateStr,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.redAccent,
                          fontSize: 13,
                        ),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  void _showPermissionDetails(List<Attendance> permissions) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.assignment_turned_in, color: Colors.teal),
            SizedBox(width: 8),
            Text('تفاصيل الإذن والانصراف المبكر'),
          ],
        ),
        content: SizedBox(
          width: 450,
          child: permissions.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                    'لا يوجد أذونات أو انصراف مبكر مسجل',
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: permissions.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (c, i) {
                    final r = permissions[i];
                    final desc = _getStatusText(r.status) +
                        (r.leaveType != null && r.leaveType!.isNotEmpty
                            ? ' (${_getExcuseTypeTitle(r.leaveType, r.notes)})'
                            : '');
                    final timeStr = r.checkOutTime != null
                        ? DateFormat('hh:mm a', 'ar').format(r.checkOutTime!)
                        : (r.checkInTime != null
                            ? DateFormat('hh:mm a', 'ar')
                                .format(r.checkInTime!)
                            : '--:--');
                    return ListTile(
                      dense: true,
                      leading: const CircleAvatar(
                        radius: 12,
                        backgroundColor: Colors.teal,
                        child: Icon(
                          Icons.exit_to_app,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                      title: Text(
                        DateFormat('EEEE, yyyy/MM/dd', 'ar').format(r.date),
                      ),
                      subtitle: Text(
                        '$timeStr${(r.notes != null && r.notes!.trim().isNotEmpty) ? ' - ${r.notes}' : ''}',
                      ),
                      trailing: Text(
                        desc,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  void _showOvertimeDetails(List<Attendance> overtimes) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.more_time, color: Colors.blue),
            SizedBox(width: 8),
            Text('تفاصيل الوقت الإضافي'),
          ],
        ),
        content: SizedBox(
          width: 450,
          child: overtimes.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text(
                    'لا يوجد وقت إضافي مسجل في هذه الفترة',
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: overtimes.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (c, i) {
                    final r = overtimes[i];
                    final totalM = (r.overtimeHours * 60).round();
                    final checkOutStr = r.checkOutTime != null
                        ? DateFormat('hh:mm a', 'ar')
                            .format(r.checkOutTime!)
                        : '--:--';
                    return ListTile(
                      dense: true,
                      leading: const CircleAvatar(
                        radius: 12,
                        backgroundColor: Colors.teal,
                        child: Icon(
                          Icons.add,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                      title: Text(
                        DateFormat('EEEE, yyyy/MM/dd', 'ar').format(r.date),
                      ),
                      subtitle: Text('انصراف: $checkOutStr'),
                      trailing: Text(
                        _formatHM(totalM),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.teal,
                          fontSize: 13,
                        ),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  // Restored old breakdown (81ad48a): late ×1.5, early/permission ×1.0,
  // absence × amount × multiplier, plus active penalties.
  void _showDeductionsDetails({
    required double lateDed,
    required double permDed,
    required double absDed,
    required double hourly,
    required int totalLateMinutes,
    required int totalEarlyMinutes,
    required int absentDays,
  }) {
    final total = lateDed + permDed + absDed + _penaltiesTotal;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.money_off, color: Colors.deepOrange),
            SizedBox(width: 8),
            Text('تفاصيل الخصومات التقديرية'),
          ],
        ),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'سعر ساعة الموظف: ${hourly.toStringAsFixed(2)} ج.م',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'التأخير الإجمالي: ${_formatHM(totalLateMinutes)} — الانصراف المبكر: ${_formatHM(totalEarlyMinutes)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.timer, color: Colors.amber),
                  title: const Text('خصم التأخير (×1.5)'),
                  trailing: Text(
                    '${lateDed.toStringAsFixed(2)} ج.م',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.logout, color: Colors.deepOrange),
                  title: const Text('خصم الانصراف المبكر (×1.0)'),
                  trailing: Text(
                    '${permDed.toStringAsFixed(2)} ج.م',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.person_off, color: Colors.red),
                  title: Text('خصم الغياب ($absentDays يوم)'),
                  trailing: Text(
                    '${absDed.toStringAsFixed(2)} ج.م',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.gavel, color: Colors.purple),
                  title: const Text('جزاءات نشطة'),
                  subtitle: _penaltyTitles.isEmpty
                      ? const Text('لا يوجد جزاءات نشطة لهذا الموظف')
                      : Text(_penaltyTitles.join('\n')),
                  trailing: Text(
                    '${_penaltiesTotal.toStringAsFixed(2)} ج.م',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                const Divider(),
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.account_balance_wallet,
                    color: Colors.purple,
                  ),
                  title: const Text(
                    'الإجمالي التقديري للخصومات',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  trailing: Text(
                    '${total.toStringAsFixed(2)} ج.م',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: Colors.red,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
      child: Row(
        children: [
          const Icon(Icons.filter_list, size: 20, color: Colors.blueGrey),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildDateFilterChip('all', 'الكل'),
                  const SizedBox(width: 6),
                  _buildDateFilterChip('today', 'اليوم'),
                  const SizedBox(width: 6),
                  _buildDateFilterChip('this_week', 'هذا الأسبوع'),
                  const SizedBox(width: 6),
                  _buildDateFilterChip('this_month', 'هذا الشهر'),
                  const SizedBox(width: 6),
                  ActionChip(
                    avatar: const Icon(Icons.date_range, size: 16),
                    label: Text(
                      _dateFilter == 'custom' && _customDateRange != null
                          ? '${DateFormat('MM/dd').format(_customDateRange!.start)} - ${DateFormat('MM/dd').format(_customDateRange!.end)}'
                          : 'فترة مخصصة',
                      style: TextStyle(
                        fontSize: 12,
                        color: _dateFilter == 'custom' ? Colors.white : null,
                      ),
                    ),
                    backgroundColor: _dateFilter == 'custom'
                        ? Theme.of(context).primaryColor
                        : null,
                    onPressed: () async {
                      final picked = await showDateRangePicker(
                        context: context,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2035),
                        initialDateRange: _customDateRange ??
                            DateTimeRange(
                              start: DateTime.now().subtract(const Duration(days: 7)),
                              end: DateTime.now(),
                            ),
                      );
                      if (picked != null) {
                        setState(() {
                          _customDateRange = picked;
                          _dateFilter = 'custom';
                        });
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${_filteredAttendanceList.length} سجل',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(width: 4),
          DropdownButton<String>(
            value: _statusFilter,
            underline: const SizedBox(),
            icon: const Icon(Icons.arrow_drop_down, size: 20),
            items: const [
              DropdownMenuItem(value: 'all', child: Text('جميع الحالات', style: TextStyle(fontSize: 12))),
              DropdownMenuItem(value: 'present', child: Text('حاضر', style: TextStyle(fontSize: 12, color: Colors.green))),
              DropdownMenuItem(value: 'late', child: Text('متأخر', style: TextStyle(fontSize: 12, color: Colors.amber))),
              DropdownMenuItem(value: 'excused', child: Text('إذن', style: TextStyle(fontSize: 12, color: Colors.teal))),
              DropdownMenuItem(value: 'absent', child: Text('غائب', style: TextStyle(fontSize: 12, color: Colors.red))),
              DropdownMenuItem(value: 'leave', child: Text('إجازة', style: TextStyle(fontSize: 12, color: Colors.orange))),
            ],
            onChanged: (v) {
              if (v != null) setState(() => _statusFilter = v);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDateFilterChip(String key, String label) {
    final isSelected = _dateFilter == key;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: isSelected ? Colors.white : null,
        ),
      ),
      selected: isSelected,
      selectedColor: Theme.of(context).primaryColor,
      onSelected: (selected) {
        if (selected) {
          setState(() => _dateFilter = key);
        }
      },
    );
  }

  // restored from 81ad48a: cards are tappable (tap = filter, overtime/
  // deductions = details dialog). Long-press always opens the details.
  Widget _summaryCard(
    String title,
    String value,
    IconData icon,
    Color color, [
    VoidCallback? onTap,
    VoidCallback? onLongPress,
  ]) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(height: 4),
              Text(
                title,
                style: TextStyle(
                  color: isDark ? Colors.grey.shade400 : Colors.grey[600],
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  value,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.schedule, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            _dateFilter == 'all' && _statusFilter == 'all'
                ? 'لا يوجد سجل حضور لهذا الموظف'
                : 'لا توجد سجلات تطابق الفلتر المحدد',
            style: TextStyle(fontSize: 18, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceList() {
    final list = _filteredAttendanceList;
    return ListView.builder(
      padding: const EdgeInsets.all(16.0),
      itemCount: list.length,
      itemBuilder: (context, index) {
        final record = list[index];
        return _buildAttendanceCard(record);
      },
    );
  }

  /// Restored from 81ad48a (_markLeaveDay): quick permission per day —
  /// mapped onto the current schema (no migration): leave/late/early +
  /// with/without deduction become status + leaveType + notes.
  Future<void> _showQuickPermissionDialog(Attendance record) async {
    String permissionType = 'leave'; // leave | late | early
    bool excused = true; // بدون خصم هو الافتراضي
    String excuseKind = record.leaveType?.isNotEmpty == true
        ? record.leaveType!
        : 'personal';
    final reasonCtrl = TextEditingController();
    const excuseItems = [
      DropdownMenuItem(value: 'personal', child: Text('إذن شخصي')),
      DropdownMenuItem(value: 'mission', child: Text('مأمورية عمل رسمية')),
      DropdownMenuItem(value: 'medical', child: Text('عذر طبي / كشف')),
      DropdownMenuItem(value: 'emergency', child: Text('ظرف طارئ / عائلي')),
      DropdownMenuItem(value: 'study', child: Text('دراسة / امتحانات')),
      DropdownMenuItem(value: 'other', child: Text('إذن عام')),
    ];

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('إذن — عايز إذن لايه؟'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'اليوم: ${DateFormat('yyyy/MM/dd - EEEE', 'ar').format(record.date)}',
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: permissionType,
                  decoration: const InputDecoration(
                    labelText: 'نوع الإذن',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'leave',
                      child: Text('إذن يوم كامل'),
                    ),
                    DropdownMenuItem(
                      value: 'late',
                      child: Text('حضور متأخر بإذن'),
                    ),
                    DropdownMenuItem(
                      value: 'early',
                      child: Text('انصراف مبكر بإذن'),
                    ),
                  ],
                  onChanged: (v) =>
                      setDialogState(() => permissionType = v ?? 'leave'),
                ),
                const SizedBox(height: 12),
                const Text('الخصم:'),
                RadioListTile<bool>(
                  value: false,
                  groupValue: excused,
                  title: const Text('مع الخصم (يُحتسب طبيعي)'),
                  onChanged: (v) => setDialogState(() => excused = v ?? false),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
                RadioListTile<bool>(
                  value: true,
                  groupValue: excused,
                  title: const Text('بدون خصم (إذن معتمد)'),
                  onChanged: (v) => setDialogState(() => excused = v ?? true),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
                if (excused) ...[
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: excuseItems.any((e) => e.value == excuseKind)
                        ? excuseKind
                        : 'personal',
                    decoration: const InputDecoration(
                      labelText: 'سبب الإذن',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: excuseItems,
                    onChanged: (v) {
                      if (v != null) setDialogState(() => excuseKind = v);
                    },
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: reasonCtrl,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظة إضافية (اختياري)',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                foregroundColor: Colors.white,
              ),
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    String status;
    String? leaveType;
    final extra = reasonCtrl.text.trim();
    if (permissionType == 'late') {
      if (excused) {
        status = 'excused_late';
        leaveType = excuseKind;
      } else {
        status = 'late';
        leaveType = null;
      }
    } else if (permissionType == 'early') {
      if (excused) {
        status = 'excused';
        leaveType = excuseKind;
      } else {
        status = 'present';
        leaveType = null;
      }
    } else {
      status = 'leave';
      leaveType = 'other';
    }
    final kindName = _getExcuseTypeTitle(leaveType ?? excuseKind);
    final prefix = excused
        ? '[$kindName - بدون خصم]'
        : (permissionType == 'leave'
            ? '[إذن يوم كامل - مع الخصم]'
            : '[إذن - مع الخصم]');
    final notes = extra.isEmpty
        ? prefix
        : '$prefix $extra${(record.notes != null && record.notes!.trim().isNotEmpty) ? ' | ${record.notes}' : ''}';

    setState(() => _isChecking = true);
    try {
      final service = ref.read(staffManagementServiceProvider);
      await service.recordManualAttendance(
        widget.staff.staffId,
        date: record.date,
        status: status,
        checkInTime: record.checkInTime,
        checkOutTime: record.checkOutTime,
        workingHours: record.workingHours,
        notes: notes,
        leaveType: leaveType,
        source: 'manual',
      );
      await _loadAttendance();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم تسجيل الإذن'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل تسجيل الإذن: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  /// Restored from 81ad48a (_clearLeaveDay): cancel a permission and put the
  /// day back to its natural status derived from the recorded times.
  Future<void> _clearPermission(Attendance record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إلغاء الإذن'),
        content: Text(
          'إلغاء الإذن ليوم ${DateFormat('yyyy/MM/dd').format(record.date)} ويرجع الخصم طبيعي؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('إلغاء الإذن'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    String status;
    if (record.checkInTime != null) {
      final ci =
          record.checkInTime!.hour * 60 + record.checkInTime!.minute;
      status =
          ci > _scheduleStartMinutes() + _graceMinutes ? 'late' : 'present';
    } else if (record.checkOutTime != null) {
      status = 'present';
    } else {
      status = 'absent';
    }

    setState(() => _isChecking = true);
    try {
      final service = ref.read(staffManagementServiceProvider);
      await service.recordManualAttendance(
        widget.staff.staffId,
        date: record.date,
        status: status,
        checkInTime: record.checkInTime,
        checkOutTime: record.checkOutTime,
        workingHours: record.workingHours,
        notes: record.notes,
        leaveType: null,
        source: 'manual',
      );
      await _loadAttendance();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم إلغاء الإذن — الخصم رجع طبيعي'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل إلغاء الإذن: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  Widget _buildAttendanceCard(Attendance record) {
    final theme = Theme.of(context);
    final statusColor = _getStatusColor(record.status);

    return Card(
      margin: const EdgeInsets.only(bottom: 12.0),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _editRecord(record),
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
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
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
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.edit_note, size: 22),
                        tooltip: 'تعديل السجل / إذن',
                        onPressed: () => _editRecord(record),
                      ),
                    ],
                  ),
                ],
              ),
              // Dedicated Excuse Details Banner or Notes
              _buildExcuseDetailsSection(record, theme.brightness == Brightness.dark),
              const Divider(height: 20),
              Row(
                children: [
                  _buildTimeInfo(Icons.login, 'حضور', record.checkInTime),
                  const Spacer(),
                  _buildTimeInfo(Icons.logout, 'انصراف', record.checkOutTime),
                  PermissionGuard(
                    permission: Permission.manageAttendance,
                    showUpgradePrompt: false,
                    child: IconButton(
                      icon: const Icon(
                        Icons.beach_access,
                        size: 20,
                        color: Colors.purple,
                      ),
                      tooltip: 'إذن: حضور متأخر / انصراف مبكر / يوم كامل',
                      onPressed: _isChecking
                          ? null
                          : () => _showQuickPermissionDialog(record),
                    ),
                  ),
                  if (_isPermissionRecord(record))
                    PermissionGuard(
                      permission: Permission.manageAttendance,
                      showUpgradePrompt: false,
                      child: IconButton(
                        icon: const Icon(
                          Icons.block,
                          size: 20,
                          color: Colors.deepOrange,
                        ),
                        tooltip: 'إلغاء الإذن',
                        onPressed: _isChecking
                            ? null
                            : () => _clearPermission(record),
                      ),
                    ),
                ],
              ),
            ],
          ),
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
      case 'excused':
        return Colors.teal;
      case 'excused_late':
        return Colors.deepOrange;
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
      case 'excused':
        return 'معفي بإذن';
      case 'excused_late':
        return 'متأخر بإذن';
      default:
        return status;
    }
  }

  Widget _buildExcuseDetailsSection(Attendance record, bool isDark) {
    final isExcused = record.status == 'excused' || record.status == 'excused_late';
    final hasLeaveType = record.leaveType != null && record.leaveType!.isNotEmpty;
    final hasNotes = record.notes != null && record.notes!.trim().isNotEmpty;

    if (!isExcused && !hasLeaveType && !hasNotes) {
      return const SizedBox.shrink();
    }

    if (isExcused || hasLeaveType) {
      final accentColor = record.status == 'excused' ? Colors.teal : Colors.deepOrange;
      final typeLabel = _getExcuseTypeTitle(record.leaveType, record.notes);

      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 10, bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: accentColor.withValues(alpha: isDark ? 0.15 : 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: accentColor.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  record.status == 'excused' ? Icons.verified_user : Icons.schedule_outlined,
                  size: 16,
                  color: accentColor,
                ),
                const SizedBox(width: 6),
                Text(
                  'تفاصيل الإذن: $typeLabel',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: accentColor,
                  ),
                ),
              ],
            ),
            if (hasNotes) ...[
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, size: 14, color: Colors.grey),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      record.notes!,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white70 : Colors.black87,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      );
    }

    // Standard notes for non-excuse records
    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Row(
        children: [
          const Icon(Icons.notes, size: 14, color: Colors.grey),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              record.notes!,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.grey[400] : Colors.grey[700],
                fontStyle: FontStyle.italic,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  String _getExcuseTypeTitle(String? type, [String? notes]) {
    switch (type) {
      case 'personal':
        return 'إذن شخصي';
      case 'mission':
        return 'مأمورية عمل رسمية';
      case 'medical':
        return 'عذر طبي / كشف';
      case 'emergency':
        return 'ظرف طارئ / عائلي';
      case 'study':
        return 'دراسة / امتحانات';
      case 'sick':
        return 'إجازة مرضية';
      case 'annual':
        return 'إجازة اعتيادية';
    }
    if (notes != null) {
      if (notes.contains('مأمورية')) return 'مأمورية عمل رسمية';
      if (notes.contains('طبي') || notes.contains('مرض')) return 'عذر طبي';
      if (notes.contains('طارئ')) return 'ظرف طارئ';
      if (notes.contains('شخصي')) return 'إذن شخصي';
      if (notes.contains('دراسة') || notes.contains('امتحان')) return 'دراسة / امتحانات';
    }
    return 'إذن معتمد';
  }
}
