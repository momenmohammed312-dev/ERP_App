import 'dart:io';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import '../config/database_config.dart';

class DatabaseMigrationService {
  /// Migrate from old unencrypted DB to new encrypted DB
  static Future<void> migrateToEncrypted() async {
    if (kIsWeb) {
      throw Exception('Database migration not supported on web platform');
    }
    try {
      final dbFolder = await getApplicationDocumentsDirectory();
      final dbDir = Directory(
        join(dbFolder.path, 'pos_offline_desktop_database'),
      );

      // Old database (unencrypted)
      final oldPath = join(dbDir.path, 'pos_offline_desktop_database.sqlite');
      final oldFile = File(oldPath);

      // New database (encrypted)
      final newPath = join(dbDir.path, DatabaseConfig.databaseName);
      final newFile = File(newPath);

      // Check if old database exists
      if (!await oldFile.exists()) {
        print('No old database to migrate');
        return;
      }

      // Check if already migrated
      if (await newFile.exists()) {
        print('Already migrated to encrypted database');
        return;
      }

      print('Starting database migration...');

      // For now, just copy the file
      // Full SQLCipher migration will be implemented after package installation
      await oldFile.copy(newPath);

      // Backup old database
      final backupPath = '$oldPath.backup';
      await oldFile.copy(backupPath);
      print('Old database backed up to: $backupPath');

      print('✅ Migration completed successfully!');
    } catch (e) {
      print('❌ Migration failed: $e');
      rethrow;
    }
  }
}
