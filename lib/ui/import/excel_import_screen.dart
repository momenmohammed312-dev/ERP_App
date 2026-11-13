import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:pos_offline_desktop/core/config/app_features.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/platform/platform_utils.dart';
import 'package:pos_offline_desktop/core/services/vegetable_market_import_service.dart';

/// شاشة استيراد الأرصدة الافتتاحية وبيانات سوق الخضار من إكسل (.xlsx)
class ExcelImportScreen extends StatefulWidget {
  final AppDatabase db;

  const ExcelImportScreen({super.key, required this.db});

  @override
  State<ExcelImportScreen> createState() => _ExcelImportScreenState();
}

class _ExcelImportScreenState extends State<ExcelImportScreen> {
  File? _pickedFile;
  Uint8List? _pickedBytes;
  String? _pickedName;
  VegetableExcelPreview? _preview;
  bool _importCustomers = true;
  bool _importSuppliers = true;
  bool _importing = false;
  bool _downloadingTemplate = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    if (!AppFeatures.hasShipmentTracking) {
      return const Scaffold(
        body: Center(
          child: Text('ميزة الاستيراد متاحة في فليفر سوق الخضار فقط'),
        ),
      );
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('استيراد الأرصدة الافتتاحية (.xlsx)'),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Opening-balance template download card
              Card(
                color: Colors.teal.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.table_chart_outlined, color: Colors.teal),
                          Gap(8),
                          Expanded(
                            child: Text(
                              'قالب البداية النظيفة (الأرصدة الافتتاحية)',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Gap(6),
                      const Text(
                        'يحتوي القالب على ورقتَي عمل بالعربية: «العملاء» (الاسم، الهاتف، العنوان، رصيد الآجل الافتتاحي، رصيد البرانيك الفارغة) و«الموردين» (الاسم، الهاتف، العنوان، الرصيد الافتتاحي).',
                        style: TextStyle(fontSize: 12.5, color: Colors.black87),
                      ),
                      const Gap(10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _downloadingTemplate
                              ? null
                              : _downloadOpeningBalanceTemplate,
                          icon: _downloadingTemplate
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.download_outlined),
                          label: const Text('تحميل قالب الأرصدة الافتتاحية (.xlsx)'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const Gap(14),

              // Pick file card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.upload_file,
                            size: 30,
                            color: Colors.blue,
                          ),
                          const Gap(12),
                          Expanded(
                            child: Text(
                              _pickedName == null
                                  ? 'اختر ملف .xlsx المجهّز للاستيراد'
                                  : 'الملف المختار: $_pickedName',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                      const Gap(12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          ElevatedButton.icon(
                            onPressed: _importing ? null : _pickFile,
                            icon: const Icon(Icons.folder_open),
                            label: const Text('اختيار ملف .xlsx'),
                          ),
                          if (_pickedBytes != null || _pickedFile != null)
                            OutlinedButton.icon(
                              onPressed: _importing ? null : _previewFile,
                              icon: const Icon(Icons.preview),
                              label: const Text('تحديث المعاينة'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const Gap(14),

              // Preview card
              if (_preview != null) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'معاينة البيانات قبل التنفيذ',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        if (_preview!.detectedSheets.isNotEmpty) ...[
                          const Gap(4),
                          Text(
                            'الأوراق المكتشفة: ${_preview!.detectedSheets.join('، ')}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                        const Divider(height: 18),
                        SwitchListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          value: _importCustomers,
                          onChanged: _importing
                              ? null
                              : (v) => setState(() => _importCustomers = v),
                          title: Text('استيراد الزباين (${_preview!.customers.length})'),
                          subtitle: Text(
                            'آجل افتتاحي: ${_preview!.customersOpeningDebtTotal.toStringAsFixed(2)} ج.م • برانيك فارغة: ${_preview!.openingBarnikaTotal}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        SwitchListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          value: _importSuppliers,
                          onChanged: _importing
                              ? null
                              : (v) => setState(() => _importSuppliers = v),
                          title: Text('استيراد الموردين (${_preview!.suppliers.length})'),
                          subtitle: Text(
                            'رصيد افتتاحي: ${_preview!.suppliersOpeningCreditTotal.toStringAsFixed(2)} ج.م',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        if (_preview!.shipmentsCount > 0 ||
                            _preview!.salesCount > 0 ||
                            _preview!.expensesCount > 0 ||
                            _preview!.collectionsCount > 0 ||
                            _preview!.emptyBarnikaRecordsCount > 0) ...[
                          const Divider(height: 16),
                          _buildCountRow('الشحنات', _preview!.shipmentsCount),
                          _buildCountRow('المبيعات', _preview!.salesCount),
                          _buildCountRow('المصروفات', _preview!.expensesCount),
                          _buildCountRow('التحصيلات', _preview!.collectionsCount),
                          _buildCountRow(
                            'سجلات البرانيك',
                            _preview!.emptyBarnikaRecordsCount,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const Gap(12),
                if (_preview!.duplicateWarnings.isNotEmpty) ...[
                  Card(
                    color: Colors.orange.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.warning_amber_rounded,
                                color: Colors.orange,
                              ),
                              const Gap(8),
                              Expanded(
                                child: Text(
                                  'تنبيه تكرار/تشابه أسماء (${_preview!.duplicateWarnings.length}) — سيتم تخطيها تلقائياً',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.orange.shade900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const Gap(8),
                          ..._preview!.duplicateWarnings.take(8).map(
                                (w) => Padding(
                                  padding: const EdgeInsets.only(bottom: 3),
                                  child: Text(
                                    '• $w',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                              ),
                          if (_preview!.duplicateWarnings.length > 8)
                            Text(
                              'و ${_preview!.duplicateWarnings.length - 8} تنبيهات أخرى...',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: Colors.orange.shade800,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const Gap(12),
                ],
              ],

              // Error display
              if (_error != null) ...[
                Card(
                  color: Colors.red.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                ),
                const Gap(12),
              ],

              // Import execute button
              ElevatedButton.icon(
                onPressed: (_importing ||
                        (_pickedBytes == null && _pickedFile == null))
                    ? null
                    : _runImport,
                icon: _importing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.cloud_download),
                label: Text(_importing ? 'جاري الاستيراد...' : 'تنفيذ الاستيراد'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                ),
              ),
              const Gap(24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCountRow(String label, int count) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            '$count سجل',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.teal,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadOpeningBalanceTemplate() async {
    setState(() {
      _downloadingTemplate = true;
      _error = null;
    });
    try {
      final bytes = VegetableMarketImportService.generateOpeningBalanceTemplateBytes();
      final appDir = await getApplicationDocumentsDirectory();
      final filePath = path.join(appDir.path, 'قالب_الأرصدة_الافتتاحية_سوق_الخضار.xlsx');
      await File(filePath).writeAsBytes(bytes, flush: true);
      await Share.shareXFiles(
        [XFile(filePath)],
        text: 'قالب الأرصدة الافتتاحية - سوق الخضار (مدار)',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم تجهيز القالب: $filePath'),
          backgroundColor: Colors.teal,
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'تعذر إنشاء القالب: $e');
      }
    } finally {
      if (mounted) setState(() => _downloadingTemplate = false);
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final picked = result.files.first;
    final sourcePath = picked.path;
    final pickedBytes = picked.bytes;
    if (sourcePath == null && pickedBytes == null) {
      setState(() => _error = 'تعذر الوصول إلى الملف المختار');
      return;
    }

    final bytes = pickedBytes ?? await File(sourcePath!).readAsBytes();
    File? target;
    if (PlatformUtils.isMobile || sourcePath == null) {
      final appDir = await getApplicationDocumentsDirectory();
      target = File(path.join(appDir.path, 'import_staging.xlsx'));
      await target.writeAsBytes(bytes, flush: true);
    } else {
      target = File(sourcePath);
    }

    setState(() {
      _pickedFile = target;
      _pickedBytes = bytes;
      _pickedName = picked.name;
      _preview = null;
      _error = null;
    });

    await _previewFile();
  }

  Future<Uint8List?> _resolveBytes() async {
    if (_pickedBytes != null) return _pickedBytes;
    if (_pickedFile != null && await _pickedFile!.exists()) {
      final b = await _pickedFile!.readAsBytes();
      _pickedBytes = b;
      return b;
    }
    return null;
  }

  Future<void> _previewFile() async {
    final bytes = await _resolveBytes();
    if (bytes == null) return;
    setState(() => _error = null);
    try {
      final preview =
          await VegetableMarketImportService(widget.db).previewExcelBytes(bytes);
      if (!mounted) return;
      setState(() => _preview = preview);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'فشل قراءة الملف: $e');
      }
    }
  }

  Future<void> _runImport() async {
    final bytes = await _resolveBytes();
    if (bytes == null) return;
    setState(() {
      _importing = true;
      _error = null;
    });
    try {
      final result =
          await VegetableMarketImportService(widget.db).importFromExcelBytes(
        bytes,
        importCustomers: _importCustomers,
        importSuppliers: _importSuppliers,
      );
      if (!mounted) return;
      final skippedText = result.skippedDuplicates > 0
          ? ' | تخطي مكرر: ${result.skippedDuplicates}'
          : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تم الاستيراد: ${result.total} سجل (زباين: ${result.customers}، موردين: ${result.suppliers}، برانيك: ${result.emptyBarnika}$skippedText)'
            '${result.errors.isNotEmpty ? ' — أخطاء: ${result.errors.length}' : ''}',
          ),
          backgroundColor: result.errors.isEmpty ? Colors.green : Colors.orange,
          duration: const Duration(seconds: 5),
        ),
      );
      if (result.errors.isNotEmpty || result.duplicateDetails.isNotEmpty) {
        _showDetailsDialog(
          errors: result.errors,
          duplicates: result.duplicateDetails,
        );
      }
      setState(() {
        _pickedFile = null;
        _pickedBytes = null;
        _pickedName = null;
        _preview = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'فشل الاستيراد: $e');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  void _showDetailsDialog({
    required List<String> errors,
    required List<String> duplicates,
  }) {
    showDialog(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(
            errors.isNotEmpty
                ? 'نتائج الاستيراد (${errors.length} أخطاء، ${duplicates.length} تخطي)'
                : 'تنبيهات التكرار المتخطاة (${duplicates.length})',
          ),
          content: SizedBox(
            width: 380,
            height: 300,
            child: ListView(
              children: [
                ...errors.take(20).map(
                      (e) => ListTile(
                        leading: const Icon(Icons.error, color: Colors.red, size: 18),
                        title: Text(e, style: const TextStyle(fontSize: 12)),
                      ),
                    ),
                ...duplicates.take(20).map(
                      (d) => ListTile(
                        leading: const Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.orange,
                          size: 18,
                        ),
                        title: Text(d, style: const TextStyle(fontSize: 12)),
                      ),
                    ),
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
      ),
    );
  }
}
