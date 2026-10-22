import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'google_drive_auth_service.dart';
import 'cloud_backup_encryption_service.dart';
import '../../models/cloud_backup_metadata.dart';
import '../enhanced_backup_service.dart';

class GoogleDriveBackupException implements Exception {
  final String message;
  GoogleDriveBackupException(this.message);
  @override
  String toString() => message;
}

class GoogleDriveBackupService {
  static const String folderName = 'MADAR ERP Backups';
  static const int defaultMaxBackups = 5;

  final GoogleDriveAuthService _authService;
  final CloudBackupEncryptionService _encryptionService;
  final EnhancedBackupService _localBackupService;

  drive.DriveApi? _mockDriveApi;
  String? _cachedFolderId;

  @visibleForTesting
  static Directory? customTempDirectory;

  @visibleForTesting
  static Directory? customBackupDirectory;

  Future<Directory> _getTempDirectory() async {
    if (customTempDirectory != null) return customTempDirectory!;
    try {
      return await getTemporaryDirectory();
    } catch (_) {
      return Directory.systemTemp;
    }
  }

  GoogleDriveBackupService({
    GoogleDriveAuthService? authService,
    CloudBackupEncryptionService? encryptionService,
    EnhancedBackupService? localBackupService,
  })  : _authService = authService ?? GoogleDriveAuthService(),
        _encryptionService = encryptionService ?? CloudBackupEncryptionService(),
        _localBackupService = localBackupService ?? EnhancedBackupService();

  @visibleForTesting
  void setMockDriveApi(drive.DriveApi mockApi) {
    _mockDriveApi = mockApi;
  }

  drive.DriveApi _getDriveApi() {
    if (_mockDriveApi != null) return _mockDriveApi!;
    final client = _authService.client;
    if (client == null) {
      throw GoogleDriveBackupException('حساب Google Drive غير متصل. يرجى تسجيل الدخول أولاً.');
    }
    return drive.DriveApi(client);
  }

  // ════════════════════════════════════════════════════════════════════════
  // 1. إدارة مجلد النسخ السحابية في Google Drive (Folder Management)
  // ════════════════════════════════════════════════════════════════════════

  Future<String> getOrCreateBackupFolder() async {
    if (_cachedFolderId != null) return _cachedFolderId!;

    final api = _getDriveApi();
    final query = "mimeType = 'application/vnd.google-apps.folder' and name = '$folderName' and trashed = false";

    final fileList = await api.files.list(
      q: query,
      spaces: 'drive',
      $fields: 'files(id, name)',
    );

    if (fileList.files != null && fileList.files!.isNotEmpty) {
      _cachedFolderId = fileList.files!.first.id!;
      return _cachedFolderId!;
    }

    // إنشاء المجلد إذا لم يكن موجوداً
    final folderMetadata = drive.File()
      ..name = folderName
      ..mimeType = 'application/vnd.google-apps.folder'
      ..description = 'مجلد النسخ الاحتياطية المشفرة لنظام مِدار | MADAR ERP';

    final createdFolder = await api.files.create(
      folderMetadata,
      $fields: 'id',
    );

    _cachedFolderId = createdFolder.id!;
    debugPrint('📁 تم إنشاء مجلد النسخ الاحتياطية في Google Drive: $_cachedFolderId');
    return _cachedFolderId!;
  }

  // ════════════════════════════════════════════════════════════════════════
  // 2. رفع النسخة الاحتياطية المشفرة للسحابة (Upload Cloud Backup)
  // ════════════════════════════════════════════════════════════════════════

