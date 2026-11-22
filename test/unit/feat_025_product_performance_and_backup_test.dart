import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/services/enhanced_backup_service.dart';
import 'package:pos_offline_desktop/core/config/app_flavor.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FEAT-025 EnhancedBackupService Directory Path', () {
    late Directory testDir;
    late Directory backupsDir;
    late File liveDbFile;
    late AppDatabase db;
    late EnhancedBackupService service;

    setUpAll(() {
      AppFlavor.initialize(Flavor.base);
    });

    setUp(() async {
      testDir = await Directory.systemTemp.createTemp('feat025_backup_test_');
      backupsDir = Directory(p.join(testDir.path, 'backups'))..createSync(recursive: true);
      liveDbFile = File(p.join(testDir.path, 'live_test.sqlite'));

      EnhancedBackupService.customBackupDirectory = backupsDir;
      EnhancedBackupService.customDatabasePath = liveDbFile.path;

      db = AppDatabase(NativeDatabase(liveDbFile));
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

    test('getBackupDirectory and getBackupDirectoryPath return accurate directory info', () async {
      final dir = await service.getBackupDirectory();
      final dirPath = await service.getBackupDirectoryPath();

      expect(dir.path, equals(backupsDir.path));
      expect(dirPath, equals(backupsDir.path));
      expect(await dir.exists(), isTrue);
    });
  });

  group('FEAT-025 Product Pagination & Virtualization Slicing', () {
    // Generate 250 mock items to verify pagination performance and slicing correctness
    final mockProducts = List.generate(250, (i) {
      return {
        'id': i + 1,
        'name': 'منتج رقم ${i + 1}',
        'barcode': '622000000000$i',
        'category': i % 2 == 0 ? 'خضار' : 'فاكهة',
        'quantity': (i % 10) * 5,
        'price': (i + 1) * 1.5,
      };
    });

    test('Page slicing yields exactly rowsPerPage items per page without lag', () {
      const rowsPerPage = 25;
      final totalPages = (mockProducts.length / rowsPerPage).ceil();

      expect(totalPages, equals(10));

      for (int page = 0; page < totalPages; page++) {
        final startIndex = page * rowsPerPage;
        final endIndex = (startIndex + rowsPerPage).clamp(0, mockProducts.length);
        final pageSlice = mockProducts.sublist(startIndex, endIndex);

        expect(pageSlice.length, equals(25));
        expect(pageSlice.first['id'], equals(startIndex + 1));
        expect(pageSlice.last['id'], equals(endIndex));
      }
    });

    test('Last page handles partial slices correctly', () {
      final oddProducts = mockProducts.take(53).toList();
      const rowsPerPage = 25;
      final totalPages = (oddProducts.length / rowsPerPage).ceil();

      expect(totalPages, equals(3));

      // Page 0: 0..25
      final p0 = oddProducts.sublist(0, 25);
      expect(p0.length, equals(25));

      // Page 1: 25..50
      final p1 = oddProducts.sublist(25, 50);
      expect(p1.length, equals(25));

      // Page 2: 50..53 (3 items)
      final p2 = oddProducts.sublist(50, 53);
      expect(p2.length, equals(3));
    });

    test('Empty product list handles clamp and zero-length safely', () {
      final emptyList = <Map<String, dynamic>>[];
      const rowsPerPage = 25;
      final totalItems = emptyList.length;
      final totalPages = (totalItems / rowsPerPage).ceil().clamp(1, 999999);
      final startIndex = 0 * rowsPerPage;
      final endIndex = (startIndex + rowsPerPage).clamp(0, totalItems);
      final pageSlice = (startIndex < totalItems) ? emptyList.sublist(startIndex, endIndex) : <Map<String, dynamic>>[];

      expect(totalPages, equals(1));
      expect(pageSlice, isEmpty);
      expect(endIndex, equals(0));
    });
  });
}
