import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/database/app_database.dart';
import '../../core/provider/app_database_provider.dart';
import '../../core/provider/auth_provider.dart';
import '../../core/database/dao/staff_management_dao.dart';
import '../../services/staff_management_service.dart';
import '../../services/attendance/attendance_file_import_service.dart';
import 'staff_form_page.dart';
import 'staff_details_page.dart';
import 'attendance_page.dart';
import 'biometric_enrollment_page.dart';
import 'employee_dashboard_page.dart';

class StaffListPage extends ConsumerStatefulWidget {
  const StaffListPage({super.key});

  @override
  ConsumerState<StaffListPage> createState() => _StaffListPageState();
}

class _StaffListPageState extends ConsumerState<StaffListPage> {
  late StaffManagementService _service;
  late StaffManagementDao _dao;
  List<Staff> _staffList = [];
  List<Staff> _filteredStaffList = [];
  Map<String, String> _biometricIdByStaffId = {};
  bool _isLoading = true;
  bool _isSyncingAttendance = false;
  bool _isImportingFile = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _init();
    _searchController.addListener(_filterStaff);
  }

  Future<void> _init() async {
    await _initializeService();
    await _loadStaff();
  }

  Future<void> _initializeService() async {
    final db = ref.read(appDatabaseProvider);
    _dao = StaffManagementDao(db);
    _service = StaffManagementService(_dao, db);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadStaff() async {
    setState(() => _isLoading = true);
    try {
      final staff = await _dao.getAllStaff();
      final deviceDao = ref.read(attendanceDeviceDaoProvider);
      final Map<String, String> biometricMap = {};
      for (final s in staff) {
        final mappings = await deviceDao.getMappingsForStaff(s.staffId);
        if (mappings.isNotEmpty) {
          biometricMap[s.staffId] = mappings.first.externalUserId;
        }
      }
      setState(() {
        _staffList = staff;
        _filteredStaffList = staff;
        _biometricIdByStaffId = biometricMap;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ في تحميل بيانات الموظفين: $e')),
      );
    }
  }

  Future<void> _importAttendance() async {
    if (_isSyncingAttendance) return;
    setState(() => _isSyncingAttendance = true);
    try {
      final syncService = ref.read(attendanceSyncServiceProvider);
      final user = ref.read(authProvider);
      final result = await syncService.syncAllDevices(
        triggeredBy: user?.username ?? 'manual_all',
      );
      await _loadStaff();
      if (!mounted) return;
      if (result.error != null && result.matched == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.error!.length < 140 ? result.error! : 'فشل استيراد الحضور',
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تمت المزامنة: ${result.fetched} من الأجهزة، ${result.matched} اتسجل حضور'
              '${result.info == null ? '' : '\n${result.info}'}',
            ),
            backgroundColor: result.matched > 0 ? Colors.green : Colors.orange,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل استيراد الحضور: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncingAttendance = false);
    }
  }

  /// استيراد الحضور من ملف إكسل مُصدَّر من جهاز البصمة (.xls / .xlsx / .csv):
  /// اختيار الملف ← معاينة ← تأكيد ← تنفيذ ← نتيجة بالأرقام.
  Future<void> _importFromExcel() async {
    if (_isImportingFile) return;
    FilePickerResult? picked;
    try {
      picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xls', 'xlsx', 'csv'],
        withData: true,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذّر فتح اختيار الملف: $e')),
      );
      return;
    }
    if (picked == null || picked.files.isEmpty || !mounted) return;
    final file = picked.files.single;
    Uint8List? bytes = file.bytes;
    if (bytes == null && file.path != null) {
      try {
        bytes = await File(file.path!).readAsBytes();
      } catch (_) {}
    }
    if (bytes == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذّرت قراءة الملف المختار')),
      );
      return;
    }
    if (!mounted) return;

    setState(() => _isImportingFile = true);
    try {
      final service = ref.read(attendanceFileImportProvider);
      final preview = await service.parseFile(
        bytes: bytes,
        fileName: file.name,
      );
      if (!mounted) return;
      if (preview.punches.isEmpty) {
        final hint = preview.errors.isNotEmpty
            ? preview.errors.first
            : 'لا توجد بصمات صالحة في الملف';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(hint), backgroundColor: Colors.red),
        );
        return;
      }
      if (preview.importablePunches == 0) {
        _showSkippedIdsDialog(
          title: 'مفيش أرقام بصمة مربوطة في الملف',
          unknownIds: preview.unknownIdList,
          invalidIds: preview.invalidIdList,
        );
        return;
      }
      final confirmed = await _showExcelConfirmDialog(preview);
      if (confirmed != true || !mounted) return;
      final user = ref.read(authProvider);
      final result = await service.importPunches(
        preview,
        triggeredBy: user?.username ?? 'excel_import',
      );
      await _loadStaff();
      if (!mounted) return;
      if (result.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.error!), backgroundColor: Colors.red),
        );
        return;
      }
      final skipped = result.skippedUnknown + result.skippedInvalid;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم الاستيراد: ${result.matched} حضور مسجّل '
            '(${result.fetched} بصمة مربوطة'
            '${result.duplicate > 0 ? '، ${result.duplicate} مكرر' : ''}'
            '${skipped > 0 ? '، $skipped متخطية' : ''}'
            '${result.linkedIds > 0 ? '، ${result.linkedIds} رقم بصمة تم ربطه' : ''}'
            '${result.absencesCreated > 0 ? '، ${result.absencesCreated} غياب تلقائي' : ''})',
          ),
          backgroundColor: skipped > 0 || result.unmatched > 0
              ? Colors.orange
              : Colors.green,
          duration: const Duration(seconds: 6),
        ),
      );
      if (result.unknownIds.isNotEmpty ||
          result.invalidIds.isNotEmpty ||
          result.unmatchedSamples.isNotEmpty) {
        _showSkippedIdsDialog(
          title: 'أرقام بصمة متخطاة',
          unknownIds: result.unknownIds,
          invalidIds: result.invalidIds,
          unmatchedSamples: result.unmatchedSamples,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل استيراد الملف: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isImportingFile = false);
    }
  }

  Future<bool?> _showExcelConfirmDialog(AttendanceFilePreview preview) {
    String range = '—';
    if (preview.minTime != null && preview.maxTime != null) {
      String fmt(DateTime t) => '${t.year}/${t.month}/${t.day}';
      range = '${fmt(preview.minTime!)} ← ${fmt(preview.maxTime!)}';
    }
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('تأكيد استيراد ${preview.fileName}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('البصمات: ${preview.punches.length}'),
            Text('الفترة: $range'),
            Text(
              'الصفوف المقروءة من الملف: ${preview.rowsRead}',
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 6),
            Text(
              '✔ مرتبط بموظف موجود: ${preview.matchedIds} رقم بصمة '
              '(${preview.importablePunches} بصمة)',
              style: const TextStyle(color: Colors.green),
            ),
            if (preview.invalidIds > 0)
              Text(
                '⚠ أرقام مرتبطة بموظف غير صالح: ${preview.invalidIds} '
                '(${preview.skippedInvalidPunches} بصمة) — سيتم تخطيها',
                style: const TextStyle(color: Colors.orange),
              ),
            if (preview.unknownIds > 0)
              Text(
                '✖ أرقام بصمة غير معروفة: ${preview.unknownIds} '
                '(${preview.skippedUnknownPunches} بصمة) — سيتم تخطيها',
                style: const TextStyle(color: Colors.red),
              ),
            if (preview.skippedRows > 0)
              Text('صفوف متجاوَزة: ${preview.skippedRows}'),
            if (preview.blankRows > 0)
              Text(
                'صفوف فارغة متجاهلة: ${preview.blankRows}',
                style: const TextStyle(fontSize: 12),
              ),
            if (preview.warnings.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('تحذيرات القراءة:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              ...preview.warnings
                  .take(4)
                  .map((e) => Text('• $e',
                      style: const TextStyle(fontSize: 12))),
            ],
            if (preview.errors.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('ملاحظات:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              ...preview.errors
                  .take(4)
                  .map((e) => Text('• $e',
                      style: const TextStyle(fontSize: 12))),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تنفيذ الاستيراد'),
          ),
        ],
      ),
    );
  }

  /// تقرير أرقام البصمة المتخطاة: غير معروفة (تحتاج ربط يدوي) وغير صالحة
  /// (مع السبب)، مع توضيح أن الاستيراد ربط كل سجلاته بنفس الموظف.
  void _showSkippedIdsDialog({
    required String title,
    required List<String> unknownIds,
    required List<String> invalidIds,
    List<String> unmatchedSamples = const [],
  }) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 440,
          height: 360,
          child: ListView(
            children: [
              if (unknownIds.isNotEmpty) ...[
                Text(
                  'أرقام غير معروفة (${unknownIds.length}) — '
                  'اربطها من إدارة الموظفين ← رقم البصمة ثم أعد الاستيراد:',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
                ...unknownIds.map(
                  (s) => ListTile(
                    dense: true,
                    title: Text(s, style: const TextStyle(fontSize: 12)),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              if (invalidIds.isNotEmpty) ...[
                Text(
                  'أرقام مرتبطة بموظف غير صالح (${invalidIds.length}):',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.orange,
                  ),
                ),
                ...invalidIds.map(
                  (s) => ListTile(
                    dense: true,
                    title: Text(s, style: const TextStyle(fontSize: 12)),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              if (unmatchedSamples.isNotEmpty) ...[
                const Text(
                  'حركات لم تُعتمد:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                ...unmatchedSamples.map(
                  (s) => ListTile(
                    dense: true,
                    title: Text(s, style: const TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('موافق'),
          ),
        ],
      ),
    );
  }

  void _filterStaff() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredStaffList = _staffList
          .where(
            (staff) =>
                staff.name.toLowerCase().contains(query) ||
                staff.position.toLowerCase().contains(query) ||
                staff.staffId.toLowerCase().contains(query) ||
                (staff.phone?.toLowerCase().contains(query) ?? false),
          )
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0D1117) : Colors.grey.shade50;
    final cardBg = isDark ? const Color(0xFF161B22) : Colors.white;
    final textColor = isDark ? const Color(0xFFE6EDF3) : Colors.black87;
    final subTextColor = isDark ? const Color(0xFF8B949E) : Colors.black54;
    final goldColor = const Color(0xFFC9A84C);
    final borderColor = isDark ? const Color(0xFF30363D) : Colors.grey.shade300;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text('إدارة الموظفين'),
        backgroundColor: bgColor,
        foregroundColor: textColor,
        elevation: 0,
        actions: [
          IconButton(
            icon: _isImportingFile
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.upload_file),
            onPressed: (_isImportingFile || _isSyncingAttendance)
                ? null
                : _importFromExcel,
            tooltip: 'استيراد الحضور من ملف إكسل',
          ),
          IconButton(
            icon: _isSyncingAttendance
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
            onPressed: (_isSyncingAttendance || _isImportingFile)
                ? null
                : _importAttendance,
            tooltip: 'مزامنة الحضور من أجهزة البصمة',
          ),
          IconButton(
            icon: const Icon(Icons.dashboard),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const EmployeeDashboardPage(),
                ),
              );
            },
            tooltip: 'لوحة الموظفين',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadStaff,
            tooltip: 'تحديث',
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSearchBar(textColor, subTextColor, goldColor, cardBg, borderColor, isDark),
          _buildStatsCards(textColor, goldColor, cardBg, borderColor),
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator(color: goldColor))
                : _filteredStaffList.isEmpty
                ? _buildEmptyState(textColor, subTextColor, goldColor)
                : _buildStaffList(textColor, subTextColor, goldColor, cardBg, borderColor, isDark),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addNewStaff,
        backgroundColor: goldColor,
        foregroundColor: const Color(0xFF0D1117),
        tooltip: 'إضافة موظف جديد',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildSearchBar(Color textColor, Color subTextColor, Color goldColor, Color cardBg, Color borderColor, bool isDark) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: TextField(
        controller: _searchController,
        style: TextStyle(color: textColor),
        decoration: InputDecoration(
          hintText: 'البحث بالاسم، المنصب، أو الرقم الوظيفي...',
          hintStyle: TextStyle(color: subTextColor),
          prefixIcon: Icon(Icons.search, color: goldColor),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.clear, color: subTextColor),
                  onPressed: () => _searchController.clear(),
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: borderColor),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: borderColor),
          ),
          filled: true,
          fillColor: cardBg,
        ),
      ),
    );
  }

  Widget _buildStatsCards(Color textColor, Color goldColor, Color cardBg, Color borderColor) {
    final activeStaff = _staffList
        .where((s) => s.status == 'active' && s.isActive)
        .length;
    final totalStaff = _staffList.length;
    final totalSalary = _staffList.fold<double>(
      0,
      (sum, staff) => sum + staff.basicSalary,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        children: [
          _buildStatCard('$activeStaff', 'موظف نشط', Colors.green, cardBg, borderColor),
          const SizedBox(width: 8),
          _buildStatCard('$totalStaff', 'إجمالي الموظفين', goldColor, cardBg, borderColor),
          const SizedBox(width: 8),
          _buildStatCard(totalSalary.toStringAsFixed(0), 'إجمالي المرتبات', Colors.tealAccent, cardBg, borderColor),
        ],
      ),
    );
  }

  Widget _buildStatCard(String value, String label, Color color, Color cardBg, Color borderColor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(Color textColor, Color subTextColor, Color goldColor) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline, size: 80, color: subTextColor),
          const SizedBox(height: 16),
          Text(
            'لا يوجد موظفين',
            style: TextStyle(fontSize: 22, color: textColor),
          ),
          const SizedBox(height: 8),
          Text(
            'اضغط على زر الإضافة لإنشاء موظف جديد',
            style: TextStyle(color: subTextColor),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _addNewStaff,
            icon: const Icon(Icons.add),
            label: const Text('إضافة موظف جديد'),
            style: ElevatedButton.styleFrom(
              backgroundColor: goldColor,
              foregroundColor: const Color(0xFF0D1117),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStaffList(Color textColor, Color subTextColor, Color goldColor, Color cardBg, Color borderColor, bool isDark) {
    return ListView.builder(
      padding: const EdgeInsets.all(8.0),
      itemCount: _filteredStaffList.length,
      itemBuilder: (context, index) {
        final staff = _filteredStaffList[index];
        return _buildStaffCard(staff, textColor, subTextColor, goldColor, cardBg, borderColor, isDark);
      },
    );
  }

  Widget _buildStaffCard(Staff staff, Color textColor, Color subTextColor, Color goldColor, Color cardBg, Color borderColor, bool isDark) {
    final isActive = staff.status == 'active' && staff.isActive;
    final statusColor = isActive ? Colors.green : Colors.redAccent;
    final statusText = isActive ? 'نشط' : 'غير نشط';

    return Card(
      color: cardBg,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor.withValues(alpha: 0.3)),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isActive ? Colors.green.withValues(alpha: 0.15) : Colors.redAccent.withValues(alpha: 0.15),
          child: Icon(
            Icons.person,
            color: isActive ? Colors.green : Colors.redAccent,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                staff.name,
                style: TextStyle(fontWeight: FontWeight.bold, color: textColor),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: statusColor.withValues(alpha: 0.5)),
              ),
              child: Text(
                statusText,
                style: TextStyle(
                  color: statusColor,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(staff.position, style: TextStyle(color: subTextColor)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.badge, size: 16, color: subTextColor),
                    const SizedBox(width: 4),
                    Text(staff.staffId, style: TextStyle(color: subTextColor)),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.fingerprint,
                      size: 16,
                      color: _biometricIdByStaffId.containsKey(staff.staffId)
                          ? Colors.teal
                          : subTextColor.withValues(alpha: 0.5),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _biometricIdByStaffId.containsKey(staff.staffId)
                          ? 'بصمة: ${_biometricIdByStaffId[staff.staffId]}'
                          : 'بدون بصمة',
                      style: TextStyle(
                        color: _biometricIdByStaffId.containsKey(staff.staffId)
                            ? Colors.teal
                            : subTextColor.withValues(alpha: 0.5),
                        fontWeight: _biometricIdByStaffId.containsKey(staff.staffId)
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
                if (staff.phone != null && staff.phone!.isNotEmpty)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.phone, size: 16, color: subTextColor),
                      const SizedBox(width: 4),
                      Text(staff.phone!, style: TextStyle(color: subTextColor)),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.attach_money, size: 16, color: Colors.green),
                const SizedBox(width: 4),
                Text(
                  staff.employmentType == 'weekly'
                      ? 'الراتب الأسبوعي: ${staff.basicSalary.toStringAsFixed(2)} ج.م'
                      : staff.employmentType == 'daily'
                          ? 'اليومية: ${staff.basicSalary.toStringAsFixed(2)} ج.م'
                          : 'المرتب الأساسي: ${staff.basicSalary.toStringAsFixed(2)} ج.م',
                  style: const TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          color: cardBg,
          iconColor: subTextColor,
          onSelected: (value) => _handleMenuAction(value, staff),
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'view',
              child: Row(
                children: [
                  Icon(Icons.visibility, color: goldColor),
                  const SizedBox(width: 8),
                  Text('عرض التفاصيل', style: TextStyle(color: textColor)),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'edit',
              child: Row(
                children: [
                  Icon(Icons.edit, color: Colors.orange),
                  const SizedBox(width: 8),
                  Text('تعديل', style: TextStyle(color: textColor)),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'biometric',
              child: Row(
                children: [
                  const Icon(Icons.fingerprint, color: Colors.teal),
                  const SizedBox(width: 8),
                  Text('ربط البصمة والجهاز', style: TextStyle(color: textColor)),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'attendance',
              child: Row(
                children: [
                  Icon(Icons.schedule, color: Colors.green),
                  const SizedBox(width: 8),
                  Text('سجل الحضور', style: TextStyle(color: textColor)),
                ],
              ),
            ),
            if (isActive) ...[
              PopupMenuItem(
                value: 'terminate',
                child: Row(
                  children: [
                    Icon(Icons.block, color: Colors.orangeAccent),
                    const SizedBox(width: 8),
                    Text('إنهاء الخدمة', style: TextStyle(color: textColor)),
                  ],
                ),
              ),
            ] else ...[
              PopupMenuItem(
                value: 'activate',
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green),
                    const SizedBox(width: 8),
                    Text('تفعيل', style: TextStyle(color: textColor)),
                  ],
                ),
              ),
            ],
            const PopupMenuDivider(),
            PopupMenuItem(
              value: 'delete',
              child: Row(
                children: const [
                  Icon(Icons.delete_forever, color: Colors.redAccent),
                  SizedBox(width: 8),
                  Text('حذف الموظف', style: TextStyle(color: Colors.redAccent)),
                ],
              ),
            ),
          ],
        ),
        onTap: () => _viewStaffDetails(staff),
      ),
    );
  }

  void _handleMenuAction(String action, Staff staff) async {
    switch (action) {
      case 'view':
        _viewStaffDetails(staff);
        break;
      case 'edit':
        _editStaff(staff);
        break;
      case 'biometric':
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => BiometricEnrollmentPage(staff: staff),
          ),
        );
        _loadStaff();
        break;
      case 'attendance':
        _viewAttendance(staff);
        break;
      case 'terminate':
        _terminateStaff(staff);
        break;
      case 'activate':
        _activateStaff(staff);
        break;
      case 'delete':
        _deleteStaff(staff);
        break;
    }
  }

  void _addNewStaff() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const StaffFormPage()),
    );
    if (result == true) {
      _loadStaff();
    }
  }

  void _viewStaffDetails(Staff staff) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => StaffDetailsPage(staff: staff)),
    );
    if (result == true) {
      _loadStaff();
    }
  }

  void _deleteStaff(Staff staff) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.redAccent, width: 1.5),
        ),
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 28),
            SizedBox(width: 8),
            Text(
              'تأكيد حذف الموظف',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'هل أنت متأكد من حذف الموظف "${staff.name}" نهائياً؟',
              style: const TextStyle(color: Color(0xFFE6EDF3), fontSize: 14),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
              ),
              child: const Text(
                'ملاحظة: سيتم استبعاد الموظف من القوائم وأجهزة البصمة، مع الحفاظ على الأثر المحاسبي لسجلات الرواتب السابقة.',
                style: TextStyle(color: Colors.redAccent, fontSize: 12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء', style: TextStyle(color: Color(0xFFC9A84C))),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.delete_forever, size: 18),
            label: const Text('تأكيد الحذف'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final user = ref.read(authProvider);
        await _service.deleteStaff(user, staff.staffId);
        await _loadStaff();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم حذف الموظف "${staff.name}" بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
      } catch (e) {
        if (!mounted) return;
        final errorMsg = e.toString().replaceAll('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _editStaff(Staff staff) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => StaffFormPage(staff: staff)),
    );
    if (result == true) {
      _loadStaff();
    }
  }

  void _viewAttendance(Staff staff) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AttendancePage(staff: staff)),
    );
  }

  void _terminateStaff(Staff staff) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        title: const Text('تأكيد إنهاء الخدمة'),
        content: Text(
          'هل أنت متأكد من إنهاء خدمة الموظف "${staff.name}"؟',
          style: const TextStyle(color: Color(0xFFE6EDF3)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء', style: TextStyle(color: Color(0xFFC9A84C))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('إنهاء الخدمة'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final user = ref.read(authProvider);
        await _service.terminateStaff(user, staff.staffId);
        _loadStaff();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إنهاء خدمة الموظف بنجاح')),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في إنهاء الخدمة: $e')),
        );
      }
    }
  }

  void _activateStaff(Staff staff) async {
    try {
      final user = ref.read(authProvider);
      await _service.updateStaffInfo(user, staffId: staff.staffId, status: 'active');
      _loadStaff();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تفعيل الموظف بنجاح')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ في تفعيل الموظف: $e')),
      );
    }
  }
}
