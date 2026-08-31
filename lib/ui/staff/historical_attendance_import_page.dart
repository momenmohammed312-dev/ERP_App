import 'dart:io';
import 'package:flutter/material.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/provider/app_database_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_offline_desktop/core/services/historical_attendance_import_service.dart';

class HistoricalAttendanceImportPage extends ConsumerStatefulWidget {
  const HistoricalAttendanceImportPage({super.key});
  @override
  ConsumerState<HistoricalAttendanceImportPage> createState() => _HistoricalAttendanceImportPageState();
}

class _HistoricalAttendanceImportPageState extends ConsumerState<HistoricalAttendanceImportPage> {
  File? _file;
  Excel? _excel;
  Map<String, Staff?>? _match;
  Map<String, List<RowParseResult>>? _parsed;
  List<SheetImportReport>? _report;
  bool _importing = false;
  String? _error;

  Future<void> _pickFile() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx'], withData: false);
    if (res != null && res.files.single.path != null) {
      final file = File(res.files.single.path!);
      try {
        final bytes = await file.readAsBytes();
        final excel = Excel.decodeBytes(bytes);
        final db = ref.read(appDatabaseProvider);
        final staffList = await db.staffManagementDao.getAllStaff();
        final service = HistoricalAttendanceImportService(db);
        final match = service.matchSheetsToStaff(excel.tables.keys.toList(), staffList);
        final parsed = <String, List<RowParseResult>>{};
        for (final e in excel.tables.entries) {
          parsed[e.key] = service.parseSheetRows(e.value);
        }
        setState(() {
          _file = file;
          _excel = excel;
          _match = match;
          _parsed = parsed;
          _report = null;
          _error = null;
        });
      } catch (e) {
        setState(() => _error = 'فشل قراءة الملف: $e');
      }
    }
  }

  Future<void> _runImport() async {
    if (_excel == null) return;
    setState(() { _importing = true; _error = null; });
    try {
      final db = ref.read(appDatabaseProvider);
      final service = HistoricalAttendanceImportService(db);
      final reports = await service.importFromExcel(_excel!);
      setState(() => _report = reports);
      if (mounted) {
        final total = reports.fold(0, (s, r) => s + r.imported);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم الاستيراد: $total سجل'), backgroundColor: Colors.green));
      }
    } catch (e) {
      setState(() => _error = 'فشل الاستيراد: $e');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('استيراد حضور تاريخي - أغسطس')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                Row(children: [const Icon(Icons.upload_file, color: Colors.blue), const SizedBox(width: 12), Expanded(child: Text(_file == null ? 'اختر ملف .xlsx (شيت لكل موظف)' : 'الملف: ${_file!.path.split(Platform.pathSeparator).last}'))]),
                const SizedBox(height: 12),
                ElevatedButton.icon(onPressed: _importing ? null : _pickFile, icon: const Icon(Icons.folder_open), label: const Text('اختيار ملف')),
              ]),
            ),
          ),
          if (_error != null) Card(color: Colors.red.shade50, child: Padding(padding: const EdgeInsets.all(12), child: Text(_error!, style: const TextStyle(color: Colors.red)))),
          if (_match != null) ...[
            const SizedBox(height: 12),
            const Text('معاينة المطابقة (Preview إجباري)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            Card(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(columns: const [DataColumn(label: Text('الشيت')), DataColumn(label: Text('الموظف المطابق')), DataColumn(label: Text('الصفوف')), DataColumn(label: Text('حضور/غياب'))], rows: _match!.entries.map((e) {
                  final staff = e.value;
                  final rows = _parsed![e.key] ?? [];
                  final present = rows.where((r) => r.status == 'present').length;
                  final absent = rows.where((r) => r.status == 'absent').length;
                  final hasError = rows.any((r) => r.error != null);
                  return DataRow(cells: [
                    DataCell(Text(e.key)),
                    DataCell(Text(staff == null ? '❌ لم يُطابق' : '✅ ${staff.name} (${staff.staffId})', style: TextStyle(color: staff == null ? Colors.red : Colors.green))),
                    DataCell(Text('${rows.length}')),
                    DataCell(Text('حضور:$present غياب:$absent ${hasError ? '⚠ أخطاء' : ''}')),
                  ]);
                }).toList()),
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: ExpansionTile(title: const Text('تفاصيل الصفوف (أول 5 صفوف لكل شيت)'), children: _parsed!.entries.map((e) {
                final rows = e.value.take(5).toList();
                return Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(e.key, style: const TextStyle(fontWeight: FontWeight.bold)),
                    ...rows.map((r) => Text('صف ${r.rowIndex}: ${r.date?.toIso8601String().substring(0,10) ?? '-'} حضور:${r.rawPresence} انصراف:${r.rawCheckout} → ${r.status} ${r.error ?? ''}', style: TextStyle(fontSize: 12, color: r.error != null ? Colors.red : Colors.black54))),
                  ]),
                );
              }).toList()),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(onPressed: _importing ? null : _runImport, icon: _importing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.cloud_download), label: Text(_importing ? 'جاري الاستيراد...' : 'تأكيد وتنفيذ الاستيراد'), style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), backgroundColor: Colors.teal, foregroundColor: Colors.white)),
          ],
          if (_report != null) ...[
            const SizedBox(height: 16),
            const Text('تقرير النتيجة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            Card(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(columns: const [DataColumn(label: Text('الشيت')), DataColumn(label: Text('مطابق')), DataColumn(label: Text('مستورد')), DataColumn(label: Text('تخطي')), DataColumn(label: Text('تعارض')), DataColumn(label: Text('أخطاء'))], rows: _report!.map((r) => DataRow(cells: [
                  DataCell(Text(r.sheetName)),
                  DataCell(Text(r.staff == null ? '—' : r.staff!.name)),
                  DataCell(Text('${r.imported}', style: const TextStyle(color: Colors.green))),
                  DataCell(Text('${r.skippedExists}')),
                  DataCell(Text('${r.conflicts}', style: TextStyle(color: r.conflicts > 0 ? Colors.orange : Colors.black))),
                  DataCell(Text('${r.parseErrors}', style: TextStyle(color: r.parseErrors > 0 ? Colors.red : Colors.black))),
                ])).toList()),
              ),
            ),
            ..._report!.where((r) => r.errors.isNotEmpty).map((r) => Card(color: Colors.orange.shade50, child: Padding(padding: const EdgeInsets.all(8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(r.sheetName, style: const TextStyle(fontWeight: FontWeight.bold)), ...r.errors.map((e) => Text('• $e', style: const TextStyle(fontSize: 12))) ])))),
          ],
        ]),
      ),
    );
  }
}
