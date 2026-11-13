import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pos_offline_desktop/core/services/settings_service.dart';
import 'package:pos_offline_desktop/services/enhanced_backup_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Directory cloudSyncDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('madar_cloud_sync_test_');
    cloudSyncDir = Directory(p.join(tempDir.path, 'GoogleDrive_My_Drive'));
    await cloudSyncDir.create(recursive: true);
  });

  tearDown(() async {
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  test('SettingsService persists and retrieves cloud sync folder path and enabled status', () async {
    expect(await SettingsService.getCloudSyncFolderPath(), isNull);
    expect(await SettingsService.isCloudFolderSyncEnabled(), isTrue);

    await SettingsService.setCloudSyncFolderPath(cloudSyncDir.path);
    expect(await SettingsService.getCloudSyncFolderPath(), equals(cloudSyncDir.path));

    await SettingsService.setCloudFolderSyncEnabled(false);
    expect(await SettingsService.isCloudFolderSyncEnabled(), isFalse);

    await SettingsService.setCloudFolderSyncEnabled(true);
    expect(await SettingsService.isCloudFolderSyncEnabled(), isTrue);

    await SettingsService.setCloudSyncFolderPath(null);
    expect(await SettingsService.getCloudSyncFolderPath(), isNull);
  });

  test('EnhancedBackupService.syncBackupToCloudFolder copies backup file to cloud directory', () async {
    final service = EnhancedBackupService();
    await SettingsService.setCloudSyncFolderPath(cloudSyncDir.path);
    await SettingsService.setCloudFolderSyncEnabled(true);

    // Create a mock backup file
    final mockBackupFile = File(p.join(tempDir.path, 'backup_20261024_test.posbackup'));
    await mockBackupFile.writeAsString('encrypted_backup_payload_bytes_for_testing');

    final copiedPath = await service.syncBackupToCloudFolder(mockBackupFile.path);
    expect(copiedPath, isNotNull);
    expect(File(copiedPath!).existsSync(), isTrue);
    expect(p.dirname(copiedPath), equals(cloudSyncDir.path));
    expect(p.basename(copiedPath), equals('backup_20261024_test.posbackup'));

    // Check listing
    final cloudList = await service.listCloudFolderBackups();
    expect(cloudList.length, equals(1));
    expect(cloudList.first.filename, equals('backup_20261024_test.posbackup'));
  });

  test('EnhancedBackupService.syncBackupToCloudFolder respects disabled setting', () async {
    final service = EnhancedBackupService();
    await SettingsService.setCloudSyncFolderPath(cloudSyncDir.path);
    await SettingsService.setCloudFolderSyncEnabled(false);

    final mockBackupFile = File(p.join(tempDir.path, 'backup_disabled.posbackup'));
    await mockBackupFile.writeAsString('payload');

    final copiedPath = await service.syncBackupToCloudFolder(mockBackupFile.path);
    expect(copiedPath, isNull);
    expect(File(p.join(cloudSyncDir.path, 'backup_disabled.posbackup')).existsSync(), isFalse);
  });
}
