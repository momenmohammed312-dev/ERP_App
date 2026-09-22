import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/database/app_database.dart';
import '../../core/provider/app_database_provider.dart';
import '../../core/database/dao/staff_management_dao.dart';
import '../../core/models/user_model.dart';
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

  double _latePenalty = 0.0;
  double _absencePenalty = 0.0;

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

      double latePen = 0.0;
      double absPen = 0.0;
      try {
        final lateRow = await (db.select(db.attendanceSettings)
              ..where((t) => t.settingKey.equals('late_penalty_amount')))
            .getSingleOrNull();
        if (lateRow != null) {
          latePen = double.tryParse(lateRow.settingValue) ?? 0.0;
        }
        final absRow = await (db.select(db.attendanceSettings)
              ..where((t) => t.settingKey.equals('absence_penalty_amount')))
            .getSingleOrNull();
        if (absRow != null) {
          absPen = double.tryParse(absRow.settingValue) ?? 0.0;
        }
      } catch (_) {}

      setState(() {
        _attendanceList = attendance.reversed.toList();
        _latePenalty = latePen;
        _absencePenalty = absPen;
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

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) {
        DateTime date = selectedDate;
        TimeOfDay? inTime = checkInTime;
        TimeOfDay? outTime = checkOutTime;
        String selStatus = status;
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
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: noteCtrl,
                      decoration: const InputDecoration(
                        labelText: 'ملاحظات / سبب الإذن',
                        border: OutlineInputBorder(),
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
        final ci = result['checkIn'] as TimeOfDay?;
        final co = result['checkOut'] as TimeOfDay?;
        final st = result['status'] as String;
        final nt = result['notes'] as String;

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
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildSummaryCards(),
                Expanded(
                  child: _attendanceList.isEmpty
                      ? _buildEmptyState()
                      : _buildAttendanceList(),
                ),
              ],
            ),
      ),
    );
  }

  Widget _buildSummaryCards() {
    final list = _attendanceList;
    final absentDays = list.where((r) => r.status == 'absent').length;
    final lateDays = list.where((r) => r.status == 'late').length;
    final excusedDays = list
        .where((r) => r.status == 'excused' || r.status == 'excused_late')
        .length;
    final totalOvertime = list.fold<double>(0.0, (s, r) => s + r.overtimeHours);
    final totalDeductions =
        (lateDays * _latePenalty) + (absentDays * _absencePenalty);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: _summaryCard('غياب', '$absentDays يوم', Icons.person_off, Colors.red),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _summaryCard('تأخير', '$lateDays يوم', Icons.timer, Colors.amber),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _summaryCard('إذن', '$excusedDays يوم', Icons.assignment_turned_in, Colors.teal),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _summaryCard('إضافي', '${totalOvertime.toStringAsFixed(1)}س', Icons.more_time, Colors.blue),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _summaryCard('خصومات', '${totalDeductions.toStringAsFixed(0)} ج.م', Icons.money_off, Colors.deepOrange),
          ),
        ],
      ),
    );
  }

  Widget _summaryCard(String title, String value, IconData icon, Color color) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
            'لا يوجد سجل حضور لهذا الموظف',
            style: TextStyle(fontSize: 18, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16.0),
      itemCount: _attendanceList.length,
      itemBuilder: (context, index) {
        final record = _attendanceList[index];
        return _buildAttendanceCard(record);
      },
    );
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
              if (record.notes != null && record.notes!.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.notes, size: 14, color: Colors.grey),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        record.notes!,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.brightness == Brightness.dark
                              ? Colors.grey[400]
                              : Colors.grey[700],
                          fontStyle: FontStyle.italic,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
              const Divider(height: 20),
              Row(
                children: [
                  _buildTimeInfo(Icons.login, 'حضور', record.checkInTime),
                  const Spacer(),
                  _buildTimeInfo(Icons.logout, 'انصراف', record.checkOutTime),
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
}
