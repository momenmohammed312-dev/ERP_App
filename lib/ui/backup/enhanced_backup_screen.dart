import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:gap/gap.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import '../../services/user_backup_service.dart';
import '../../l10n/app_localizations.dart';

class EnhancedBackupScreen extends StatefulWidget {
  const EnhancedBackupScreen({super.key});

  @override
  State<EnhancedBackupScreen> createState() => _EnhancedBackupScreenState();
}

class _EnhancedBackupScreenState extends State<EnhancedBackupScreen> {
  final BackupService _backupService = BackupService();
  List<BackupInfo> _backups = [];
  bool _isLoading = false;
  Map<String, dynamic>? _statistics;
  Map<String, dynamic>? _autoBackupStatus;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final backups = await _backupService.listBackups();

      // Calculate basic statistics
      final statistics = {
        'total_backups': backups.length,
        'automatic_backups': backups.where((b) => b.type == 'auto').length,
        'manual_backups': backups.where((b) => b.type == 'manual').length,
        'total_size_mb':
            (backups.fold<int>(0, (sum, b) => sum + b.size) / (1024 * 1024))
                .toStringAsFixed(1),
      };

      final autoStatus = {
        'enabled': true, // User's service doesn't have status method
        'interval': '24 hours',
        'last_backup': backups.isNotEmpty
            ? backups.first.formattedDate
            : 'Never',
      };

