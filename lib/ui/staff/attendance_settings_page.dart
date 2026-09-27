import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/provider/app_database_provider.dart';
import 'package:pos_offline_desktop/core/models/user_model.dart';
import 'package:pos_offline_desktop/services/attendance/attendance_calculation_engine.dart';
import 'package:pos_offline_desktop/widgets/permission_guard.dart';

class AttendanceSettingsPage extends ConsumerStatefulWidget {
  const AttendanceSettingsPage({super.key});

  @override
  ConsumerState<AttendanceSettingsPage> createState() => _AttendanceSettingsPageState();
}

class _AttendanceSettingsPageState extends ConsumerState<AttendanceSettingsPage> {
  bool _isLoading = true;
  bool _isSaving = false;

  // Work schedule defaults
  TimeOfDay _workStart = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _workEnd = const TimeOfDay(hour: 17, minute: 0);
  final Map<String, bool> _workDays = {
    'sun': true, 'mon': true, 'tue': true, 'wed': true, 'thu': true,
    'fri': false, 'sat': false,
  };
  String _weekendDay = 'fri';

  // Grace & penalties (locked old rules: late hour × multiplier,
  // absence day-wage or fixed amount per day)
  int _gracePeriodMinutes = 15;
  double _latePenaltyMultiplier = 1.5;
  double _perfectAttendanceBonus = 0.0;
  double _absencePenaltyAmount = 0;
  String _absenceMode = 'day_wage'; // 'day_wage' | 'fixed'
  // Overtime starts past the scheduled end + this grace (old rule)
  int _overtimeGraceMinutes = 30;
  double _overtimeRateMultiplier = 1.5;
  double _overtimeThresholdHours = 8;

