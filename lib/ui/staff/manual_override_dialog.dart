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

  const ManualOverrideDialog({
    super.key,
    required this.staff,
    this.initialDate,
    this.initialStatus,
    this.initialCheckInTime,
    this.initialCheckOutTime,
    this.initialNotes,
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

      await service.recordManualOverride(
        user,
        widget.staff.staffId,
        date: _selectedDate,
        status: _status,
        reason: _reasonController.text,
        checkInTime: checkIn,
        checkOutTime: checkOut,
        notes: _notesController.text,
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
