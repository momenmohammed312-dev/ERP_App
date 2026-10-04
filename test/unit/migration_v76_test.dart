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

  test('v75 → v76 migration preserves existing Phase A orders and scrap, and adds Phase B1 tables', () async {
    final tempDir = Directory.systemTemp.createTempSync('drift_v76_migration_');
    final dbFile = File('${tempDir.path}/test_v75_to_v76.db');
    addTearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    // 1. Build a raw SQLite DB at schema version 75 with Phase A data
    final raw = sqlite3.open(dbFile.path);
    try {
      raw.execute('PRAGMA foreign_keys = ON');

      // Create products table
      raw.execute('''
        CREATE TABLE products (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          quantity INTEGER NOT NULL,
          price REAL NOT NULL,
          status TEXT DEFAULT 'Active',
          unit TEXT,
          category TEXT,
          barcode TEXT,
          carton_quantity INTEGER,
          carton_price REAL,
          cost_price REAL,
          min_stock_level INTEGER DEFAULT 0,
          barneka INTEGER DEFAULT 0,
          product_type TEXT,
          sync_id TEXT,
          created_at INTEGER,
          updated_at INTEGER
        );
      ''');

      // Create customers table
      raw.execute('''
        CREATE TABLE customers (
          id TEXT PRIMARY KEY,
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
        );
      ''');

      // Create invoices table
      raw.execute('''
        CREATE TABLE invoices (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          invoice_number TEXT,
          customer_id TEXT,
          customer_name TEXT,
          customer_contact TEXT,
          customer_address TEXT,
          payment_method TEXT,
          total_amount REAL DEFAULT 0,
          paid_amount REAL DEFAULT 0,
          date INTEGER,
          status TEXT DEFAULT 'pending',
          voided_at INTEGER,
          void_reason TEXT,
          void_by TEXT,
          cash_amount REAL DEFAULT 0,
          card_amount REAL DEFAULT 0,
          credit_amount REAL DEFAULT 0,
          shipment_id INTEGER,
          sync_id TEXT,
          created_at INTEGER,
          updated_at INTEGER
        );
      ''');

      // Create Phase A tables
      raw.execute('''
        CREATE TABLE bill_of_materials (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          finished_product_id INTEGER NOT NULL REFERENCES products(id),
          code TEXT,
          name TEXT NOT NULL,
          yield_quantity REAL DEFAULT 1,
          waste_percentage REAL DEFAULT 0,
          status TEXT DEFAULT 'Active',
          notes TEXT,
          created_at INTEGER,
          updated_at INTEGER
        );
      ''');

      raw.execute('''
        CREATE TABLE bom_items (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          bom_id INTEGER NOT NULL REFERENCES bill_of_materials(id) ON DELETE CASCADE,
          raw_material_product_id INTEGER NOT NULL REFERENCES products(id),
          quantity_required REAL NOT NULL,
          unit TEXT,
          waste_percentage_override REAL,
          sort_order INTEGER DEFAULT 0,
          notes TEXT
        );
      ''');

      raw.execute('''
        CREATE TABLE manufacturing_orders (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          order_number TEXT NOT NULL UNIQUE,
          bom_id INTEGER NOT NULL REFERENCES bill_of_materials(id),
          finished_product_id INTEGER NOT NULL REFERENCES products(id),
          planned_quantity REAL NOT NULL,
          produced_quantity REAL DEFAULT 0,
          status TEXT DEFAULT 'planned',
          planned_date INTEGER,
          started_at INTEGER,
          completed_at INTEGER,
          cancelled_at INTEGER,
          cancel_reason TEXT,
          notes TEXT,
          created_by TEXT,
          created_at INTEGER,
          updated_at INTEGER
        );
      ''');

      raw.execute('''
        CREATE TABLE manufacturing_scrap (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          manufacturing_order_id INTEGER NOT NULL REFERENCES manufacturing_orders(id) ON DELETE CASCADE,
          product_id INTEGER NOT NULL REFERENCES products(id),
          bom_item_id INTEGER REFERENCES bom_items(id) ON DELETE SET NULL,
          quantity REAL NOT NULL,
          reason TEXT NOT NULL,
          responsible_party TEXT NOT NULL,
          disposition_note TEXT,
          performed_by TEXT,
          created_at INTEGER
        );
      ''');

      // Seed a finished product, customer, BOM, order, and scrap row
      raw.execute('''
        INSERT INTO products (id, name, quantity, price, product_type)
        VALUES (1, 'Finished Chair', 10, 150.0, 'finished_product');
      ''');
      raw.execute('''
        INSERT INTO products (id, name, quantity, price, product_type)
        VALUES (2, 'Wood Plank', 50, 20.0, 'raw_material');
      ''');

      raw.execute('''
        INSERT INTO bill_of_materials (id, finished_product_id, name, yield_quantity)
        VALUES (1, 1, 'Standard Chair BOM', 1.0);
      ''');
      raw.execute('''
        INSERT INTO bom_items (id, bom_id, raw_material_product_id, quantity_required)
        VALUES (1, 1, 2, 4.0);
      ''');

      raw.execute('''
        INSERT INTO manufacturing_orders (id, order_number, bom_id, finished_product_id, planned_quantity, status)
        VALUES (1, 'MO-PHASE-A-001', 1, 1, 10.0, 'completed');
      ''');

      raw.execute('''
        INSERT INTO manufacturing_scrap (id, manufacturing_order_id, product_id, quantity, reason, responsible_party)
        VALUES (1, 1, 2, 1.0, 'process_error', 'Worker A');
      ''');

      // Stamp version at 75
      raw.execute('PRAGMA user_version = 75;');
    } finally {
      raw.dispose();
    }

    // 2. Open via AppDatabase — triggers onUpgrade from 75 to 76
    final db = AppDatabase(NativeDatabase(dbFile));
    addTearDown(db.close);

    // Force open
    final versionRow = await db.customSelect('PRAGMA user_version').getSingle();
    final version = versionRow.read<int>('user_version');
    expect(version, 76, reason: 'Database upgraded from 75 to 76');

    // 3. Assert pre-existing rows survived with defaults populated
    final moRow = await db.customSelect('SELECT * FROM manufacturing_orders WHERE id = 1').getSingle();
    expect(moRow.read<String>('order_number'), 'MO-PHASE-A-001');
    expect(moRow.read<String>('order_type'), 'internal');
    expect(moRow.read<String>('pricing_mode'), 'inclusive');
    expect(moRow.read<String>('scrap_policy'), 'customer_bears');
    expect(moRow.read<String>('delivery_status'), 'undelivered');
    expect(moRow.read<double>('piece_unit_value'), 0.0);
    expect(moRow.read<double>('service_unit_price'), 0.0);
    expect(moRow.read<int?>('invoice_id'), isNull);
    expect(moRow.read<String?>('customer_id'), isNull);

    final scrapRow = await db.customSelect('SELECT * FROM manufacturing_scrap WHERE id = 1').getSingle();
    expect(scrapRow.read<String>('reason'), 'process_error');
    expect(scrapRow.read<String>('responsible_party'), 'Worker A');
    expect(scrapRow.read<String>('fault_party'), 'factory');
    expect(scrapRow.read<String?>('compensation_action'), isNull);
    expect(scrapRow.read<double>('compensation_amount'), 0.0);

    // 4. Assert new Phase B1 tables exist
    final tablesQuery = await db.customSelect("SELECT name FROM sqlite_master WHERE type='table'").get();
    final tableNames = tablesQuery.map((r) => r.read<String>('name')).toSet();

    expect(tableNames, contains('customer_material_receipts'));
    expect(tableNames, contains('customer_material_receipt_items'));
    expect(tableNames, contains('customer_stock_balances'));
    expect(tableNames, contains('customer_stock_movements'));
    expect(tableNames, contains('manufacturing_deliveries'));
    expect(tableNames, contains('manufacturing_delivery_items'));

    // 5. Test idempotency: reopen after winding back PRAGMA user_version to 75
    await db.close();

    final rawReopen = sqlite3.open(dbFile.path);
    rawReopen.execute('PRAGMA user_version = 75;');
    rawReopen.dispose();

    final dbSecond = AppDatabase(NativeDatabase(dbFile));
    addTearDown(dbSecond.close);

    final secondVersionRow = await dbSecond.customSelect('PRAGMA user_version').getSingle();
    expect(secondVersionRow.read<int>('user_version'), 76);

    final moRowAfterReRun = await dbSecond.customSelect('SELECT * FROM manufacturing_orders WHERE id = 1').getSingle();
    expect(moRowAfterReRun.read<String>('order_number'), 'MO-PHASE-A-001');
    expect(moRowAfterReRun.read<String>('order_type'), 'internal');
  });
}
