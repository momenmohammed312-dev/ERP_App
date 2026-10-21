import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as raw_sqlite;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('v80 Unified Migration Tests', () {
    test('a) Fresh in-memory DB creates all v80 tables, columns, indexes and seeds 11 accounts', () async {
      final db = AppDatabase(NativeDatabase.memory());
      
      final uvResult = await db.customSelect('PRAGMA user_version').getSingle();
      final uv = uvResult.data['user_version'] as int;
      expect(uv, 80, reason: 'Database schema version must be 80');

      // 7 tables check
      final tablesResult = await db.customSelect("SELECT name FROM sqlite_master WHERE type='table'").get();
      final tableNames = tablesResult.map((r) => r.data['name'] as String).toSet();
      
      expect(tableNames, contains('accounts'));
      expect(tableNames, contains('journal_entries'));
      expect(tableNames, contains('journal_lines'));
      expect(tableNames, contains('partners'));
      expect(tableNames, contains('equity_transactions'));
      expect(tableNames, contains('monthly_attendance_summary_table'));
      expect(tableNames, contains('product_variants'));

      // Indexes check
      final indexesResult = await db.customSelect("SELECT name FROM sqlite_master WHERE type='index'").get();
      final indexNames = indexesResult.map((r) => r.data['name'] as String).toSet();
      expect(indexNames, contains('idx_accounts_code'));
      expect(indexNames, contains('idx_journal_entries_posting_key'));
      expect(indexNames, contains('idx_journal_lines_entry'));
      expect(indexNames, contains('idx_monthly_summary_staff_period'));
      expect(indexNames, contains('idx_variants_product'));

      // Columns check
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

      // Accounts seeded check
      final accounts = await db.accountsDao.getAllAccounts();
      expect(accounts.length, 11, reason: 'Chart of accounts must have exactly 11 system accounts');
      final codes = accounts.map((a) => a.code).toSet();
      expect(codes, containsAll([
        '1000', '1010', '1100', '1200', '2000',
        '3000', '3100', '3200', '4000', '4100', '5000'
      ]));

      // Overtime grace minutes check
      final setting = await db.customSelect(
        "SELECT setting_value FROM attendance_settings WHERE setting_key = 'overtime_grace_minutes'",
      ).getSingleOrNull();
      expect(setting, isNotNull);
      expect(setting!.data['setting_value'], '30');

      await db.close();
    });

    test('b) Upgrades from simulated v79 (without accounting tables) to v80 and creates accounting tables', () async {
      final clientFixture = File('scratch/client_copy.sqlite');
      expect(clientFixture.existsSync(), isTrue, reason: 'scratch/client_copy.sqlite fixture must exist');

      final tempFile = File('scratch/sim_v79_upgrade.sqlite');
      if (tempFile.existsSync()) tempFile.deleteSync();
      clientFixture.copySync(tempFile.path);

      // تحويل النسخة إلى v79 بدون جداول المحاسبة لمحاكاة قاعدة بيانات ترقت إلى v79 من فرع main
      final raw = raw_sqlite.sqlite3.open(tempFile.path);
      try {
        raw.execute('''
          DROP TABLE IF EXISTS monthly_attendance_summary_table;
          DROP TABLE IF EXISTS journal_lines;
          DROP TABLE IF EXISTS journal_entries;
          DROP TABLE IF EXISTS accounts;
          DROP TABLE IF EXISTS equity_transactions;
          DROP TABLE IF EXISTS partners;
          PRAGMA user_version = 79;
        ''');
      } finally {
        raw.dispose();
      }

      // فتحها بـ AppDatabase لترقيتها من 79 إلى 80
      final db = AppDatabase(NativeDatabase(tempFile));
      try {
        await db.customSelect('SELECT 1').get();

        final uvRes = await db.customSelect('PRAGMA user_version').getSingle();
        expect(uvRes.data['user_version'], 80, reason: 'user_version must be upgraded to 80');

        final tablesRes = await db.customSelect("SELECT name FROM sqlite_master WHERE type='table'").get();
        final names = tablesRes.map((r) => r.data['name'] as String).toSet();
        expect(names, contains('accounts'));
        expect(names, contains('journal_entries'));
        expect(names, contains('journal_lines'));
        expect(names, contains('partners'));
        expect(names, contains('equity_transactions'));
        expect(names, contains('monthly_attendance_summary_table'));
        expect(names, contains('product_variants'));

        final accounts = await db.accountsDao.getAllAccounts();
        expect(accounts.length, 11, reason: '11 system accounts must be seeded for v79 upgraded DB');
      } finally {
        await db.close();
        if (tempFile.existsSync()) tempFile.deleteSync();
      }
    });

    test('c) Upgrades from real client database copy (v78 with pre-existing accounting data) with zero row loss', () async {
      final clientFixture = File('scratch/client_copy.sqlite');
      expect(clientFixture.existsSync(), isTrue, reason: 'scratch/client_copy.sqlite fixture must exist');

      final tempFile = File('scratch/client_v80_test.sqlite');
      if (tempFile.existsSync()) tempFile.deleteSync();
      clientFixture.copySync(tempFile.path);

      // فتح نسخة العميل بـ AppDatabase لترقيتها من 78 إلى 80
      final db = AppDatabase(NativeDatabase(tempFile));
      try {
        await db.customSelect('SELECT 1').get();

        // 1. فحص user_version
        final uvRes = await db.customSelect('PRAGMA user_version').getSingle();
        expect(uvRes.data['user_version'], 80, reason: 'Database must upgrade to v80');

        // 2. فحص السلامة الهيكلية PRAGMA integrity_check
        final integrityRes = await db.customSelect('PRAGMA integrity_check').getSingle();
        expect(integrityRes.data['integrity_check'], 'ok', reason: 'Integrity check must return ok');

        // 3. التأكد من سلامة الجداول السابقة وعدم فقدان أي صف
        final accCount = (await db.customSelect('SELECT count(*) as c FROM accounts').getSingle()).data['c'] as int;
        expect(accCount, 12, reason: 'Must preserve all 12 existing client accounts without overwriting');

        final jeCount = (await db.customSelect('SELECT count(*) as c FROM journal_entries').getSingle()).data['c'] as int;
        expect(jeCount, 35, reason: 'Must preserve all 35 journal entries');

        final jlCount = (await db.customSelect('SELECT count(*) as c FROM journal_lines').getSingle()).data['c'] as int;
        expect(jlCount, 70, reason: 'Must preserve all 70 journal lines');

        final masCount = (await db.customSelect('SELECT count(*) as c FROM monthly_attendance_summary_table').getSingle()).data['c'] as int;
        expect(masCount, 33, reason: 'Must preserve all 33 monthly attendance summaries');

        final invCount = (await db.customSelect('SELECT count(*) as c FROM invoices').getSingle()).data['c'] as int;
        expect(invCount, 108, reason: 'Must preserve all 108 client invoices');

        // 4. التحقق من وجود product_variants
        final tablesRes = await db.customSelect("SELECT name FROM sqlite_master WHERE type='table'").get();
        final names = tablesRes.map((r) => r.data['name'] as String).toSet();
        expect(names, contains('product_variants'));

        // 5. التحقق من وجود الأعمدة الجديدة
        Future<List<String>> getColumns(String table) async {
          final info = await db.customSelect('PRAGMA table_info($table)').get();
          return info.map((r) => r.data['name'] as String).toList();
        }

        final bioCols = await getColumns('staff_biometric_mappings');
        expect(bioCols, contains('device_user_name'));

        final advCols = await getColumns('staff_advances');
        expect(advCols, contains('paid_amount'));
        expect(advCols, contains('deduct_on_period'));
      } finally {
        await db.close();
        if (tempFile.existsSync()) tempFile.deleteSync();
      }
    });
  });
}