  Future<CloudBackupMetadata> uploadBackup({
    File? sourceLocalFile,
    bool isAuto = false,
    String? description,
    int maxRetention = defaultMaxBackups,
  }) async {
    final api = _getDriveApi();
    File? tempSnapshotFile;
    File? tempEncryptedFile;

    try {
      debugPrint('☁️ بدء تحضير ورفع النسخة السحابية المشفرة...');

      // 1. الحصول على ملف قاعدة البيانات أو إنشاء لقطة ذرية
      File localToUpload;
      if (sourceLocalFile != null && await sourceLocalFile.exists()) {
        localToUpload = sourceLocalFile;
      } else {
        // إنشاء لقطة ذرية آمنة عبر الخدمة المحلية
        final backupInfo = await _localBackupService.createBackup(
          type: isAuto ? 'cloud_auto' : 'cloud_manual',
          description: description ?? 'نسخة احتياطية للرفع السحابي',
        );
        tempSnapshotFile = File(backupInfo.filePath);
        localToUpload = tempSnapshotFile;
      }

      // 2. تشفير الملف بخوارزمية AES-256-GCM
      final tempDir = await _getTempDirectory();
      final timestamp = DateTime.now();
      final cloudFilename =
          'MADAR_Cloud_${timestamp.year}${timestamp.month.toString().padLeft(2, '0')}${timestamp.day.toString().padLeft(2, '0')}_'
          '${timestamp.hour.toString().padLeft(2, '0')}${timestamp.minute.toString().padLeft(2, '0')}${timestamp.second.toString().padLeft(2, '0')}.poscloudbackup';

      tempEncryptedFile = File(p.join(tempDir.path, cloudFilename));
      await _encryptionService.encryptBackupFile(
        sourceFile: localToUpload,
        targetEncryptedFile: tempEncryptedFile,
      );

      final encryptedLength = await tempEncryptedFile.length();
      final encryptedBytes = await tempEncryptedFile.readAsBytes();
      final sha256Checksum = crypto.sha256.convert(encryptedBytes).toString();

      // 3. مجلد الوجهة في Google Drive
      final folderId = await getOrCreateBackupFolder();

      // 4. إعداد بيانات الملف والرفع
      final driveFileMeta = drive.File()
        ..name = cloudFilename
        ..parents = [folderId]
        ..description = description ?? 'نسخة سحابية مشفرة لنظام مِدار ERP'
        ..appProperties = {
          'app': 'madar_erp',
          'isCloudBackup': 'true',
          'isAutoBackup': isAuto.toString(),
          'checksum': sha256Checksum,
          'appVersion': '2.3.0',
        };

      final mediaStream = tempEncryptedFile.openRead();
      final media = drive.Media(mediaStream, encryptedLength);

      final uploadedFile = await api.files.create(
        driveFileMeta,
        uploadMedia: media,
        $fields: 'id, name, size, createdTime, appProperties, webViewLink',
      );

      debugPrint('✅ تم رفع النسخة بنجاح إلى Google Drive: ${uploadedFile.id} ($encryptedLength bytes)');

      // 5. تطبيق سياسة الاحتفاظ السحابي الآمنة
      if (maxRetention > 0) {
        try {
          await applyRetentionPolicy(maxBackups: maxRetention);
        } catch (e) {
          debugPrint('Notice during retention cleanup: $e');
        }
      }

      return CloudBackupMetadata.fromDriveProperties(
        fileId: uploadedFile.id!,
        fileName: uploadedFile.name ?? cloudFilename,
        fileSize: int.tryParse(uploadedFile.size ?? '') ?? encryptedLength,
        createdTime: uploadedFile.createdTime ?? DateTime.now(),
        appProperties: uploadedFile.appProperties,
        webViewLink: uploadedFile.webViewLink,
      );
    } catch (e) {
      debugPrint('❌ فشل رفع النسخة الاحتياطية إلى Google Drive: $e');
      throw GoogleDriveBackupException('تعذر رفع النسخة السحابية: $e');
    } finally {
      // تنظيف الملفات المؤقتة المعزولة
      try {
        if (tempEncryptedFile != null && await tempEncryptedFile.exists()) {
          await tempEncryptedFile.delete();
        }
      } catch (_) {}
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  // 3. استعراض النسخ السحابية المتوفرة (List Cloud Backups)
  // ════════════════════════════════════════════════════════════════════════

  Future<List<CloudBackupMetadata>> listCloudBackups() async {
    final api = _getDriveApi();
    final folderId = await getOrCreateBackupFolder();

    final query = "'$folderId' in parents and trashed = false and appProperties has { key='app' and value='madar_erp' }";

    final fileList = await api.files.list(
      q: query,
      spaces: 'drive',
      orderBy: 'createdTime desc',
      $fields: 'files(id, name, size, createdTime, appProperties, webViewLink)',
    );

    final results = <CloudBackupMetadata>[];
    if (fileList.files != null) {
      for (final f in fileList.files!) {
        if (f.id == null || f.name == null) continue;
        results.add(
          CloudBackupMetadata.fromDriveProperties(
            fileId: f.id!,
            fileName: f.name!,
            fileSize: int.tryParse(f.size ?? '0') ?? 0,
            createdTime: f.createdTime ?? DateTime.now(),
            appProperties: f.appProperties,
            webViewLink: f.webViewLink,
          ),
        );
      }
    }
    return results;
  }

  // ════════════════════════════════════════════════════════════════════════
  // 4. تنزيل نسخة سحابية (Download Cloud Backup)
  // ════════════════════════════════════════════════════════════════════════

  Future<File> downloadCloudBackup({
    required String fileId,
    required File targetFile,
  }) async {
    final api = _getDriveApi();

    try {
      debugPrint('📥 بدء تنزيل النسخة السحابية من Google Drive: $fileId');

      final media = await api.files.get(
        fileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;

      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      final sink = targetFile.openWrite();
      await sink.addStream(media.stream);
      await sink.flush();
      await sink.close();

      debugPrint('✅ تم تنزيل الملف بنجاح: ${targetFile.path} (${await targetFile.length()} bytes)');
      return targetFile;
    } catch (e) {
      debugPrint('❌ فشل تنزيل النسخة السحابية: $e');
      throw GoogleDriveBackupException('تعذر تنزيل النسخة من Google Drive: $e');
    }
  }

  Future<Directory> _getBackupDirectory() async {
    if (customBackupDirectory != null) {
      return customBackupDirectory!;
    }
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(appDir.path, 'data', 'backups'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  // ════════════════════════════════════════════════════════════════════════
  // 5. استعادة النسخة السحابية كاملة (Restore Cloud Backup Workflow)
  // ════════════════════════════════════════════════════════════════════════

  Future<bool> restoreCloudBackup({
    required String fileId,
    String? recoveryKeyOrPassphrase,
  }) async {
    final tempDir = await _getTempDirectory();
    final backupDir = await _getBackupDirectory();
    final restoreId = DateTime.now().millisecondsSinceEpoch;
    final tempDownloadedFile = File(p.join(tempDir.path, 'cloud_dl_$restoreId.poscloudbackup'));
    final tempDecryptedFile = File(p.join(backupDir.path, 'cloud_dec_$restoreId.posbackup'));

    try {
      // 1. تنزيل النسخة المشفرة
      await downloadCloudBackup(fileId: fileId, targetFile: tempDownloadedFile);

      // 2. فك التشفير المصادق بـ GCM والتحقق من كود الاسترداد
      debugPrint('🔓 جاري فك تشفير النسخة السحابية والتحقق من كود الاسترداد...');
      await _encryptionService.decryptBackupFile(
        encryptedFile: tempDownloadedFile,
        targetDecryptedFile: tempDecryptedFile,
        recoveryKeyOrPassphrase: recoveryKeyOrPassphrase,
      );

      // 3. تمرير الملف المفكوك للخدمة المحلية لتطبيق دورة الاستعادة الآمنة
      // (لقطة أمان مسبقة + تنظيف الـ Sidecars + استبدال الملف + تحديث الاتصال)
      final restored = await _localBackupService.restoreBackup(
        p.basename(tempDecryptedFile.path),
        createPreRestoreBackup: true,
      );

      return restored;
    } finally {
      // تنظيف الملفات المؤقتة
      try {
        if (await tempDownloadedFile.exists()) await tempDownloadedFile.delete();
        if (await tempDecryptedFile.exists()) await tempDecryptedFile.delete();
      } catch (_) {}
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  // 6. حذف نسخة سحابية محددة يدوياً
  // ════════════════════════════════════════════════════════════════════════

  Future<void> deleteCloudBackup(String fileId) async {
    final api = _getDriveApi();
    try {
      await api.files.delete(fileId);
      debugPrint('🗑️ تم حذف النسخة السحابية بنجاح: $fileId');
    } catch (e) {
      debugPrint('❌ فشل حذف النسخة السحابية: $e');
      throw GoogleDriveBackupException('تعذر حذف النسخة من Google Drive: $e');
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  // 7. سياسة الاحتفاظ السحابي الآمن (Safe Retention & Deletion)
  // ════════════════════════════════════════════════════════════════════════

  Future<int> applyRetentionPolicy({int maxBackups = defaultMaxBackups}) async {
    if (maxBackups < 1) return 0;

    final api = _getDriveApi();
    final cloudBackups = await listCloudBackups();

    // قاعدة أمان: لا يتم الحذف إلا إذا كان عدد النسخ يتجاوز الحد الأقصى
    // ونضمن دائماً بقاء نسخة صالحة واحدة على الأقل
    if (cloudBackups.length <= maxBackups || cloudBackups.length <= 1) {
      return 0;
    }

    int deletedCount = 0;
    // مرتبة تنازلياً من الأحدث للأقدم، لذا النسخ الزائدة تكون في نهاية القائمة
    final excessBackups = cloudBackups.sublist(maxBackups);

    for (final backup in excessBackups) {
      // حظر قاطع لحذف آخر نسخة
      if (cloudBackups.length - deletedCount <= 1) break;

      try {
        await api.files.delete(backup.id);
        deletedCount++;
        debugPrint('🗑️ تم تدوير وحذف النسخة السحابية القديمة: ${backup.name} (${backup.id})');
      } catch (e) {
        debugPrint('Notice: Error deleting expired backup ${backup.id}: $e');
      }
    }

    return deletedCount;
  }
}
