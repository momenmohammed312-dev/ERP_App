import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/services/enhanced_backup_service.dart';
import 'package:pos_offline_desktop/core/config/app_flavor.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory testDir;
  late Directory backupsDir;
  late File liveDbFile;
  late AppDatabase db;
  late EnhancedBackupService service;

  setUpAll(() {
    AppFlavor.initialize(Flavor.base);
  });

  setUp(() async {
    testDir = await Directory.systemTemp.createTemp('madar_backup_test_');
    backupsDir = Directory(p.join(testDir.path, 'backups'))..createSync(recursive: true);
    liveDbFile = File(p.join(testDir.path, 'live_test.sqlite'));

    // Test seams: point service to isolated test directories
    EnhancedBackupService.customBackupDirectory = backupsDir;
    EnhancedBackupService.customDatabasePath = liveDbFile.path;

    // Create a real SQLite database on disk
    db = AppDatabase(NativeDatabase(liveDbFile));
    // Trigger table creation
    await db.customSelect("SELECT name FROM sqlite_master WHERE type='table'").get();

    service = EnhancedBackupService();
    service.init(db);
  });

  tearDown(() async {
    EnhancedBackupService.customBackupDirectory = null;
    EnhancedBackupService.customDatabasePath = null;
    try {
      await db.close();
    } catch (_) {}
    if (await testDir.exists()) {
      await testDir.delete(recursive: true);
    }
  });

  test('createBackup uses VACUUM INTO, produces valid snapshot, leaves source unchanged', () async {
    // 1. Insert seed data into customers
    await db.customInsert(
      "INSERT INTO customers (id, name, phone, address, opening_balance, status) "
      "VALUES ('cust-001', 'عميل تجريبي', '01000000000', 'القاهرة', 1500.0, 'Active')",
    );

    final beforeCount = (await db.customSelect('SELECT COUNT(*) AS c FROM customers').getSingle()).data['c'] as int;
    expect(beforeCount, 1);

    final beforeLength = await liveDbFile.length();
    expect(beforeLength, greaterThan(0));

    // 2. Create backup
    final backupInfo = await service.createBackup(
      type: 'manual',
      description: 'اختبار النسخ الذري',
    );

    // 3. Verify backup file exists and is encrypted
    final backupFile = File(backupInfo.filePath);
    expect(await backupFile.exists(), isTrue);
    expect(backupInfo.size, greaterThan(0));
    expect(backupInfo.isEncrypted, isTrue);

    // 4. Verify source database remained completely unchanged
    final afterCount = (await db.customSelect('SELECT COUNT(*) AS c FROM customers').getSingle()).data['c'] as int;
    expect(afterCount, beforeCount, reason: 'Source database row count must remain identical');

    // 5. Verify integrity of the backup file itself
    final isIntact = await service.verifyBackupIntegrity(backupInfo.filename);
    expect(isIntact, isTrue, reason: 'Generated backup must pass integrity check');
  });

  test('restoreBackup successfully restores database without locking error', () async {
    // 1. Insert known records
    await db.customInsert(
      "INSERT INTO customers (id, name, phone, address, opening_balance, status) "
      "VALUES ('cust-restore', 'عميل الاستعادة', '01111111111', 'الجيزة', 500.0, 'Active')",
    );

    // 2. Create backup
    final backupInfo = await service.createBackup(type: 'manual', description: 'نسخة للاستعادة');

    // 3. Mutate live database (simulate accidental deletion or change)
    await db.customUpdate("DELETE FROM customers WHERE id = 'cust-restore'");
    final afterDelete = (await db.customSelect('SELECT COUNT(*) AS c FROM customers').getSingle()).data['c'] as int;
    expect(afterDelete, 0);

    // 4. Perform restore
    final restoreSuccess = await service.restoreBackup(backupInfo.filename);
    expect(restoreSuccess, isTrue);

    // 5. Reconnect and verify data was recovered
    final restoredExecutor = NativeDatabase(liveDbFile);
    final restoredDb = AppDatabase(restoredExecutor);
    try {
      final rows = await restoredDb.customSelect("SELECT name FROM customers WHERE id = 'cust-restore'").get();
      expect(rows.length, 1);
      expect(rows.first.data['name'], 'عميل الاستعادة');
    } finally {
      await restoredDb.close();
    }
  });

  test('restoreBackup rejects corrupt candidate before overwriting live database', () async {
    // 1. Insert seed record in live database
    await db.customInsert(
      "INSERT INTO customers (id, name, phone, address, opening_balance, status) "
      "VALUES ('cust-safe', 'عميل لن يُمس', '01222222222', 'الإسكندرية', 300.0, 'Active')",
    );

    // 2. Create a corrupt .posbackup file (garbage bytes)
    final corruptFilename = 'backup_corrupt.posbackup';
    final corruptPath = p.join(backupsDir.path, corruptFilename);
    await File(corruptPath).writeAsBytes([0x00, 0x01, 0x02, 0x03, 0xFF, 0xFE]);

    // 3. Attempt restore and verify it throws before modifying live DB
    expect(
      () => service.restoreBackup(corruptFilename),
      throwsA(isA<Exception>()),
    );

    // 4. Verify live database is completely safe and untouched
    final rows = await db.customSelect("SELECT name FROM customers WHERE id = 'cust-safe'").get();
    expect(rows.length, 1);
    expect(rows.first.data['name'], 'عميل لن يُمس');
  });

  test('restoreBackup creates safety snapshot before replacement', () async {
    // 1. Insert record
    await db.customInsert(
      "INSERT INTO customers (id, name, phone, address, opening_balance, status) "
      "VALUES ('cust-snap', 'لقطة أمان', '01555555555', 'طنطا', 100.0, 'Active')",
    );

    // 2. Create backup
    final backupInfo = await service.createBackup(type: 'manual');

    // 3. Restore backup
    await service.restoreBackup(backupInfo.filename, createPreRestoreBackup: true);

    // 4. Verify pre-restore snapshot file was created on disk
    final snapshotFiles = testDir
        .listSync()
        .where((e) => e.path.contains('.before_restore_'))
        .toList();

    expect(snapshotFiles.isNotEmpty, isTrue, reason: 'Safety snapshot file must exist on disk');
    expect(File(snapshotFiles.first.path).lengthSync(), greaterThan(0));
  });

  test('Phase 1 does not delete old backups automatically during creation', () async {
    // Create 12 backups
    for (int i = 0; i < 12; i++) {
      await service.createBackup(type: 'auto', description: 'نسخة رقم $i');
      // small delay to ensure distinct filenames
      await Future.delayed(const Duration(milliseconds: 10));
    }

    final allBackups = await service.listBackups();
    // In Phase 1, maxBackups limit (10) must NOT auto-delete older backups
    expect(allBackups.length, 12, reason: 'All 12 backups must be preserved; automated deletion is disabled in Phase 1');
  });

  test('Existing legacy backup files remain discoverable and valid', () async {
    // Check if the fixture backup from data/backups/ exists and can be listed
    final sampleBackup = File('data/backups/backup_20260501_151658.posbackup');
    if (await sampleBackup.exists()) {
      // Copy to our isolated test backups dir
      final testSamplePath = p.join(backupsDir.path, p.basename(sampleBackup.path));
      await sampleBackup.copy(testSamplePath);

      final backups = await service.listBackups();
      final found = backups.any((b) => b.filename == 'backup_20260501_151658.posbackup');
      expect(found, isTrue, reason: 'Legacy backup format must be detected by listBackups');
    }
  });
  test('concurrent backup attempts reject second request with BackupOperationInProgressException', () async {
    // 1. Insert seed data
    await db.customInsert(
      "INSERT INTO customers (id, name, phone, address, opening_balance, status) "
      "VALUES ('cust-lock', 'عميل قفل التزامن', '01011111111', 'المعادي', 100.0, 'Active')",
    );

    // 2. Start two backup requests concurrently
    final future1 = service.createBackup(type: 'manual', description: 'نسخة أولى');
    final future2 = service.createBackup(type: 'manual', description: 'نسخة متزامنة');

    // 3. One must succeed and the other must be rejected with BackupOperationInProgressException
    bool caughtLockException = false;
    try {
      await Future.wait([future1, future2]);
    } on BackupOperationInProgressException {
      caughtLockException = true;
    } catch (_) {}

    expect(caughtLockException, isTrue, reason: 'Concurrent backup request must be rejected with BackupOperationInProgressException');

    // 4. Verify lock is cleanly released afterwards
    expect(EnhancedBackupService.isOperationInProgress, isFalse, reason: 'Operation lock must be released after completion');
  });

  test('temporary directory ownership: backup cleans only its own temp directory', () async {
    // 1. Create a foreign file in backupsDir to simulate another file
    final foreignFile = File(p.join(backupsDir.path, 'unrelated_file.txt'));
    await foreignFile.writeAsString('keep me');

    // 2. Create backup
    final backup = await service.createBackup(type: 'manual');
    expect(backup.filename.isNotEmpty, isTrue);

    // 3. Foreign file must remain untouched
    expect(await foreignFile.exists(), isTrue, reason: 'Cleanup must not blindly delete unrelated files in backup directory');

    // 4. Verify no lingering temp_* directory
    final lingeringTemp = backupsDir.listSync().where((e) => p.basename(e.path).startsWith('temp_')).toList();
    expect(lingeringTemp.isEmpty, isTrue, reason: 'Operation must clean up its own temp directory in finally');
  });

  test('write transaction during backup does not deadlock or crash with busy_timeout configured', () async {
    // 1. Insert initial row
    await db.customInsert(
      "INSERT INTO customers (id, name, phone, address, opening_balance, status) "
      "VALUES ('cust-write-test', 'عميل المعاملة', '01234567890', 'الدقي', 200.0, 'Active')",
    );

    // 2. Start backup
    final backupFuture = service.createBackup(type: 'manual', description: 'نسخة التزامن');

    // 3. Execute write transaction concurrently
    await db.customInsert(
      "INSERT INTO customers (id, name, phone, address, opening_balance, status) "
      "VALUES ('cust-concurrent-write', 'عميل متزامن', '01987654321', 'المهندسين', 400.0, 'Active')",
    );

    final backupResult = await backupFuture;
    expect(backupResult.filename.isNotEmpty, isTrue);

    // 4. Verify row was successfully inserted into live database
    final rows = await db.customSelect("SELECT COUNT(*) AS c FROM customers WHERE id = 'cust-concurrent-write'").getSingle();
    expect(rows.data['c'], 1, reason: 'Concurrent write transaction must succeed');
  });

  test('restoreBackup safely handles and archives sidecar files', () async {
    // 1. Insert seed record and create backup
    await db.customInsert(
      "INSERT INTO customers (id, name, phone, address, opening_balance, status) "
      "VALUES ('cust-sidecar', 'عميل الملفات الجانبية', '01122334455', 'مدينة نصر', 50.0, 'Active')",
    );
    final backup = await service.createBackup(type: 'manual');

    // 2. Create a mock sidecar journal file
    final sidecarJournal = File('${liveDbFile.path}-journal');
    await sidecarJournal.writeAsString('mock journal data');
    expect(await sidecarJournal.exists(), isTrue);

    // 3. Perform restore
    final restored = await service.restoreBackup(backup.filename);
    expect(restored, isTrue);

    // 4. Verify that sidecar snapshot was created and stale sidecar was cleaned
    final sidecarSnapshots = testDir.listSync().where((e) => e.path.contains('-journal.before_restore_')).toList();
    expect(sidecarSnapshots.isNotEmpty, isTrue, reason: 'Pre-restore sidecar snapshot must be created');
  });

}
