import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' as drift;
import '../../core/database/app_database.dart';
import '../../core/provider/app_database_provider.dart';
import '../../core/database/dao/staff_management_dao.dart';
import 'package:intl/intl.dart';

class AttendancePage extends ConsumerStatefulWidget {
  final Staff staff;

  const AttendancePage({super.key, required this.staff});

  @override
  ConsumerState<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends ConsumerState<AttendancePage> {
  late StaffManagementDao _dao;
  List<Attendance> _attendanceList = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAttendance();
  }

  Future<void> _loadAttendance() async {
    setState(() => _isLoading = true);
    final db = ref.read(appDatabaseProvider);
    _dao = StaffManagementDao(db);
    try {
      final attendance = await _dao.getAttendanceByStaff(widget.staff.staffId);
      setState(() {
        _attendanceList = attendance.reversed.toList();
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

        await _dao.addAttendance(
          AttendanceTableCompanion.insert(
            staffId: widget.staff.staffId,
            date: dt,
            checkInTime: drift.Value(checkInDateTime),
            checkOutTime: checkOutDateTime != null
                ? drift.Value(checkOutDateTime)
                : const drift.Value.absent(),
            status: st,
            workingHours: workingHours != null
                ? drift.Value(workingHours)
                : const drift.Value.absent(),
            notes: nt.isNotEmpty ? drift.Value(nt) : const drift.Value.absent(),
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
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
            SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
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
      await _dao.checkIn(widget.staff.staffId);
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
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  Future<void> _checkOut() async {
    setState(() => _isChecking = true);
    try {
      await _dao.checkOut(widget.staff.staffId);
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
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _attendanceList.isEmpty
          ? _buildEmptyState()
          : _buildAttendanceList(),
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
