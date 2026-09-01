import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/database/app_database.dart';
import '../../core/provider/app_database_provider.dart';
import '../../core/provider/auth_provider.dart';
import '../../core/database/dao/staff_management_dao.dart';
import '../../services/staff_management_service.dart';

class StaffFormPage extends ConsumerStatefulWidget {
  final Staff? staff;

  const StaffFormPage({super.key, this.staff});

  @override
  ConsumerState<StaffFormPage> createState() => _StaffFormPageState();
}

class _StaffFormPageState extends ConsumerState<StaffFormPage> {
  final _formKey = GlobalKey<FormState>();
  late StaffManagementService _service;

  final _nameController = TextEditingController();
  final _positionController = TextEditingController();
  final _nationalIdController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _addressController = TextEditingController();
  final _departmentController = TextEditingController();
  final _basicSalaryController = TextEditingController();
  final _hourlyRateController = TextEditingController();
  final _bankNameController = TextEditingController();
  final _bankAccountController = TextEditingController();
  final _emergencyContactController = TextEditingController();
  final _emergencyPhoneController = TextEditingController();
  final _notesController = TextEditingController();

  String _selectedEmploymentType = 'full_time';
  DateTime? _hireDate;
  DateTime? _contractEndDate;
  bool _isLoading = false;

  // Work schedule
  bool _useDefaultSchedule = true;
  TimeOfDay _workScheduleStart = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _workScheduleEnd = const TimeOfDay(hour: 17, minute: 0);
  final Map<String, bool> _workDays = {
    'sun': true, 'mon': true, 'tue': true, 'wed': true, 'thu': true,
    'fri': false, 'sat': false,
  };
  String _weekendDay = 'fri';

  @override
  void initState() {
    super.initState();
    _initializeService();
  }

  Future<void> _initializeService() async {
    final db = ref.read(appDatabaseProvider);
    _service = StaffManagementService(StaffManagementDao(db), db);
    if (widget.staff != null) {
      _populateForm(widget.staff!);
    }
  }

  void _populateForm(Staff staff) {
    _nameController.text = staff.name;
    _positionController.text = staff.position;
    _nationalIdController.text = staff.nationalId ?? '';
    _phoneController.text = staff.phone ?? '';
    _emailController.text = staff.email ?? '';
    _addressController.text = staff.address ?? '';
    _departmentController.text = staff.department ?? '';
    _basicSalaryController.text = staff.basicSalary.toString();
    _hourlyRateController.text = staff.hourlyRate?.toString() ?? '';
    _selectedEmploymentType = staff.employmentType;
    _hireDate = staff.hireDate;
    _contractEndDate = staff.contractEndDate;
    _bankNameController.text = staff.bankName ?? '';
    _bankAccountController.text = staff.bankAccount ?? '';
    _emergencyContactController.text = staff.emergencyContact ?? '';
    _emergencyPhoneController.text = staff.emergencyPhone ?? '';
    _notesController.text = staff.notes ?? '';

    // Work schedule
    _useDefaultSchedule = staff.useDefaultSchedule;
    if (staff.workScheduleStart != null) {
      _workScheduleStart = _parseTime(staff.workScheduleStart!);
    }
    if (staff.workScheduleEnd != null) {
      _workScheduleEnd = _parseTime(staff.workScheduleEnd!);
    }
    if (staff.workDays != null && staff.workDays!.isNotEmpty) {
      final days = staff.workDays!.split(',');
      for (final key in _workDays.keys) {
        _workDays[key] = days.contains(key);
      }
    }
    _weekendDay = staff.weekendDay ?? 'fri';
  }