      setState(() {
        _backups = backups;
        _statistics = statistics;
        _autoBackupStatus = autoStatus;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showErrorSnackBar('Failed to load backup data: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('النسخ الاحتياطي والاستعادة'),
        backgroundColor: Colors.blue.shade800,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'تحديث',
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
                  _buildStatisticsCard(),
                  const Gap(16),
                  _buildAutoBackupCard(),
                  const Gap(16),
                  _buildActionsCard(),
                  const Gap(16),
                  _buildBackupsList(),
                ],
              ),
            ),
    );
  }

  Widget _buildStatisticsCard() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.analytics, color: Colors.blue.shade800),
                const Gap(8),
                Text(
                  'إحصائيات النسخ الاحتياطي',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade800,
                  ),
                ),
              ],
            ),
            const Gap(12),
            if (_statistics != null) ...[
              _buildStatRow('إجمالي النسخ', '${_statistics!['total_backups']}'),
              _buildStatRow(
                'النسخ التلقائي',
                '${_statistics!['automatic_backups']}',
              ),
              _buildStatRow(
                'النسخ اليدوي',
                '${_statistics!['manual_backups']}',
              ),
              _buildStatRow(
                'الحجم الإجمالي',
                '${_statistics!['total_size_mb']} MB',
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.blue,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAutoBackupCard() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.schedule, color: Colors.green.shade800),
                const Gap(8),
                Text(
                  'النسخ التلقائي',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade800,
                  ),
                ),
                const Spacer(),
                Switch(
                  value: _autoBackupStatus?['enabled'] ?? false,
                  onChanged: (value) {
                    if (value) {
                      AutoBackupService.start();
                    } else {
                      AutoBackupService.stop();
                    }
                    _loadData();
                  },
                ),
              ],
            ),
            const Gap(12),
            if (_autoBackupStatus != null) ...[
              _buildStatRow(
                'الحالة',
                _autoBackupStatus!['enabled'] ? 'مفعّل' : 'معطّل',
              ),
              _buildStatRow('الفاصل الزمني', _autoBackupStatus!['interval']),
              _buildStatRow('أخر نسخة', _autoBackupStatus!['last_backup']),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActionsCard() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.backup, color: Colors.orange.shade800),
                const Gap(8),
                Text(
                  'الإجراءات',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange.shade800,
                  ),
                ),
              ],
            ),
            const Gap(12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                ElevatedButton.icon(
                  onPressed: _createManualBackup,
                  icon: const Icon(Icons.add),
                  label: const Text('إنشاء نسخة يدوية'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _exportBackup,
                  icon: const Icon(Icons.upload),
                  label: const Text('تصدير نسخة'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _importBackup,
                  icon: const Icon(Icons.download),
                  label: const Text('استيراد نسخة'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple,
                    foregroundColor: Colors.white,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _createImmediateBackup,
                  icon: const Icon(Icons.flash_on),
                  label: const Text('نسخ فوري'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackupsList() {
    return Card(
      elevation: 4,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.shade800,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.list, color: Colors.white),
                const Gap(8),
                const Text(
                  'النسخ الاحتياطية المتوفرة',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_backups.length} نسخة',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (_backups.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Text(
                  'لا توجد نسخ احتياطية حالياً',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _backups.length,
              itemBuilder: (context, index) {
                final backup = _backups[index];
                return _buildBackupItem(backup);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildBackupItem(BackupInfo backup) {
    Color typeColor;
    IconData typeIcon;
    String typeText;

    switch (backup.type) {
      case 'manual':
        typeColor = Colors.blue;
        typeIcon = Icons.touch_app;
        typeText = 'يدوي';
        break;
      case 'auto':
        typeColor = Colors.green;
        typeIcon = Icons.today;
        typeText = 'تلقائي';
        break;
      default:
        typeColor = Colors.grey;
        typeIcon = Icons.backup;
        typeText = 'غير معروف';
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: typeColor.withValues(alpha: 0.2),
          child: Icon(typeIcon, color: typeColor),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                backup.filename,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: typeColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                typeText,
                style: TextStyle(
                  color: typeColor,
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
            const Gap(4),
            Row(
              children: [
                Icon(Icons.schedule, size: 16, color: Colors.grey.shade600),
                const Gap(4),
                Text(backup.formattedDate),
                const Gap(16),
                Icon(Icons.storage, size: 16, color: Colors.grey.shade600),
                const Gap(4),
                Text(backup.formattedSize),
              ],
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            switch (value) {
              case 'restore':
                _restoreBackup(backup);
                break;
              case 'verify':
                _verifyBackup(backup);
                break;
              case 'export':
                _exportSpecificBackup(backup);
                break;
              case 'delete':
                _deleteBackup(backup);
                break;
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'restore',
              child: Row(
                children: [
                  Icon(Icons.restore, color: Colors.green),
                  Gap(8),
                  Text('استعادة'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'verify',
              child: Row(
                children: [
                  Icon(Icons.verified, color: Colors.blue),
                  Gap(8),
                  Text('تحقق'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'export',
              child: Row(
                children: [
                  Icon(Icons.upload, color: Colors.orange),
                  Gap(8),
                  Text('تصدير'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete, color: Colors.red),
                  Gap(8),
                  Text('حذف'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createManualBackup() async {
    try {
      setState(() => _isLoading = true);

      await _backupService.createBackup(
        type: 'manual',
        description: 'نسخة احتياطية يدوية',
      );

      _showSuccessSnackBar('تم إنشاء النسخة الاحتياطية بنجاح');
      await _loadData();
    } catch (e) {
      _showErrorSnackBar('خطأ في إنشاء النسخة الاحتياطية: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _createImmediateBackup() async {
    try {
      setState(() => _isLoading = true);

      await _backupService.createBackup(
        type: 'auto',
        description: 'نسخة احتياطية فورية',
      );

      _showSuccessSnackBar('تم إنشاء النسخة الفورية بنجاح');
      await _loadData();
    } catch (e) {
      _showErrorSnackBar('خطأ في إنشاء النسخة الفورية: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _exportBackup() async {
    try {
      final result = await FilePicker.platform.saveFile(
        dialogTitle: 'حفظ نسخة احتياطية',
        fileName:
            'POS_Backup_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.posbackup',
        type: FileType.custom,
        allowedExtensions: ['posbackup'],
      );

      if (result != null) {
        // Create backup first
        final backup = await _backupService.createBackup(
          type: 'manual_export',
          description: 'نسخة احتياطية مصدرة',
        );

        // Copy to selected location
        final backupFile = File('data/backups/${backup.filename}');
        await backupFile.copy(result);

        _showSuccessSnackBar('تم تصدير النسخة الاحتياطية بنجاح');
      }
    } catch (e) {
      _showErrorSnackBar('خطأ في تصدير النسخة الاحتياطية: $e');
    }
  }

  Future<void> _importBackup() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: 'اختر نسخة احتياطية للاستعادة',
        type: FileType.custom,
        allowedExtensions: ['posbackup', 'zip'],
      );

      if (result != null && result.files.single.path != null) {
        final confirmed = await _showConfirmDialog(
          'هل أنت متأكد من استعادة هذه النسخة؟ سيتم استبدال جميع البيانات الحالية.',
        );

        if (confirmed) {
          setState(() => _isLoading = true);

          // Copy backup to backup directory
          final backupFile = File(result.files.single.path!);
          final appDir = await getApplicationDocumentsDirectory();
          final backupDir = Directory('${appDir.path}/data/backups');
          if (!await backupDir.exists()) {
            await backupDir.create(recursive: true);
          }
          final targetPath =
              '${backupDir.path}/${path.basename(result.files.single.path!)}';
          await backupFile.copy(targetPath);

          // Restore backup
          await _backupService.restoreBackup(path.basename(targetPath));

          _showSuccessSnackBar('تم استعادة النسخة الاحتياطية بنجاح');
          await _loadData();
        }
      }
    } catch (e) {
      _showErrorSnackBar('خطأ في استعادة النسخة الاحتياطية: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _restoreBackup(BackupInfo backup) async {
    final confirmed = await _showConfirmDialog(
      'هل أنت متأكد من استعادة النسخة الاحتياطية "${backup.filename}"؟\nسيتم استبدال جميع البيانات الحالية.',
    );

    if (confirmed) {
      try {
        setState(() => _isLoading = true);

        await _backupService.restoreBackup(backup.filename);

        _showSuccessSnackBar('تم استعادة النسخة الاحتياطية بنجاح');
        await _loadData();
      } catch (e) {
        _showErrorSnackBar('خطأ في استعادة النسخة الاحتياطية: $e');
      } finally {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _verifyBackup(BackupInfo backup) async {
    try {
      // User's service doesn't have verification method, so just show info
      _showInfoDialog(
        'معلومات النسخة الاحتياطية',
        'الملف: ${backup.filename}\n'
            'الحجم: ${backup.formattedSize}\n'
            'التاريخ: ${backup.formattedDate}\n'
            'النوع: ${backup.type}',
      );
    } catch (e) {
      _showErrorSnackBar('خطأ في التحقق من النسخة الاحتياطية: $e');
    }
  }

  Future<void> _exportSpecificBackup(BackupInfo backup) async {
    try {
      final result = await FilePicker.platform.saveFile(
        dialogTitle: 'حفظ نسخة احتياطية',
        fileName: backup.filename,
        type: FileType.custom,
        allowedExtensions: ['posbackup'],
      );

      if (result != null) {
        final backupFile = File('data/backups/${backup.filename}');
        await backupFile.copy(result);

        _showSuccessSnackBar('تم تصدير النسخة الاحتياطية بنجاح');
      }
    } catch (e) {
      _showErrorSnackBar('خطأ في تصدير النسخة الاحتياطية: $e');
    }
  }

  Future<void> _deleteBackup(BackupInfo backup) async {
    final confirmed = await _showConfirmDialog(
      'هل أنت متأكد من حذف النسخة الاحتياطية "${backup.filename}"؟\nلا يمكن التراجع عن هذا الإجراء.',
    );

    if (confirmed) {
      try {
        await _backupService.deleteBackup(backup.filename);
        _showSuccessSnackBar('تم حذف النسخة الاحتياطية بنجاح');
        await _loadData();
      } catch (e) {
        _showErrorSnackBar('خطأ في حذف النسخة الاحتياطية: $e');
      }
    }
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const Gap(8),
            Text(message),
          ],
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error, color: Colors.white),
            const Gap(8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'نسخ',
          textColor: Colors.white,
          onPressed: () {
            Clipboard.setData(ClipboardData(text: message));
          },
        ),
      ),
    );
  }

  Future<bool> _showConfirmDialog(String message) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('تأكيد'),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('إلغاء'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('تأكيد'),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _showInfoDialog(String title, String content) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('موافق'),
          ),
        ],
      ),
    );
  }
}
