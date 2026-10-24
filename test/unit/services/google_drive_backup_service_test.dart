import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:pos_offline_desktop/services/cloud/google_drive_backup_service.dart';
import 'package:pos_offline_desktop/services/cloud/google_drive_auth_service.dart';
import 'package:pos_offline_desktop/services/cloud/cloud_backup_encryption_service.dart';
import 'package:pos_offline_desktop/services/enhanced_backup_service.dart';
import 'package:path/path.dart' as p;

class MockSecureStorage extends FlutterSecureStorage {
  final Map<String, String> _data = {};

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      _data.remove(key);
    } else {
      _data[key] = value;
    }
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    return _data[key];
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _data.remove(key);
  }
}

class FakeFilesResource implements drive.FilesResource {
  final List<drive.File> files = [];
  final Map<String, Uint8List> fileContents = {};
  int deleteCalls = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final member = invocation.memberName;
    if (member == #list) {
      final q = invocation.namedArguments[const Symbol('q')] as String?;
      final results = <drive.File>[];
      for (final f in files) {
        if (q != null && q.contains("mimeType = 'application/vnd.google-apps.folder'")) {
          if (f.mimeType == 'application/vnd.google-apps.folder') {
            results.add(f);
          }
        } else if (q != null && q.contains('appProperties has')) {
          if (f.appProperties != null && f.appProperties!['app'] == 'madar_erp') {
            results.add(f);
          }
        } else {
          results.add(f);
        }
      }
      return Future.value(drive.FileList()..files = results);
    } else if (member == #create) {
      final request = invocation.positionalArguments[0] as drive.File;
      final uploadMedia = invocation.namedArguments[const Symbol('uploadMedia')] as drive.Media?;
      final newId = 'file_${DateTime.now().millisecondsSinceEpoch}_${files.length}';
      final newFile = drive.File()
        ..id = newId
        ..name = request.name
        ..parents = request.parents
        ..mimeType = request.mimeType
        ..description = request.description
        ..appProperties = request.appProperties
        ..size = uploadMedia != null ? uploadMedia.length.toString() : '1024'
        ..createdTime = DateTime.now();

      if (uploadMedia != null) {
        return uploadMedia.stream.fold<List<int>>([], (a, b) => a..addAll(b)).then((bytes) {
          fileContents[newId] = Uint8List.fromList(bytes);
          files.add(newFile);
          return newFile;
        });
      }

      files.add(newFile);
      return Future.value(newFile);
    } else if (member == #get) {
      final fileId = invocation.positionalArguments[0] as String;
      final downloadOptions = invocation.namedArguments[const Symbol('downloadOptions')] as drive.DownloadOptions?;
      final file = files.firstWhere((f) => f.id == fileId);
      if (downloadOptions == drive.DownloadOptions.fullMedia) {
        final content = fileContents[fileId] ?? Uint8List.fromList('MDRC\x01mockEncryptedData'.codeUnits);
        return Future.value(drive.Media(Stream.value(content), content.length));
      }
      return Future.value(file);
    } else if (member == #delete) {
      final fileId = invocation.positionalArguments[0] as String;
      deleteCalls++;
      files.removeWhere((f) => f.id == fileId);
      fileContents.remove(fileId);
      return Future.value();
    }
    return super.noSuchMethod(invocation);
  }
}

class FakeDriveApi implements drive.DriveApi {
  final FakeFilesResource _files;
  FakeDriveApi(this._files);

  @override
  drive.FilesResource get files => _files;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GoogleDriveBackupService backupService;
  late FakeFilesResource fakeFiles;
  late Directory tempDir;
  late Directory localBackupsDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('gdrive_test_');
    localBackupsDir = Directory(p.join(tempDir.path, 'local_backups'))..createSync(recursive: true);

    fakeFiles = FakeFilesResource();
    final fakeApi = FakeDriveApi(fakeFiles);

    final mockStorage = MockSecureStorage();
    final encryptionService = CloudBackupEncryptionService(secureStorage: mockStorage);

