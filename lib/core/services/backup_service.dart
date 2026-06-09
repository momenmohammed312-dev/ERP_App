import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:drift/drift.dart';
import 'package:archive/archive.dart';
import 'package:encrypt/encrypt.dart' as encrypt_pkg;
import 'package:crypto/crypto.dart';
import '../database/app_database.dart';
import 'package:path/path.dart' as path;
import '../models/user_model.dart';
import '../utils/logger.dart';
import '../utils/app_utils.dart';
import 'validation/permission_validator.dart';

/// Enhanced Backup Service for POS System
/// خدمة النسخ الاحتياطي المحسنة لنظام نقاط البيع
class BackupService {
  final AppDatabase _db;
  static const String _backupDir = 'data/backups';
  static const String _encryptionKey =
      'POS-BACKUP-KEY-2024-SECURE!!!'; // hashed via deriveAesKey to 32 bytes
  static const int _maxBackups = 7; // الاحتفاظ بآخر 7 نسخ
  static Timer? _autoBackupTimer;

  BackupService(this._db);

  /// Create a complete backup of the database with encryption
  /// إنشاء نسخة احتياطية كاملة ومشفرة من قاعدة البيانات
  Future<BackupInfo> createBackup(
    User? user, {
    String type = 'manual',
    String? description,
    int? createdBy,
  }) async {
    PermissionValidator.requirePermission(user, Permission.createBackup, 'إنشاء نسخة احتياطية');
    if (kIsWeb) {
      throw Exception('Backup operations not supported on web platform');
    }
    try {
      AppLogger.i('📦 بدء النسخ الاحتياطي...');

      // 1. إنشاء مجلد النسخ الاحتياطية
      final backupDirectory = await _getBackupDirectory();

      // 2. توليد اسم الملف
      final timestamp = DateTime.now();
      final filename = 'backup_${_formatTimestamp(timestamp)}.posbackup';
      final backupPath = path.join(backupDirectory.path, filename);

      // 3. الحصول على جميع بيانات الجداول
      final backupData = await _getAllTablesData();

      // 4. إنشاء ملف المعلومات
      final info = {
        'version': '2.0.0',
        'created_at': timestamp.toIso8601String(),
        'type': type,
        'description': description,
        'created_by': createdBy,
        'database': 'pos_offline_desktop',
        'tables': backupData,
        'checksum': sha256
            .convert(utf8.encode(jsonEncode(backupData)))
            .toString(),
      };

      // 5. إنشاء أرشيف
      final archive = Archive();

      // إضافة ملف البيانات
      final dataBytes = utf8.encode(jsonEncode(info));
      final dataFile = ArchiveFile(
        'backup_data.json',
        dataBytes.length,
        dataBytes,
      );
      archive.addFile(dataFile);

      // 6. ضغط الأرشيف
      AppLogger.i('📦 ضغط الملفات...');
      final zipData = ZipEncoder().encode(archive);
      if (zipData == null) {
        throw Exception('فشل في إنشاء أرشيف ZIP');
      }

      // 7. تشفير الملف
      AppLogger.i('🔒 تشفير النسخة الاحتياطية...');
      final encryptedBytes = _encryptData(zipData);

      // 8. حفظ النسخة النهائية
      await File(backupPath).writeAsBytes(encryptedBytes);

      // 9. الحصول على حجم الملف
      final backupFile = File(backupPath);
      final size = await backupFile.length();

      AppLogger.i('✅ تم إنشاء النسخة الاحتياطية بنجاح');
      AppLogger.i('📁 الموقع: $backupPath');
      AppLogger.i('📊 الحجم: ${_formatBytes(size)}');

      // 10. تنظيف النسخ القديمة
      await _cleanOldBackups();

      return BackupInfo(
        filename: filename,
        createdAt: timestamp,
        size: size,
        type: type,
        description: description,
        createdBy: createdBy,
      );
    } catch (e) {
      AppLogger.e('❌ خطأ في النسخ الاحتياطي', e);
      rethrow;
    }
  }

