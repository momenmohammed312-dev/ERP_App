import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';

class LocalBackupService {
  static const String _backupDir = 'backups';
  static const int _maxBackups = 7; // Keep last 7 days
  static const int _transactionThreshold = 100; // Backup after 100 transactions

  /// Create automatic backup
  static Future<String> createAutoBackup({
    bool isTransactionBased = false,
  }) async {
    try {
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final backupName = isTransactionBased
          ? 'auto_transaction_${_transactionThreshold}_$timestamp'
          : 'auto_daily_$timestamp';

      return await createBackup(backupName);
    } catch (e) {
      print('Auto backup failed: $e');
      rethrow;
    }
  }

  /// Create manual backup
  static Future<String> createManualBackup(String customName) async {
    try {
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final backupName = 'manual_${customName}_$timestamp';

      return await createBackup(backupName);
    } catch (e) {
      print('Manual backup failed: $e');
      rethrow;
    }
  }

  /// Create backup
  static Future<String> createBackup(String backupName) async {
    if (kIsWeb) {
      throw Exception('Backup operations not supported on web platform');
    }
    try {
      // Get backup directory
      final backupDir = await _getBackupDirectory();

      // Get database file
      final dbFile = await _getDatabaseFile();
      if (!await dbFile.exists()) {
        throw Exception('Database file not found');
      }

      // Create backup filename
      final backupFilename = '$backupName.zip';
      final backupPath = path.join(backupDir.path, backupFilename);

      // Read database file
      final dbBytes = await dbFile.readAsBytes();

      // Create archive
      final archive = Archive();

      // Add database file to archive
      final dbFileData = ArchiveFile(
        'pos_database.db',
        dbBytes.length,
        dbBytes,
      );
      archive.addFile(dbFileData);

      // Add metadata file
      final metadata = {
        'created': DateTime.now().toIso8601String(),
        'version': '2.0.0',
        'type': backupName.startsWith('manual') ? 'manual' : 'auto',
        'database_size': dbBytes.length,
        'checksum': sha256.convert(dbBytes).toString(),
      };

      final metadataBytes = utf8.encode(jsonEncode(metadata));
      final metadataFile = ArchiveFile(
        'metadata.json',
        metadataBytes.length,
        metadataBytes,
      );
      archive.addFile(metadataFile);

      // Compress and save
      final zipData = ZipEncoder().encode(archive);
      if (zipData == null) {
        throw Exception('Failed to create zip archive');
      }

      final backupFile = File(backupPath);
      await backupFile.writeAsBytes(zipData);

      // Clean old backups
      await _cleanOldBackups();

      print('✅ Backup created: $backupFilename');
      return backupPath;
    } catch (e) {
      print('Backup creation failed: $e');
      rethrow;
    }
  }

  /// Restore from backup
  static Future<bool> restoreFromBackup(String backupPath) async {
    if (kIsWeb) {
      throw Exception('Backup restore not supported on web platform');
    }
    try {
      final backupFile = File(backupPath);
      if (!await backupFile.exists()) {
        throw Exception('Backup file not found');
      }

      // Read backup file
      final backupBytes = await backupFile.readAsBytes();

      // Extract archive
      final archive = ZipDecoder().decodeBytes(backupBytes);

      // Find database file
      ArchiveFile? dbFile;
      ArchiveFile? metadataFile;

      for (final file in archive.files) {
        if (file.name == 'pos_database.db') {
          dbFile = file;
        } else if (file.name == 'metadata.json') {
          metadataFile = file;
        }
      }

      if (dbFile == null) {
        throw Exception('Database file not found in backup');
      }

      // Verify checksum if metadata exists
      if (metadataFile != null) {
        final metadataJson = utf8.decode(metadataFile.content as List<int>);
        final metadata = jsonDecode(metadataJson) as Map<String, dynamic>;

        final expectedChecksum = metadata['checksum'] as String?;
        if (expectedChecksum != null) {
          final actualChecksum = sha256
              .convert(dbFile.content as List<int>)
              .toString();
          if (actualChecksum != expectedChecksum) {
            throw Exception('Backup checksum verification failed');
          }
        }

        print('Restoring from backup created: ${metadata['created']}');
      }

      // Get current database path
      final currentDbFile = await _getDatabaseFile();

      // Create backup of current database before restore
      if (await currentDbFile.exists()) {
        final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
        final preRestoreBackup = path.join(
          currentDbFile.parent.path,
          'pre_restore_$timestamp.db',
        );
        await currentDbFile.copy(preRestoreBackup);
        print('Current database backed up to: $preRestoreBackup');
      }

      // Restore database
      await currentDbFile.writeAsBytes(dbFile.content as List<int>);

      print('✅ Database restored successfully');
      return true;
    } catch (e) {
      print('Restore failed: $e');
      return false;
    }
  }

