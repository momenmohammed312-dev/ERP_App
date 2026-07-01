import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_offline_desktop/core/models/user_model.dart';
import 'package:pos_offline_desktop/core/provider/app_database_provider.dart';
import 'package:pos_offline_desktop/core/provider/auth_provider.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:intl/intl.dart';

class ManualOverrideDialog extends ConsumerStatefulWidget {
  final Staff staff;

  const ManualOverrideDialog({super.key, required this.staff});

  @override
  ConsumerState<ManualOverrideDialog> createState() => _ManualOverrideDialogState();
}

class _ManualOverrideDialogState extends ConsumerState<ManualOverrideDialog> {
  final _reasonController = TextEditingController();
  final _notesController = TextEditingController();
  
  DateTime _selectedDate = DateTime.now();
  TimeOfDay? _checkInTime;
  TimeOfDay? _checkOutTime;
  String _status = 'present';
  
  bool _isLoading = false;

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
                final d = await showDatePicker(context: context, initialDate: _selectedDate, firstDate: DateTime(2000), lastDate: DateTime.now());
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
              ],
              onChanged: (v) => setState(() => _status = v!),
              decoration: const InputDecoration(labelText: 'الحالة'),
            ),
            ListTile(
              title: const Text('وقت الحضور'),
              subtitle: Text(_checkInTime?.format(context) ?? 'غير محدد'),
              trailing: const Icon(Icons.access_time),
              onTap: () async {
                final t = await showTimePicker(context: context, initialTime: _checkInTime ?? TimeOfDay.now());
                if (t != null) setState(() => _checkInTime = t);
              },
            ),
            ListTile(
              title: const Text('وقت الانصراف'),
              subtitle: Text(_checkOutTime?.format(context) ?? 'غير محدد'),
              trailing: const Icon(Icons.access_time),
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