  /// Restore database from encrypted backup file
  /// استعادة قاعدة البيانات من ملف النسخ الاحتياطي المشفر
  Future<void> restoreBackup(User? user, String filename) async {
    PermissionValidator.requirePermission(user, Permission.restoreBackup, 'استعادة نسخة احتياطية');
    if (kIsWeb) {
      throw Exception('Backup restore not supported on web platform');
    }
    try {
      AppLogger.i('📥 بدء الاستعادة من: $filename');

      final backupDirectory = await _getBackupDirectory();
      final backupPath = path.join(backupDirectory.path, filename);
      final backupFile = File(backupPath);

      if (!await backupFile.exists()) {
        throw Exception('ملف النسخة الاحتياطية غير موجود');
      }

      // 1. فك تشفير الملف
      AppLogger.i('🔓 فك تشفير النسخة الاحتياطية...');
      final encryptedBytes = await backupFile.readAsBytes();
      final decryptedBytes = _decryptData(encryptedBytes);

      // 2. فك ضغط الأرشيف
      AppLogger.i('📦 فك ضغط الملفات...');
      final archive = ZipDecoder().decodeBytes(decryptedBytes);

      // 3. استخراج ملف البيانات
      ArchiveFile? dataFile;
      for (final file in archive.files) {
        if (file.name == 'backup_data.json') {
          dataFile = file;
          break;
        }
      }

      if (dataFile == null) {
        throw Exception('ملف البيانات غير موجود في النسخة الاحتياطية');
      }

      // 4. قراءة البيانات والتحقق منها
      final dataJson = utf8.decode(dataFile.content as List<int>);
      final backup = jsonDecode(dataJson) as Map<String, dynamic>;

      if (!_validateBackupFormat(backup)) {
        throw Exception('صيغة النسخة الاحتياطية غير صالحة');
      }

      // التحقق من_checksum
      final tablesData = backup['tables'] as Map<String, dynamic>;
      final expectedChecksum = backup['checksum'] as String;
      final actualChecksum = sha256
          .convert(utf8.encode(jsonEncode(tablesData)))
          .toString();

      if (expectedChecksum != actualChecksum) {
        throw Exception('فشل التحقق من سلامة النسخة الاحتياطية');
      }

      // 5. استعادة البيانات
      AppLogger.i('💾 استعادة قاعدة البيانات...');
      await _restoreTablesData(tablesData);

      AppLogger.i('✅ تمت الاستعادة بنجاح');
      AppLogger.i('📅 تاريخ الإنشاء: ${backup['created_at']}');
    } catch (e) {
      AppLogger.e('❌ خطأ في الاستعادة', e);
      rethrow;
    }
  }

  /// Get enhanced backup information
  /// الحصول على معلومات النسخة الاحتياطية المحسنة
  Future<Map<String, dynamic>?> getBackupInfo(String filename) async {
    if (kIsWeb) {
      return null; // Backup info not available on web
    }
    try {
      final backupDirectory = await _getBackupDirectory();
      final backupPath = path.join(backupDirectory.path, filename);
      final backupFile = File(backupPath);

      if (!await backupFile.exists()) {
        return null;
      }

      final encryptedBytes = await backupFile.readAsBytes();
      final decryptedBytes = _decryptData(encryptedBytes);
      final archive = ZipDecoder().decodeBytes(decryptedBytes);

      // البحث عن ملف البيانات
      for (final file in archive.files) {
        if (file.name == 'backup_data.json') {
          final dataJson = utf8.decode(file.content as List<int>);
          final backup = jsonDecode(dataJson) as Map<String, dynamic>;

          return {
            'version': backup['version'],
            'timestamp': backup['created_at'],
            'type': backup['type'],
            'description': backup['description'],
            'created_by': backup['created_by'],
            'database': backup['database'],
            'tablesCount': (backup['tables'] as Map<String, dynamic>).length,
            'fileSize': await backupFile.length(),
            'filename': filename,
          };
        }
      }

      return null;
    } catch (e) {
      debugPrint('Error getting backup info: $e');
      return null;
    }
  }

  /// List all encrypted backup files
  /// قائمة جميع ملفات النسخ الاحتياطي المشفرة
  Future<List<BackupInfo>> listBackups() async {
    if (kIsWeb) {
      return []; // No backups available on web
    }
    try {
      final backupDirectory = await _getBackupDirectory();
      final files = await backupDirectory
          .list()
          .where(
            (entity) => entity is File && entity.path.endsWith('.posbackup'),
          )
          .cast<File>()
          .toList();

      final backups = <BackupInfo>[];

      for (final file in files) {
        try {
          final filename = path.basename(file.path);
          final size = await file.length();

          // محاولة استخراج التاريخ من اسم الملف
          DateTime createdAt;
          try {
            final timestampStr = filename
                .replaceAll('backup_', '')
                .replaceAll('.posbackup', '');
            createdAt = _parseTimestamp(timestampStr);
          } catch (e) {
            createdAt = (await file.stat()).modified;
          }

          // الحصول على معلومات إضافية
          final info = await getBackupInfo(filename);

          backups.add(
            BackupInfo(
              filename: filename,
              createdAt: createdAt,
              size: size,
              type: info?['type'] ?? 'unknown',
              description: info?['description'],
              createdBy: info?['created_by'],
            ),
          );
        } catch (e) {
          debugPrint('Error reading backup info for ${file.path}: $e');
        }
      }

      // Sort by creation date (newest first)
      backups.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      return backups;
    } catch (e) {
      debugPrint('Error listing backups: $e');
      return [];
    }
  }