  /// Get list of available backups
  static Future<List<BackupInfo>> getAvailableBackups() async {
    if (kIsWeb) {
      return []; // No backups available on web
    }
    try {
      final backupDir = await _getBackupDirectory();
      final backupFiles = await backupDir
          .list()
          .where((entity) => entity is File && entity.path.endsWith('.zip'))
          .cast<File>()
          .toList();

      final backups = <BackupInfo>[];

      for (final file in backupFiles) {
        try {
          final info = await _getBackupInfo(file);
          if (info != null) {
            backups.add(info);
          }
        } catch (e) {
          print('Error reading backup ${file.path}: $e');
        }
      }

      // Sort by creation date (newest first)
      backups.sort((a, b) => b.created.compareTo(a.created));
      return backups;
    } catch (e) {
      print('Error getting backup list: $e');
      return [];
    }
  }

  /// Delete backup
  static Future<bool> deleteBackup(String backupPath) async {
    if (kIsWeb) {
      throw Exception('Backup deletion not supported on web platform');
    }
    try {
      final file = File(backupPath);
      if (await file.exists()) {
        await file.delete();
        print('Backup deleted: $backupPath');
        return true;
      }
      return false;
    } catch (e) {
      print('Error deleting backup: $e');
      return false;
    }
  }

  /// Get backup directory
  static Future<Directory> _getBackupDirectory() async {
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

  /// Get database file
  static Future<File> _getDatabaseFile() async {
    if (kIsWeb) {
      throw Exception('File system operations not supported on web platform');
    }
    final appDir = await getApplicationDocumentsDirectory();
    final dbDir = Directory(
      path.join(appDir.path, 'pos_offline_desktop_database'),
    );
    return File(path.join(dbDir.path, 'pos_system_encrypted.db'));
  }

  /// Clean old backups (keep only last _maxBackups)
  static Future<void> _cleanOldBackups() async {
    try {
      final backups = await getAvailableBackups();

      if (backups.length > _maxBackups) {
        // Keep only the newest _maxBackups
        final backupsToDelete = backups.skip(_maxBackups);

        for (final backup in backupsToDelete) {
          await deleteBackup(backup.filePath);
        }
      }
    } catch (e) {
      print('Error cleaning old backups: $e');
    }
  }

  /// Get backup info from file
  static Future<BackupInfo?> _getBackupInfo(File backupFile) async {
    try {
      final backupBytes = await backupFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(backupBytes);

      // Find metadata file
      ArchiveFile? metadataFile;
      for (final file in archive.files) {
        if (file.name == 'metadata.json') {
          metadataFile = file;
          break;
        }
      }

      if (metadataFile == null) {
        // Fallback: use file modification time
        final stat = await backupFile.stat();
        return BackupInfo(
          filePath: backupFile.path,
          fileName: path.basename(backupFile.path),
          created: stat.modified,
          size: stat.size,
          type: 'unknown',
          version: 'unknown',
        );
      }

      final metadataJson = utf8.decode(metadataFile.content as List<int>);
      final metadata = jsonDecode(metadataJson) as Map<String, dynamic>;

      return BackupInfo(
        filePath: backupFile.path,
        fileName: path.basename(backupFile.path),
        created: DateTime.parse(metadata['created'] as String),
        size: await backupFile.length(),
        type: metadata['type'] as String? ?? 'unknown',
        version: metadata['version'] as String? ?? 'unknown',
      );
    } catch (e) {
      print('Error parsing backup info: $e');
      return null;
    }
  }
}

/// Backup information model
class BackupInfo {
  final String filePath;
  final String fileName;
  final DateTime created;
  final int size;
  final String type;
  final String version;

  BackupInfo({
    required this.filePath,
    required this.fileName,
    required this.created,
    required this.size,
    required this.type,
    required this.version,
  });

  String get sizeString {
    final sizeInMB = size / (1024 * 1024);
    return '${sizeInMB.toStringAsFixed(1)} MB';
  }

  String get createdString {
    return created.toIso8601String().split('T')[0];
  }
}
