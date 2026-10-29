import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/database/app_database.dart';
import '../../core/provider/app_database_provider.dart';
import '../../core/provider/auth_provider.dart';
import '../../core/database/dao/staff_management_dao.dart';
import '../../services/staff_management_service.dart';
import '../../core/theme/madar_colors.dart';

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
  final _biometricIdController = TextEditingController();
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

  StaffBiometricMapping? _currentBiometricMapping;

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
      final deviceDao = ref.read(attendanceDeviceDaoProvider);
      final mappings = await deviceDao.getMappingsForStaff(widget.staff!.staffId);
      if (mappings.isNotEmpty) {
        final devices = await deviceDao.getAllDevices();
        final devMap = {for (final d in devices) d.id: d};
        _currentBiometricMapping = mappings.firstWhere(
          (m) =>
              devMap[m.deviceId]?.connectionType != 'file_import' &&
              m.externalUserId.isNotEmpty,
          orElse: () => mappings.firstWhere(
            (m) => m.externalUserId.isNotEmpty,
            orElse: () => mappings.first,
          ),
        );
        _biometricIdController.text = _currentBiometricMapping!.externalUserId;
        if (mounted) setState(() {});
      }
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
    const validTypes = ['full_time', 'weekly', 'daily', 'part_time', 'contract'];
    if (validTypes.contains(staff.employmentType)) {
      _selectedEmploymentType = staff.employmentType;
    } else if (staff.employmentType == 'monthly') {
      _selectedEmploymentType = 'full_time';
    } else {
      _selectedEmploymentType = 'full_time';
    }
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
    _biometricIdController.dispose();
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
      backgroundColor: MadarColors.bgDark,
      appBar: AppBar(
        title: Text(
          widget.staff == null ? 'إضافة موظف جديد' : 'تعديل بيانات الموظف',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: MadarColors.bgDark,
        foregroundColor: MadarColors.textLight,
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _saveForm,
              icon: _isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.check, size: 18),
              label: const Text('حفظ البيانات'),
              style: ElevatedButton.styleFrom(
                backgroundColor: MadarColors.success,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
            ),
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

  Widget _buildFormCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: MadarColors.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MadarColors.border),
      ),
      padding: const EdgeInsets.all(18.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: MadarColors.gold.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: MadarColors.gold.withValues(alpha: 0.3),
                  ),
                ),
                child: Icon(icon, size: 18, color: MadarColors.gold),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: const TextStyle(
                  color: MadarColors.textLight,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _buildBasicInfo() {
    return _buildFormCard(
      title: 'المعلومات الأساسية',
      icon: Icons.person_outline,
      children: [
        TextFormField(
          controller: _nameController,
          style: const TextStyle(color: MadarColors.textLight),
          decoration: _buildInputDecoration('الاسم الكامل *', Icons.person),
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
          style: const TextStyle(color: MadarColors.textLight),
          decoration: _buildInputDecoration('المنصب (اختياري)', Icons.work_outline),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _biometricIdController,
          style: const TextStyle(color: MadarColors.textLight),
          keyboardType: TextInputType.text,
          decoration: _buildInputDecoration(
            'رقم البصمة بالجهاز (ID في جهاز البصمة)',
            Icons.fingerprint,
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _selectedEmploymentType,
          dropdownColor: MadarColors.bgCard,
          style: const TextStyle(color: MadarColors.textLight, fontSize: 14),
          decoration: _buildInputDecoration(
            'نوع التوظيف والراتب',
            Icons.badge_outlined,
          ),
          items: const [
            DropdownMenuItem(value: 'full_time', child: Text('دوام كامل (راتب شهري)')),
            DropdownMenuItem(value: 'weekly', child: Text('راتب أسبوعي')),
            DropdownMenuItem(value: 'daily', child: Text('يومية (راتب يومي)')),
            DropdownMenuItem(value: 'part_time', child: Text('دوام جزئي (بالساعة)')),
            DropdownMenuItem(value: 'contract', child: Text('عقد عمل')),
          ],
          onChanged: (value) {
            if (value != null) {
              setState(() {
                _selectedEmploymentType = value;
              });
            }
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _basicSalaryController,
          style: const TextStyle(color: MadarColors.textLight),
          keyboardType: TextInputType.number,
          decoration: _buildInputDecoration(
            _selectedEmploymentType == 'weekly'
                ? 'الراتب الأسبوعي'
                : _selectedEmploymentType == 'daily'
                    ? 'اليومية (الراتب اليومي)'
                    : _selectedEmploymentType == 'full_time'
                        ? 'الراتب الشهري الأساسي'
                        : 'الراتب الأساسي',
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
        if ((double.tryParse(_basicSalaryController.text.trim()) ?? 0) <= 0)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 18,
                  color: Colors.amber,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'راتب صفر: لن يتم احتساب خصومات التأخير ولا الانصراف المبكر ولا الغياب لهذا الموظف (سعر الساعة = 0).',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.amber.shade300,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (_selectedEmploymentType == 'part_time') ...[
          const SizedBox(height: 12),
          TextFormField(
            controller: _hourlyRateController,
            style: const TextStyle(color: MadarColors.textLight),
            keyboardType: TextInputType.number,
            decoration: _buildInputDecoration(
              'السعر بالساعة',
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
    );
  }

  Widget _buildEmploymentInfo() {
    return _buildFormCard(
      title: 'معلومات التوظيف',
      icon: Icons.work_outline,
      children: [
        TextFormField(
          controller: _departmentController,
          style: const TextStyle(color: MadarColors.textLight),
          decoration: _buildInputDecoration('القسم', Icons.business_outlined),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: MadarColors.bgDark.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: MadarColors.border),
          ),
          child: ListTile(
            leading: const Icon(Icons.calendar_today, color: MadarColors.gold, size: 20),
            title: const Text('تاريخ التعيين', style: TextStyle(color: MadarColors.textLight, fontSize: 13)),
            subtitle: Text(
              _hireDate != null
                  ? '${_hireDate!.day}/${_hireDate!.month}/${_hireDate!.year}'
                  : 'اختر تاريخ',
              style: TextStyle(
                color: _hireDate != null ? MadarColors.gold : MadarColors.textMuted,
                fontWeight: FontWeight.bold,
              ),
            ),
            trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: MadarColors.textMuted),
            onTap: _selectHireDate,
          ),
        ),
        if (_selectedEmploymentType == 'contract') ...[
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: MadarColors.bgDark.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: MadarColors.border),
            ),
            child: ListTile(
              leading: const Icon(Icons.event_outlined, color: MadarColors.gold, size: 20),
              title: const Text('تاريخ نهاية العقد', style: TextStyle(color: MadarColors.textLight, fontSize: 13)),
              subtitle: Text(
                _contractEndDate != null
                    ? '${_contractEndDate!.day}/${_contractEndDate!.month}/${_contractEndDate!.year}'
                    : 'اختر تاريخ',
                style: TextStyle(
                  color: _contractEndDate != null ? MadarColors.gold : MadarColors.textMuted,
                  fontWeight: FontWeight.bold,
                ),
              ),
              trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: MadarColors.textMuted),
              onTap: _selectContractEndDate,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildContactInfo() {
    return _buildFormCard(
      title: 'معلومات الاتصال',
      icon: Icons.contact_phone_outlined,
      children: [
        TextFormField(
          controller: _nationalIdController,
          style: const TextStyle(color: MadarColors.textLight),
          decoration: _buildInputDecoration('الرقم القومي', Icons.badge_outlined),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _phoneController,
          style: const TextStyle(color: MadarColors.textLight),
          keyboardType: TextInputType.phone,
          decoration: _buildInputDecoration('رقم الهاتف', Icons.phone_outlined),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _emailController,
          style: const TextStyle(color: MadarColors.textLight),
          keyboardType: TextInputType.emailAddress,
          decoration: _buildInputDecoration(
            'البريد الإلكتروني',
            Icons.email_outlined,
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _addressController,
          style: const TextStyle(color: MadarColors.textLight),
          maxLines: 2,
          decoration: _buildInputDecoration('العنوان', Icons.home_outlined),
        ),
      ],
    );
  }

  Widget _buildBankInfo() {
    return _buildFormCard(
      title: 'معلومات الحساب البنكي',
      icon: Icons.account_balance_outlined,
      children: [
        TextFormField(
          controller: _bankNameController,
          style: const TextStyle(color: MadarColors.textLight),
          decoration: _buildInputDecoration(
            'اسم البنك',
            Icons.account_balance,
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _bankAccountController,
          style: const TextStyle(color: MadarColors.textLight),
          decoration: _buildInputDecoration(
            'رقم الحساب البنكي',
            Icons.credit_card,
          ),
        ),
      ],
    );
  }

  Widget _buildEmergencyContact() {
    return _buildFormCard(
      title: 'جهة الاتصال في حالات الطوارئ',
      icon: Icons.emergency_outlined,
      children: [
        TextFormField(
          controller: _emergencyContactController,
          style: const TextStyle(color: MadarColors.textLight),
          decoration: _buildInputDecoration(
            'اسم شخص الطوارئ',
            Icons.person_outline,
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _emergencyPhoneController,
          style: const TextStyle(color: MadarColors.textLight),
          keyboardType: TextInputType.phone,
          decoration: _buildInputDecoration(
            'رقم هاتف الطوارئ',
            Icons.phone_in_talk_outlined,
          ),
        ),
      ],
    );
  }

  Widget _buildNotes() {
    return _buildFormCard(
      title: 'ملاحظات إضافية',
      icon: Icons.note_alt_outlined,
      children: [
        TextFormField(
          controller: _notesController,
          maxLines: 3,
          style: const TextStyle(color: MadarColors.textLight),
          decoration: _buildInputDecoration('ملاحظات عن الموظف', Icons.notes),
        ),
      ],
    );
  }

  Widget _buildWorkScheduleSection() {
    return _buildFormCard(
      title: 'جدول مواعيد العمل',
      icon: Icons.schedule_outlined,
      children: [
        Container(
          decoration: BoxDecoration(
            color: MadarColors.bgDark.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: MadarColors.border),
          ),
          child: SwitchListTile(
            title: const Text(
              'استخدام جدول العمل الافتراضي',
              style: TextStyle(color: MadarColors.textLight, fontWeight: FontWeight.bold, fontSize: 14),
            ),
            subtitle: Text(
              _useDefaultSchedule ? 'مطبق من إعدادات الحضور العامة' : 'جدول مخصص لهذا الموظف',
              style: const TextStyle(color: MadarColors.textMuted, fontSize: 12),
            ),
            value: _useDefaultSchedule,
            onChanged: (v) => setState(() => _useDefaultSchedule = v),
            activeColor: MadarColors.gold,
          ),
        ),
        if (!_useDefaultSchedule) ...[
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: MadarColors.bgDark.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: MadarColors.border),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.login, color: MadarColors.success, size: 20),
                  title: const Text('وقت بدء العمل', style: TextStyle(color: MadarColors.textLight, fontSize: 13)),
                  subtitle: Text(_formatTime(_workScheduleStart), style: const TextStyle(color: MadarColors.gold, fontWeight: FontWeight.bold)),
                  trailing: const Icon(Icons.access_time, color: MadarColors.textMuted),
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: _workScheduleStart,
                    );
                    if (picked != null) setState(() => _workScheduleStart = picked);
                  },
                ),
                const Divider(height: 1, color: MadarColors.border),
                ListTile(
                  leading: const Icon(Icons.logout, color: MadarColors.error, size: 20),
                  title: const Text('وقت نهاية العمل', style: TextStyle(color: MadarColors.textLight, fontSize: 13)),
                  subtitle: Text(_formatTime(_workScheduleEnd), style: const TextStyle(color: MadarColors.gold, fontWeight: FontWeight.bold)),
                  trailing: const Icon(Icons.access_time, color: MadarColors.textMuted),
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: _workScheduleEnd,
                    );
                    if (picked != null) setState(() => _workScheduleEnd = picked);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'أيام العمل الأسبوعية',
              style: TextStyle(
                color: MadarColors.textLight,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
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
    );
  }

  Widget _buildScheduleDayChip(String key, String label) {
    final selected = _workDays[key] ?? false;
    return FilterChip(
      label: Text(
        label,
        style: TextStyle(
          color: selected ? Colors.white : MadarColors.textMuted,
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          fontSize: 12,
        ),
      ),
      selected: selected,
      selectedColor: MadarColors.success.withValues(alpha: 0.25),
      checkmarkColor: MadarColors.success,
      backgroundColor: MadarColors.bgDark.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: selected ? MadarColors.success : MadarColors.border,
        ),
      ),
      onSelected: (val) => setState(() => _workDays[key] = val),
    );
  }

  InputDecoration _buildInputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: MadarColors.textSecondary, fontSize: 13),
      prefixIcon: Icon(icon, color: MadarColors.gold, size: 20),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: MadarColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: MadarColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: MadarColors.gold, width: 1.5),
      ),
      filled: true,
      fillColor: MadarColors.bgDark.withValues(alpha: 0.6),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
      if (salary == null || salary < 0) {
        throw Exception('الراتب يجب أن يكون رقماً موجباً أو صفراً');
      }

      String effectiveStaffId;
      if (widget.staff == null) {
        final user = ref.read(authProvider);
        effectiveStaffId = await _service.addNewStaff(
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
        effectiveStaffId = widget.staff!.staffId;
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

      // Save or update Biometric ID mapping
      final enteredBiometricId = _biometricIdController.text.trim();

      if (enteredBiometricId.isNotEmpty) {
        final syncService = ref.read(attendanceSyncServiceProvider);
        await syncService.reconcileAndLinkBiometricId(
          staffId: effectiveStaffId,
          externalUserId: enteredBiometricId,
          staffNameOnDevice: _nameController.text.trim(),
          preferredDeviceId: _currentBiometricMapping?.deviceId,
        );
      } else if (_currentBiometricMapping != null && enteredBiometricId.isEmpty) {
        final deviceDao = ref.read(attendanceDeviceDaoProvider);
        await deviceDao.deleteMapping(_currentBiometricMapping!.id);
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