  /// Delete an encrypted backup file
  /// حذف ملف نسخ احتياطي مشفر
  Future<void> deleteBackup(User? user, String filename) async {
    PermissionValidator.requirePermission(user, Permission.deleteBackup, 'حذف نسخة احتياطية');
    if (kIsWeb) {
      throw Exception('Backup deletion not supported on web platform');
    }
    try {
      final backupDirectory = await _getBackupDirectory();
      final backupPath = path.join(backupDirectory.path, filename);
      final file = File(backupPath);

      if (await file.exists()) {
        await file.delete();
        AppLogger.i('🗑️ تم حذف النسخة الاحتياطية: $filename');
      }
    } catch (e) {
      AppLogger.e('Error deleting backup', e);
      rethrow;
    }
  }

  /// Start automatic backup scheduling
  /// بدء جدولة النسخ الاحتياطي التلقائي
  void startAutoBackup({Duration interval = const Duration(hours: 24)}) {
    stopAutoBackup(); // إيقاف أي timer موجود

    _autoBackupTimer = Timer.periodic(interval, (_) async {
      try {
        AppLogger.i('⏰ بدء النسخ الاحتياطي التلقائي...');
        await createBackup(
          null,
          type: 'auto',
          description: 'نسخة احتياطية تلقائية مجدولة',
        );
        AppLogger.i('✅ اكتمل النسخ الاحتياطي التلقائي');
      } catch (e) {
        AppLogger.e('❌ فشل النسخ الاحتياطي التلقائي', e);
      }
    });

    AppLogger.i(
      '✅ تم تفعيل النسخ الاحتياطي التلقائي (كل ${interval.inHours} ساعة)',
    );
  }

  /// Stop automatic backup scheduling
  /// إيقاف جدولة النسخ الاحتياطي التلقائي
  void stopAutoBackup() {
    _autoBackupTimer?.cancel();
    _autoBackupTimer = null;
    AppLogger.i('⏹️ تم إيقاف النسخ الاحتياطي التلقائي');
  }

  /// Force immediate backup
  /// إنشاء نسخة احتياطية فورية
  Future<BackupInfo> forceBackup({String? description}) async {
    try {
      AppLogger.i('⏰ إنشاء نسخة احتياطية فورية...');
      final backup = await createBackup(
        null,
        type: 'manual',
        description: description ?? 'نسخة احتياطية فورية',
      );
      AppLogger.i('✅ اكتملت النسخة الاحتياطية الفورية');
      return backup;
    } catch (e) {
      AppLogger.e('❌ فشلت النسخة الاحتياطية الفورية', e);
      rethrow;
    }
  }

  /// Get backup directory
  /// الحصول على مجلد النسخ الاحتياطية
  Future<Directory> _getBackupDirectory() async {
    if (kIsWeb) {
      throw Exception('File system operations not supported on web platform');
    }
    final appDir = await getApplicationDocumentsDirectory();
    final backupDir = Directory(path.join(appDir.path, _backupDir));

    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }

