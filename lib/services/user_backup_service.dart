// ════════════════════════════════════════════════════════════════════════
// نظام النسخ الاحتياطي والاستعادة - POS SaaS Offline (User Version)
// ════════════════════════════════════════════════════════════════════════

import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive_io.dart';
import 'package:encrypt/encrypt.dart' as encrypt_pkg;
import 'package:intl/intl.dart';

// ════════════════════════════════════════════════════════════════════════
// 1. نموذج النسخة الاحتياطية
// ════════════════════════════════════════════════════════════════════════

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

// ════════════════════════════════════════════════════════════════════════
// 2. خدمة النسخ الاحتياطي
// ════════════════════════════════════════════════════════════════════════

class BackupService {
  static const String _backupDir = 'data/backups';
  static const String _encryptionKey = 'YOUR-32-CHAR-BACKUP-KEY-HERE!!!';
  static const int _maxBackups = 7; // الاحتفاظ بآخر 7 نسخ

  // Singleton
  static final BackupService _instance = BackupService._internal();
  factory BackupService() => _instance;
  BackupService._internal();

  // ════════════════════════════════════════════════════════════════════
  // إنشاء نسخة احتياطية
  // ════════════════════════════════════════════════════════════════════

  Future<BackupInfo> createBackup({
    String type = 'manual',
    String? description,
    int? createdBy,
  }) async {
    try {
      print('📦 بدء النسخ الاحتياطي...');

      // 1. إنشاء مجلد النسخ الاحتياطية
      final backupDirectory = Directory(_backupDir);
      if (!await backupDirectory.exists()) {
        await backupDirectory.create(recursive: true);
      }

      // 2. توليد اسم الملف
      final timestamp = DateTime.now();
      final filename = 'backup_${_formatTimestamp(timestamp)}.posbackup';
      final backupPath = join(_backupDir, filename);

      // 3. إغلاق قاعدة البيانات مؤقتاً
      final dbPath = await _getDatabasePath();
      final dbFile = File(dbPath);

      if (!await dbFile.exists()) {
        throw Exception('قاعدة البيانات غير موجودة');
      }

      // 4. إنشاء ملف مؤقت للنسخة
      final tempDir = Directory('$_backupDir/temp');
      if (!await tempDir.exists()) {
        await tempDir.create(recursive: true);
      }

      // 5. نسخ قاعدة البيانات
      final tempDbPath = join(tempDir.path, 'database.db');
      await dbFile.copy(tempDbPath);

      // 6. نسخ ملفات الإعدادات (إن وجدت)
      final configFile = File('data/config.json');
      String? tempConfigPath;
      if (await configFile.exists()) {
        tempConfigPath = join(tempDir.path, 'config.json');
        await configFile.copy(tempConfigPath);
      }

      // 7. إنشاء ملف المعلومات
      final infoPath = join(tempDir.path, 'backup_info.json');
      final info = {
        'created_at': timestamp.toIso8601String(),
        'type': type,
        'description': description,
        'created_by': createdBy,
        'version': '1.0',
      };
      await File(infoPath).writeAsString(jsonEncode(info));

      // 8. ضغط الملفات
      print('📦 ضغط الملفات...');
      final encoder = ZipFileEncoder();
      final tempZipPath = join(_backupDir, 'temp_backup.zip');
      encoder.create(tempZipPath);
      encoder.addDirectory(tempDir);
      encoder.close();

      // 9. تشفير الملف
      print('🔒 تشفير النسخة الاحتياطية...');
      final zipFile = File(tempZipPath);
      final zipBytes = await zipFile.readAsBytes();
      final encryptedBytes = _encryptData(zipBytes);

      // 10. حفظ النسخة النهائية
      await File(backupPath).writeAsBytes(encryptedBytes);

      // 11. تنظيف الملفات المؤقتة
      await tempDir.delete(recursive: true);
      await zipFile.delete();

      // 12. الحصول على حجم الملف
      final backupFile = File(backupPath);
      final size = await backupFile.length();

      print('✅ تم إنشاء النسخة الاحتياطية بنجاح');
      print('📁 الموقع: $backupPath');
      print('📊 الحجم: $_formatBytes(size)');

      // 13. تنظيف النسخ القديمة
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
      print('❌ خطأ في النسخ الاحتياطي: $e');
      rethrow;
    }
  }

  // ════════════════════════════════════════════════════════════════════
  // استعادة من نسخة احتياطية
  // ════════════════════════════════════════════════════════════════════

  Future<void> restoreBackup(String filename) async {
    try {
      print('📥 بدء الاستعادة من: $filename');

      final backupPath = join(_backupDir, filename);
      final backupFile = File(backupPath);

      if (!await backupFile.exists()) {
        throw Exception('ملف النسخة الاحتياطية غير موجود');
      }

      // 1. فك تشفير الملف
      print('🔓 فك تشفير النسخة الاحتياطية...');
      final encryptedBytes = await backupFile.readAsBytes();
      final decryptedBytes = _decryptData(encryptedBytes);

      // 2. حفظ ZIP مؤقت
      final tempZipPath = join(_backupDir, 'temp_restore.zip');
      await File(tempZipPath).writeAsBytes(decryptedBytes);

      // 3. فك الضغط
      print('📦 فك ضغط الملفات...');
      final tempDir = Directory('$_backupDir/restore_temp');
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
      await tempDir.create(recursive: true);

      final zipDecoder = ZipDecoder();
      final archive = zipDecoder.decodeBytes(decryptedBytes);

      for (final file in archive) {
        final filename = file.name;
        if (file.isFile) {
          final data = file.content as List<int>;
          final filePath = join(tempDir.path, filename);
          await File(filePath).create(recursive: true);
          await File(filePath).writeAsBytes(data);
        }
      }

      // 4. استعادة قاعدة البيانات
      print('💾 استعادة قاعدة البيانات...');
      final dbPath = await _getDatabasePath();
      final targetDbPath = dbPath;
      final sourceDbPath = join(tempDir.path, 'database.db');

      if (await File(sourceDbPath).exists()) {
        // إنشاء نسخة احتياطية من القاعدة الحالية
        if (await File(targetDbPath).exists()) {
          final backupCurrentPath = '$targetDbPath.before_restore';
          await File(targetDbPath).copy(backupCurrentPath);
        }

        // استعادة القاعدة الجديدة
        await File(sourceDbPath).copy(targetDbPath);
      }

      // 5. استعادة الإعدادات
      final configPath = join(tempDir.path, 'config.json');
      if (await File(configPath).exists()) {
        await File(configPath).copy('data/config.json');
      }

      // 6. تنظيف
      await tempDir.delete(recursive: true);
      await File(tempZipPath).delete();

      print('✅ تمت الاستعادة بنجاح');
    } catch (e) {
      print('❌ خطأ في الاستعادة: $e');
      rethrow;
    }
  }

