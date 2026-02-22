import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'lib/services/user_backup_service.dart';

void main() {
  // Initialize Flutter binding for tests
  TestWidgetsFlutterBinding.ensureInitialized();

  group('User Backup Service Integration Test', () {
    late BackupService backupService;

    setUpAll(() async {
      backupService = BackupService();
      // Ensure backup directory exists
      final backupDir = Directory('data/backups');
      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }
    });

    test('BackupService should be singleton', () {
      final service1 = BackupService();
      final service2 = BackupService();
      expect(identical(service1, service2), true);
    });

    test('Should list backups successfully', () async {
      try {
        final backups = await backupService.listBackups();
        expect(backups, isA<List<BackupInfo>>());
        print('✅ Successfully listed ${backups.length} backups');
      } catch (e) {
        print('❌ Failed to list backups: $e');
        rethrow;
      }
    });

    test('Should create manual backup successfully', () async {
      try {
        await backupService.createBackup(
          type: 'manual',
          description: 'Test backup from integration test',
        );

        final backups = await backupService.listBackups();
        expect(backups.isNotEmpty, true);
        print('✅ Successfully created manual backup');
      } catch (e) {
        print('❌ Failed to create backup: $e');
        rethrow;
      }
    });

    test('BackupInfo should have correct properties', () async {
      final backups = await backupService.listBackups();
      if (backups.isNotEmpty) {
        final backup = backups.first;
        expect(backup.filename, isA<String>());
        expect(backup.createdAt, isA<DateTime>());
        expect(backup.size, isA<int>());
        expect(backup.type, isIn(['auto', 'manual']));
        expect(backup.formattedSize, isA<String>());
        expect(backup.formattedDate, isA<String>());

        print('✅ BackupInfo properties validated:');
        print('   - Filename: ${backup.filename}');
        print('   - Size: ${backup.formattedSize}');
        print('   - Date: ${backup.formattedDate}');
        print('   - Type: ${backup.type}');
      }
    });

    test('Should handle backup statistics', () async {
      try {
        final backups = await backupService.listBackups();

        // Calculate statistics manually
        final totalBackups = backups.length;
        final autoBackups = backups.where((b) => b.type == 'auto').length;
        final manualBackups = backups.where((b) => b.type == 'manual').length;
        final totalSize = backups.fold<int>(0, (sum, b) => sum + b.size);

        print('✅ Backup Statistics:');
        print('   - Total Backups: $totalBackups');
        print('   - Auto Backups: $autoBackups');
        print('   - Manual Backups: $manualBackups');
        print(
          '   - Total Size: ${(totalSize / (1024 * 1024)).toStringAsFixed(2)} MB',
        );

        expect(totalBackups, greaterThanOrEqualTo(0));
        expect(autoBackups, greaterThanOrEqualTo(0));
        expect(manualBackups, greaterThanOrEqualTo(0));
      } catch (e) {
        print('❌ Failed to calculate statistics: $e');
        rethrow;
      }
    });

    test('Should handle backup cleanup', () async {
      try {
        // This test verifies the cleanup mechanism works
        // The service should keep only the last 7 backups
        await backupService.createBackup(
          type: 'manual',
          description: 'Test backup for cleanup',
        );

        final backups = await backupService.listBackups();
        expect(backups.length, lessThanOrEqualTo(7));
        print('✅ Backup cleanup working correctly (max 7 backups)');
      } catch (e) {
        print('❌ Failed cleanup test: $e');
        rethrow;
      }
    });
  });

  group('AutoBackupService Test', () {
    test('Should start and stop without errors', () async {
      try {
        AutoBackupService.start();
        print('✅ AutoBackupService started successfully');

        AutoBackupService.stop();
        print('✅ AutoBackupService stopped successfully');
      } catch (e) {
        print('❌ AutoBackupService error: $e');
        rethrow;
      }
    });

    test('Should create immediate backup', () async {
      try {
        await AutoBackupService.createNow();
        print('✅ Immediate backup created successfully');
      } catch (e) {
        print('❌ Failed to create immediate backup: $e');
        rethrow;
      }
    });
  });
}
