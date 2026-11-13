import 'dart:io';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../../../core/services/settings_service.dart';
import '../../../services/enhanced_backup_service.dart';

/// بطاقة إدارة المزامنة السحابية التلقائية عبر مجلد Google Drive / السحابة المحلي
class CloudFolderSyncCard extends StatefulWidget {
  final VoidCallback? onBackupRestored;
  final VoidCallback? onFolderChanged;

  const CloudFolderSyncCard({
    super.key,
    this.onBackupRestored,
    this.onFolderChanged,
  });

  @override
  State<CloudFolderSyncCard> createState() => _CloudFolderSyncCardState();
}

class _CloudFolderSyncCardState extends State<CloudFolderSyncCard> {
  final EnhancedBackupService _backupService = EnhancedBackupService();

  String? _syncFolderPath;
  bool _isSyncEnabled = true;
  List<EnhancedBackupInfo> _syncedBackups = [];
  bool _isLoading = false;
  bool _isActionInProgress = false;
  String _actionMessage = '';

  @override
  void initState() {
    super.initState();
    _loadSyncFolderData();
  }

  Future<void> _loadSyncFolderData() async {
    setState(() => _isLoading = true);
    try {
      final folderPath = await SettingsService.getCloudSyncFolderPath();
      final isEnabled = await SettingsService.isCloudFolderSyncEnabled();
      List<EnhancedBackupInfo> backups = [];
      if (folderPath != null && await Directory(folderPath).exists()) {
        backups = await _backupService.listCloudFolderBackups();
      }

      if (mounted) {
        setState(() {
          _syncFolderPath = folderPath;
          _isSyncEnabled = isEnabled;
          _syncedBackups = backups;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickSyncFolder() async {
    try {
      final selectedDirectory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'اختر مجلد Google Drive أو مجلد السحابة للمزامنة التلقائية',
      );

      if (selectedDirectory != null && selectedDirectory.trim().isNotEmpty) {
        final dir = Directory(selectedDirectory.trim());
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }

        await SettingsService.setCloudSyncFolderPath(dir.path);
        await SettingsService.setCloudFolderSyncEnabled(true);
        await _loadSyncFolderData();
        widget.onFolderChanged?.call();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white),
                  const Gap(8),
                  Expanded(child: Text('تم تحديد مجلد المزامنة السحابية بنجاح: ${dir.path}')),
                ],
              ),
              backgroundColor: const Color(0xFF2EA043),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تعذر اختيار المجلد: $e'),
            backgroundColor: const Color(0xFFF85149),
          ),
        );
      }
    }
  }

  Future<void> _autoDetectCloudFolder() async {
    setState(() {
      _isActionInProgress = true;
      _actionMessage = 'جاري البحث عن مجلدات Google Drive / OneDrive على هذا الجهاز...';
    });

    try {
      final detected = await _detectLocalCloudPaths();
      if (detected.isNotEmpty) {
        if (!mounted) return;
        final selected = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF161B22)
                : Colors.white,
            title: Row(
              children: const [
                Icon(Icons.cloud_done_rounded, color: Color(0xFF58A6FF)),
                Gap(8),
                Text('تم العثور على مجلدات سحابية'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('اختر المجلد الذي ترغب في استخدامه للمزامنة التلقائية:'),
                const Gap(12),
                ...detected.map(
                  (path) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: _getCloudServiceIcon(path),
                    title: Text(_getCloudServiceName(path), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    subtitle: Text(path, style: const TextStyle(fontSize: 11)),
                    onTap: () => Navigator.pop(ctx, path),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء'),
              ),
            ],
          ),
        );

        if (selected != null) {
          final targetDir = Directory(p.join(selected, 'MADAR_Backups'));
          if (!await targetDir.exists()) {
            await targetDir.create(recursive: true);
          }
          await SettingsService.setCloudSyncFolderPath(targetDir.path);
          await SettingsService.setCloudFolderSyncEnabled(true);
          await _loadSyncFolderData();
          widget.onFolderChanged?.call();
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('لم يتم العثور على مسار Google Drive افتراضي تلقائياً. يرجى اختياره يدوياً.'),
              backgroundColor: Color(0xFFD29922),
            ),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isActionInProgress = false);
    }
  }

  Future<List<String>> _detectLocalCloudPaths() async {
    final candidates = <String>[];
    if (Platform.isWindows) {
      // 1. Google Drive Virtual Drive (G:\My Drive or G:\)
      final driveLetters = ['G', 'H', 'I', 'D', 'E', 'F'];
      for (final letter in driveLetters) {
        final myDrive = Directory('$letter:\\My Drive');
        if (await myDrive.exists()) {
          candidates.add(myDrive.path);
        } else {
          final rootDrive = Directory('$letter:\\');
          if (await rootDrive.exists()) {
            try {
              // check if contains .shortcut-targets-by-id or Google Drive markers
              if (await Directory('$letter:\\Shared drives').exists() || await Directory('$letter:\\Other computers').exists()) {
                candidates.add(rootDrive.path);
              }
            } catch (_) {}
          }
        }
      }

      // 2. User profile folders
      final userProfile = Platform.environment['USERPROFILE'];
      if (userProfile != null) {
        final gdriveUser = Directory(p.join(userProfile, 'Google Drive'));
        if (await gdriveUser.exists()) candidates.add(gdriveUser.path);

        final oneDriveUser = Directory(p.join(userProfile, 'OneDrive'));
        if (await oneDriveUser.exists()) candidates.add(oneDriveUser.path);

        final dropboxUser = Directory(p.join(userProfile, 'Dropbox'));
        if (await dropboxUser.exists()) candidates.add(dropboxUser.path);
      }
    }
    return candidates;
  }

  Future<void> _openFolderInExplorer() async {
    if (_syncFolderPath == null) return;
    try {
      if (Platform.isWindows) {
        await Process.run('explorer.exe', [_syncFolderPath!]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [_syncFolderPath!]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [_syncFolderPath!]);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر فتح المجلد: $e'), backgroundColor: const Color(0xFFF85149)),
        );
      }
    }
  }

  Future<void> _syncLatestNow() async {
    setState(() {
      _isActionInProgress = true;
      _actionMessage = 'جاري نسخ أحدث نسخة احتياطية إلى مجلد السحابة...';
    });
    try {
      final res = await _backupService.syncLatestBackupToCloudFolder();
      await _loadSyncFolderData();
      if (mounted) {
        if (res != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: const [
                  Icon(Icons.check_circle, color: Colors.white),
                  Gap(8),
                  Text('تمت المزامنة بنجاح إلى مجلد Google Drive'),
                ],
              ),
              backgroundColor: const Color(0xFF2EA043),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('لا توجد نسخ احتياطية محلية لمزامنتها أو أن المجلد غير متاح.'),
              backgroundColor: Color(0xFFD29922),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشلت المزامنة: $e'), backgroundColor: const Color(0xFFF85149)),
        );
      }
    } finally {
      if (mounted) setState(() => _isActionInProgress = false);
    }
  }

  Future<void> _restoreFromSyncedFile(EnhancedBackupInfo backup) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF161B22) : Colors.white;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cardBg,
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFF85149)),
            Gap(8),
            Text('تأكيد الاستعادة من السحابة'),
          ],
        ),
        content: Text(
          'هل أنت متأكد من استعادة النسخة (${backup.filename}) من مجلد السحابة؟\n\n'
          '⚠️ سيتم أخذ نسخة أمان تلقائية للبيانات الحالية قبل الاستعادة.',
          style: const TextStyle(height: 1.4, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF85149), foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('استعادة الآن'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isActionInProgress = true;
      _actionMessage = 'جاري استعادة البيانات والتحقق من صحتها...';
    });

    try {
      final success = await _backupService.restoreBackup(backup.filename);
      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تمت استعادة البيانات بنجاح من مجلد السحابة'),
              backgroundColor: Color(0xFF2EA043),
            ),
          );
          widget.onBackupRestored?.call();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('فشلت عملية الاستعادة'),
              backgroundColor: Color(0xFFF85149),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في الاستعادة: $e'), backgroundColor: const Color(0xFFF85149)),
        );
      }
    } finally {
      if (mounted) setState(() => _isActionInProgress = false);
    }
  }

  Future<void> _removeSyncFolder() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF161B22) : Colors.white,
        title: const Text('إلغاء ربط مجلد السحابة'),
        content: const Text('هل ترغب في إلغاء تحديد مجلد المزامنة السحابية؟ (لن يتم حذف أي ملفات سحابية موجودة بالفعل).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF85149), foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('إلغاء الربط'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await SettingsService.setCloudSyncFolderPath(null);
      await _loadSyncFolderData();
      widget.onFolderChanged?.call();
    }
  }

  Widget _getCloudServiceIcon(String folderPath) {
    final lower = folderPath.toLowerCase();
    if (lower.contains('google drive') || lower.contains('my drive')) {
      return const Icon(Icons.cloud_sync, color: Color(0xFF4285F4), size: 24);
    } else if (lower.contains('onedrive')) {
      return const Icon(Icons.cloud_circle, color: Color(0xFF0078D4), size: 24);
    } else if (lower.contains('dropbox')) {
      return const Icon(Icons.cloud_queue, color: Color(0xFF0061FF), size: 24);
    }
    return const Icon(Icons.folder_special, color: Color(0xFFC9A84C), size: 24);
  }

  String _getCloudServiceName(String folderPath) {
    final lower = folderPath.toLowerCase();
    if (lower.contains('google drive') || lower.contains('my drive')) {
      return 'Google Drive';
    } else if (lower.contains('onedrive')) {
      return 'Microsoft OneDrive';
    } else if (lower.contains('dropbox')) {
      return 'Dropbox';
    }
    return 'مجلد متزامن محلي / شبكي';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF161B22) : Colors.white;
    final innerBg = isDark ? const Color(0xFF21262D) : const Color(0xFFF6F8FA);
    final textColor = isDark ? const Color(0xFFE6EDF3) : const Color(0xFF1F2328);
    final subTextColor = isDark ? const Color(0xFF8B949E) : const Color(0xFF656D76);
    final borderColor = isDark ? const Color(0xFF30363D) : const Color(0xFFD0D7DE);
    final blueColor = const Color(0xFF58A6FF);
    final greenColor = const Color(0xFF2EA043);
    final goldColor = const Color(0xFFC9A84C);

    final hasFolder = (_syncFolderPath != null && _syncFolderPath!.trim().isNotEmpty);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          color: cardBg,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: borderColor),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ترويسة البطاقة
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: blueColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.cloud_sync_rounded,
                        color: blueColor,
                        size: 28,
                      ),
                    ),
                    const Gap(14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'المزامنة السحابية عبر مجلد Google Drive',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: textColor,
                                ),
                              ),
                              const Gap(8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: greenColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: greenColor.withValues(alpha: 0.4)),
                                ),
                                child: Text(
                                  hasFolder ? 'مزامنة نشطة' : 'جاهز للإعداد',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: greenColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const Gap(4),
                          Text(
                            'حفظ ومزامنة النسخ المشفرة تلقائياً في مجلد Google Drive أو السحابة المحلي بدون الحاجة لـ OAuth',
                            style: TextStyle(fontSize: 12, color: subTextColor),
                          ),
                        ],
                      ),
                    ),
                    if (_isLoading)
                      const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    else
                      IconButton(
                        icon: Icon(Icons.refresh, color: subTextColor),
                        tooltip: 'تحديث حالة المجلد',
                        onPressed: _loadSyncFolderData,
                      ),
                  ],
                ),
                const Gap(16),
                Divider(color: borderColor, height: 1),
                const Gap(16),

                if (_isActionInProgress) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: innerBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: blueColor.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                        const Gap(14),
                        Expanded(
                          child: Text(
                            _actionMessage,
                            style: TextStyle(fontSize: 13, color: blueColor, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else if (!hasFolder) ...[
                  // حالة عدم وجود مجلد محدد
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: innerBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: borderColor),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: goldColor.withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.folder_shared_rounded, color: goldColor, size: 24),
                            ),
                            const Gap(12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'اختر مجلد Google Drive لرفع ومزامنة النسخ تلقائياً',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: textColor),
                                  ),
                                  const Gap(3),
                                  Text(
                                    'حدد مجلد Google Drive المثبت على جهازك (مثل G:\\My Drive أو مجلد المستخدم). سيقوم البرنامج بنسخ أي نسخة احتياطية مشفرة فور إنشائها لترفعها السحابة تلقائياً.',
                                    style: TextStyle(fontSize: 12, color: subTextColor, height: 1.4),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const Gap(16),
                        Wrap(
                          spacing: 12,
                          runSpacing: 10,
                          children: [
                            ElevatedButton.icon(
                              onPressed: _pickSyncFolder,
                              icon: const Icon(Icons.folder_open_rounded, size: 18),
                              label: const Text('اختيار مجلد Google Drive يدوياً'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: blueColor,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: _autoDetectCloudFolder,
                              icon: Icon(Icons.auto_awesome_rounded, size: 18, color: goldColor),
                              label: Text('اكتشاف مجلدات Google Drive تلقائياً', style: TextStyle(color: textColor)),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: borderColor),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  // حالة وجود مجلد محدد ونشط
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: innerBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: greenColor.withValues(alpha: 0.4)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _getCloudServiceIcon(_syncFolderPath!),
                            const Gap(12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        _getCloudServiceName(_syncFolderPath!),
                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: textColor),
                                      ),
                                      const Gap(8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: greenColor.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          'متصل وجاهز',
                                          style: TextStyle(color: greenColor, fontSize: 10, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const Gap(3),
                                  SelectableText(
                                    _syncFolderPath!,
                                    style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 12,
                                      color: blueColor,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.folder_open, size: 20),
                              tooltip: 'فتح المجلد في مستكشف الملفات (Windows Explorer)',
                              onPressed: _openFolderInExplorer,
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 20),
                              tooltip: 'تغيير المجلد',
                              onPressed: _pickSyncFolder,
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, size: 20, color: Colors.redAccent),
                              tooltip: 'إلغاء ربط المجلد',
                              onPressed: _removeSyncFolder,
                            ),
                          ],
                        ),
                        const Gap(14),
                        Divider(color: borderColor, height: 1),
                        const Gap(12),
                        Row(
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  Switch(
                                    value: _isSyncEnabled,
                                    activeThumbColor: greenColor,
                                    onChanged: (val) async {
                                      await SettingsService.setCloudFolderSyncEnabled(val);
                                      setState(() => _isSyncEnabled = val);
                                    },
                                  ),
                                  const Gap(6),
                                  Expanded(
                                    child: Text(
                                      'مزامنة النسخ الاحتياطية تلقائياً فور إنشائها (عند إغلاق اليومية والنسخ التلقائي)',
                                      style: TextStyle(fontSize: 12, color: textColor),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            ElevatedButton.icon(
                              onPressed: _syncLatestNow,
                              icon: const Icon(Icons.sync_rounded, size: 16),
                              label: const Text('مزامنة أحدث نسخة الآن', style: TextStyle(fontSize: 12)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: blueColor,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                elevation: 0,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const Gap(16),

                  // قائمة النسخ المحفوظة حالياً في مجلد السحابة
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'النسخ الاحتياطية المتوفرة في مجلد السحابة (${_syncedBackups.length})',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: textColor),
                      ),
                      Text(
                        'يتم الاحتفاظ تلقائياً بأحدث 15 نسخة مشفرة',
                        style: TextStyle(fontSize: 11, color: subTextColor),
                      ),
                    ],
                  ),
                  const Gap(10),

                  if (_syncedBackups.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: innerBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: borderColor),
                      ),
                      child: Center(
                        child: Text(
                          'لا توجد نسخ احتياطية في هذا المجلد حتى الآن. اضغط "مزامنة أحدث نسخة الآن" أو قم بإنشاء نسخة احتياطية جديدة.',
                          style: TextStyle(fontSize: 12, color: subTextColor),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  else
                    Container(
                      decoration: BoxDecoration(
                        color: innerBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: borderColor),
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _syncedBackups.length,
                        separatorBuilder: (context, index) => Divider(color: borderColor, height: 1),
                        itemBuilder: (ctx, index) {
                          final item = _syncedBackups[index];
                          final formattedDate = DateFormat('yyyy-MM-dd HH:mm').format(item.createdAt);
                          return ListTile(
                            dense: true,
                            leading: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: greenColor.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Icon(Icons.cloud_done_rounded, color: greenColor, size: 20),
                            ),
                            title: Text(
                              item.filename,
                              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: textColor),
                            ),
                            subtitle: Text(
                              '$formattedDate  |  الحجم: ${item.formattedSize}  |  🔒 مشفر',
                              style: TextStyle(fontSize: 11, color: subTextColor),
                            ),
                            trailing: OutlinedButton.icon(
                              onPressed: () => _restoreFromSyncedFile(item),
                              icon: const Icon(Icons.restore_rounded, size: 14),
                              label: const Text('استعادة', style: TextStyle(fontSize: 11)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: blueColor,
                                side: BorderSide(color: blueColor.withValues(alpha: 0.5)),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
