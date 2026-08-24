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
  List<BiometricDevice> _devices = [];
  int? _selectedDeviceId;
  bool _loadingPreview = false;
  bool _importing = false;
  String? _fileError;

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
      final preview = await service.preview(_pickedFile!.path, deviceId: _selectedDeviceId!);
      if (!mounted) return;
      setState(() => _preview = preview);
      if (preview.fileErrors.isNotEmpty) {
        setState(() => _fileError = preview.fileErrors.join('\n'));
      }
    } catch (e) {
      setState(() => _fileError = 'فشل قراءة الملف: $e');
    } finally {
      if (mounted) setState(() => _loadingPreview = false);
    }
  }

  Future<void> _doImport() async {
    if (_preview == null || _selectedDeviceId == null) return;
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
      final db = ref.read(appDatabaseProvider);
      final service = StaffExcelImportService(db);
      final result = await service.import(_preview!, deviceId: _selectedDeviceId!);
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(result.errors.isEmpty ? 'تم الاستيراد' : 'اكتمل مع ملاحظات'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('تمت إضافة ${result.addedStaff} موظف'),
                Text('تم ربط ${result.addedMappings} بصمة'),
                if (result.errors.isNotEmpty) ...[
                  const Gap(12),
                  const Text('لم يتم استيراد:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                  const Gap(4),
                  ...result.errors.map((e) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text('• $e', style: const TextStyle(fontSize: 12)),
                      )),
                ],
              ],
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('موافق'))],
        ),
      );
      if (result.addedStaff > 0) {
        setState(() {
          _pickedFile = null;
          _preview = null;
        });
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل الاستيراد: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('استيراد موظفين من Excel')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            // Device selector — إجباري قبل المعاينة
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('الجهاز المرتبط برقم البصمة *', style: TextStyle(fontWeight: FontWeight.bold)),
                    const Gap(8),
                    DropdownButtonFormField<int>(
                      initialValue: _selectedDeviceId,
                      decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'اختر الجهاز'),
                      items: _devices.map((d) => DropdownMenuItem(value: d.id, child: Text('${d.name} (${d.ipAddress ?? d.deviceCode})'))).toList(),
                      onChanged: (v) => setState(() {
                        _selectedDeviceId = v;
                        _preview = null;
                      }),
                    ),
                    if (_devices.isEmpty) const Padding(padding: EdgeInsets.only(top: 8), child: Text('لا يوجد أجهزة — أضف جهازاً من إدارة الأجهزة أولاً', style: TextStyle(color: Colors.red, fontSize: 12))),
                  ],
                ),
              ),
            ),
            const Gap(12),
            // File picker
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.upload_file, size: 32, color: Colors.blue),
                        const Gap(12),
                        Expanded(child: Text(_pickedFile == null ? 'اختر ملف .xlsx' : 'الملف: ${_pickedFile!.path.split('/').last.split('\\').last}')),
                      ],
                    ),
                    const Gap(12),
                    Row(
                      children: [
                        ElevatedButton.icon(onPressed: _pickFile, icon: const Icon(Icons.folder_open), label: const Text('اختيار ملف')),
                        const Gap(8),
                        OutlinedButton.icon(
                          onPressed: (_pickedFile != null && !_loadingPreview) ? _doPreview : null,
                          icon: _loadingPreview ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.preview),
                          label: const Text('معاينة'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (_fileError != null) ...[
              const Gap(12),
              Card(color: Colors.red.shade50, child: Padding(padding: const EdgeInsets.all(12), child: Text(_fileError!, style: const TextStyle(color: Colors.red)))),
            ],
            if (_preview != null) ...[
              const Gap(16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('المعاينة — صالح: ${_preview!.validCount} / مرفوض: ${_preview!.invalidCount} / الإجمالي: ${_preview!.total}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      const Gap(8),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          headingRowColor: WidgetStateProperty.all(Colors.grey.shade100),
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
                              color: WidgetStateProperty.all(v.isValid ? Colors.white : Colors.red.shade50),
                              cells: [
                                DataCell(Text('${r.excelRowNumber}')),
                                DataCell(Text(r.name.isEmpty ? '-' : r.name)),
                                DataCell(Text(v.resolvedStaffId ?? r.staffIdRaw ?? '(تلقائي)')),
                                DataCell(Text(r.position.isEmpty ? '-' : r.position)),
                                DataCell(Text(r.basicSalary.toStringAsFixed(0))),
                                DataCell(Text(r.externalId.isEmpty ? '-' : r.externalId)),
                                DataCell(v.isValid
                                    ? const Icon(Icons.check_circle, color: Colors.green, size: 18)
                                    : Tooltip(message: v.errors.join('\n'), child: const Icon(Icons.error, color: Colors.red, size: 18))),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                      if (_preview!.rows.any((v) => !v.isValid)) ...[
                        const Gap(8),
                        ..._preview!.rows.where((v) => !v.isValid).map((v) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Text('صف ${v.row.excelRowNumber}: ${v.errors.join('، ')}', style: const TextStyle(fontSize: 12, color: Colors.red)),
                            )),
                      ],
                    ],
                  ),
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
          ],
        ),
      ),
    );
  }
}