    backupService = GoogleDriveBackupService(
      authService: GoogleDriveAuthService(storage: mockStorage),
      encryptionService: encryptionService,
      localBackupService: EnhancedBackupService(),
    );
    backupService.setMockDriveApi(fakeApi);
    GoogleDriveBackupService.customTempDirectory = tempDir;
    GoogleDriveBackupService.customBackupDirectory = localBackupsDir;
    EnhancedBackupService.customBackupDirectory = localBackupsDir;
  });

  tearDown(() async {
    GoogleDriveBackupService.customTempDirectory = null;
    GoogleDriveBackupService.customBackupDirectory = null;
    EnhancedBackupService.customBackupDirectory = null;
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('getOrCreateBackupFolder creates folder if missing and reuses it', () async {
    final folderId1 = await backupService.getOrCreateBackupFolder();
    expect(folderId1.isNotEmpty, isTrue);

    // Verify folder was added to fake files
    expect(fakeFiles.files.any((f) => f.id == folderId1 && f.mimeType == 'application/vnd.google-apps.folder'), isTrue);

    // Calling again returns same cached ID
    final folderId2 = await backupService.getOrCreateBackupFolder();
    expect(folderId2, folderId1);
  });

  test('uploadBackup encrypts file and uploads with madar_erp appProperties', () async {
    final dummyLocalDb = File(p.join(tempDir.path, 'test_db.sqlite'));
    await dummyLocalDb.writeAsString('SQLite format 3 dummy header and table data');

    final metadata = await backupService.uploadBackup(
      sourceLocalFile: dummyLocalDb,
      description: 'اختبار رفع نسخة مشفرة',
    );

    expect(metadata.id.isNotEmpty, isTrue);
    expect(metadata.name.contains('MADAR_Cloud_'), isTrue);
    expect(metadata.isEncrypted, isTrue);

    // Verify uploaded file in Drive has appProperties
    final uploaded = fakeFiles.files.firstWhere((f) => f.id == metadata.id);
    expect(uploaded.appProperties?['app'], 'madar_erp');
    expect(uploaded.appProperties?['isCloudBackup'], 'true');
    expect(uploaded.appProperties?['checksum']?.isNotEmpty, isTrue);
  });

  test('listCloudBackups lists only files belonging to MADAR ERP', () async {
    // 1. Add foreign file
    fakeFiles.files.add(
      drive.File()
        ..id = 'foreign_doc_1'
        ..name = 'MyResume.pdf'
        ..appProperties = {'app': 'other_app'}
        ..createdTime = DateTime.now(),
    );

    // 2. Upload MADAR backup
    final dummyDb = File(p.join(tempDir.path, 'test_db2.sqlite'));
    await dummyDb.writeAsString('test database');
    await backupService.uploadBackup(sourceLocalFile: dummyDb);

    final list = await backupService.listCloudBackups();
    expect(list.length, 1);
    expect(list.first.name.startsWith('MADAR_Cloud_'), isTrue);
    expect(list.any((b) => b.id == 'foreign_doc_1'), isFalse);
  });

  test('applyRetentionPolicy rotates oldest backups and preserves at least 1 backup', () async {
    final folderId = await backupService.getOrCreateBackupFolder();

    // Add 7 MADAR backups with different dates
    for (int i = 1; i <= 7; i++) {
      fakeFiles.files.add(
        drive.File()
          ..id = 'cloud_backup_$i'
          ..name = 'MADAR_Cloud_20261021_00000$i.poscloudbackup'
          ..parents = [folderId]
          ..appProperties = {'app': 'madar_erp'}
          ..createdTime = DateTime(2026, 10, 21, 0, 0, i),
      );
    }

    // Apply policy: retain max 5
    final deleted = await backupService.applyRetentionPolicy(maxBackups: 5);
    expect(deleted, 2);
    expect(fakeFiles.deleteCalls, 2);

    // Verify that at least 1 backup is preserved even with maxBackups = 1
    final remainingAfter = await backupService.listCloudBackups();
    expect(remainingAfter.length, 5);

    // Attempting extreme retention with maxBackups = 0 or 1 never leaves 0 backups
    final deletedMore = await backupService.applyRetentionPolicy(maxBackups: 1);
    expect(deletedMore, 4);

    final finalRemaining = await backupService.listCloudBackups();
    expect(finalRemaining.length, 1, reason: 'At least one restorable backup must always be preserved');
  });

  test('cloud retention never deletes local backup files on disk', () async {
    // 1. Place a local backup file on disk
    final localBackupFile = File(p.join(localBackupsDir.path, 'backup_local_keep.posbackup'));
    await localBackupFile.writeAsString('local backup data');
    expect(await localBackupFile.exists(), isTrue);

    // 2. Run cloud retention
    await backupService.applyRetentionPolicy(maxBackups: 1);

    // 3. Local file must remain untouched
    expect(await localBackupFile.exists(), isTrue, reason: 'Local backup files must NEVER be deleted by cloud retention');
  });

  test('end-to-end: upload -> download on replacement device -> decrypt with recovery key', () async {
    // 1. Original device: create synthetic SQLite content
    final originalDbFile = File(p.join(tempDir.path, 'company_original.sqlite'));
    final testSqlitePayload = 'SQLite format 3\x00${'Customer invoice #12345: 5000.00 EGP - MADAR ERP\n' * 20}';
    await originalDbFile.writeAsString(testSqlitePayload);

    // 2. Original device: retrieve recovery key
    final mockStorage = MockSecureStorage();
    final originalEncryptionService = CloudBackupEncryptionService(secureStorage: mockStorage);
    final originalBackupService = GoogleDriveBackupService(
      authService: GoogleDriveAuthService(storage: mockStorage),
      encryptionService: originalEncryptionService,
      localBackupService: EnhancedBackupService(),
    );
    originalBackupService.setMockDriveApi(FakeDriveApi(fakeFiles));

    final originalRecoveryKey = await originalEncryptionService.getOrCreateLocalMasterKey();
    expect(originalRecoveryKey.startsWith('MDR-'), isTrue);

    // 3. Original device: upload to Google Drive
    final uploadedMeta = await originalBackupService.uploadBackup(
      sourceLocalFile: originalDbFile,
      description: 'نسخة نهاية اليوم',
    );
    expect(uploadedMeta.id.isNotEmpty, isTrue);

    // 4. Replacement device simulation:
    // A fresh device has an empty secure storage (no master key stored yet)
    final freshStorage = MockSecureStorage();
    final freshEncryptionService = CloudBackupEncryptionService(secureStorage: freshStorage);
    final freshBackupService = GoogleDriveBackupService(
      authService: GoogleDriveAuthService(storage: freshStorage),
      encryptionService: freshEncryptionService,
      localBackupService: EnhancedBackupService(),
    );
    freshBackupService.setMockDriveApi(FakeDriveApi(fakeFiles));

    // 5. Replacement device downloads encrypted file from Drive
    final downloadedEncryptedFile = File(p.join(tempDir.path, 'downloaded_recovery.poscloudbackup'));
    await freshBackupService.downloadCloudBackup(
      fileId: uploadedMeta.id,
      targetFile: downloadedEncryptedFile,
    );
    expect(await downloadedEncryptedFile.exists(), isTrue);

    // 6. Replacement device decrypts using only the 16-character recovery key
    final recoveredDbFile = File(p.join(tempDir.path, 'company_recovered.sqlite'));
    await freshEncryptionService.decryptBackupFile(
      encryptedFile: downloadedEncryptedFile,
      targetDecryptedFile: recoveredDbFile,
      recoveryKeyOrPassphrase: originalRecoveryKey,
    );

    // 7. Verification: Bit-for-bit restored payload
    expect(await recoveredDbFile.exists(), isTrue);
    final recoveredContent = await recoveredDbFile.readAsString();
    expect(recoveredContent, testSqlitePayload);
  });

  test('deleteCloudBackup removes backup from Google Drive', () async {
    fakeFiles.files.add(
      drive.File()
        ..id = 'target_to_delete'
        ..name = 'MADAR_Cloud_20261021_000001.poscloudbackup'
        ..appProperties = {'app': 'madar_erp'},
    );

    await backupService.deleteCloudBackup('target_to_delete');
    expect(fakeFiles.deleteCalls, 1);
    expect(fakeFiles.files.any((f) => f.id == 'target_to_delete'), isFalse);
  });
}
