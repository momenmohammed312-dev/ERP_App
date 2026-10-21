import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as raw_sqlite;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('v79 Migration on In-Memory DB', () {
    test('fresh DB creates all tables, indexes, and seeds 11 accounts + overtime_grace_minutes', () async {
      final db = AppDatabase(NativeDatabase.memory());
      
      // Trigger database opening and migrations
      final versionResult = await db.customSelect('PRAGMA user_version').getSingle();
      final version = versionResult.data['user_version'] as int;
      expect(version, 79, reason: 'Database schema version must be 79');

      // Verify the 7 new tables exist
      final tablesResult = await db.customSelect("SELECT name FROM sqlite_master WHERE type='table'").get();
      final tableNames = tablesResult.map((r) => r.data['name'] as String).toSet();
      
      expect(tableNames, contains('accounts'));
      expect(tableNames, contains('journal_entries'));
      expect(tableNames, contains('journal_lines'));
      expect(tableNames, contains('partners'));
      expect(tableNames, contains('equity_transactions'));
      expect(tableNames, contains('monthly_attendance_summary_table'));
      expect(tableNames, contains('product_variants'));

      // Verify indexes
      final indexesResult = await db.customSelect("SELECT name FROM sqlite_master WHERE type='index'").get();
      final indexNames = indexesResult.map((r) => r.data['name'] as String).toSet();
      expect(indexNames, contains('idx_monthly_summary_staff_period'));
      expect(indexNames, contains('idx_journal_entries_posting_key'));
      expect(indexNames, contains('idx_journal_lines_entry'));
      expect(indexNames, contains('idx_variants_product'));

      // Verify columns
      Future<List<String>> getColumns(String table) async {
        final info = await db.customSelect('PRAGMA table_info($table)').get();
        return info.map((r) => r.data['name'] as String).toList();
      }

      final staffBioCols = await getColumns('staff_biometric_mappings');
      expect(staffBioCols, contains('device_user_name'));

      final invItemCols = await getColumns('invoice_items');
      expect(invItemCols, contains('variant_id'));

      final returnItemCols = await getColumns('sales_return_items');
      expect(returnItemCols, contains('variant_id'));

      final advanceCols = await getColumns('staff_advances');
      expect(advanceCols, contains('paid_amount'));
      expect(advanceCols, contains('deduct_on_period'));

      // Verify 11 accounts seeded
      final accounts = await db.accountsDao.getAllAccounts();
      expect(accounts.length, 11, reason: 'Chart of accounts must have exactly 11 system accounts');
      final codes = accounts.map((a) => a.code).toSet();
      expect(codes, containsAll([
        '1000', '1010', '1100', '1200', '2000',
        '3000', '3100', '3200', '4000', '4100', '5000'
      ]));

      // Verify overtime_grace_minutes=30 seeded
      final setting = await db.customSelect(
        "SELECT setting_value FROM attendance_settings WHERE setting_key = 'overtime_grace_minutes'",
      ).getSingleOrNull();
      expect(setting, isNotNull);
      expect(setting!.data['setting_value'], '30');

      await db.close();
    });

    test('v79 migration is idempotent (re-running causes no error or duplicates)', () async {
      final db = AppDatabase(NativeDatabase.memory());
      // Initial trigger
      await db.customSelect('PRAGMA user_version').getSingle();

      // Trigger migrations step again explicitly
      final m = db.createMigrator();
      await db.migration.onUpgrade(m, 78, 79);

      // Verify accounts count is still 11
      final accounts = await db.accountsDao.getAllAccounts();
      expect(accounts.length, 11);

      await db.close();
    });
  });

  group('v79 Migration on Client Copy (scratch/client_test2.sqlite)', () {
    test('upgrades 78 -> 79 with zero row loss on client database', () async {
      final copySrc = File('scratch/client_copy.sqlite');
      final clientFile = File('scratch/client_test2.sqlite');
      
      // Ensure a fresh copy of client_copy.sqlite
      expect(copySrc.existsSync(), isTrue);
      copySrc.copySync(clientFile.path);

      // 1. Inspect pre-migration state using raw sqlite3 without running AppDatabase
      final raw = raw_sqlite.sqlite3.open(clientFile.path);
      final preVersionResult = raw.select('PRAGMA user_version');
      final preVersion = preVersionResult.first['user_version'] as int;
      expect(preVersion, 78, reason: 'Client copy must start at schema version 78');

      final preTablesResult = raw.select("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'");
      final tableNames = preTablesResult.map((r) => r['name'] as String).toList();

      final preRowCounts = <String, int>{};
      for (final table in tableNames) {
        final countResult = raw.select('SELECT COUNT(*) as c FROM "$table"');
        preRowCounts[table] = countResult.first['c'] as int;
      }
      raw.dispose();

      // 2. Open DB with AppDatabase so migration 78 -> 79 runs
      final migratedDb = AppDatabase(NativeDatabase(clientFile));
      
      final postVersionRow = await migratedDb.customSelect('PRAGMA user_version').getSingle();
      final postVersion = postVersionRow.data['user_version'] as int;
      expect(postVersion, 79, reason: 'Migrated database version must be 79');

      // 3. Verify row counts on all pre-existing business tables are 100% identical (zero row loss)
      for (final entry in preRowCounts.entries) {
        final table = entry.key;
        if (table == '_migration_log') continue;
        final expectedCount = entry.value;
        final countRow = await migratedDb.customSelect('SELECT COUNT(*) as c FROM "$table"').getSingle();
        final actualCount = countRow.data['c'] as int;
        expect(actualCount, expectedCount, reason: 'Row count changed for table $table after v79 migration!');
      }

      // 4. Verify new tables exist and are healthy
      final postTables = await migratedDb.customSelect("SELECT name FROM sqlite_master WHERE type='table'").get();
      final postTableNames = postTables.map((r) => r.data['name'] as String).toSet();
      expect(postTableNames, containsAll([
        'accounts',
        'journal_entries',
        'journal_lines',
        'partners',
        'equity_transactions',
        'monthly_attendance_summary_table',
        'product_variants',
      ]));

      // 5. Verify existing accounts are preserved (12 accounts in client DB)
      final accounts = await migratedDb.accountsDao.getAllAccounts();
      expect(accounts.length, 12, reason: 'Client DB has 12 accounts which must be preserved without duplicate injection');

      // 6. Verify safeAddColumn added columns
      final bioCols = (await migratedDb.customSelect('PRAGMA table_info(staff_biometric_mappings)').get()).map((r) => r.data['name']).toList();
      expect(bioCols, contains('device_user_name'));

      final invCols = (await migratedDb.customSelect('PRAGMA table_info(invoice_items)').get()).map((r) => r.data['name']).toList();
      expect(invCols, contains('variant_id'));

      final returnCols = (await migratedDb.customSelect('PRAGMA table_info(sales_return_items)').get()).map((r) => r.data['name']).toList();
      expect(returnCols, contains('variant_id'));

      final advCols = (await migratedDb.customSelect('PRAGMA table_info(staff_advances)').get()).map((r) => r.data['name']).toList();
      expect(advCols, contains('paid_amount'));
      expect(advCols, contains('deduct_on_period'));

      await migratedDb.close();
    });
  });
}