  TimeOfDay _parseTime(String time) {
    final parts = time.split(':');
    if (parts.length != 2) return const TimeOfDay(hour: 9, minute: 0);
    return TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 9,
      minute: int.tryParse(parts[1]) ?? 0,
    );
  }

  String _formatTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  void dispose() {
    _nameController.dispose();
    _positionController.dispose();
    _nationalIdController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _departmentController.dispose();
    _basicSalaryController.dispose();
    _hourlyRateController.dispose();
    _bankNameController.dispose();
    _bankAccountController.dispose();
    _emergencyContactController.dispose();
    _emergencyPhoneController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2D2D2D),
      appBar: AppBar(
        title: Text(
          widget.staff == null ? 'إضافة موظف جديد' : 'تعديل بيانات الموظف',
        ),
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
        actions: [
          if (widget.staff != null)
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.redAccent),
              tooltip: 'حذف الموظف',
              onPressed: _isLoading ? null : _deleteStaff,
            ),
          TextButton(
            onPressed: _isLoading ? null : _saveForm,
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text('حفظ', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildBasicInfo(),
              const SizedBox(height: 16),
              _buildEmploymentInfo(),
              const SizedBox(height: 16),
              _buildContactInfo(),
              const SizedBox(height: 16),
              _buildEmergencyContact(),
              const SizedBox(height: 16),
              _buildBankInfo(),
              const SizedBox(height: 16),
              _buildNotes(),
              const SizedBox(height: 16),
              _buildWorkScheduleSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBasicInfo() {
    return Card(
      color: const Color(0xFF3A3A3A),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'المعلومات الأساسية',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Colors.blue[400],
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameController,
              style: const TextStyle(color: Colors.white),
              decoration: _buildInputDecoration('الاسم الكامل', Icons.person),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'هذا الحقل مطلوب';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _positionController,
              style: const TextStyle(color: Colors.white),
              decoration: _buildInputDecoration('المنصب (اختياري)', Icons.work),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              // ignore: deprecated_member_use
              value: _selectedEmploymentType,
              decoration: _buildInputDecoration(
                'نوع التوظيف',
                Icons.work_outline,
              ),
              items: const [
                DropdownMenuItem(value: 'full_time', child: Text('دوام')),
                DropdownMenuItem(value: 'part_time', child: Text('جزئي')),
                DropdownMenuItem(value: 'contract', child: Text('عقد')),
              ],
              onChanged: (value) {
                setState(() {
                  _selectedEmploymentType = value!;
                });
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _basicSalaryController,
              keyboardType: TextInputType.number,
              decoration: _buildInputDecoration(
                'الراتب الأساسي',
                Icons.attach_money,
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'هذا الحقل مطلوب';
                }
                if (double.tryParse(value) == null) {
                  return 'يرجى إدخال رقم صحيح';
                }
                return null;
              },
            ),
            if (_selectedEmploymentType == 'part_time') ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _hourlyRateController,
                keyboardType: TextInputType.number,
                decoration: _buildInputDecoration(
                  'الساعة بالساعة',
                  Icons.schedule,
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'هذا الحقل مطلوب';
                  }
                  if (double.tryParse(value) == null) {
                    return 'يرجى إدخال رقم صحيح';
                  }
                  return null;
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmploymentInfo() {
    return Card(
      color: const Color(0xFF3A3A3A),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'معلومات التوظيف',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Colors.blue[400],
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _departmentController,
              decoration: _buildInputDecoration('القسم', Icons.business),
            ),
            const SizedBox(height: 12),
            ListTile(
              title: const Text('تاريخ التعيين'),
              subtitle: Text(
                _hireDate != null
                    ? '${_hireDate!.day}/${_hireDate!.month}/${_hireDate!.year}'
                    : 'اختر تاريخ',
              ),
              trailing: IconButton(
                icon: const Icon(Icons.calendar_today),
                onPressed: _selectHireDate,
              ),
            ),
            if (_selectedEmploymentType == 'contract') ...[
              const SizedBox(height: 12),
              ListTile(
                title: const Text('تاريخ نهاية العقد'),
                subtitle: Text(
                  _contractEndDate != null
                      ? '${_contractEndDate!.day}/${_contractEndDate!.month}/${_contractEndDate!.year}'
                      : 'اختر تاريخ',
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.event),
                  onPressed: _selectContractEndDate,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildContactInfo() {
    return Card(
      color: const Color(0xFF3A3A3A),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'معلومات الاتصال',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Colors.blue[400],
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nationalIdController,
              decoration: _buildInputDecoration('الرقم القومي', Icons.badge),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: _buildInputDecoration('رقم الهاتف', Icons.phone),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: _buildInputDecoration(
                'البريد الإلكتروني',
                Icons.email,
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _addressController,
              maxLines: 3,
              decoration: _buildInputDecoration('العنوان', Icons.home),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBankInfo() {
    return Card(
      color: const Color(0xFF3A3A3A),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'معلومات البنك',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Colors.blue[400],
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _bankNameController,
              decoration: _buildInputDecoration(
                'اسم البنك',
                Icons.account_balance,
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _bankAccountController,
              decoration: _buildInputDecoration(
                'رقم الحساب',
                Icons.credit_card,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmergencyContact() {
    return Card(
      color: const Color(0xFF3A3A3A),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'معلومات الطوارئ',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Colors.blue[400],
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _emergencyContactController,
              decoration: _buildInputDecoration(
                'اسم الشخص للطوارئ',
                Icons.contact_phone,
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _emergencyPhoneController,
              keyboardType: TextInputType.phone,
              decoration: _buildInputDecoration(
                'رقم هاتف الطوارئ',
                Icons.phone_in_talk,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotes() {
    return Card(
      color: const Color(0xFF3A3A3A),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ملاحظات',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Colors.blue[400],
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _notesController,
              maxLines: 4,
              style: const TextStyle(color: Colors.white),
              decoration: _buildInputDecoration('ملاحظات إضافية', Icons.note),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkScheduleSection() {
    return Card(
      color: const Color(0xFF3A3A3A),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'جدول العمل',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Colors.blue[400],
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              title: const Text(
                'استخدام الجدول الافتراضي',
                style: TextStyle(color: Colors.white),
              ),
              subtitle: Text(
                _useDefaultSchedule ? 'من إعدادات الحضور العامة' : 'جدول مخصص لهذا الموظف',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              value: _useDefaultSchedule,
              onChanged: (v) => setState(() => _useDefaultSchedule = v),
              activeColor: Colors.blue[400],
            ),
            if (!_useDefaultSchedule) ...[
              const Divider(color: Colors.white24),
              ListTile(
                title: const Text('وقت بدء العمل', style: TextStyle(color: Colors.white)),
                subtitle: Text(_formatTime(_workScheduleStart), style: const TextStyle(color: Colors.white70)),
                trailing: const Icon(Icons.access_time, color: Colors.blue),
                onTap: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: _workScheduleStart,
                  );
                  if (picked != null) setState(() => _workScheduleStart = picked);
                },
              ),
              ListTile(
                title: const Text('وقت نهاية العمل', style: TextStyle(color: Colors.white)),
                subtitle: Text(_formatTime(_workScheduleEnd), style: const TextStyle(color: Colors.white70)),
                trailing: const Icon(Icons.access_time, color: Colors.blue),
                onTap: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: _workScheduleEnd,
                  );
                  if (picked != null) setState(() => _workScheduleEnd = picked);
                },
              ),
              const SizedBox(height: 8),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text('أيام العمل', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  _buildScheduleDayChip('sun', 'الأحد'),
                  _buildScheduleDayChip('mon', 'الاثنين'),
                  _buildScheduleDayChip('tue', 'الثلاثاء'),
                  _buildScheduleDayChip('wed', 'الأربعاء'),
                  _buildScheduleDayChip('thu', 'الخميس'),
                  _buildScheduleDayChip('fri', 'الجمعة'),
                  _buildScheduleDayChip('sat', 'السبت'),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildScheduleDayChip(String key, String label) {
    final selected = _workDays[key] ?? false;
    return FilterChip(
      label: Text(label, style: TextStyle(color: selected ? Colors.white : Colors.white70)),
      selected: selected,
      selectedColor: Colors.green.withValues(alpha: 0.3),
      checkmarkColor: Colors.green,
      onSelected: (val) => setState(() => _workDays[key] = val),
    );
  }

  InputDecoration _buildInputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white70),
      prefixIcon: Icon(icon, color: Colors.blue[400]),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.blue[700]!),
      ),
      filled: true,
      fillColor: const Color(0xFF4A4A4A),
    );
  }

  Future<void> _selectHireDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _hireDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _hireDate = picked;
      });
    }
  }

  Future<void> _selectContractEndDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _contractEndDate ?? DateTime.now(),
      firstDate: _hireDate ?? DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _contractEndDate = picked;
      });
    }
  }

  Future<void> _deleteStaff() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل أنت متأكد من حذف الموظف "${widget.staff!.name}" نهائيا؟ لا يمكن التراجع.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white), child: const Text('حذف')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _isLoading = true);
    try {
      final user = ref.read(authProvider);
      await _service.deleteStaffCompletely(user, widget.staff!.staffId);
      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حذف الموظف'), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل الحذف: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveForm() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Validation
      if (_nameController.text.trim().isEmpty) {
        throw Exception('اسم الموظف مطلوب');
      }
      if (_basicSalaryController.text.trim().isEmpty) {
        throw Exception('الراتب الأساسي مطلوب');
      }

      final salary = double.tryParse(_basicSalaryController.text);
      if (salary == null || salary <= 0) {
        throw Exception('الراتب الأساسي يجب أن يكون رقماً موجباً');
      }

      if (widget.staff == null) {
        final user = ref.read(authProvider);
        await _service.addNewStaff(
          user,
          name: _nameController.text.trim(),
          // position is optional — default to empty string
          position: _positionController.text.trim(),
          employmentType: _selectedEmploymentType,
          basicSalary: salary,
          nationalId: _nationalIdController.text.trim().isEmpty
              ? null
              : _nationalIdController.text.trim(),
          phone: _phoneController.text.trim().isEmpty
              ? null
              : _phoneController.text.trim(),
          email: _emailController.text.trim().isEmpty
              ? null
              : _emailController.text.trim(),
          address: _addressController.text.trim().isEmpty
              ? null
              : _addressController.text.trim(),
          department: _departmentController.text.trim().isEmpty
              ? null
              : _departmentController.text.trim(),
          hourlyRate: _hourlyRateController.text.trim().isEmpty
              ? null
              : double.tryParse(_hourlyRateController.text),
          contractEndDate: _contractEndDate,
          bankName: _bankNameController.text.trim().isEmpty
              ? null
              : _bankNameController.text.trim(),
          bankAccount: _bankAccountController.text.trim().isEmpty
              ? null
              : _bankAccountController.text.trim(),
          emergencyContact: _emergencyContactController.text.trim().isEmpty
              ? null
              : _emergencyContactController.text.trim(),
          emergencyPhone: _emergencyPhoneController.text.trim().isEmpty
              ? null
              : _emergencyPhoneController.text.trim(),
          notes: _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
          useDefaultSchedule: _useDefaultSchedule,
          workScheduleStart: _useDefaultSchedule ? null : _formatTime(_workScheduleStart),
          workScheduleEnd: _useDefaultSchedule ? null : _formatTime(_workScheduleEnd),
          workDays: _useDefaultSchedule
              ? null
              : _workDays.entries.where((e) => e.value).map((e) => e.key).join(','),
          weekendDay: _useDefaultSchedule ? null : _weekendDay,
        );
      } else {
        final user = ref.read(authProvider);
        await _service.updateStaffInfo(
          user,
          staffId: widget.staff!.staffId,
          name: _nameController.text.trim(),
          // position is optional — keep existing value if field is empty
          position: _positionController.text.trim(),
          department: _departmentController.text.trim().isEmpty
              ? null
              : _departmentController.text.trim(),
          employmentType: _selectedEmploymentType,
          basicSalary: salary,
          hourlyRate: _hourlyRateController.text.trim().isEmpty
              ? null
              : double.tryParse(_hourlyRateController.text),
          phone: _phoneController.text.trim().isEmpty
              ? null
              : _phoneController.text.trim(),
          email: _emailController.text.trim().isEmpty
              ? null
              : _emailController.text.trim(),
          address: _addressController.text.trim().isEmpty
              ? null
              : _addressController.text.trim(),
          bankName: _bankNameController.text.trim().isEmpty
              ? null
              : _bankNameController.text.trim(),
          bankAccount: _bankAccountController.text.trim().isEmpty
              ? null
              : _bankAccountController.text.trim(),
          emergencyContact: _emergencyContactController.text.trim().isEmpty
              ? null
              : _emergencyContactController.text.trim(),
          emergencyPhone: _emergencyPhoneController.text.trim().isEmpty
              ? null
              : _emergencyPhoneController.text.trim(),
          notes: _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
          contractEndDate: _contractEndDate,
          useDefaultSchedule: _useDefaultSchedule,
          workScheduleStart: _useDefaultSchedule ? null : _formatTime(_workScheduleStart),
          workScheduleEnd: _useDefaultSchedule ? null : _formatTime(_workScheduleEnd),
          workDays: _useDefaultSchedule
              ? null
              : _workDays.entries.where((e) => e.value).map((e) => e.key).join(','),
          weekendDay: _useDefaultSchedule ? null : _weekendDay,
        );
      }

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.staff == null
                  ? 'تم إضافة الموظف بنجاح'
                  : 'تم تحديث بيانات الموظف بنجاح',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e, st) {
      if (!mounted) return;

      // Log detailed error for debugging
      debugPrint('Staff form error: $e');
      debugPrint('Stack trace: $st');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ: ${e.toString().replaceFirst('Exception: ', '')}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}
