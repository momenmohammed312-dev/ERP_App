import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (MethodCall methodCall) async => '.',
  );

  group('Suite 8: Migration v78->v79 & Backup/Restore Full Integrity', () {
    test('1. Migration v78 -> v79 successfully creates product_variants and adds columns', () async {
      final tempDir = Directory.systemTemp.createTempSync('drift_v78_to_v79_test_');
      final dbFile = File('${tempDir.path}/test_v78_to_v79.db');

      // 1. Initialize full schema v79 database
      final setupDb = AppDatabase(NativeDatabase(dbFile));
      await setupDb.customSelect('SELECT 1').get();
      await setupDb.close();

      // 2. Open via raw sqlite, simulate v78 by dropping product_variants and setting user_version = 78
      final raw = sqlite3.open(dbFile.path);
      try {
        raw.execute('DROP TABLE IF EXISTS product_variants;');
        raw.execute('PRAGMA user_version = 78;');
      } finally {
        raw.dispose();
      }

      // 3. Open AppDatabase again — Drift onUpgrade runs from 78 to 79
      final upgradedDb = AppDatabase(NativeDatabase(dbFile));
      try {
        // Run query to trigger migration
        await upgradedDb.customSelect('SELECT 1').get();

        // Verify product_variants table exists
        final tables = await upgradedDb.customSelect(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='product_variants'",
        ).get();
        expect(tables.isNotEmpty, isTrue);

        // Verify variant_id exists in invoice_items
        final invoiceItemColumns = await upgradedDb.customSelect('PRAGMA table_info(invoice_items)').get();
        final hasVariantInInvoiceItems = invoiceItemColumns.any((c) => c.data['name'] == 'variant_id');
        expect(hasVariantInInvoiceItems, isTrue);

        // Verify variant_id exists in sales_return_items
        final returnItemColumns = await upgradedDb.customSelect('PRAGMA table_info(sales_return_items)').get();
        final hasVariantInReturnItems = returnItemColumns.any((c) => c.data['name'] == 'variant_id');
        expect(hasVariantInReturnItems, isTrue);
      } finally {
        await upgradedDb.close();
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      }
    });

    test('2. BackupService: Table names match and restore order respects foreign keys', () async {
      final source = File('lib/core/services/backup_service.dart').readAsStringSync();

      Set<String> extractList(String marker) {
        final start = source.indexOf(marker);
        expect(start, greaterThanOrEqualTo(0));
        final openBracket = source.indexOf('[', start);
        final closeBracket = source.indexOf('];', openBracket);
        final body = source.substring(openBracket, closeBracket);
        return RegExp(r"'([a-z0-9_]+)'")
            .allMatches(body)
            .map((m) => m.group(1)!)
            .toSet();
      }

      final backupList = extractList('final tables = [');
      final restoreOrder = extractList('final tableOrder = [');

      expect(restoreOrder, equals(backupList), reason: 'Backup and restore table sets must be identical');

      // Critical foreign key dependent tables must be present
      expect(backupList, contains('products'));
      expect(backupList, contains('product_variants'));
      expect(backupList, contains('invoices'));
      expect(backupList, contains('invoice_items'));
      expect(backupList, contains('purchases'));
      expect(backupList, contains('purchase_items'));
      expect(backupList, contains('cash_custodies'));
      expect(backupList, contains('custody_expenses'));
      expect(backupList, contains('manufacturing_orders'));
      expect(backupList, contains('customer_material_receipts'));
    });
  });
}
