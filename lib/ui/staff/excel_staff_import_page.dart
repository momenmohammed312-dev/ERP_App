import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:gap/gap.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/provider/app_database_provider.dart';
import 'package:pos_offline_desktop/core/services/staff_excel_import_service.dart';

class ExcelStaffImportPage extends ConsumerStatefulWidget {
  const ExcelStaffImportPage({super.key});

  @override
  ConsumerState<ExcelStaffImportPage> createState() => _ExcelStaffImportPageState();
}

class _ExcelStaffImportPageState extends ConsumerState<ExcelStaffImportPage> {
  File? _pickedFile;
  StaffExcelPreview? _preview;
  StaffExcelCorrectionPreview? _correctionPreview;
  List<BiometricDevice> _devices = [];
  int? _selectedDeviceId;
  bool _loadingPreview = false;
  bool _importing = false;
  String? _fileError;
  bool _isCorrectionMode = true; // افتراضي: تصحيح (طلب العميل)

  // تنظيف المكرر
  List<Staff> _orphans = [];
  final Set<String> _selectedOrphans = {};
  bool _loadingOrphans = false;

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    final dao = ref.read(attendanceDeviceDaoProvider);
    final devices = await dao.getAllDevices();
    if (mounted) setState(() => _devices = devices);
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
      withData: false,
    );
    if (result != null && result.files.single.path != null) {
      setState(() {
        _pickedFile = File(result.files.single.path!);
        _preview = null;
        _correctionPreview = null;
        _fileError = null;
      });
    }
  }

  Future<void> _doPreview() async {
    if (_pickedFile == null) return;
    if (_selectedDeviceId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('اختر الجهاز أولاً قبل المعاينة'), backgroundColor: Colors.orange));
      return;
    }
    setState(() {
      _loadingPreview = true;
      _fileError = null;
    });
    try {
      final db = ref.read(appDatabaseProvider);
      final service = StaffExcelImportService(db);
      if (_isCorrectionMode) {
        final preview = await service.previewCorrection(_pickedFile!.path, deviceId: _selectedDeviceId!);
        if (!mounted) return;
        setState(() => _correctionPreview = preview);
        if (preview.fileErrors.isNotEmpty) setState(() => _fileError = preview.fileErrors.join('\n'));
      } else {
        final preview = await service.preview(_pickedFile!.path, deviceId: _selectedDeviceId!);
        if (!mounted) return;
        setState(() => _preview = preview);
        if (preview.fileErrors.isNotEmpty) setState(() => _fileError = preview.fileErrors.join('\n'));
      }
    } catch (e) {
      setState(() => _fileError = 'فشل قراءة الملف: $e');
    } finally {
      if (mounted) setState(() => _loadingPreview = false);
    }
  }

  Future<void> _doImport() async {
    if (_selectedDeviceId == null) return;
    final db = ref.read(appDatabaseProvider);
    final service = StaffExcelImportService(db);
    if (_isCorrectionMode) {
      if (_correctionPreview == null) return;
      final toUpdate = _correctionPreview!.updateCount + _correctionPreview!.createCount;
      if (toUpdate == 0) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا يوجد صفوف للتصحيح'), backgroundColor: Colors.red));
        return;
      }
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('تأكيد التصحيح'),
          content: Text('سيتم تحديث ${_correctionPreview!.updateCount} موظف ونقل أكواد البصمة، وإنشاء ${_correctionPreview!.createCount} جديد.\nالصفوف بدون تغيير: ${_correctionPreview!.noChangeCount}\nلن يتم مساس الحضور القديم. متأكد؟'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تأكيد التصحيح')),
          ],
        ),
      );
      if (confirm != true) return;
      setState(() => _importing = true);
      try {
        final result = await service.importCorrection(_correctionPreview!, deviceId: _selectedDeviceId!);
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(result.errors.isEmpty ? 'تم التصحيح' : 'اكتمل مع ملاحظات'),
            content: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text('تم تحديث ${result.updated} موظف'),
                Text('تم إنشاء ${result.created} جديد'),
                Text('تم تخطي ${result.skipped}'),
                if (result.errors.isNotEmpty) ...[
                  const Gap(12),
                  const Text('ملاحظات:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                  ...result.errors.map((e) => Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text('• $e', style: const TextStyle(fontSize: 12)))),
                ],
              ]),
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('موافق'))],
          ),
        );
        if (result.updated > 0 || result.created > 0) setState(() { _pickedFile = null; _correctionPreview = null; });
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل: $e'), backgroundColor: Colors.red));
      } finally {
        if (mounted) setState(() => _importing = false);
      }
    } else {
      if (_preview == null) return;
      final valid = _preview!.validCount;
      if (valid == 0) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا يوجد صفوف صالحة للاستيراد'), backgroundColor: Colors.red));
        return;
      }
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('تأكيد الاستيراد'),
          content: Text('سيتم إضافة $valid موظف جديد مع ربط البصمة للجهاز المختار. الصفوف المرفوضة ${_preview!.invalidCount} لن تُكتب. متأكد؟'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('استيراد')),
          ],
        ),
      );
      if (confirm != true) return;
      setState(() => _importing = true);
      try {
        final result = await service.import(_preview!, deviceId: _selectedDeviceId!);
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(result.errors.isEmpty ? 'تم الاستيراد' : 'اكتمل مع ملاحظات'),
            content: SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text('تمت إضافة ${result.addedStaff} موظف'),
                Text('تم ربط ${result.addedMappings} بصمة'),
                if (result.errors.isNotEmpty) ...[
                  const Gap(12),
                  const Text('لم يتم استيراد:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                  ...result.errors.map((e) => Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text('• $e', style: const TextStyle(fontSize: 12)))),
                ],
              ]),
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('موافق'))],
          ),
        );
        if (result.addedStaff > 0) setState(() { _pickedFile = null; _preview = null; });
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل الاستيراد: $e'), backgroundColor: Colors.red));
      } finally {
        if (mounted) setState(() => _importing = false);
      }
    }
  }

  Future<void> _loadOrphans() async {
    setState(() => _loadingOrphans = true);
    try {
      final db = ref.read(appDatabaseProvider);
      final service = StaffExcelImportService(db);
      final list = await service.findOrphanStaff();
      if (!mounted) return;
      setState(() { _orphans = list; _selectedOrphans.clear(); });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل فحص المكرر: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _loadingOrphans = false);
    }
  }

  Future<void> _deleteSelectedOrphans() async {
    if (_selectedOrphans.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('سيتم حذف ${_selectedOrphans.length} موظف بدون حضور نهائياً (مع فك ربط البصمة). لا يمكن التراجع. متأكد؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final db = ref.read(appDatabaseProvider);
      final service = StaffExcelImportService(db);
      final n = await service.deleteOrphanStaff(_selectedOrphans.toList());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم حذف $n موظف'), backgroundColor: Colors.green));
      _loadOrphans();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل الحذف: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: const Text('استيراد / تصحيح موظفين من Excel')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('الجهاز المرتبط برقم البصمة *', style: TextStyle(fontWeight: FontWeight.bold)),
                  const Gap(8),
                  DropdownButtonFormField<int>(
                    initialValue: _selectedDeviceId,
                    decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'اختر الجهاز'),
                    items: _devices.map((d) => DropdownMenuItem(value: d.id, child: Text('${d.name} (${d.ipAddress ?? d.deviceCode})'))).toList(),
                    onChanged: (v) => setState(() { _selectedDeviceId = v; _preview = null; _correctionPreview = null; }),
                  ),
                  if (_devices.isEmpty) const Padding(padding: EdgeInsets.only(top: 8), child: Text('لا يوجد أجهزة — أضف جهازاً من إدارة الأجهزة أولاً', style: TextStyle(color: Colors.red, fontSize: 12))),
                ]),
              ),
            ),
            const Gap(12),
            Card(
              color: isDark ? const Color(0xFF2E2A15) : Colors.amber.shade50,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: isDark ? const Color(0xFF6B5A1E) : Colors.amber.shade200),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('وضع الاستيراد', style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.amber.shade200 : Colors.black87)),
                  const Gap(8),
                  SegmentedButton<bool>(
                    style: ButtonStyle(
                      backgroundColor: WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.selected)) return isDark ? Colors.amber.shade700 : Colors.amber.shade200;
                        return null;
                      }),
                      foregroundColor: WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.selected)) return isDark ? Colors.white : Colors.black87;
                        return isDark ? Colors.white70 : Colors.black54;
                      }),
                    ),
                    segments: const [
                      ButtonSegment(value: true, label: Text('تصحيح بالاسم'), icon: Icon(Icons.edit)),
                      ButtonSegment(value: false, label: Text('إضافة جديدة'), icon: Icon(Icons.person_add)),
                    ],
                    selected: {_isCorrectionMode},
                    onSelectionChanged: (s) => setState(() { _isCorrectionMode = s.first; _preview = null; _correctionPreview = null; _fileError = null; }),
                  ),
                  const Gap(8),
                  Text(
                    _isCorrectionMode
                        ? 'يقرأ الإكسل (اسم الموظف + كود البصمة) ويحدّث كود البصمة للموظف المطابق بالاسم. ينقل الكود لو كان مربوط لموظف آخر، ويحذف الدبلرة. لا يمس الحضور القديم.'
                        : 'إضافة موظفين جدد فقط — يرفض أي اسم/كود بصمة موجود مسبقاً.',
                    style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black87),
                  ),
                ]),
              ),
            ),
            const Gap(12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  Row(children: [
                    const Icon(Icons.upload_file, size: 32, color: Colors.blue),
                    const Gap(12),
                    Expanded(child: Text(_pickedFile == null ? 'اختر ملف .xlsx' : 'الملف: ${_pickedFile!.path.split('/').last.split('\\').last}')),
                  ]),
                  const Gap(12),
                  Row(children: [
                    ElevatedButton.icon(onPressed: _pickFile, icon: const Icon(Icons.folder_open), label: const Text('اختيار ملف')),
                    const Gap(8),
                    OutlinedButton.icon(
                      onPressed: (_pickedFile != null && !_loadingPreview) ? _doPreview : null,
                      icon: _loadingPreview ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.preview),
                      label: const Text('معاينة'),
                    ),
                  ]),
                ]),
              ),
            ),
            if (_fileError != null) ...[
              const Gap(12),
              Card(
                color: isDark ? const Color(0xFF2D1B1B) : Colors.red.shade50,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: isDark ? const Color(0xFF6B2A2A) : Colors.red.shade200),
                ),
                child: Padding(padding: const EdgeInsets.all(12), child: Text(_fileError!, style: TextStyle(color: isDark ? Colors.red.shade300 : Colors.red))),
              ),
            ],
            if (_isCorrectionMode && _correctionPreview != null) ...[
              const Gap(16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('معاينة التصحيح — تحديث: ${_correctionPreview!.updateCount} / إنشاء: ${_correctionPreview!.createCount} / بدون تغيير: ${_correctionPreview!.noChangeCount} / مرفوض: ${_correctionPreview!.invalidCount} / الإجمالي: ${_correctionPreview!.total}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    const Gap(8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        headingRowColor: WidgetStateProperty.all(isDark ? const Color(0xFF21262D) : Colors.grey.shade100),
                        columns: const [
                          DataColumn(label: Text('#')),
                          DataColumn(label: Text('الاسم')),
                          DataColumn(label: Text('الكود الجديد')),
                          DataColumn(label: Text('الحالي')),
                          DataColumn(label: Text('الإجراء')),
                          DataColumn(label: Text('الحالة')),
                        ],
                        rows: _correctionPreview!.items.map((it) {
                          final r = it.row;
                          final cur = it.currentMappings.isEmpty ? '-' : it.currentMappings.map((m) => m.externalUserId).join(',');
                          String actionLabel;
                          Color c;
                          switch (it.action) {
                            case 'update': actionLabel = 'تحديث'; c = Colors.orange; break;
                            case 'create': actionLabel = 'إنشاء'; c = Colors.blue; break;
                            case 'no_change': actionLabel = 'كما هو'; c = Colors.green; break;
                            default: actionLabel = it.action; c = Colors.grey;
                          }
                          return DataRow(
                            color: WidgetStateProperty.all(
                              it.isValid
                                  ? (it.action == 'no_change'
                                      ? (isDark ? const Color(0xFF1A2E1A) : Colors.green.shade50)
                                      : (isDark ? const Color(0xFF161B22) : Colors.white))
                                  : (isDark ? const Color(0xFF2D1B1B) : Colors.red.shade50),
                            ),
                            cells: [
                              DataCell(Text('${r.excelRowNumber}')),
                              DataCell(Text(r.name.isEmpty ? '-' : r.name)),
                              DataCell(Text(r.externalId.isEmpty ? '-' : r.externalId)),
                              DataCell(Text(cur)),
                              DataCell(Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: c.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)), child: Text(actionLabel, style: TextStyle(color: c, fontSize: 12)))),
                              DataCell(it.isValid ? const Icon(Icons.check_circle, color: Colors.green, size: 18) : Tooltip(message: it.errors.join('\n'), child: const Icon(Icons.error, color: Colors.red, size: 18))),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                    if (_correctionPreview!.items.any((e) => !e.isValid)) ...[
                      const Gap(8),
                      ..._correctionPreview!.items.where((e) => !e.isValid).map((e) => Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text('صف ${e.row.excelRowNumber} (${e.row.name}): ${e.errors.join('، ')}', style: const TextStyle(fontSize: 12, color: Colors.red)))),
                    ],
                  ]),
                ),
              ),
              const Gap(16),
              ElevatedButton.icon(
                onPressed: _importing ? null : _doImport,
                icon: _importing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save),
                label: Text(_importing ? 'جاري التصحيح...' : 'تطبيق التصحيح (${_correctionPreview!.updateCount + _correctionPreview!.createCount})'),
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), backgroundColor: Colors.teal, foregroundColor: Colors.white),
              ),
            ],
            if (!_isCorrectionMode && _preview != null) ...[
              const Gap(16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('المعاينة — صالح: ${_preview!.validCount} / مرفوض: ${_preview!.invalidCount} / الإجمالي: ${_preview!.total}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    const Gap(8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        headingRowColor: WidgetStateProperty.all(isDark ? const Color(0xFF21262D) : Colors.grey.shade100),
                        columns: const [
                          DataColumn(label: Text('#')),
                          DataColumn(label: Text('الاسم')),
                          DataColumn(label: Text('الكود')),
                          DataColumn(label: Text('الوظيفة')),
                          DataColumn(label: Text('المرتب')),
                          DataColumn(label: Text('رقم البصمة')),
                          DataColumn(label: Text('الحالة')),
                        ],
                        rows: _preview!.rows.map((v) {
                          final r = v.row;
                          return DataRow(
                            color: WidgetStateProperty.all(v.isValid ? (isDark ? const Color(0xFF161B22) : Colors.white) : (isDark ? const Color(0xFF2D1B1B) : Colors.red.shade50)),
                            cells: [
                              DataCell(Text('${r.excelRowNumber}')),
                              DataCell(Text(r.name.isEmpty ? '-' : r.name)),
                              DataCell(Text(v.resolvedStaffId ?? r.staffIdRaw ?? '(تلقائي)')),
                              DataCell(Text(r.position.isEmpty ? '-' : r.position)),
                              DataCell(Text(r.basicSalary.toStringAsFixed(0))),
                              DataCell(Text(r.externalId.isEmpty ? '-' : r.externalId)),
                              DataCell(v.isValid ? const Icon(Icons.check_circle, color: Colors.green, size: 18) : Tooltip(message: v.errors.join('\n'), child: const Icon(Icons.error, color: Colors.red, size: 18))),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                    if (_preview!.rows.any((v) => !v.isValid)) ...[
                      const Gap(8),
                      ..._preview!.rows.where((v) => !v.isValid).map((v) => Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text('صف ${v.row.excelRowNumber}: ${v.errors.join('، ')}', style: const TextStyle(fontSize: 12, color: Colors.red)))),
                    ],
                  ]),
                ),
              ),
              const Gap(16),
              ElevatedButton.icon(
                onPressed: _importing ? null : _doImport,
                icon: _importing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.cloud_download),
                label: Text(_importing ? 'جاري الاستيراد...' : 'استيراد ${_preview!.validCount} موظف'),
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), backgroundColor: Colors.teal, foregroundColor: Colors.white),
              ),
            ],
            const Gap(24),
            const Divider(),
            const Gap(8),
            Card(
              color: isDark ? const Color(0xFF2D1B1B) : Colors.red.shade50,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: isDark ? const Color(0xFF6B2A2A) : Colors.red.shade200),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('تنظيف المكرر الفاضي (بدون حضور)', style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.red.shade300 : Colors.red)),
                  const Gap(4),
                  Text('يبحث عن موظفين وظيفتهم "موظف" ومرتبهم 0 وبدون أي سجل حضور — دول غالباً الدبلرة اللي عايز تشيلهم.', style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black54)),
                  const Gap(12),
                  Row(children: [
                    ElevatedButton.icon(onPressed: _loadingOrphans ? null : _loadOrphans, icon: _loadingOrphans ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.search), label: const Text('فحص المكررات')),
                    const Gap(8),
                    if (_orphans.isNotEmpty) ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white), onPressed: _selectedOrphans.isEmpty ? null : _deleteSelectedOrphans, icon: const Icon(Icons.delete_forever), label: Text('حذف المحدد (${_selectedOrphans.length})')),
                  ]),
                  if (_orphans.isNotEmpty) ...[
                    const Gap(12),
                    Row(children: [
                      TextButton(onPressed: () => setState(() => _selectedOrphans.addAll(_orphans.map((e) => e.staffId))), child: const Text('تحديد الكل')),
                      TextButton(onPressed: () => setState(() => _selectedOrphans.clear()), child: const Text('إلغاء التحديد')),
                    ]),
                    ..._orphans.map((s) => CheckboxListTile(
                          value: _selectedOrphans.contains(s.staffId),
                          onChanged: (v) => setState(() => v == true ? _selectedOrphans.add(s.staffId) : _selectedOrphans.remove(s.staffId)),
                          title: Text(s.name),
                          subtitle: Text('${s.staffId} — ${s.position} — ${s.basicSalary.toStringAsFixed(0)} ج.م'),
                          dense: true,
                        )),
                  ] else if (!_loadingOrphans && _orphans.isEmpty) ...[
                    const Gap(8),
                    Text('اضغط "فحص المكررات" لعرض القائمة.', style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.black54)),
                  ],
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
