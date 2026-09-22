import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_offline_desktop/core/provider/app_database_provider.dart';
import 'package:pos_offline_desktop/core/provider/auth_provider.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:intl/intl.dart';

class ManualOverrideDialog extends ConsumerStatefulWidget {
  final Staff staff;
  final DateTime? initialDate;
  final String? initialStatus;
  final DateTime? initialCheckInTime;
  final DateTime? initialCheckOutTime;
  final String? initialNotes;
  final String? initialLeaveType;

  const ManualOverrideDialog({
    super.key,
    required this.staff,
    this.initialDate,
    this.initialStatus,
    this.initialCheckInTime,
    this.initialCheckOutTime,
    this.initialNotes,
    this.initialLeaveType,
  });

  @override
  ConsumerState<ManualOverrideDialog> createState() => _ManualOverrideDialogState();
}

class _ManualOverrideDialogState extends ConsumerState<ManualOverrideDialog> {
  final _reasonController = TextEditingController();
  final _notesController = TextEditingController();
  
  late DateTime _selectedDate;
  TimeOfDay? _checkInTime;
  TimeOfDay? _checkOutTime;
  String _status = 'present';
  String _leaveType = 'personal';
  bool _isHourlyExcuse = false;
  TimeOfDay? _excuseFromTime;
  TimeOfDay? _excuseToTime;
  
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate ?? DateTime.now();
    const validStatuses = [
      'present',
      'absent',
      'late',
      'leave',
      'excused',
      'excused_late',
    ];
    if (widget.initialStatus != null && validStatuses.contains(widget.initialStatus)) {
      _status = widget.initialStatus!;
    }
    if (widget.initialLeaveType != null && widget.initialLeaveType!.isNotEmpty) {
      _leaveType = widget.initialLeaveType!;
    }
    if (widget.initialCheckInTime != null) {
      _checkInTime = TimeOfDay.fromDateTime(widget.initialCheckInTime!);
    }
    if (widget.initialCheckOutTime != null) {
      _checkOutTime = TimeOfDay.fromDateTime(widget.initialCheckOutTime!);
    }
    if (widget.initialNotes != null && widget.initialNotes!.isNotEmpty) {
      _notesController.text = widget.initialNotes!;
    }
  }

  String _getExcuseTypeName(String type) {
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
      default:
        return 'إذن معتمد';
    }
  }

  Future<void> _submit() async {
    if (_reasonController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('يجب إدخال سبب التعديل اليدوي')));
      return;
    }

    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final user = ref.read(authProvider);
      final service = ref.read(staffManagementServiceProvider); // Critical: Use the service, not the DAO
      
      DateTime? checkIn;
      if (_checkInTime != null) {
        checkIn = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, _checkInTime!.hour, _checkInTime!.minute);
      }
      
      DateTime? checkOut;
      if (_checkOutTime != null) {
        checkOut = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, _checkOutTime!.hour, _checkOutTime!.minute);
      }

      String finalNotes = _notesController.text.trim();
      String? excuseType;
      if (_status == 'excused' || _status == 'excused_late') {
        excuseType = _leaveType;
        final typeName = _getExcuseTypeName(_leaveType);
        String timing = '';
        if (_isHourlyExcuse && _excuseFromTime != null && _excuseToTime != null) {
          timing = 'من ${_excuseFromTime!.format(context)} إلى ${_excuseToTime!.format(context)}';
        } else if (!_isHourlyExcuse) {
          timing = 'يوم كامل معفي';
        }
        if (timing.isNotEmpty) {
          finalNotes = finalNotes.isNotEmpty ? '[$typeName - $timing] $finalNotes' : '[$typeName - $timing]';
        } else {
          finalNotes = finalNotes.isNotEmpty ? '[$typeName] $finalNotes' : '[$typeName]';
        }
      }

      await service.recordManualOverride(
        user,
        widget.staff.staffId,
        date: _selectedDate,
        status: _status,
        reason: _reasonController.text,
        checkInTime: checkIn,
        checkOutTime: checkOut,
        notes: finalNotes.isNotEmpty ? finalNotes : null,
        leaveType: excuseType,
      );

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e')));
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('yyyy-MM-dd');
    return AlertDialog(
      title: const Text('تعديل الحضور يدوياً (مراقب)'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('التاريخ'),
              subtitle: Text(dateFormat.format(_selectedDate)),
              trailing: const Icon(Icons.calendar_today),
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _selectedDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2035),
                );
                if (d != null) setState(() => _selectedDate = d);
              },
            ),
            DropdownButtonFormField<String>(
              value: _status,
              items: const [
                DropdownMenuItem(value: 'present', child: Text('حاضر')),
                DropdownMenuItem(value: 'absent', child: Text('غائب')),
                DropdownMenuItem(value: 'late', child: Text('متأخر')),
                DropdownMenuItem(value: 'leave', child: Text('إجازة')),
                DropdownMenuItem(value: 'excused', child: Text('إذن (معفي)')),
                DropdownMenuItem(value: 'excused_late', child: Text('متأخر بإذن')),
              ],
              onChanged: (v) => setState(() => _status = v!),
              decoration: const InputDecoration(labelText: 'الحالة'),
            ),
            if (_status == 'excused' || _status == 'excused_late') ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (_status == 'excused' ? Colors.teal : Colors.deepOrange).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: (_status == 'excused' ? Colors.teal : Colors.deepOrange).withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _status == 'excused' ? Icons.verified_user : Icons.schedule_outlined,
                          size: 18,
                          color: _status == 'excused' ? Colors.teal : Colors.deepOrange,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'تفاصيل الإذن والتصريح',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _status == 'excused' ? Colors.teal : Colors.deepOrange,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: _leaveType,
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
                        if (v != null) setState(() => _leaveType = v);
                      },
                    ),
                    const SizedBox(height: 10),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('إذن بساعات محددة', style: TextStyle(fontSize: 14)),
                      subtitle: Text(
                        _isHourlyExcuse ? 'تحديد فترة الإذن بالوقت' : 'إذن يوم كامل معفي',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      value: _isHourlyExcuse,
                      onChanged: (v) => setState(() => _isHourlyExcuse = v),
                    ),
                    if (_isHourlyExcuse) ...[
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                final picked = await showTimePicker(
                                  context: context,
                                  initialTime: _excuseFromTime ?? const TimeOfDay(hour: 9, minute: 0),
                                );
                                if (picked != null) setState(() => _excuseFromTime = picked);
                              },
                              icon: const Icon(Icons.access_time, size: 16),
                              label: Text(
                                _excuseFromTime != null ? 'من: ${_excuseFromTime!.format(context)}' : 'من الساعة',
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
                                  initialTime: _excuseToTime ?? const TimeOfDay(hour: 12, minute: 0),
                                );
                                if (picked != null) setState(() => _excuseToTime = picked);
                              },
                              icon: const Icon(Icons.access_time_filled, size: 16),
                              label: Text(
                                _excuseToTime != null ? 'إلى: ${_excuseToTime!.format(context)}' : 'إلى الساعة',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
            ListTile(
              title: const Text('وقت الحضور'),
              subtitle: Text(_checkInTime?.format(context) ?? 'غير محدد'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_checkInTime != null)
                    IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      tooltip: 'مسح وقت الحضور',
                      onPressed: () => setState(() => _checkInTime = null),
                    ),
                  const Icon(Icons.access_time),
                ],
              ),
              onTap: () async {
                final t = await showTimePicker(context: context, initialTime: _checkInTime ?? TimeOfDay.now());
                if (t != null) setState(() => _checkInTime = t);
              },
            ),
            ListTile(
              title: const Text('وقت الانصراف'),
              subtitle: Text(_checkOutTime?.format(context) ?? 'غير محدد'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_checkOutTime != null)
                    IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      tooltip: 'مسح وقت الانصراف',
                      onPressed: () => setState(() => _checkOutTime = null),
                    ),
                  const Icon(Icons.access_time),
                ],
              ),
              onTap: () async {
                final t = await showTimePicker(context: context, initialTime: _checkOutTime ?? TimeOfDay.now());
                if (t != null) setState(() => _checkOutTime = t);
              },
            ),
            TextField(
              controller: _reasonController,
              decoration: const InputDecoration(labelText: 'سبب التعديل (مطلوب)'),
              maxLines: 2,
            ),
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(labelText: 'ملاحظات إضافية'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _submit,
          child: _isLoading ? const CircularProgressIndicator() : const Text('حفظ'),
        ),
      ],
    );
  }
}
