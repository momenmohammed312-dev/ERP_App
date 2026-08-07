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
          final dir = Directory.systemTemp.createTempSync('drift_test_');
          return dir.path;
        },
      );

  test('migration v50 → v52 creates vegetable tables and new columns', () async {
    final dbPath =
        Directory.systemTemp.path + '/pos_migration_test_${DateTime.now().millisecondsSinceEpoch}.db';
    final file = File(dbPath);

    // Build a minimal v50 schema that existed before vegetable shipments were added.
    final raw = sqlite3.open(dbPath);
    try {
      raw.execute('PRAGMA foreign_keys = ON');

      // Core tables that existed at v50.
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

      // Set schema version to 50 — the last version before vegetable shipments.
      raw.execute('PRAGMA user_version = 50');

      // Insert representative v50 data that must survive the upgrade.
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
      raw.execute(
        "INSERT INTO cash_sessions (opened_by, opened_at, status, opening_balance) "
        "VALUES ('admin', 1767218400, 'closed', 1000.0)",
      );
    } finally {
      raw.dispose();
    }

    // Open the same file via AppDatabase — schemaVersion is 52, so onUpgrade runs.
    final db = AppDatabase(NativeDatabase(file));
    try {
      // Verify schema was upgraded to 52.
      final versionRow = await db.customSelect('PRAGMA user_version').getSingle();
      final version = versionRow.read<int>('user_version');
      expect(version, 52, reason: 'schema should be upgraded to 52');

      // Verify vegetable_shipments table was created by v51 migration.
      final shipmentTables = await db.customSelect(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='vegetable_shipments'",
      ).get();
      expect(shipmentTables.isNotEmpty, isTrue,
          reason: 'vegetable_shipments table must exist after v51 migration');

      // Verify empty_barnika_tracking table was created by v51 migration.
      final barnikaTables = await db.customSelect(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='empty_barnika_tracking'",
      ).get();
      expect(barnikaTables.isNotEmpty, isTrue,
          reason: 'empty_barnika_tracking table must exist after v51 migration');

      // Verify invoices.shipment_id column was added by v51 migration.
      final invoiceCols = await db.customSelect(
        "PRAGMA table_info(invoices)",
      ).get();
      final invoiceColNames = invoiceCols
          .map((r) => r.read<String>('name'))
          .toList();
      expect(invoiceColNames, contains('shipment_id'),
          reason: 'invoices must have shipment_id after v51 migration');

      // Verify invoice_items.shipment_id column was added by v51 migration.
      final itemCols = await db.customSelect(
        "PRAGMA table_info(invoice_items)",
      ).get();
      final itemColNames = itemCols
          .map((r) => r.read<String>('name'))
          .toList();
      expect(itemColNames, contains('shipment_id'),
          reason: 'invoice_items must have shipment_id after v51 migration');

      // Verify cash_sessions.settlement_amount was added by v52 migration.
      final sessionCols = await db.customSelect(
        "PRAGMA table_info(cash_sessions)",
      ).get();
      final sessionColNames = sessionCols
          .map((r) => r.read<String>('name'))
          .toList();
      expect(sessionColNames, contains('settlement_amount'),
          reason: 'cash_sessions must have settlement_amount after v52 migration');

      // Verify v50 data is preserved.
      final supplierRows = await db.customSelect(
        "SELECT name FROM suppliers WHERE id='sup-1'",
      ).get();
      expect(supplierRows.isNotEmpty, isTrue,
          reason: 'supplier data must survive migration');
      expect(supplierRows.first.read<String>('name'), 'مورّد اختبار');

      final customerRows = await db.customSelect(
        "SELECT name FROM customers WHERE id='cust-1'",
      ).get();
      expect(customerRows.isNotEmpty, isTrue,
          reason: 'customer data must survive migration');

      final invoiceRows = await db.customSelect(
        "SELECT total_amount FROM invoices WHERE id=1",
      ).get();
      expect(invoiceRows.isNotEmpty, isTrue,
          reason: 'invoice data must survive migration');
      expect(invoiceRows.first.read<double>('total_amount'), 50.0);

      final itemRows = await db.customSelect(
        "SELECT quantity FROM invoice_items WHERE id=1",
      ).get();
      expect(itemRows.isNotEmpty, isTrue,
          reason: 'invoice item data must survive migration');
      expect(itemRows.first.read<int>('quantity'), 10);
    } finally {
      await db.close();
      if (file.existsSync()) {
        file.deleteSync();
      }
    }
  });
}
