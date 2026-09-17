import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import 'package:pos_offline_desktop/core/database/app_database.dart';

/// Verifies the v65 → v66 upgrade for Weekly Payroll columns:
/// existing staff rows survive, default to 'monthly', weekly_salary NULL.
void main() {
  test('migration v65 → v69 keeps staff data and adds new columns',
      () async {
    final dir = await Directory.systemTemp.createTemp('v66mig');
    final file = File('${dir.path}/v65.db');

    // Minimal v65 staff_table (WITHOUT the new columns).
    final raw = sqlite3.sqlite3.open(file.path);
    try {
      raw.execute('''
        CREATE TABLE staff_table (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          staff_id TEXT NOT NULL UNIQUE,
          name TEXT NOT NULL,
          position TEXT NOT NULL,
          employment_type TEXT NOT NULL,
          basic_salary REAL NOT NULL,
          hire_date INTEGER NOT NULL,
          status TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          is_active INTEGER NOT NULL DEFAULT 1
        )
      ''');
      raw.execute(
        "INSERT INTO staff_table (staff_id, name, position, employment_type, basic_salary, hire_date, status, created_at, updated_at) "
        "VALUES ('STAFF0001', 'موظف قديم', 'Cashier', 'full_time', 9000.0, 1700000000, 'active', 1700000000, 1700000000)",
      );
      raw.execute('PRAGMA user_version = 65');
      // Minimal customers table with TEXT status so beforeOpen fixes
      // become no-ops instead of failing the open.
      raw.execute('''
        CREATE TABLE customers (
          id TEXT NOT NULL PRIMARY KEY,
          name TEXT NOT NULL,
          status TEXT DEFAULT 'Active'
        )
      ''');
    } finally {
      raw.dispose();
    }

    // Open via AppDatabase — onUpgrade must run v66..current (v71).
    final db = AppDatabase(NativeDatabase(file));
    try {
      final versionRow =
          await db.customSelect('PRAGMA user_version').getSingle();
      expect(versionRow.read<int>('user_version'), 71,
          reason: 'schema should be upgraded to current (71)');

      final cols = await db.customSelect(
        "SELECT name FROM pragma_table_info('staff_table')",
      ).get();
      final names = cols.map((r) => r.read<String>('name')).toSet();
      expect(names.contains('pay_frequency'), isTrue);
      expect(names.contains('weekly_salary'), isTrue);

      final advCols = await db.customSelect(
        "SELECT name FROM pragma_table_info('staff_advances')",
      ).get();
      final advNames =
          advCols.map((r) => r.read<String>('name')).toSet();
      expect(advNames.contains('paid_amount'), isTrue,
          reason: 'v68 must add paid_amount');
      expect(advNames.contains('deduct_on_period'), isTrue,
          reason: 'v69 must add deduct_on_period');

      // Pre-existing row survives with safe defaults.
      final staff = await db.staffManagementDao.getStaffById('STAFF0001');
      expect(staff, isNotNull);
      expect(staff!.name, 'موظف قديم');
      expect(staff.basicSalary, 9000.0);
      expect(staff.payFrequency, 'monthly',
          reason: 'existing staff default to monthly');
      expect(staff.weeklySalary, isNull);
    } finally {
      await db.close();
      await dir.delete(recursive: true);
    }
  });
}
