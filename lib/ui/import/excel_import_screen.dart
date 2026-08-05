import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';

import 'package:pos_offline_desktop/core/config/app_features.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/services/vegetable_market_import_service.dart';

/// شاشة استيراد البيانات من إكسل (vegetable flavor only)
class ExcelImportScreen extends StatefulWidget {
  final AppDatabase db;

  const ExcelImportScreen({super.key, required this.db});

  @override
  State<ExcelImportScreen> createState() => _ExcelImportScreenState();
}

class _ExcelImportScreenState extends State<ExcelImportScreen> {
  File? _pickedFile;
  Map<String, dynamic>? _preview;
  bool _importing = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    if (!AppFeatures.hasShipmentTracking) {
      return const Scaffold(body: Center(child: Text('ميزة الاستيراد متاحة في فليفر سوق الخضار فقط')));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('استيراد من إكسل (سوق الخضار)')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Pick file
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.upload_file, size: 32, color: Colors.blue),
                        const Gap(12),
                        Expanded(
                          child: Text(
                            _pickedFile == null
                                ? 'اختر ملف .xlsx للاستيراد'
                                : 'الملف: ${_pickedFile!.path.split('/').last}',
                          ),
                        ),
                      ],
                    ),
                    const Gap(12),
                    ElevatedButton.icon(
                      onPressed: _importing ? null : _pickFile,
                      icon: const Icon(Icons.folder_open),
                      label: const Text('اختيار ملف'),
                    ),
                    if (_pickedFile != null) ...[
                      const Gap(8),
                      OutlinedButton.icon(
                        onPressed: _importing ? null : _previewFile,
                        icon: const Icon(Icons.preview),
                        label: const Text('معاينة قبل الاستيراد'),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const Gap(16),

            // Preview
            if (_preview != null) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('معاينة البيانات', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const Gap(8),
                      _buildPreviewRow('الموردين', _preview!['suppliers']),
                      _buildPreviewRow('العملاء', _preview!['customers']),
                      _buildPreviewRow('الشحنات', _preview!['shipments']),
                      _buildPreviewRow('المبيعات', _preview!['sales']),
                      _buildPreviewRow('المصروفات', _preview!['expenses']),
                      _buildPreviewRow('التحصيلات', _preview!['collections']),
                      _buildPreviewRow('البرانيك الفاضية', _preview!['emptyBarnika']),
                    ],
                  ),
                ),
              ),
              const Gap(16),
            ],

            // Error display
            if (_error != null)
              Card(
                color: Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(_error!, style: const TextStyle(color: Colors.red)),
                ),
              ),

            const Gap(16),

            // Import button
            ElevatedButton.icon(
              onPressed: _importing ? null : _runImport,
              icon: _importing
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.cloud_download),
              label: Text(_importing ? 'جاري الاستيراد...' : 'تنفيذ الاستيراد'),
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), backgroundColor: Colors.teal, foregroundColor: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewRow(String label, dynamic value) {
    final count = (value is List) ? value.length : 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text('$count سجل', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal)),
        ],
      ),
    );
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      withData: false,
    );
    if (result != null && result.files.single.path != null) {
      setState(() {
        _pickedFile = File(result.files.single.path!);
        _preview = null;
        _error = null;
      });
    }
  }

  Future<void> _previewFile() async {
    if (_pickedFile == null) return;
    setState(() => _error = null);
    try {
      final bytes = await _pickedFile!.readAsBytes();
      final excel = Excel.decodeBytes(bytes);
      final preview = <String, dynamic>{};

      // Sheets expected by the import service
      final sheets = ['suppliers', 'customers', 'shipments', 'sales', 'expenses', 'collections', 'emptyBarnikaRecords'];
      for (final sheetName in sheets) {
        final sheet = excel.tables[sheetName];
        if (sheet != null) {
          // Skip header row
          preview[sheetName] = sheet.rows.skip(1).map((r) => r.map((c) => c?.value).toList()).toList();
        } else {
          preview[sheetName] = [];
        }
      }
      setState(() => _preview = preview);
    } catch (e) {
      setState(() => _error = 'فشل قراءة الملف: $e');
    }
  }

  Future<void> _runImport() async {
    if (_pickedFile == null) return;
    setState(() {
      _importing = true;
      _error = null;
    });
    try {
      final result = await VegetableMarketImportService(widget.db).importFromFile(_pickedFile!.path);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم الاستيراد: ${result.total} سجل (موردين: ${result.suppliers}, عملاء: ${result.customers}, شحنات: ${result.shipments}, مبيعات: ${result.sales}, مصروفات: ${result.expenses}, تحصيلات: ${result.collections}, برانيك: ${result.emptyBarnika})${result.errors.isNotEmpty ? ' — أخطاء: ${result.errors.length}' : ''}'),
          backgroundColor: result.errors.isEmpty ? Colors.green : Colors.orange,
          duration: const Duration(seconds: 5),
        ),
      );
      if (result.errors.isNotEmpty) {
        _showErrorsDialog(result.errors);
      }
      setState(() {
        _pickedFile = null;
        _preview = null;
      });
    } catch (e) {
      setState(() => _error = 'فشل الاستيراد: $e');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  void _showErrorsDialog(List<String> errors) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('أخطاء الاستيراد (أول 20)'),
        content: SizedBox(
          width: 400,
          height: 300,
          child: ListView(
            children: errors.take(20).map((e) => ListTile(title: Text(e, style: const TextStyle(fontSize: 12)))).toList(),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('موافق'))],
      ),
    );
  }
}