    return backupDir;
  }

  // Private methods

  Future<Map<String, dynamic>> _getAllTablesData() async {
    final tablesData = <String, dynamic>{};

    // Get data from each table
    final tables = [
      'products',
      'customers',
      'suppliers',
      'invoices',
      'invoice_items',
      'expenses',
      'days',
      'purchases',
      'purchase_items',
      'credit_payments',
      'enhanced_suppliers',
      'enhanced_purchases',
      'enhanced_purchase_items',
      'supplier_payments',
      'purchase_budgets',
      'budget_categories',
      'budget_transactions',
      'budget_alerts',
      'ledger_transactions',
    ];

    for (final tableName in tables) {
      try {
        final result = await _db.customSelect('SELECT * FROM $tableName').get();
        tablesData[tableName] = result.map((row) => row.data).toList();
      } catch (e) {
        debugPrint('Error getting data from table $tableName: $e');
        tablesData[tableName] = [];
      }
    }

    return tablesData;
  }

  bool _validateBackupFormat(Map<String, dynamic> backup) {
    return backup.containsKey('version') &&
        backup.containsKey('timestamp') &&
        backup.containsKey('database') &&
        backup.containsKey('tables');
  }

  Future<void> _restoreTablesData(Map<String, dynamic> tablesData) async {
    // Define table order to respect foreign key constraints
    final tableOrder = [
      'customers',
      'suppliers',
      'products',
      'categories',
      'days',
      'invoices',
      'invoice_items',
      'purchases',
      'purchase_items',
      'credit_payments',
      'expenses',
      'ledger_transactions',
      'enhanced_suppliers',
      'enhanced_purchases',
      'enhanced_purchase_items',
      'supplier_payments',
      'purchase_budgets',
      'budget_categories',
      'budget_transactions',
      'budget_alerts',
    ];

    for (final tableName in tableOrder) {
      if (tablesData.containsKey(tableName)) {
        await _restoreTable(tableName, tablesData[tableName] as List);
      }
    }
  }

  Future<void> _restoreTable(String tableName, List<dynamic> data) async {
    if (data.isEmpty) return;

    try {
      // Clear existing data
      await _db.customUpdate('DELETE FROM $tableName');

      // Insert new data
      for (final row in data as List<Map<String, dynamic>>) {
        final columns = row.keys.join(', ');
        final placeholders = List.filled(row.values.length, '?').join(', ');
        final values = row.values.toList();

        await _db.customUpdate(
          'INSERT INTO $tableName ($columns) VALUES ($placeholders)',
          variables: values.map((v) => Variable(v)).toList(),
        );
      }

      debugPrint('Restored $tableName with ${data.length} records');
    } catch (e) {
      debugPrint('Error restoring table $tableName: $e');
      rethrow;
    }
  }

  /// Clean old backups (keep only last _maxBackups)
  /// تنظيف النسخ القديمة (الاحتفاظ بآخر _maxBackups نسخ فقط)
  Future<void> _cleanOldBackups() async {
    try {
      final backups = await listBackups();

      if (backups.length <= _maxBackups) return;

      // حذف النسخ الزائدة
      for (var i = _maxBackups; i < backups.length; i++) {
        await deleteBackup(null, backups[i].filename);
      }

      AppLogger.i(
        '🧹 تم تنظيف ${backups.length - _maxBackups} نسخة احتياطية قديمة',
      );
    } catch (e) {
      AppLogger.e('Error cleaning old backups', e);
    }
  }

  /// Encrypt data using AES
  /// تشفير البيانات باستخدام AES
  List<int> _encryptData(List<int> data) {
    final keyBytes = deriveAesKey(_encryptionKey);
    final key = encrypt_pkg.Key(keyBytes);
    final iv = encrypt_pkg.IV.fromLength(16);
    final encrypter = encrypt_pkg.Encrypter(
      encrypt_pkg.AES(key, mode: encrypt_pkg.AESMode.cbc),
    );

    final encrypted = encrypter.encryptBytes(data, iv: iv);
    return [...iv.bytes, ...encrypted.bytes]; // Include IV in the result
  }

  /// Decrypt data using AES
  /// فك تشفير البيانات باستخدام AES
  List<int> _decryptData(List<int> encryptedData) {
    if (encryptedData.length < 16) {
      throw Exception('Encrypted data too short');
    }

    final keyBytes = deriveAesKey(_encryptionKey);
    final key = encrypt_pkg.Key(keyBytes);
    final iv = encrypt_pkg.IV.fromLength(16);
    final encrypter = encrypt_pkg.Encrypter(
      encrypt_pkg.AES(key, mode: encrypt_pkg.AESMode.cbc),
    );

    final encrypted = encrypt_pkg.Encrypted(
      Uint8List.fromList(encryptedData.sublist(16)),
    );
    return encrypter.decryptBytes(encrypted, iv: iv);
  }

  /// Format timestamp for filename
  /// تنسيق الطابع الزمني لاسم الملف
  String _formatTimestamp(DateTime dt) {
    return DateFormat('yyyyMMdd_HHmmss').format(dt);
  }

  /// Parse timestamp from filename
  /// تحليل الطابع الزمني من اسم الملف
  DateTime _parseTimestamp(String timestamp) {
    return DateFormat('yyyyMMdd_HHmmss').parse(timestamp);
  }

  /// Format bytes to human readable format
  /// تنسيق البايتات إلى صيغة مقروءة للإنسان
  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(2)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  void dispose() {
    stopAutoBackup();
  }
}

/// Backup information model
/// نموذج معلومات النسخة الاحتياطية
class BackupInfo {
  final String filename;
  final DateTime createdAt;
  final int size;
  final String type; // auto, manual
  final String? description;
  final int? createdBy;

  BackupInfo({
    required this.filename,
    required this.createdAt,
    required this.size,
    required this.type,
    this.description,
    this.createdBy,
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
}
