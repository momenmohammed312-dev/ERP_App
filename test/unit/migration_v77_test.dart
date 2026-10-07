import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('v76 -> v77 migration preserves existing orders and adds input columns/BOM type', () async {
    final tempDir = Directory.systemTemp.createTempSync('drift_v77_migration_');
    final dbFile = File('${tempDir.path}/test_v76_to_v77.db');
    
    // 1. Create a raw v76 database
    final raw = sqlite3.open(dbFile.path);
    try {
      raw.execute('''
        CREATE TABLE customers (id TEXT PRIMARY KEY, name TEXT);
        CREATE TABLE ledger_transactions (id INTEGER PRIMARY KEY, type TEXT, amount REAL, is_opening_balance INTEGER, customer_id TEXT);
        CREATE TABLE attendance_sync_logs(id INTEGER PRIMARY KEY, device_sn TEXT, last_sync_time TEXT);
        CREATE TABLE sync_queue(id INTEGER PRIMARY KEY, operation TEXT, table_name TEXT, payload TEXT, created_at TEXT, retry_count INTEGER);
        CREATE TABLE products (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          quantity REAL DEFAULT 0,
          price REAL DEFAULT 0
        );
      ''');

      raw.execute('''
        CREATE TABLE bill_of_materials (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          finished_product_id INTEGER NOT NULL REFERENCES products(id),
          name TEXT NOT NULL
        );
      ''');

      raw.execute('''
        CREATE TABLE manufacturing_orders (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          order_number TEXT NOT NULL UNIQUE,
          bom_id INTEGER NOT NULL REFERENCES bill_of_materials(id),
          finished_product_id INTEGER NOT NULL REFERENCES products(id),
          planned_quantity REAL NOT NULL,
          order_type TEXT DEFAULT 'internal',
          status TEXT DEFAULT 'planned'
        );
      ''');

      raw.execute('''
        INSERT INTO products (id, name, quantity, price)
        VALUES (1, 'Finished Chair', 10, 150.0);
      ''');

      raw.execute('''
        INSERT INTO bill_of_materials (id, finished_product_id, name)
        VALUES (1, 1, 'Standard Chair BOM');
      ''');

      raw.execute('''
        INSERT INTO manufacturing_orders (id, order_number, bom_id, finished_product_id, planned_quantity, status)
        VALUES (1, 'MO-76-TEST', 1, 1, 10.0, 'completed');
      ''');

      raw.execute('PRAGMA user_version = 76;');
    } finally {
      raw.dispose();
    }

    // 2. Open via AppDatabase -> triggers onUpgrade from 76 to 77
    final db = AppDatabase(NativeDatabase(dbFile));
    addTearDown(db.close);

    final versionRow = await db.customSelect('PRAGMA user_version').getSingle();
    final version = versionRow.read<int>('user_version');
    expect(version, 77, reason: 'Database upgraded from 76 to 77');

    // 3. Assert pre-existing rows survived and new columns are null
    final moRow = await db.customSelect('SELECT * FROM manufacturing_orders WHERE id = 1').getSingle();
    expect(moRow.read<String>('order_number'), 'MO-76-TEST');
    expect(moRow.read<int?>('input_product_id'), isNull);
    expect(moRow.read<String?>('input_color'), isNull);
    expect(moRow.read<String?>('input_size'), isNull);
    expect(moRow.read<double?>('input_quantity'), isNull);

    final bomRow = await db.customSelect('SELECT * FROM bill_of_materials WHERE id = 1').getSingle();
    expect(bomRow.read<String>('name'), 'Standard Chair BOM');
    expect(bomRow.read<String?>('type'), isNull);

    // 4. Test idempotency
    await db.close();

    final rawReopen = sqlite3.open(dbFile.path);
    rawReopen.execute('PRAGMA user_version = 76;');
    rawReopen.dispose();

    final dbSecond = AppDatabase(NativeDatabase(dbFile));
    addTearDown(dbSecond.close);

    final secondVersionRow = await dbSecond.customSelect('PRAGMA user_version').getSingle();
    expect(secondVersionRow.read<int>('user_version'), 77);
  });
}