  // Absence generation
  int _absencesGenerated = 0;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    try {
      final db = ref.read(appDatabaseProvider);
      final settings = await db.select(db.attendanceSettings).get();

      for (final s in settings) {
        switch (s.settingKey) {
          case 'default_work_start':
            _workStart = _parseTime(s.settingValue);
          case 'default_work_end':
            _workEnd = _parseTime(s.settingValue);
          case 'default_work_days':
            final days = s.settingValue.split(',');
            for (final key in _workDays.keys) {
              _workDays[key] = days.contains(key);
            }
          case 'default_weekend':
            _weekendDay = s.settingValue;
          case 'grace_period_minutes':
            _gracePeriodMinutes = int.tryParse(s.settingValue) ?? 15;
          case 'late_penalty_per_hour':
            _latePenaltyMultiplier = double.tryParse(s.settingValue) ?? 1.5;
          case 'late_penalty_multiplier':
            // Pre-v72 key: honoured on read so an existing database keeps its
            // configured value. New writes use `late_penalty_per_hour`.
            _latePenaltyMultiplier = double.tryParse(s.settingValue) ?? 1.5;
          case 'perfect_attendance_bonus':
            _perfectAttendanceBonus = double.tryParse(s.settingValue) ?? 0;
          case 'absence_deduction_mode':
            _absenceMode = s.settingValue == 'fixed' ? 'fixed' : 'day_wage';
          case 'overtime_grace_minutes':
            _overtimeGraceMinutes = int.tryParse(s.settingValue) ?? 30;
          case 'absence_penalty_amount':
            _absencePenaltyAmount = double.tryParse(s.settingValue) ?? 0;
          case 'overtime_rate_multiplier':
            _overtimeRateMultiplier = double.tryParse(s.settingValue) ?? 1.5;
          case 'overtime_threshold_hours':
            _overtimeThresholdHours = double.tryParse(s.settingValue) ?? 8;
        }
      }
    } catch (e) {
      debugPrint('Error loading attendance settings: $e');
    }
    if (mounted) setState(() => _isLoading = false);
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

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);
    try {
      final db = ref.read(appDatabaseProvider);
      final now = DateTime.now();

      final settingsMap = {
        'default_work_start': _formatTime(_workStart),
        'default_work_end': _formatTime(_workEnd),
        'default_work_days': _workDays.entries.where((e) => e.value).map((e) => e.key).join(','),
        'default_weekend': _weekendDay,
        'grace_period_minutes': _gracePeriodMinutes.toString(),
        'late_penalty_per_hour': _latePenaltyMultiplier.toString(),
        'perfect_attendance_bonus': _perfectAttendanceBonus.toString(),
        'absence_deduction_mode': _absenceMode,
        'overtime_grace_minutes': _overtimeGraceMinutes.toString(),
        'absence_penalty_amount': _absencePenaltyAmount.toString(),
        'overtime_rate_multiplier': _overtimeRateMultiplier.toString(),
        'overtime_threshold_hours': _overtimeThresholdHours.toString(),
      };

      for (final entry in settingsMap.entries) {
        // Check if setting exists
        final existing = await (db.select(db.attendanceSettings)
              ..where((s) => s.settingKey.equals(entry.key)))
            .getSingleOrNull();

        if (existing != null) {
          await db.update(db.attendanceSettings).replace(
            existing.copyWith(
              settingValue: entry.value,
              updatedAt: now,
            ),
          );
        } else {
          await db.into(db.attendanceSettings).insert(
            AttendanceSettingsCompanion.insert(
              settingKey: entry.key,
              settingValue: entry.value,
              createdAt: now,
              updatedAt: now,
            ),
          );
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حفظ الإعدادات'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في الحفظ: $e'), backgroundColor: Colors.red),
        );
      }
    }
    if (mounted) setState(() => _isSaving = false);
  }

  Future<void> _generateAbsences() async {
    try {
      final db = ref.read(appDatabaseProvider);
      final deviceDao = ref.read(attendanceDeviceDaoProvider);
      final engine = AttendanceCalculationEngine(
        db,
        deviceDao,
        db.staffManagementDao,
      );
      // يوم مغلق فقط (أمس): اليوم الحالي مفتوح ولا يُحسم غيابه.
      // يشمل فحص أيام العمل وجداول الموظفين داخل المحرك.
      final yesterday =
          DateTime.now().subtract(const Duration(days: 1));
      final created =
          await engine.generateAbsencesForRange(yesterday, yesterday);

      setState(() => _absencesGenerated = created);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم توليد $created سجل غياب تلقائي'),
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
    }
  }

  @override
  Widget build(BuildContext context) {
    return PermissionGuard(
      permission: Permission.manageAttendance,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('إعدادات الحضور والانصراف'),
          actions: [
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _isSaving ? null : _saveSettings,
              tooltip: 'حفظ',
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildWorkScheduleSection(),
                    const SizedBox(height: 20),
                    _buildGracePenaltySection(),
                    const SizedBox(height: 20),
                    _buildAutoAbsenceSection(),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildWorkScheduleSection() {
    return _buildSection(
      title: 'جدول العمل الافتراضي',
      icon: Icons.schedule,
      children: [
        ListTile(
          title: const Text('وقت بدء العمل'),
          subtitle: Text(_formatTime(_workStart)),
          trailing: const Icon(Icons.access_time),
          onTap: () async {
            final picked = await showTimePicker(
              context: context,
              initialTime: _workStart,
            );
            if (picked != null) setState(() => _workStart = picked);
          },
        ),
        const Divider(height: 1),
        ListTile(
          title: const Text('وقت نهاية العمل'),
          subtitle: Text(_formatTime(_workEnd)),
          trailing: const Icon(Icons.access_time),
          onTap: () async {
            final picked = await showTimePicker(
              context: context,
              initialTime: _workEnd,
            );
            if (picked != null) setState(() => _workEnd = picked);
          },
        ),
        const Divider(height: 1),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text('أيام العمل', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        Wrap(
          spacing: 8,
          children: [
            _buildDayChip('sun', 'الأحد'),
            _buildDayChip('mon', 'الاثنين'),
            _buildDayChip('tue', 'الثلاثاء'),
            _buildDayChip('wed', 'الأربعاء'),
            _buildDayChip('thu', 'الخميس'),
            _buildDayChip('fri', 'الجمعة'),
            _buildDayChip('sat', 'السبت'),
          ],
        ),
        const SizedBox(height: 12),
        const Divider(height: 1),
        ListTile(
          title: const Text('ساعات العمل اليومية'),
          subtitle: Text('${_overtimeThresholdHours.toStringAsFixed(1)} ساعة'),
          trailing: const Icon(Icons.timer),
          onTap: () async {
            final controller = TextEditingController(
              text: _overtimeThresholdHours.toString(),
            );
            final result = await showDialog<double>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('ساعات العمل اليومية'),
                content: TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'الساعات',
                    suffixText: 'ساعة',
                  ),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
                  ElevatedButton(
                    onPressed: () {
                      final val = double.tryParse(controller.text);
                      if (val != null) Navigator.pop(ctx, val);
                    },
                    child: const Text('موافق'),
                  ),
                ],
              ),
            );
            if (result != null) setState(() => _overtimeThresholdHours = result);
          },
        ),
      ],
    );
  }

  Widget _buildDayChip(String key, String label) {
    final selected = _workDays[key] ?? false;
    return FilterChip(
      label: Text(label),
      selected: selected,
      selectedColor: Colors.green.withValues(alpha: 0.2),
      checkmarkColor: Colors.green,
      onSelected: (val) => setState(() => _workDays[key] = val),
    );
  }

  Widget _buildGracePenaltySection() {
    return _buildSection(
      title: 'فترة السماح والعقوبات',
      icon: Icons.warning_amber,
      children: [
        ListTile(
          title: const Text('فترة السماح بالتأخير'),
          subtitle: Text('$_gracePeriodMinutes دقيقة'),
          trailing: const Icon(Icons.timer),
          onTap: () async {
            final controller = TextEditingController(text: _gracePeriodMinutes.toString());
            final result = await showDialog<int>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('فترة السماح (دقائق)'),
                content: TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(suffixText: 'دقيقة'),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
                  ElevatedButton(
                    onPressed: () {
                      final val = int.tryParse(controller.text);
                      if (val != null) Navigator.pop(ctx, val);
                    },
                    child: const Text('موافق'),
                  ),
                ],
              ),
            );
            if (result != null) setState(() => _gracePeriodMinutes = result);
          },
        ),
        const Divider(height: 1),
        ListTile(
          title: const Text('مضاعف خصم التأخير'),
          subtitle: Text(
            'ساعة التأخير × ${_latePenaltyMultiplier.toStringAsFixed(1)} من سعر الساعة',
          ),
          trailing: const Icon(Icons.money_off),
          onTap: () async {
            final controller = TextEditingController(
              text: _latePenaltyMultiplier.toString(),
            );
            final result = await showDialog<double>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('مضاعف خصم التأخير'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: controller,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(suffixText: 'x'),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        ActionChip(
                          label: const Text('1x'),
                          onPressed: () => Navigator.pop(ctx, 1.0),
                        ),
                        ActionChip(
                          label: const Text('1.5x'),
                          onPressed: () => Navigator.pop(ctx, 1.5),
                        ),
                        ActionChip(
                          label: const Text('2x'),
                          onPressed: () => Navigator.pop(ctx, 2.0),
                        ),
                      ],
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('إلغاء'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      final val = double.tryParse(controller.text);
                      if (val != null && val > 0) Navigator.pop(ctx, val);
                    },
                    child: const Text('موافق'),
                  ),
                ],
              ),
            );
            if (result != null) {
              setState(() => _latePenaltyMultiplier = result);
            }
          },
        ),
        const Divider(height: 1),
        ListTile(
          title: const Text('خصم الغياب (اليوم بيوم)'),
          subtitle: Text(
            _absenceMode == 'fixed'
                ? 'مبلغ ثابت: ${_absencePenaltyAmount.toStringAsFixed(0)} ج.م لليوم'
                : 'أجر يوم كامل لكل يوم غياب',
          ),
          trailing: const Icon(Icons.money_off),
          onTap: () async {
            String mode = _absenceMode;
            final controller = TextEditingController(
              text: _absencePenaltyAmount > 0
                  ? _absencePenaltyAmount.toString()
                  : '',
            );
            final result = await showDialog<Map<String, dynamic>>(
              context: context,
              builder: (ctx) => StatefulBuilder(
                builder: (ctx, setDialogState) => AlertDialog(
                  title: const Text('خصم الغياب (اليوم بيوم)'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      RadioListTile<String>(
                        value: 'day_wage',
                        groupValue: mode,
                        title: const Text('أجر يوم'),
                        subtitle: const Text(
                          'خصم أجر يوم كامل (الأساسي ÷ 30) عن كل يوم غياب',
                        ),
                        onChanged: (v) =>
                            setDialogState(() => mode = v ?? 'day_wage'),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                      RadioListTile<String>(
                        value: 'fixed',
                        groupValue: mode,
                        title: const Text('مبلغ ثابت لليوم'),
                        onChanged: (v) =>
                            setDialogState(() => mode = v ?? 'fixed'),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                      if (mode == 'fixed') ...[
                        const SizedBox(height: 8),
                        TextField(
                          controller: controller,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            hintText: '0 = بدون غرامة',
                            suffixText: 'ج.م / يوم',
                          ),
                        ),
                      ],
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('إلغاء'),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        final val = double.tryParse(controller.text) ?? 0;
                        Navigator.pop(ctx, {'mode': mode, 'amount': val});
                      },
                      child: const Text('موافق'),
                    ),
                  ],
                ),
              ),
            );
            if (result != null) {
              setState(() {
                _absenceMode = result['mode'] as String;
                _absencePenaltyAmount = result['amount'] as double;
              });
            }
          },
        ),
        const Divider(height: 1),
        ListTile(
          title: const Text('مضاعف العمل الإضافي'),
          subtitle: Text('x${_overtimeRateMultiplier.toStringAsFixed(1)}'),
          trailing: const Icon(Icons.access_time),
          onTap: () async {
            final controller = TextEditingController(
              text: _overtimeRateMultiplier.toString(),
            );
            final result = await showDialog<double>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('مضاعف العمل الإضافي'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: controller,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(suffixText: 'x'),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        ActionChip(label: const Text('1x'), onPressed: () => Navigator.pop(ctx, 1.0)),
                        ActionChip(label: const Text('1.5x'), onPressed: () => Navigator.pop(ctx, 1.5)),
                        ActionChip(label: const Text('2x'), onPressed: () => Navigator.pop(ctx, 2.0)),
                        ActionChip(label: const Text('3x'), onPressed: () => Navigator.pop(ctx, 3.0)),
                      ],
                    ),
                  ],
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
                  ElevatedButton(
                    onPressed: () {
                      final val = double.tryParse(controller.text);
                      if (val != null && val > 0) Navigator.pop(ctx, val);
                    },
                    child: const Text('موافق'),
                  ),
                ],
              ),
            );
            if (result != null) setState(() => _overtimeRateMultiplier = result);
          },
        ),
        const Divider(height: 1),
        ListTile(
          title: const Text('مهلة بداية الإضافي'),
          subtitle: Text(
            'الإضافي بعد نهاية الدوام بـ $_overtimeGraceMinutes دقيقة',
          ),
          trailing: const Icon(Icons.more_time),
          onTap: () async {
            final controller = TextEditingController(
              text: _overtimeGraceMinutes.toString(),
            );
            final result = await showDialog<int>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('مهلة بداية الإضافي (دقائق)'),
                content: TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    hintText: 'مثال: 30',
                    suffixText: 'دقيقة',
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('إلغاء'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      final val = int.tryParse(controller.text);
                      if (val != null && val >= 0) Navigator.pop(ctx, val);
                    },
                    child: const Text('موافق'),
                  ),
                ],
              ),
            );
            if (result != null) {
              setState(() => _overtimeGraceMinutes = result);
            }
          },
        ),
      ],
    );
  }

  Widget _buildAutoAbsenceSection() {
    return _buildSection(
      title: 'الغياب التلقائي',
      icon: Icons.person_off,
      children: [
        ListTile(
          title: const Text('توليد سجلات غياب الأمس'),
          subtitle: const Text(
              'يسجل غياب لكل موظف نشط لم يحضر في آخر يوم عمل مغلق'),
          trailing: ElevatedButton.icon(
            onPressed: _generateAbsences,
            icon: const Icon(Icons.play_arrow),
            label: const Text('تشغيل'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
          ),
        ),
        if (_absencesGenerated > 0) ...[
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.check_circle, color: Colors.green),
            title: Text('تم توليد $_absencesGenerated سجل غياب'),
          ),
        ],
      ],
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Icon(icon, size: 20, color: Colors.blue[700]),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue[700],
                  ),
                ),
              ],
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}
