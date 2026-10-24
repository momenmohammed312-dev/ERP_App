// ════════════════════════════════════════════════════════════════════════
// نظام النسخ الاحتياطي والاستعادة المحسّن - POS SaaS Offline
// ════════════════════════════════════════════════════════════════════════

import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive_io.dart';
import 'package:encrypt/encrypt.dart' as encrypt_pkg;
import 'package:intl/intl.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/utils/app_utils.dart';
import 'package:pos_offline_desktop/core/config/app_flavor.dart';
import 'package:pos_offline_desktop/core/services/backup_service.dart'
    as core_backup;

// ════════════════════════════════════════════════════════════════════════
// 1. نموذج النسخة الاحتياطية المحسّن
// ════════════════════════════════════════════════════════════════════════

class EnhancedBackupInfo {
  final String filename;
  final String filePath;
  final DateTime createdAt;
  final int size;
  final String type; // auto, manual, transaction
  final String? description;
  final int? createdBy;
  final String version;
  final String checksum;
  final bool isEncrypted;

  EnhancedBackupInfo({
    required this.filename,
    required this.filePath,
    required this.createdAt,
    required this.size,
    required this.type,
    this.description,
    this.createdBy,
    this.version = '2.0.0',
    required this.checksum,
    this.isEncrypted = true,
  });

