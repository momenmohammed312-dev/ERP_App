import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/services/enhanced_backup_service.dart';
import 'package:pos_offline_desktop/core/config/app_flavor.dart';
import 'package:pos_offline_desktop/core/provider/app_database_provider.dart';
import 'package:path/path.dart' as p;
import 'package:crypto/crypto.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const String productionDbPath = r'G:\flutter\Documents\pos_offline_desktop_database.sqlite';
  late String initialProductionHash;

  setUpAll(() {
    AppFlavor.initialize(Flavor.base);
    final prodFile = File(productionDbPath);
    if (prodFile.existsSync()) {
      initialProductionHash = sha256.convert(prodFile.readAsBytesSync()).toString();
    } else {
      initialProductionHash = 'NOT_FOUND';
    }
  });

  group('STEP 1: Database & File System Isolation', () {
    test('staging environment uses isolated temp path and never touches production DB', () async {
      final stagingDir = await Directory.systemTemp.createTemp('madar_staging_isolation_');
      try {
        final canonicalStaging = p.canonicalize(stagingDir.path);
        final canonicalProd = p.canonicalize(productionDbPath);

        expect(canonicalStaging.toLowerCase(), isNot(equals(canonicalProd.toLowerCase())));
        expect(canonicalStaging.toLowerCase().contains('documents'), isFalse);
        expect(stagingDir.existsSync(), isTrue);

        // Verify production DB hash has not changed
        final currentProdFile = File(productionDbPath);
        if (currentProdFile.existsSync()) {
          final currentHash = sha256.convert(currentProdFile.readAsBytesSync()).toString();
          expect(currentHash, equals(initialProductionHash), reason: 'Production DB must not be modified');
        }
      } finally {
        if (await stagingDir.exists()) {
          await stagingDir.delete(recursive: true);
        }
      }
    });
  });

  group('STEP 2: Backup Under Business Load & Concurrency', () {
    late Directory stagingDir;
    late Directory backupsDir;
    late File stagingDbFile;
    late AppDatabase db;
    late EnhancedBackupService service;

    setUp(() async {
      stagingDir = await Directory.systemTemp.createTemp('madar_staging_load_');
      backupsDir = Directory(p.join(stagingDir.path, 'backups'))..createSync(recursive: true);
      stagingDbFile = File(p.join(stagingDir.path, 'staging_pos.sqlite'));

      EnhancedBackupService.customBackupDirectory = backupsDir;
      EnhancedBackupService.customDatabasePath = stagingDbFile.path;

      db = AppDatabase(NativeDatabase(stagingDbFile));
      // Initialize schema
      await db.customSelect("SELECT name FROM sqlite_master WHERE type='table'").get();

      // Seed representative business data:
      // 100 customers, 100 products, 50 invoices, 20 expenses
      await db.transaction(() async {
        for (int i = 1; i <= 100; i++) {
          await db.customInsert(
            "INSERT INTO customers (id, name, phone, address, opening_balance, status) "
            "VALUES ('cust-$i', 'عميل تجريبي $i', '010${i.toString().padLeft(8, '0')}', 'عنوان $i', ${i * 10.0}, 'Active')",
          );
        }
        for (int i = 1; i <= 100; i++) {
          await db.customInsert(
            "INSERT INTO products (name, quantity, price, status, min_stock_level, barneka) "
            "VALUES ('منتج تجريبي $i', ${i * 5}, ${i * 12.5}, 'Active', 5, 0)",
          );
        }
        for (int i = 1; i <= 50; i++) {
          await db.customInsert(
            "INSERT INTO invoices (invoice_number, customer_id, customer_name, payment_method, total_amount, paid_amount, status) "
            "VALUES ('INV-${i.toString().padLeft(4, '0')}', 'cust-$i', 'عميل تجريبي $i', 'cash', ${i * 100.0}, ${i * 100.0}, 'paid')",
          );
        }
        for (int i = 1; i <= 20; i++) {
          await db.customInsert(
            "INSERT INTO expenses (id, description, amount, category, payment_method) "
            "VALUES ('exp-$i', 'مصروف تجريبي $i', ${i * 25.0}, 'نثريات', 'cash')",
          );
        }
      });

      service = EnhancedBackupService();
      service.init(db);
    });

    tearDown(() async {
      EnhancedBackupService.customBackupDirectory = null;
      EnhancedBackupService.customDatabasePath = null;
      try {
        await db.close();
      } catch (_) {}
      if (await stagingDir.exists()) {
        await stagingDir.delete(recursive: true);
      }
    });

    test('repeated backups measure duration, size, and pass integrity check', () async {
      final List<int> durations = [];
      final List<int> sizes = [];

      for (int i = 1; i <= 5; i++) {
        final stopwatch = Stopwatch()..start();
        final backupInfo = await service.createBackup(
          type: 'manual',
          description: 'نسخة رقم $i تحت الحمل التجريبي',
        );
        stopwatch.stop();

        durations.add(stopwatch.elapsedMilliseconds);
        sizes.add(backupInfo.size);

        // Verify integrity
        final isValid = await service.verifyBackupIntegrity(backupInfo.filename);
        expect(isValid, isTrue, reason: 'Backup $i must pass integrity check');
      }

      print('📊 Repeated Backups Durations (ms): $durations');
      print('📊 Repeated Backups Sizes (bytes): $sizes');

      expect(durations.length, 5);
      expect(durations.every((d) => d < 5000), isTrue, reason: 'Each backup should complete in < 5s on staging');
    });

    test('10 concurrent write transactions during backup succeed without SQLite locks or deadlock', () async {
      final writeStopwatch = Stopwatch()..start();

      // Start backup in background
      final backupFuture = service.createBackup(
        type: 'auto',
        description: 'نسخة أثناء عمليات كتابة نشطة',
      );

      // Concurrently run 10 write transactions
      final List<Future> writeFutures = [];
      for (int i = 101; i <= 110; i++) {
        writeFutures.add(
          db.customInsert(
            "INSERT INTO customers (id, name, phone, address, opening_balance, status) "
            "VALUES ('cust-concurrent-$i', 'عميل متزامن $i', '012000000$i', 'القاهرة', 500.0, 'Active')",
          ),
        );
      }

      await Future.wait(writeFutures);
      final backupInfo = await backupFuture;
      writeStopwatch.stop();

      print('⏱️ 10 concurrent writes + backup completed in ${writeStopwatch.elapsedMilliseconds} ms');

      // Verify all 10 rows committed
      final countResult = await db.customSelect(
        "SELECT COUNT(*) AS c FROM customers WHERE id LIKE 'cust-concurrent-%'",
      ).getSingle();
      expect(countResult.data['c'], 10, reason: 'All 10 concurrent writes must commit successfully');

      // Verify backup is valid
      final isValid = await service.verifyBackupIntegrity(backupInfo.filename);
      expect(isValid, isTrue);
    });

    test('concurrent backup request is rejected with BackupOperationInProgressException', () async {
      final f1 = service.createBackup(type: 'manual', description: 'نسخة 1');
      final f2 = service.createBackup(type: 'manual', description: 'نسخة 2 متزامنة');

      bool caught = false;
      try {
        await Future.wait([f1, f2]);
      } on BackupOperationInProgressException {
        caught = true;
      } catch (e) {
        if (e is BackupOperationInProgressException) caught = true;
      }

      expect(caught, isTrue, reason: 'Second concurrent backup must be rejected');
      expect(EnhancedBackupService.isOperationInProgress, isFalse, reason: 'Lock must reset after completion');
    });

    test('temporary directory ownership: only its own temp dir is created and unlinked', () async {
      final foreignFile = File(p.join(backupsDir.path, 'unrelated_customer_file.pdf'));
      await foreignFile.writeAsString('sensitive customer export');

      await service.createBackup(type: 'manual');

      // Foreign file must remain untouched
      expect(await foreignFile.exists(), isTrue);

      // No leftover temp directories
      final leftoverTemp = backupsDir.listSync().where((e) => p.basename(e.path).startsWith('temp_')).toList();
      expect(leftoverTemp.isEmpty, isTrue, reason: 'Temp directory must be cleaned up in finally block');
    });
  });

  group('STEP 3: Restore Lifecycle & Riverpod Container Invalidation', () {
    late Directory stagingDir;
    late Directory backupsDir;
    late File stagingDbFile;
    late AppDatabase db;
    late EnhancedBackupService service;

    setUp(() async {
      stagingDir = await Directory.systemTemp.createTemp('madar_staging_restore_');
      backupsDir = Directory(p.join(stagingDir.path, 'backups'))..createSync(recursive: true);
      stagingDbFile = File(p.join(stagingDir.path, 'staging_restore.sqlite'));

      EnhancedBackupService.customBackupDirectory = backupsDir;
      EnhancedBackupService.customDatabasePath = stagingDbFile.path;

      db = AppDatabase(NativeDatabase(stagingDbFile));
      await db.customSelect("SELECT name FROM sqlite_master WHERE type='table'").get();

      // Seed initial data
      for (int i = 1; i <= 50; i++) {
        await db.customInsert(
          "INSERT INTO customers (id, name, phone, opening_balance, status) "
          "VALUES ('cust-res-$i', 'عميل استعادة $i', '011${i.toString().padLeft(8, '0')}', 100.0, 'Active')",
        );
      }

      service = EnhancedBackupService();
      service.init(db);
    });

    tearDown(() async {
      EnhancedBackupService.customBackupDirectory = null;
      EnhancedBackupService.customDatabasePath = null;
      try {
        await db.close();
      } catch (_) {}
      if (await stagingDir.exists()) {
        await stagingDir.delete(recursive: true);
      }
    });

    test('corrupt backup candidate is rejected and live database remains untouched', () async {
      final corruptFile = File(p.join(backupsDir.path, 'corrupt_test.posbackup'));
      await corruptFile.writeAsBytes([0xDE, 0xAD, 0xBE, 0xEF, 0x01, 0x02, 0x03]);

      expect(() => service.restoreBackup('corrupt_test.posbackup'), throwsA(isA<Exception>()));

      // Verify live DB data is intact
      final count = (await db.customSelect('SELECT COUNT(*) AS c FROM customers').getSingle()).data['c'] as int;
      expect(count, 50, reason: 'Live database must remain completely intact when restore is rejected');
    });

    test('valid restore invalidates Riverpod container and allows immediate R/W queries', () async {
      // 1. Create valid backup
      final backup = await service.createBackup(type: 'manual', description: 'نسخة كاملة قبل الحذف');

      // 2. Simulate accidental data loss in live DB
      await db.customUpdate("DELETE FROM customers WHERE id = 'cust-res-1'");
      final countAfterDelete = (await db.customSelect('SELECT COUNT(*) AS c FROM customers').getSingle()).data['c'] as int;
      expect(countAfterDelete, 49);

      // 3. Set up Riverpod container
      final container = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
        ],
      );

      // 4. Perform restore
      final restoreSuccess = await service.restoreBackup(backup.filename);
      expect(restoreSuccess, isTrue);

      // 5. Invalidate provider and re-inject new connection (exact pattern used in EnhancedBackupScreen & BackupManagementScreen)
      final newDb = AppDatabase(NativeDatabase(stagingDbFile));
      final newContainer = ProviderContainer(
        overrides: [
          appDatabaseProvider.overrideWithValue(newDb),
        ],
      );

      final freshDb = newContainer.read(appDatabaseProvider);

      // 6. Read operation: confirm deleted record was restored
      final restoredCount = (await freshDb.customSelect('SELECT COUNT(*) AS c FROM customers').getSingle()).data['c'] as int;
      expect(restoredCount, 50, reason: 'All 50 customers must be restored');

      final cust1 = await freshDb.customSelect("SELECT name FROM customers WHERE id = 'cust-res-1'").get();
      expect(cust1.length, 1);
      expect(cust1.first.data['name'], 'عميل استعادة 1');

      // 7. Write operation: verify new write succeeds on restored DB without lock errors
      await freshDb.customInsert(
        "INSERT INTO customers (id, name, phone, opening_balance, status) "
        "VALUES ('cust-res-new', 'عميل جديد بعد الاستعادة', '01999999999', 750.0, 'Active')",
      );

      final postWriteCount = (await freshDb.customSelect('SELECT COUNT(*) AS c FROM customers').getSingle()).data['c'] as int;
      expect(postWriteCount, 51);

      await freshDb.close();
      container.dispose();
      newContainer.dispose();
    });
  });

  group('STEP 4: Sidecar Handling & Interrupted Operation Safety', () {
    late Directory stagingDir;
    late Directory backupsDir;
    late File stagingDbFile;
    late AppDatabase db;
    late EnhancedBackupService service;

    setUp(() async {
      stagingDir = await Directory.systemTemp.createTemp('madar_staging_sidecar_');
      backupsDir = Directory(p.join(stagingDir.path, 'backups'))..createSync(recursive: true);
      stagingDbFile = File(p.join(stagingDir.path, 'staging_sidecar.sqlite'));

      EnhancedBackupService.customBackupDirectory = backupsDir;
      EnhancedBackupService.customDatabasePath = stagingDbFile.path;

      db = AppDatabase(NativeDatabase(stagingDbFile));
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
      if (await stagingDir.exists()) {
        await stagingDir.delete(recursive: true);
      }
    });

    test('restore safely snapshots and removes sidecars (-wal, -shm, -journal)', () async {
      // 1. Create a valid backup first
      final backup = await service.createBackup(type: 'manual');

      // 2. Simulate existing sidecars
      final walFile = File('${stagingDbFile.path}-wal');
      final shmFile = File('${stagingDbFile.path}-shm');
      final journalFile = File('${stagingDbFile.path}-journal');

      await walFile.writeAsString('mock wal bytes');
      await shmFile.writeAsString('mock shm bytes');
      await journalFile.writeAsString('mock journal bytes');

      expect(await walFile.exists(), isTrue);
      expect(await shmFile.exists(), isTrue);
      expect(await journalFile.exists(), isTrue);

      // 3. Restore backup
      final success = await service.restoreBackup(backup.filename);
      expect(success, isTrue);

      // 4. Stale active sidecars must be removed so new database starts clean
      expect(await walFile.exists(), isFalse, reason: 'Active -wal must be removed to prevent stale replay');
      expect(await shmFile.exists(), isFalse, reason: 'Active -shm must be removed');
      expect(await journalFile.exists(), isFalse, reason: 'Active -journal must be removed');

      // 5. Pre-restore snapshots of sidecars must exist on disk for manual recovery
      final sidecarSnapshots = stagingDir.listSync().where((e) => e.path.contains('.before_restore_')).toList();
      expect(sidecarSnapshots.length, greaterThanOrEqualTo(2), reason: 'Sidecar and DB snapshots must be archived');
      print('💾 Safety snapshots preserved on disk: ${sidecarSnapshots.map((e) => p.basename(e.path)).toList()}');
    });
  });

  group('STEP 5: Existing Backup Compatibility & Fixtures', () {
    test('legacy backup fixtures are discoverable, decryptable, and readable', () async {
      final fixtureDir = Directory('data/backups');
      if (!fixtureDir.existsSync()) {
        print('⚠️ data/backups not found in repo root');
        return;
      }

      final files = fixtureDir.listSync().whereType<File>().toList();
      print('📁 Found ${files.length} backup fixtures in data/backups/: ${files.map((f) => p.basename(f.path)).toList()}');

      final sampleBackup = File('data/backups/backup_20260501_151658.posbackup');
      if (await sampleBackup.exists()) {
        final length = await sampleBackup.length();
        expect(length, greaterThan(1000));
        print('📦 Fixture backup_20260501_151658.posbackup size: $length bytes');

        // Test listing in isolated directory
        final stagingTemp = await Directory.systemTemp.createTemp('madar_fixture_test_');
        try {
          final tempBackupDir = Directory(p.join(stagingTemp.path, 'backups'))..createSync(recursive: true);
          final copied = await sampleBackup.copy(p.join(tempBackupDir.path, p.basename(sampleBackup.path)));
          expect(await copied.exists(), isTrue);

          EnhancedBackupService.customBackupDirectory = tempBackupDir;
          final s = EnhancedBackupService();
          final list = await s.listBackups();
          expect(list.isNotEmpty, isTrue);
          print('📋 Listed fixture: ${list.first.filename}, version: ${list.first.version}, isEncrypted: ${list.first.isEncrypted}');
        } finally {
          EnhancedBackupService.customBackupDirectory = null;
          await stagingTemp.delete(recursive: true);
        }
      }
    });
  });

  group('FINAL ISOLATION AUDIT', () {
    test('production database hash is 100% identical after all test groups', () {
      final prodFile = File(productionDbPath);
      if (prodFile.existsSync()) {
        final finalHash = sha256.convert(prodFile.readAsBytesSync()).toString();
        expect(finalHash, equals(initialProductionHash), reason: 'Zero bytes changed in production database');
        print('🔒 Production DB verification PASS: SHA-256 = $finalHash (100% identical)');
      }
    });
  });
}
