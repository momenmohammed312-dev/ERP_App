import 'dart:io';
import 'package:drift/drift.dart';
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
        (MethodCall methodCall) async {
          final dir = Directory.systemTemp.createTempSync('drift_sync_test_');
          return dir.path;
        },
      );

  test('migration v50 → v54 adds sync columns, sync_queue and backfills sync_id',
      () async {
    final dbPath = Directory.systemTemp.path +
        '/pos_sync_migration_${DateTime.now().millisecondsSinceEpoch}.db';
    final file = File(dbPath);

    // Minimal v50 schema (pre-sync foundation) mirroring the existing migration
    // test scaffold, which is proven to open successfully via AppDatabase.
    final raw = sqlite3.open(dbPath);
    try {
      raw.execute('PRAGMA foreign_keys = ON');

      raw.execute('''
        CREATE TABLE suppliers (
          id TEXT NOT NULL PRIMARY KEY,
          name TEXT NOT NULL,
          phone TEXT,
          address TEXT,
          opening_balance REAL DEFAULT 0.0,
          created_at INTEGER,
          status TEXT DEFAULT 'Active'
        )
      ''');

      raw.execute('''
        CREATE TABLE customers (
          id TEXT NOT NULL PRIMARY KEY,
          name TEXT NOT NULL,
          phone TEXT,
          address TEXT,
          gstin_number TEXT,
          email TEXT,
          opening_balance REAL DEFAULT 0.0,
          total_debt REAL DEFAULT 0.0,
          total_paid REAL DEFAULT 0.0,
          created_at INTEGER,
          updated_at INTEGER,
          notes TEXT,
          is_active INTEGER DEFAULT 1,
          status TEXT DEFAULT 'Active'
        )
      ''');

      raw.execute('''
        CREATE TABLE products (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          price REAL NOT NULL,
          quantity INTEGER NOT NULL DEFAULT 0,
          barneka INTEGER NOT NULL DEFAULT 0,
          cost_price REAL,
          min_stock_level INTEGER DEFAULT 0,
          unit TEXT,
          category TEXT,
          barcode TEXT,
          status TEXT DEFAULT 'Active'
        )
      ''');

      raw.execute('''
        CREATE TABLE invoices (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          invoice_number TEXT,
          customer_id TEXT,
          customer_name TEXT,
          customer_contact TEXT,
          customer_address TEXT,
          payment_method TEXT,
          total_amount REAL DEFAULT 0.0,
          paid_amount REAL DEFAULT 0.0,
          date INTEGER,
          status TEXT DEFAULT 'pending',
          voided_at INTEGER,
          void_reason TEXT,
          voided_by TEXT,
          cash_amount REAL DEFAULT 0.0,
          card_amount REAL DEFAULT 0.0,
          credit_amount REAL DEFAULT 0.0,
          sync_id TEXT,
          created_at INTEGER,
          updated_at INTEGER
        )
      ''');

      raw.execute('''
        CREATE TABLE invoice_items (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          invoice_id INTEGER NOT NULL REFERENCES invoices(id),
          product_id INTEGER NOT NULL REFERENCES products(id),
          quantity INTEGER DEFAULT 1,
          ctn INTEGER,
          price REAL NOT NULL,
          discount REAL DEFAULT 0.0,
          commission REAL DEFAULT 0.0,
          unit_cost_at_time REAL,
          sync_id TEXT,
          created_at INTEGER,
          updated_at INTEGER
        )
      ''');

      raw.execute('''
        CREATE TABLE cash_sessions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          opened_by TEXT,
          opened_at INTEGER NOT NULL,
          closed_at INTEGER,
          status TEXT NOT NULL DEFAULT 'closed',
          opening_balance REAL NOT NULL DEFAULT 0.0,
          closing_balance REAL,
          closing_cash REAL,
          difference REAL,
          total_sales REAL NOT NULL DEFAULT 0.0,
          total_expenses REAL NOT NULL DEFAULT 0.0,
          notes TEXT
        )
      ''');

      raw.execute('PRAGMA user_version = 50');

      raw.execute(
        "INSERT INTO suppliers (id, name) VALUES ('sup-1', 'مورّد اختبار')",
      );
      raw.execute(
        "INSERT INTO customers (id, name) VALUES ('cust-1', 'عميل اختبار')",
      );
      raw.execute(
        "INSERT INTO products (name, price, quantity) VALUES ('طماطم', 5.0, 100)",
      );
      raw.execute(
        "INSERT INTO invoices (customer_id, customer_name, total_amount, paid_amount, status, date) "
        "VALUES ('cust-1', 'عميل اختبار', 50.0, 50.0, 'completed', 1767218400)",
      );
      raw.execute(
        "INSERT INTO invoice_items (invoice_id, product_id, quantity, price) "
        "VALUES (1, 1, 10, 5.0)",
      );
    } finally {
      raw.dispose();
    }

    final db = AppDatabase(NativeDatabase(file));
    try {
      final versionRow = await db.customSelect('PRAGMA user_version').getSingle();
      final version = versionRow.read<int>('user_version');
      expect(version, 54, reason: 'schema should be upgraded to 54');

      Future<List<String>> columnNames(String table) async {
        final rows = await db.customSelect('PRAGMA table_info($table)').get();
        return rows.map((r) => r.read<String>('name')).toList();
      }

      // v53 — sync columns on the three int-PK tables.
      for (final table in ['products', 'invoices', 'invoice_items']) {
        final cols = await columnNames(table);
        expect(cols, contains('sync_id'), reason: '$table must have sync_id');
        expect(cols, contains('created_at'), reason: '$table must have created_at');
        expect(cols, contains('updated_at'), reason: '$table must have updated_at');
      }

      // v53 — sync_queue table exists.
      final queueTables = await db.customSelect(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='sync_queue'",
      ).get();
      expect(queueTables.isNotEmpty, isTrue,
          reason: 'sync_queue table must exist after v53 migration');

      // v54 — device_name column on sync_queue.
      final queueCols = await columnNames('sync_queue');
      expect(queueCols, contains('device_name'),
          reason: 'sync_queue must have device_name after v54 migration');

      // v53 — backfill populated sync_id for existing rows.
      Future<bool> allSynced(String table, String idExpr) async {
        final rows = await db.customSelect(
          'SELECT sync_id FROM $table WHERE $idExpr',
        ).get();
        if (rows.isEmpty) return false;
        return rows.every(
          (r) => r.read<String?>('sync_id') != null &&
              (r.read<String?>('sync_id') ?? '').isNotEmpty,
        );
      }

      expect(await allSynced('products', "id=1"), isTrue,
          reason: 'existing products must get a sync_id backfill');
      expect(await allSynced('invoices', "id=1"), isTrue,
          reason: 'existing invoices must get a sync_id backfill');
      expect(await allSynced('invoice_items', "id=1"), isTrue,
          reason: 'existing invoice_items must get a sync_id backfill');

      // Existing data survived the upgrade.
      final productRows = await db.customSelect(
        "SELECT name FROM products WHERE id=1",
      ).get();
      expect(productRows.single.read<String>('name'), 'طماطم');
    } finally {
      await db.close();
      if (file.existsSync()) {
        file.deleteSync();
      }
    }
  });
}