  String get formattedSize {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(2)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  String get formattedDate {
    final formatter = DateFormat('yyyy-MM-dd HH:mm:ss', 'ar_EG');
    return formatter.format(createdAt);
  }

  String get formattedDateShort {
    final formatter = DateFormat('yyyy-MM-dd', 'ar_EG');
    return formatter.format(createdAt);
  }

  Map<String, dynamic> toJson() {
    return {
      'filename': filename,
      'file_path': filePath,
      'created_at': createdAt.toIso8601String(),
      'size': size,
      'type': type,
      'description': description,
      'created_by': createdBy,
      'version': version,
      'checksum': checksum,
      'is_encrypted': isEncrypted,
    };
  }

  factory EnhancedBackupInfo.fromJson(Map<String, dynamic> json) {
    return EnhancedBackupInfo(
      filename: json['filename'] as String,
      filePath: json['file_path'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      size: json['size'] as int,
      type: json['type'] as String,
      description: json['description'] as String?,
      createdBy: json['created_by'] == null
          ? null
          : int.tryParse(json['created_by'].toString()),
      version: json['version'] as String? ?? '2.0.0',
      checksum: json['checksum'] as String,
      isEncrypted: json['is_encrypted'] as bool? ?? true,
    );
  }
}

// ════════════════════════════════════════════════════════════════════════
// 2. خدمة النسخ الاحتياطي المحسّنة
// ════════════════════════════════════════════════════════════════════════

class BackupOperationInProgressException implements Exception {
  final String message;
  BackupOperationInProgressException([
    this.message = 'عملية نسخ احتياطي أو استعادة أخرى قيد التنفيذ حالياً. يرجى الانتظار حتى اكتمالها.',
  ]);
  @override
  String toString() => message;
}

class _CheckUser extends QueryExecutorUser {
  @override
  int get schemaVersion => 1;

  @override
  Future<void> beforeOpen(QueryExecutor executor, OpeningDetails details) async {}
}

class EnhancedBackupService {
  static const String _backupDir = 'data/backups';
  static const String _encryptionKey = 'POS-SaaS-Backup-Key-2024-32Chars';
  static const int _maxBackups = 10; // الاحتفاظ بآخر 10 نسخ
  static const String _backupExtension = '.posbackup';

  // Singleton
  static final EnhancedBackupService _instance =
      EnhancedBackupService._internal();
  factory EnhancedBackupService() => _instance;
  EnhancedBackupService._internal();

  static bool _isOperationInProgress = false;
  @visibleForTesting
  static bool get isOperationInProgress => _isOperationInProgress;

  AppDatabase? _db;
  @visibleForTesting
  static Directory? customBackupDirectory;

  @visibleForTesting
  static String? customDatabasePath;

  void init(AppDatabase db) {
    _db = db;
  }

  // ════════════════════════════════════════════════════════════════════
  // إنشاء نسخة احتياطية
  // ════════════════════════════════════════════════════════════════════

  Future<EnhancedBackupInfo> createBackup({
    String type = 'manual',
    String? description,
    int? createdBy,
    bool encrypt = true,
  }) async {
    if (kIsWeb) {
      throw Exception('Backup operations not supported on web platform');
    }
    if (_isOperationInProgress) {
      throw BackupOperationInProgressException();
    }
    _isOperationInProgress = true;

    Directory? thisTempDir;
    String? thisTempZipPath;

    try {
      debugPrint('📦 بدء النسخ الاحتياطي المحسّن...');

      // 1. إنشاء مجلد النسخ الاحتياطية
      final backupDirectory = await _getBackupDirectory();
      if (!await backupDirectory.exists()) {
        await backupDirectory.create(recursive: true);
      }

      // 2. توليد اسم الملف
      final timestamp = DateTime.now();
      var filename = 'backup_${_formatTimestamp(timestamp)}$_backupExtension';
      var backupPath = path.join(backupDirectory.path, filename);
      if (await File(backupPath).exists()) {
        filename =
            'backup_${_formatTimestamp(timestamp)}_${timestamp.millisecond}_${timestamp.microsecond % 1000}$_backupExtension';
        backupPath = path.join(backupDirectory.path, filename);
      }

      // 3. الحصول على مسار قاعدة البيانات
      final dbPath = await _getDatabasePath();
      final dbFile = File(dbPath);

      if (!await dbFile.exists()) {
        throw Exception('قاعدة البيانات غير موجودة: $dbPath');
      }

      // 4. إنشاء مجلد مؤقت فريد لهذه العملية
      final backupId = '${timestamp.millisecondsSinceEpoch}_${timestamp.microsecond % 1000}';
      final tempDir = Directory(path.join(backupDirectory.path, 'temp_$backupId'));
      thisTempDir = tempDir;
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
      await tempDir.create(recursive: true);

      // 5. نسخ قاعدة البيانات عبر اللقطة الذرية
      final tempDbPath = path.join(tempDir.path, 'database.db');
      await _createAtomicSnapshot(tempDbPath, dbFile);

      // 6. نسخ ملفات الإعدادات الهامة
      final configFiles = await _copyConfigFiles(tempDir.path);

      // 7. إنشاء ملف المعلومات
      final info = {
        'created_at': timestamp.toIso8601String(),
        'type': type,
        'description': description,
        'created_by': createdBy,
        'version': '2.0.0',
        'config_files': configFiles,
        'database_size': await dbFile.length(),
      };

      final infoPath = path.join(tempDir.path, 'backup_info.json');
      await File(infoPath).writeAsString(jsonEncode(info));

      // 8. ضغط الملفات
      debugPrint('📦 ضغط الملفات...');
      final encoder = ZipFileEncoder();
      final tempZipPath = path.join(backupDirectory.path, 'temp_$backupId.zip');
      thisTempZipPath = tempZipPath;
      encoder.create(tempZipPath);
      await encoder.addDirectory(tempDir);
      encoder.close();

      // 9. حساب checksum
      final zipFile = File(tempZipPath);
      final zipBytes = await zipFile.readAsBytes();
      final checksum = sha256.convert(zipBytes).toString();

      // 10. تشفير الملف (إذا مفعّل)
      List<int> finalBytes;
      if (encrypt) {
        debugPrint('🔒 تشفير النسخة الاحتياطية...');
        finalBytes = _encryptData(zipBytes);
      } else {
        finalBytes = zipBytes;
      }

      // 11. حفظ النسخة النهائية
      await File(backupPath).writeAsBytes(finalBytes);

      // 12. الحصول على حجم الملف النهائي
      final backupFile = File(backupPath);
      final size = await backupFile.length();

      debugPrint('✅ تم إنشاء النسخة الاحتياطية بنجاح');
      debugPrint('📁 الموقع: $backupPath');
      debugPrint('📊 الحجم: $_formatBytes(size)');
      debugPrint('🔐 التشفير: ${encrypt ? "مفعّل" : "معطّل"}');

      // 13. تنظيف النسخ القديمة
      await _cleanOldBackups();

      return EnhancedBackupInfo(
        filename: filename,
        filePath: backupPath,
        createdAt: timestamp,
        size: size,
        type: type,
        description: description,
        createdBy: createdBy,
        checksum: checksum,
        isEncrypted: encrypt,
      );
    } catch (e) {
      debugPrint('❌ خطأ في النسخ الاحتياطي: $e');
      rethrow;
    } finally {
      _isOperationInProgress = false;
      try {
        if (thisTempDir != null && await thisTempDir.exists()) {
          await thisTempDir.delete(recursive: true);
        }
      } catch (_) {}
      try {
        if (thisTempZipPath != null) {
          final zipF = File(thisTempZipPath);
          if (await zipF.exists()) {
            await zipF.delete();
          }
        }
      } catch (_) {}
    }
  }

  // ════════════════════════════════════════════════════════════════════
  // استعادة من نسخة احتياطية
  // ════════════════════════════════════════════════════════════════════

  Future<bool> restoreBackup(
    String filename, {
    bool createPreRestoreBackup = true,
  }) async {
    if (kIsWeb) {
      throw Exception('Backup restore not supported on web platform');
    }
    if (_isOperationInProgress) {
      throw BackupOperationInProgressException();
    }
    _isOperationInProgress = true;

    Directory? tempDir;
    try {
      debugPrint('📥 بدء الاستعادة من: $filename');

      final backupDirectory = await _getBackupDirectory();
      final backupPath = path.join(backupDirectory.path, filename);
      final backupFile = File(backupPath);

      if (!await backupFile.exists()) {
        throw Exception('ملف النسخة الاحتياطية غير موجود: $backupPath');
      }

      // 1. قراءة الملف
      final rawBytes = await backupFile.readAsBytes();
      if (rawBytes.isEmpty) {
        throw Exception('ملف النسخة الاحتياطية فارغ');
      }

      // 2. اكتشاف التنسيق + فك التشفير (إن وجد)
      final zipBytes = _detectAndDecrypt(rawBytes);

      // 3. التحقق أن الناتج ZIP فعلاً قبل فك الضغط
      if (!_isZipBytes(zipBytes)) {
        try {
          final db = _db;
          if (db == null) {
            throw Exception('Database connection not initialized in EnhancedBackupService');
          }
          final coreService = core_backup.BackupService(db);
          await coreService.restoreBackup(null, filename);
          debugPrint('✅ تمت الاستعادة بنجاح (Core BackupService)');
          return true;
        } catch (_) {
          throw Exception(
            'صيغة النسخة الاحتياطية غير مدعومة أو الملف تالف (ليس ZIP صالحاً)',
          );
        }
      }

      // 4. فك الضغط في مجلد مؤقت فريد
      final restoreId = DateTime.now().millisecondsSinceEpoch.toString();
      tempDir = Directory(path.join(backupDirectory.path, 'restore_temp_$restoreId'));
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
      await tempDir.create(recursive: true);

      final zipDecoder = ZipDecoder();
      final archive = zipDecoder.decodeBytes(zipBytes);

      for (final file in archive) {
        final fName = file.name;
        if (file.isFile) {
          final data = file.content as List<int>;
          final filePath = path.join(tempDir.path, fName);
          await File(filePath).create(recursive: true);
          await File(filePath).writeAsBytes(data);
        }
      }

      // 5. التحقق من معلومات النسخة
      final infoCandidates = [
        File(path.join(tempDir.path, 'backup_info.json')),
      ];
      for (final entity in tempDir.listSync(recursive: true)) {
        if (entity is File && path.basename(entity.path) == 'backup_info.json') {
          infoCandidates.add(entity);
          break;
        }
      }
      for (final infoFile in infoCandidates) {
        if (await infoFile.exists()) {
          try {
            final infoContent = await infoFile.readAsString();
            final info = jsonDecode(infoContent);
            debugPrint(
              '📋 معلومات النسخة: ${info['created_at']} - ${info['type']}',
            );
            break;
          } catch (_) {}
        }
      }

      // 6. استعادة قاعدة البيانات
      final dbPath = await _getDatabasePath();
      final targetDbPath = dbPath;
      String? sourceDbPath;
      for (final candidate in ['database.db', 'pos_database.db']) {
        final f = File(path.join(tempDir.path, candidate));
        if (await f.exists()) {
          sourceDbPath = f.path;
          break;
        }
      }

      if (sourceDbPath == null) {
        for (final entity in tempDir.listSync(recursive: true)) {
          if (entity is File) {
            final bName = path.basename(entity.path);
            if (bName == 'database.db' ||
                bName == 'pos_database.db' ||
                bName.endsWith('.sqlite')) {
              sourceDbPath = entity.path;
              break;
            }
          }
        }
      }

      if (sourceDbPath == null) {
        throw Exception('ملف قاعدة البيانات غير موجود في النسخة الاحتياطية');
      }

      // فحص الملف المرشح في بيئة العزل قبل المساس بالداتابيز الحية
      final isCandidateValid = await _verifyDatabaseFile(sourceDbPath);
      if (!isCandidateValid) {
        throw StateError(
          'ملف قاعدة البيانات في النسخة الاحتياطية تالف وفشل في فحص السلامة (integrity check)',
        );
      }

      final candidateSchemaVer = await _getDatabaseUserVersion(sourceDbPath);
      const maxSupportedVersion = 80;
      if (candidateSchemaVer > maxSupportedVersion) {
        throw StateError(
          'لا يمكن استعادة النسخة: أُنشئت بإصدار أحدث ($candidateSchemaVer) يتجاوز إصدار التطبيق الحالي ($maxSupportedVersion)',
        );
      }

      // مسارات ملفات الـ Sidecars المحتملة
      final targetWal = File('$targetDbPath-wal');
      final targetShm = File('$targetDbPath-shm');
      final targetJournal = File('$targetDbPath-journal');

      // إنشاء نسخة احتياطية من القاعدة الحالية ومن أي sidecars
      String? preRestoreBackup;
      String? preRestoreWal;
      String? preRestoreShm;
      String? preRestoreJournal;

      if (createPreRestoreBackup && await File(targetDbPath).exists()) {
        final timestamp = _formatTimestamp(DateTime.now());
        preRestoreBackup = '$targetDbPath.before_restore_$timestamp';
        await File(targetDbPath).copy(preRestoreBackup);
        if (await targetWal.exists()) {
          preRestoreWal = '$targetDbPath-wal.before_restore_$timestamp';
          await targetWal.copy(preRestoreWal);
        }
        if (await targetShm.exists()) {
          preRestoreShm = '$targetDbPath-shm.before_restore_$timestamp';
          await targetShm.copy(preRestoreShm);
        }
        if (await targetJournal.exists()) {
          preRestoreJournal = '$targetDbPath-journal.before_restore_$timestamp';
          await targetJournal.copy(preRestoreJournal);
        }
        debugPrint(
          '💾 تم إنشاء نسخة احتياطية قبل الاستعادة: $preRestoreBackup',
        );
      }

      // إغلاق اتصال قاعدة البيانات الحالي قبل استبدال الملف
      try {
        await _db?.close();
      } catch (e) {
        debugPrint('Notice: Database close before file swap: $e');
      }

      // حذف ملفات الـ Sidecars القديمة لضمان عدم حدوث تلوث في الاسترداد
      try {
        if (await targetWal.exists()) await targetWal.delete();
        if (await targetShm.exists()) await targetShm.delete();
        if (await targetJournal.exists()) await targetJournal.delete();
      } catch (e) {
        debugPrint('Notice: clean old sidecars: $e');
      }

      // استبدال قاعدة البيانات مع التراجع الذري عند الفشل
      try {
        await File(sourceDbPath).copy(targetDbPath);
      } catch (copyError) {
        debugPrint('❌ فشل استبدال الملف، جاري التراجع: $copyError');
        if (preRestoreBackup != null && await File(preRestoreBackup).exists()) {
          try {
            await File(preRestoreBackup).copy(targetDbPath);
            if (preRestoreWal != null && await File(preRestoreWal).exists()) {
              await File(preRestoreWal).copy(targetWal.path);
            }
            if (preRestoreJournal != null && await File(preRestoreJournal).exists()) {
              await File(preRestoreJournal).copy(targetJournal.path);
            }
            debugPrint('🔄 تم التراجع واستعادة النسخة السابقة بنجاح');
            throw FileSystemException('فشل استبدال قاعدة البيانات، ولكن تم التراجع واستعادة النسخة السابقة بنجاح: $copyError');
          } catch (rollbackError) {
            debugPrint('CRITICAL: Rollback failed: $rollbackError');
            throw FileSystemException('خطأ حرج: فشل استبدال قاعدة البيانات وفشل التراجع التلقائي: $rollbackError');
          }
        }
        rethrow;
      }
      debugPrint('✅ تمت استعادة قاعدة البيانات بنجاح');

      // 7. استعادة ملفات الإعدادات بأمان
      await _restoreConfigFiles(tempDir.path);

      debugPrint('✅ تمت الاستعادة بنجاح');
      return true;
    } catch (e) {
      debugPrint('❌ خطأ في الاستعادة: $e');
      rethrow;
    } finally {
      _isOperationInProgress = false;
      try {
        if (tempDir != null && await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      } catch (_) {
        // Ignore cleanup errors
      }
    }
  }

  // ════════════════════════════════════════════════════════════════════
  // الحصول على قائمة النسخ الاحتياطية
  // ════════════════════════════════════════════════════════════════════

  Future<List<EnhancedBackupInfo>> listBackups() async {
    if (kIsWeb) {
      return []; // No backups available on web
    }
    try {
      final backupDirectory = await _getBackupDirectory();
      if (!await backupDirectory.exists()) {
        return [];
      }

      final backups = <EnhancedBackupInfo>[];
      await for (final entity in backupDirectory.list()) {
        if (entity is File && entity.path.endsWith(_backupExtension)) {
          try {
            final info = await _getBackupInfo(entity);
            if (info != null) {
              backups.add(info);
            }
          } catch (e) {
            debugPrint('⚠️ خطأ في قراءة معلومات النسخة ${entity.path}: $e');
          }
        }
      }

      // ترتيب حسب التاريخ (الأحدث أولاً)
      backups.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      return backups;
    } catch (e) {
      debugPrint('❌ خطأ في جلب قائمة النسخ الاحتياطية: $e');
      return [];
    }
  }

  // ════════════════════════════════════════════════════════════════════
  // حذف نسخة احتياطية
  // ════════════════════════════════════════════════════════════════════

  Future<bool> deleteBackup(String filename) async {
    if (kIsWeb) {
      throw Exception('Backup deletion not supported on web platform');
    }
    if (_isOperationInProgress) {
      throw BackupOperationInProgressException();
    }
    _isOperationInProgress = true;
    try {
      final backupDirectory = await _getBackupDirectory();
      final backupPath = path.join(backupDirectory.path, filename);
      final file = File(backupPath);

      if (await file.exists()) {
        await file.delete();
        debugPrint('🗑️ تم حذف النسخة الاحتياطية: $filename');
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('❌ خطأ في حذف النسخة الاحتياطية: $e');
      return false;
    } finally {
      _isOperationInProgress = false;
    }
  }

  // ════════════════════════════════════════════════════════════════════
  // التحقق من سلامة النسخة الاحتياطية
  // ════════════════════════════════════════════════════════════════════

  Future<bool> verifyBackupIntegrity(String filename) async {
    if (kIsWeb) {
      return false; // Cannot verify on web
    }
    try {
      final backupDirectory = await _getBackupDirectory();
      final backupPath = path.join(backupDirectory.path, filename);
      final backupFile = File(backupPath);

      if (!await backupFile.exists()) {
        return false;
      }

      final encryptedBytes = await backupFile.readAsBytes();

      // محاولة فك التشفير
      List<int> zipBytes;
      try {
        zipBytes = _decryptData(encryptedBytes);
      } catch (e) {
        zipBytes = encryptedBytes;
      }

      // التحقق من checksum
      final calculatedChecksum = sha256.convert(zipBytes).toString();

      // قراءة معلومات النسخة
      final info = await _getBackupInfo(backupFile);
      if (info != null && info.checksum == calculatedChecksum) {
        debugPrint('✅ النسخة الاحتياطية سليمة: $filename');
        return true;
      }

      debugPrint('⚠️ النسخة الاحتياطية تالبة أو معدّلة: $filename');
      return false;
    } catch (e) {
      debugPrint('❌ خطأ في التحقق من النسخة الاحتياطية: $e');
      return false;
    }
  }

  // ════════════════════════════════════════════════════════════════════
  // دوال مساعدة خاصة
  // ════════════════════════════════════════════════════════════════════

  Future<Directory> _getBackupDirectory() async {
    if (customBackupDirectory != null) return customBackupDirectory!;
    if (kIsWeb) {
      throw Exception('File system operations not supported on web platform');
    }
    final appDir = await getApplicationDocumentsDirectory();
    return Directory(path.join(appDir.path, _backupDir));
  }

  Future<String> _getDatabasePath() async {
    if (customDatabasePath != null) return customDatabasePath!;
    if (kIsWeb) {
      throw Exception('File system operations not supported on web platform');
    }
    final appDir = await getApplicationDocumentsDirectory();
    final dbName = AppFlavor.databaseName;

    // فحص المسارات المحتملة بالترتيب للعثور على الملف الحقيقي
    final candidatePaths = [
      path.join(appDir.path, '$dbName.sqlite'),
      path.join(appDir.path, dbName),
      path.join(appDir.path, 'pos_offline_desktop_database', 'pos_offline_desktop_database.sqlite'),
      path.join(appDir.path, 'pos_offline_desktop_database.sqlite'),
    ];

    for (final candidate in candidatePaths) {
      if (await File(candidate).exists()) {
        return candidate;
      }
    }

    // كمسار افتراضي
    return path.join(appDir.path, '$dbName.sqlite');
  }

  Future<List<String>> _copyConfigFiles(String tempDir) async {
    final configFiles = <String>[];

    // نسخ ملفات الإعدادات المهمة
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final importantFiles = [
        'data/config.json',
        'data/settings.json',
        'data/license.json',
      ];

      for (final configPath in importantFiles) {
        final configFile = File(path.join(appDir.path, configPath));
        if (await configFile.exists()) {
          final targetPath = path.join(tempDir, path.basename(configPath));
          await configFile.copy(targetPath);
          configFiles.add(path.basename(configPath));
        }
      }
    } catch (e) {
      // Config files are optional — continue without them
    }

    return configFiles;
  }

  Future<void> _restoreConfigFiles(String tempDir) async {
    try {
      final Directory baseDir;
      if (customBackupDirectory != null) {
        baseDir = customBackupDirectory!.parent;
      } else {
        baseDir = await getApplicationDocumentsDirectory();
      }
      final targetConfigDir = Directory(path.join(baseDir.path, 'data'));
      if (!await targetConfigDir.exists()) {
        await targetConfigDir.create(recursive: true);
      }

      final tempConfigDir = Directory(tempDir);
      await for (final entity in tempConfigDir.list(recursive: true)) {
        if (entity is File && entity.path.endsWith('.json')) {
          final filename = path.basename(entity.path);
          if (filename == 'backup_info.json') continue;
          if (filename.contains('..') || filename.contains('/') || filename.contains(r'\')) continue;

          final targetPath = path.join(targetConfigDir.path, filename);
          await entity.copy(targetPath);
          debugPrint('📄 تم استعادة ملف الإعدادات: $filename');
        }
      }
    } catch (e) {
      debugPrint('⚠️ تحذير: خطأ غير حرج أثناء استعادة ملفات الإعدادات: $e');
    }
  }

  Future<void> _cleanOldBackups() async {
    // Phase 1 Zero Customer Impact: automated deletion disabled.
    return;
  }

  // ignore: unused_element
  Future<void> _legacyCleanOldBackups() async {
    try {
      final backups = await listBackups();

      if (backups.length <= _maxBackups) return;

      // حذف النسخ الزائدة
      for (var i = _maxBackups; i < backups.length; i++) {
        await deleteBackup(backups[i].filename);
      }

      debugPrint(
        '🧹 تم تنظيف ${backups.length - _maxBackups} نسخة احتياطية قديمة',
      );
    } catch (e) {
      debugPrint('⚠️ خطأ في تنظيف النسخ القديمة: $e');
    }
  }

  Future<void> _createAtomicSnapshot(
    String targetPath,
    File fallbackDbFile,
  ) async {
    final targetFile = File(targetPath);
    if (await targetFile.exists()) {
      await targetFile.delete();
    }

    final db = _db;
    if (db == null) {
      throw StateError('اتصال قاعدة البيانات غير مهيأ لأخذ نسخة احتياطية ذرية');
    }

    try {
      final normalized =
          targetPath.replaceAll(r'\', '/').replaceAll("'", "''");
      await db.customStatement('PRAGMA busy_timeout = 5000');
      await db.customStatement("VACUUM INTO '$normalized'");
      if (!await targetFile.exists() || await targetFile.length() == 0) {
        throw StateError('فشل إنشاء لقطة قاعدة البيانات أو حجمها صفر');
      }
      debugPrint('✅ تم إنشاء لقطة ذرية لقاعدة البيانات عبر VACUUM INTO');
    } catch (e) {
      debugPrint('❌ فشل تشغيل VACUUM INTO: $e');
      throw StateError('تعذر إنشاء لقطة ذرية لقاعدة البيانات عبر VACUUM INTO: $e');
    }

    // فحص سلامة الملف المعزول قبل اعتماده في الأرشيف
    final isSnapshotValid = await _verifyDatabaseFile(targetPath);
    if (!isSnapshotValid) {
      throw StateError(
        'فشلت لقطة قاعدة البيانات المؤقتة في فحص السلامة الهيكلية (integrity check)',
      );
    }
  }

  Future<bool> _verifyDatabaseFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists() || await file.length() == 0) return false;
      final executor = NativeDatabase(file);
      try {
        await executor.ensureOpen(_CheckUser());
        final rows = await executor.runSelect(
          'PRAGMA integrity_check;',
          const [],
        );
        if (rows.isEmpty) return false;
        final check = rows.first['integrity_check']?.toString();
        return check == 'ok';
      } finally {
        await executor.close();
      }
    } catch (e) {
      debugPrint('Database integrity verification failed: $e');
      return false;
    }
  }

  Future<int> _getDatabaseUserVersion(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return 0;
      final executor = NativeDatabase(file);
      try {
        await executor.ensureOpen(_CheckUser());
        final rows = await executor.runSelect('PRAGMA user_version;', const []);
        if (rows.isEmpty) return 0;
        final ver = rows.first['user_version'];
        if (ver is int) return ver;
        if (ver != null) return int.tryParse(ver.toString()) ?? 0;
        return 0;
      } finally {
        await executor.close();
      }
    } catch (e) {
      debugPrint('Database user_version check error: $e');
      return 0;
    }
  }



  Future<EnhancedBackupInfo?> _getBackupInfo(File backupFile) async {
    try {
      final filename = path.basename(backupFile.path);
      final size = await backupFile.length();

      // محاولة استخراج التاريخ من اسم الملف
      DateTime createdAt;
      try {
        final timestampStr = filename
            .replaceAll('backup_', '')
            .replaceAll(_backupExtension, '');
        createdAt = _parseTimestamp(timestampStr);
      } catch (e) {
        final stat = await backupFile.stat();
        createdAt = stat.modified;
      }

      // محاولة قراءة معلومات النسخة من الملف
      String checksum = '';
      String type = 'unknown';
      bool isEncrypted = true;

      try {
        final encryptedBytes = await backupFile.readAsBytes();
        List<int> zipBytes;

        try {
          zipBytes = _decryptData(encryptedBytes);
          isEncrypted = true;
        } catch (e) {
          zipBytes = encryptedBytes;
          isEncrypted = false;
        }

        checksum = sha256.convert(zipBytes).toString();

        // محاولة قراءة metadata
        final archive = ZipDecoder().decodeBytes(zipBytes);
        for (final file in archive.files) {
          if (file.name == 'backup_info.json') {
            final content = utf8.decode(file.content as List<int>);
            final info = jsonDecode(content);
            type = info['type'] as String? ?? 'unknown';
            break;
          }
        }
      } catch (e) {
        debugPrint('⚠️ لا يمكن قراءة معلومات النسخة: $e');
      }

      return EnhancedBackupInfo(
        filename: filename,
        filePath: backupFile.path,
        createdAt: createdAt,
        size: size,
        type: type,
        checksum: checksum,
        isEncrypted: isEncrypted,
      );
    } catch (e) {
      debugPrint('❌ خطأ في استخراج معلومات النسخة: $e');
      return null;
    }
  }

  // ════════════════════════════════════════════════════════════════════
  // دوال التشفير
  // ════════════════════════════════════════════════════════════════════

  List<int> _encryptData(List<int> data) {
    final key = encrypt_pkg.Key.fromUtf8(_encryptionKey);
    final iv = encrypt_pkg.IV.fromLength(16);
    final encrypter = encrypt_pkg.Encrypter(
      encrypt_pkg.AES(key, mode: encrypt_pkg.AESMode.cbc),
    );

    final encrypted = encrypter.encryptBytes(data, iv: iv);
    // إضافة الـ IV في البداية
    return [...iv.bytes, ...encrypted.bytes];
  }

  List<int> _decryptData(List<int> encryptedData) {
    if (encryptedData.length < 16) {
      throw Exception('البيانات المشفرة قصيرة جداً');
    }

    final key = encrypt_pkg.Key.fromUtf8(_encryptionKey);
    final iv = encrypt_pkg.IV(Uint8List.fromList(encryptedData.sublist(0, 16)));
    final encrypter = encrypt_pkg.Encrypter(
      encrypt_pkg.AES(key, mode: encrypt_pkg.AESMode.cbc),
    );

    final encrypted = encrypt_pkg.Encrypted(
      Uint8List.fromList(encryptedData.sublist(16)),
    );
    return encrypter.decryptBytes(encrypted, iv: iv);
  }

  bool _isZipBytes(List<int> bytes) {
    if (bytes.length < 4) return false;
    // ZIP local file header magic: PK\x03\x04
    return bytes[0] == 0x50 &&
        bytes[1] == 0x4B &&
        bytes[2] == 0x03 &&
        bytes[3] == 0x04;
  }

  List<int> _detectAndDecrypt(List<int> rawBytes) {
    // 1) Plain ZIP
    if (_isZipBytes(rawBytes)) {
      return rawBytes;
    }

    // 2) Try all known keys and IV formats
    final keys = [
      _encryptionKey, // Enhanced (current)
      'PosBackup@2024#SecureKey#32CharX', // User backup service
      'POS-BACKUP-KEY-2024-SECURE!!!', // Core backup service
    ];

    for (final keyStr in keys) {
      // Try with prepended IV (Enhanced/Core format)
      if (rawBytes.length > 16) {
        try {
          final iv = encrypt_pkg.IV(
            Uint8List.fromList(rawBytes.sublist(0, 16)),
          );
          final encrypted = encrypt_pkg.Encrypted(
            Uint8List.fromList(rawBytes.sublist(16)),
          );

          // Try both direct UTF8 key and SHA256 hashed key
          final keyVariants = [
            encrypt_pkg.Key.fromUtf8(keyStr.padRight(32).substring(0, 32)),
            encrypt_pkg.Key(deriveAesKey(keyStr)),
          ];

          for (final key in keyVariants) {
            final encrypter = encrypt_pkg.Encrypter(
              encrypt_pkg.AES(key, mode: encrypt_pkg.AESMode.cbc),
            );
            final decrypted = encrypter.decryptBytes(encrypted, iv: iv);
            if (_isZipBytes(decrypted)) return decrypted;
          }
        } catch (e) {
          print('Decryption attempt failed with stored IV: $e');
        }
      }

      // Try with fixed zero IV (Legacy/User format)
      try {
        final iv = encrypt_pkg.IV.fromLength(16);
        final encrypted = encrypt_pkg.Encrypted(Uint8List.fromList(rawBytes));

        final keyVariants = [
          encrypt_pkg.Key.fromUtf8(keyStr.padRight(32).substring(0, 32)),
          encrypt_pkg.Key(deriveAesKey(keyStr)),
        ];

        for (final key in keyVariants) {
          final encrypter = encrypt_pkg.Encrypter(
            encrypt_pkg.AES(key, mode: encrypt_pkg.AESMode.cbc),
          );
          final decrypted = encrypter.decryptBytes(encrypted, iv: iv);
          if (_isZipBytes(decrypted)) return decrypted;
        }
      } catch (e) {
        print('Decryption attempt failed with zero IV: $e');
      }
    }

    return rawBytes;
  }

  // ════════════════════════════════════════════════════════════════════
  // دوال مساعدة
  // ════════════════════════════════════════════════════════════════════

  String _formatTimestamp(DateTime dt) {
    return DateFormat('yyyyMMdd_HHmmss').format(dt);
  }

  DateTime _parseTimestamp(String timestamp) {
    return DateFormat('yyyyMMdd_HHmmss').parse(timestamp);
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(2)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  // ════════════════════════════════════════════════════════════════════
  // إحصائيات النسخ الاحتياطي
  // ════════════════════════════════════════════════════════════════════

  Future<Map<String, dynamic>> getBackupStatistics() async {
    try {
      final backups = await listBackups();

      final totalSize = backups.fold<int>(
        0,
        (sum, backup) => sum + backup.size,
      );
      final encryptedCount = backups.where((b) => b.isEncrypted).length;

      final typeCounts = <String, int>{};
      for (final backup in backups) {
        typeCounts[backup.type] = (typeCounts[backup.type] ?? 0) + 1;
      }

      return {
        'total_backups': backups.length,
        'total_size': totalSize,
        'total_size_mb': (totalSize / (1024 * 1024)).toStringAsFixed(2),
        'encrypted_backups': encryptedCount,
        'unencrypted_backups': backups.length - encryptedCount,
        'backup_types': typeCounts,
        'oldest_backup': backups.isNotEmpty ? backups.last.formattedDate : null,
        'newest_backup': backups.isNotEmpty
            ? backups.first.formattedDate
            : null,
        'max_backups': _maxBackups,
      };
    } catch (e) {
      debugPrint('❌ خطأ في جلب إحصائيات النسخ الاحتياطي: $e');
      return {'error': e.toString()};
    }
  }
}

// ════════════════════════════════════════════════════════════════════════
// 3. خدمة النسخ الاحتياطي التلقائي المحسّنة
// ════════════════════════════════════════════════════════════════════════

class EnhancedAutoBackupService {
  static Timer? _dailyTimer;
  static Timer? _weeklyTimer;
  static int _transactionCount = 0;
  static const int _transactionThreshold = 50; // كل 50 عملية
  static bool _isRunning = false;

  /// بدء النسخ الاحتياطي التلقائي
  static void start() {
    if (_isRunning) {
      debugPrint('النسخ الاحتياطي التلقائي يعمل بالفعل');
      return;
    }

    _isRunning = true;
    debugPrint('🔄 بدء النسخ الاحتياطي التلقائي المحسّن...');

    // جدولة النسخ اليومي
    _scheduleDailyBackup();

    // جدولة النسخ الأسبوعي
    _scheduleWeeklyBackup();

    debugPrint('✅ تم تفعيل النسخ الاحتياطي التلقائي');
    debugPrint('  - نسخ يومي: 11:00 PM');
    debugPrint('  - نسخ أسبوعي: يوم الأحد 2:00 AM');
    debugPrint('  - نسخ تلقائي: كل $_transactionThreshold عملية');
  }

  /// إيقاف النسخ الاحتياطي التلقائي
  static void stop() {
    _isRunning = false;
    _dailyTimer?.cancel();
    _weeklyTimer?.cancel();
    _dailyTimer = null;
    _weeklyTimer = null;
    debugPrint('⏹️ تم إيقاف النسخ الاحتياطي التلقائي');
  }

  /// زيادة عداد العمليات
  static void incrementTransactionCount() async {
    if (!_isRunning) return;

    _transactionCount++;

    if (_transactionCount >= _transactionThreshold) {
      debugPrint('🔄 وصلت عتبة العمليات ($_transactionThreshold) - بدء النسخ');
      await _performTransactionBackup();
      _transactionCount = 0;
    }
  }

  /// جدولة النسخ اليومي
  static void _scheduleDailyBackup() {
    _dailyTimer?.cancel();

    final now = DateTime.now();
    var scheduledTime = DateTime(
      now.year,
      now.month,
      now.day,
      23, // 11 PM
      0, // 0 minutes
      0, // 0 seconds
    );

    // إذا تجاوز الوقت المحدد، جدّل لليوم التالي
    if (scheduledTime.isBefore(now)) {
      scheduledTime = scheduledTime.add(const Duration(days: 1));
    }

    final initialDelay = scheduledTime.difference(now);
    debugPrint(
      '📅 النسخ اليومي التالي: $scheduledTime (خلال ${initialDelay.inHours} ساعة)',
    );

    _dailyTimer = Timer(initialDelay, () {
      _performDailyBackup();
      _scheduleDailyBackup(); // جدّل لليوم التالي
    });
  }

  /// جدولة النسخ الأسبوعي
  static void _scheduleWeeklyBackup() {
    _weeklyTimer?.cancel();

    final now = DateTime.now();
    var scheduledTime = DateTime(
      now.year,
      now.month,
      now.day,
      2, // 2 AM
      0, // 0 minutes
      0, // 0 seconds
    );

    // الانتقال إلى يوم الأحد التالي
    while (scheduledTime.weekday != DateTime.sunday) {
      scheduledTime = scheduledTime.add(const Duration(days: 1));
    }

    // إذا تجاوز الوقت المحدد، جدّل للأسبوع التالي
    if (scheduledTime.isBefore(now)) {
      scheduledTime = scheduledTime.add(const Duration(days: 7));
    }

    final initialDelay = scheduledTime.difference(now);
    debugPrint(
      '📅 النسخ الأسبوعي التالي: $scheduledTime (خلال ${initialDelay.inDays} يوم)',
    );

    _weeklyTimer = Timer(initialDelay, () {
      _performWeeklyBackup();
      _scheduleWeeklyBackup(); // جدّل للأسبوع التالي
    });
  }

  /// تنفيذ النسخ اليومي
  static Future<void> _performDailyBackup() async {
    try {
      debugPrint('🔄 تنفيذ النسخ الاحتياطي اليومي...');

      await EnhancedBackupService().createBackup(
        type: 'daily_auto',
        description: 'نسخ احتياطي يومي تلقائي',
      );

      debugPrint('✅ اكتمل النسخ الاحتياطي اليومي');
    } catch (e) {
      debugPrint('❌ خطأ في النسخ الاحتياطي اليومي: $e');
    }
  }

  /// تنفيذ النسخ الأسبوعي
  static Future<void> _performWeeklyBackup() async {
    try {
      debugPrint('🔄 تنفيذ النسخ الاحتياطي الأسبوعي...');

      await EnhancedBackupService().createBackup(
        type: 'weekly_auto',
        description: 'نسخ احتياطي أسبوعي تلقائي',
      );

      debugPrint('✅ اكتمل النسخ الاحتياطي الأسبوعي');
    } catch (e) {
      debugPrint('❌ خطأ في النسخ الاحتياطي الأسبوعي: $e');
    }
  }

  /// تنفيذ النسخ بناءً على العمليات
  static Future<void> _performTransactionBackup() async {
    try {
      debugPrint('🔄 تنفيذ النسخ الاحتياطي التلقائي...');

      await EnhancedBackupService().createBackup(
        type: 'transaction_auto',
        description: 'نسخ احتياطي تلقائي بعد $_transactionThreshold عملية',
      );

      debugPrint('✅ اكتمل النسخ الاحتياطي التلقائي');
    } catch (e) {
      debugPrint('❌ خطأ في النسخ الاحتياطي التلقائي: $e');
    }
  }

  /// إنشاء نسخة فورية
  static Future<void> createNow({String? description}) async {
    try {
      debugPrint('⏰ إنشاء نسخة احتياطية فورية...');

      await EnhancedBackupService().createBackup(
        type: 'immediate_auto',
        description: description ?? 'نسخ احتياطي فوري',
      );

      debugPrint('✅ اكتملت النسخة الاحتياطية الفورية');
    } catch (e) {
      debugPrint('❌ فشلت النسخة الاحتياطية الفورية: $e');
    }
  }

  /// الحصول على الإحصائيات
  static Map<String, dynamic> getStatus() {
    return {
      'is_running': _isRunning,
      'transaction_count': _transactionCount,
      'transaction_threshold': _transactionThreshold,
      'daily_backup_enabled': _dailyTimer != null,
      'weekly_backup_enabled': _weeklyTimer != null,
    };
  }

  /// إعادة تعيين عداد العمليات
  static void resetTransactionCounter() {
    _transactionCount = 0;
    debugPrint('🔄 تم إعادة تعيين عداد العمليات');
  }
}