  // ════════════════════════════════════════════════════════════════════
  // الحصول على قائمة النسخ الاحتياطية
  // ════════════════════════════════════════════════════════════════════

  Future<List<BackupInfo>> listBackups() async {
    final backupDirectory = Directory(_backupDir);
    if (!await backupDirectory.exists()) {
      return [];
    }

    final backups = <BackupInfo>[];

    await for (final entity in backupDirectory.list()) {
      if (entity is File && entity.path.endsWith('.posbackup')) {
        final filename = basename(entity.path);
        final size = await entity.length();

        // محاولة استخراج التاريخ من اسم الملف
        DateTime createdAt;
        try {
          final timestampStr = filename
              .replaceAll('backup_', '')
              .replaceAll('.posbackup', '');
          createdAt = _parseTimestamp(timestampStr);
        } catch (e) {
          createdAt = (await entity.stat()).modified;
        }

        backups.add(
          BackupInfo(
            filename: filename,
            createdAt: createdAt,
            size: size,
            type: 'unknown',
          ),
        );
      }
    }

    // ترتيب حسب التاريخ (الأحدث أولاً)
    backups.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return backups;
  }

  // ════════════════════════════════════════════════════════════════════
  // حذف نسخة احتياطية
  // ════════════════════════════════════════════════════════════════════

  Future<void> deleteBackup(String filename) async {
    final backupPath = join(_backupDir, filename);
    final file = File(backupPath);

    if (await file.exists()) {
      await file.delete();
      print('🗑️ تم حذف النسخة الاحتياطية: $filename');
    }
  }

  // ════════════════════════════════════════════════════════════════════
  // تنظيف النسخ القديمة
  // ════════════════════════════════════════════════════════════════════

  Future<void> _cleanOldBackups() async {
    final backups = await listBackups();

    if (backups.length <= _maxBackups) return;

    // حذف النسخ الزائدة
    for (var i = _maxBackups; i < backups.length; i++) {
      await deleteBackup(backups[i].filename);
    }

    print('🧹 تم تنظيف ${backups.length - _maxBackups} نسخة احتياطية قديمة');
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
    return encrypted.bytes;
  }

  List<int> _decryptData(List<int> encryptedData) {
    final key = encrypt_pkg.Key.fromUtf8(_encryptionKey);
    final iv = encrypt_pkg.IV.fromLength(16);
    final encrypter = encrypt_pkg.Encrypter(
      encrypt_pkg.AES(key, mode: encrypt_pkg.AESMode.cbc),
    );

    final encrypted = encrypt_pkg.Encrypted(Uint8List.fromList(encryptedData));
    return encrypter.decryptBytes(encrypted, iv: iv);
  }

  // ════════════════════════════════════════════════════════════════════
  // دوال مساعدة
  // ════════════════════════════════════════════════════════════════════

  Future<String> _getDatabasePath() async {
    final appDir = await getApplicationDocumentsDirectory();
    return join(
      appDir.path,
      'pos_offline_desktop_database',
      'pos_system_encrypted.db',
    );
  }

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
}

// ════════════════════════════════════════════════════════════════════════
// 3. خدمة النسخ الاحتياطي التلقائي
// ════════════════════════════════════════════════════════════════════════

class AutoBackupService {
  static Timer? _timer;
  static const Duration _interval = Duration(hours: 24); // يومياً

  /// بدء النسخ الاحتياطي التلقائي
  static void start() {
    stop(); // إيقاف أي timer موجود

    _timer = Timer.periodic(_interval, (_) async {
      try {
        print('⏰ بدء النسخ الاحتياطي التلقائي...');
        await BackupService().createBackup(type: 'auto');
        print('✅ اكتمل النسخ الاحتياطي التلقائي');
      } catch (e) {
        print('❌ فشل النسخ الاحتياطي التلقائي: $e');
      }
    });

    print('✅ تم تفعيل النسخ الاحتياطي التلقائي (كل 24 ساعة)');
  }

  /// إيقاف النسخ الاحتياطي التلقائي
  static void stop() {
    _timer?.cancel();
    _timer = null;
    print('⏹️ تم إيقاف النسخ الاحتياطي التلقائي');
  }

  /// إنشاء نسخة فورية
  static Future<void> createNow() async {
    try {
      print('⏰ إنشاء نسخة احتياطية فورية...');
      await BackupService().createBackup(type: 'auto');
      print('✅ اكتملت النسخة الاحتياطية الفورية');
    } catch (e) {
      print('❌ فشلت النسخة الاحتياطية الفورية: $e');
    }
  }
}
