import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:encrypt/encrypt.dart' as encrypt_pkg;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/tables/expenses_table.dart';
import 'package:pos_offline_desktop/core/database/tables/supplier_table.dart';
import 'package:pos_offline_desktop/core/database/tables/vegetable_shipments_table.dart';
import 'package:pos_offline_desktop/core/models/user_model.dart';
import 'package:pos_offline_desktop/core/services/backup_service.dart';
import 'package:pos_offline_desktop/core/utils/app_utils.dart';
import 'package:sqlite3/sqlite3.dart' as raw_sqlite;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('migration_v82_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async => tempDir.path,
    );
  });

  tearDownAll(() async {
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  User adminUser() => User(
        id: 1,
        username: 'admin',
        passwordHash: 'dummy',
        fullName: 'Admin User',
        role: UserRole.admin,
        createdAt: DateTime.now(),
      );

  Future<List<String>> columnNames(AppDatabase db, String table) async {
    final rows = await db.customSelect('PRAGMA table_info($table)').get();
    return rows.map((r) => r.read<String>('name')).toList();
  }

  group('Schema v82 — Vegetable Market Overhaul', () {
    test('fresh DB starts at schemaVersion 82 with all v82 columns and indexes',
        () async {
      final db = AppDatabase(NativeDatabase.memory());
      try {
        final uvRow =
            await db.customSelect('PRAGMA user_version').getSingle();
        expect(uvRow.read<int>('user_version'), 82);
        expect(db.schemaVersion, 82);

        final shipmentCols = await columnNames(db, 'vegetable_shipments');
        expect(
          shipmentCols,
          containsAll(['status', 'topping_count', 'topping_reason', 'closed_at']),
        );

        final expenseCols = await columnNames(db, 'expenses');
        expect(expenseCols, containsAll(['shipment_id', 'scope']));

        final barnikaCols = await columnNames(db, 'empty_barnika_tracking');
        expect(barnikaCols, contains('invoice_id'));

        final idxRows = await db
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type='index'",
            )
            .get();
        final idxNames = idxRows.map((r) => r.read<String>('name')).toSet();
        expect(
          idxNames,
          containsAll([
            'idx_expenses_shipment',
            'idx_empty_barnika_invoice',
            'idx_veg_shipments_status',
          ]),
        );

        // Suppliers table stays clean until an unknown-supplier shipment is created.
        expect(await db.supplierDao.getAllSuppliers(), isEmpty);
      } finally {
        await db.close();
      }
    });

    test(
        'insertShipment auto-creates unknown_supplier when supplierId is unknown_supplier or blank',
        () async {
      final db = AppDatabase(NativeDatabase.memory());
      try {
        final id = await db.vegetableShipmentDao.insertShipment(
          VegetableShipmentsCompanion.insert(
            supplierId: DefaultSupplier.unknownId,
            shipmentNumber: 'SHP-UNK-1',
            pricingMode: ShipmentPricingMode.commission,
            totalBarnikaCount: 50,
            commissionPercentage: const Value(10.0),
            totalCost: 0.0,
            barnikaRemainingCount: 50,
          ),
        );

        final shipment = await db.vegetableShipmentDao.getById(id);
        expect(shipment, isNotNull);
        expect(shipment!.supplierId, DefaultSupplier.unknownId);
        expect(shipment.status, VegetableShipmentStatus.open);
        expect(shipment.toppingCount, 0);
        expect(shipment.toppingReason, isNull);
        expect(shipment.closedAt, isNull);

        final supplier =
            await db.supplierDao.getSupplierById(DefaultSupplier.unknownId);
        expect(supplier, isNotNull);
        expect(supplier!.name, DefaultSupplier.unknownName);
      } finally {
        await db.close();
      }
    });

    test('upgrade v81 -> v82 preserves existing data with safe defaults and is idempotent',
        () async {
      final dbFile = File(
        '${tempDir.path}/upgrade_v81_to_v82_${DateTime.now().microsecondsSinceEpoch}.db',
      );

      // Initialize full DB first, then downgrade schema tables to v81 layout
      // (without the 7 new columns) and stamp PRAGMA user_version = 81.
      final setupDb = AppDatabase(NativeDatabase(dbFile));
      await setupDb.customSelect('SELECT 1').get();
      await setupDb.close();

      final raw = raw_sqlite.sqlite3.open(dbFile.path);
      try {
        raw.execute('PRAGMA foreign_keys = OFF');
        raw.execute('DROP TABLE IF EXISTS empty_barnika_tracking');
        raw.execute('DROP TABLE IF EXISTS expenses');
        raw.execute('DROP TABLE IF EXISTS vegetable_shipments');

        raw.execute('''
          CREATE TABLE vegetable_shipments (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            supplier_id TEXT NOT NULL REFERENCES suppliers(id),
            shipment_number TEXT NOT NULL UNIQUE,
            date INTEGER NOT NULL,
            pricing_mode TEXT NOT NULL,
            total_barnika_count INTEGER NOT NULL,
            cost_price_per_barnika REAL,
            lump_sum_cost REAL,
            commission_percentage REAL,
            container_price REAL,
            total_cost REAL NOT NULL,
            barnika_sold_count INTEGER NOT NULL DEFAULT 0,
            barnika_remaining_count INTEGER NOT NULL,
            notes TEXT
          )
        ''');

        raw.execute('''
          CREATE TABLE expenses (
            id TEXT NOT NULL PRIMARY KEY,
            description TEXT NOT NULL,
            amount REAL NOT NULL,
            date INTEGER NOT NULL,
            category TEXT NOT NULL,
            payment_method TEXT NOT NULL DEFAULT 'cash',
            receipt_number TEXT,
            supplier_id TEXT,
            notes TEXT,
            created_at INTEGER NOT NULL,
            user_id TEXT,
            day_id TEXT
          )
        ''');

        raw.execute('''
          CREATE TABLE empty_barnika_tracking (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            customer_id TEXT NOT NULL REFERENCES customers(id),
            date_out INTEGER NOT NULL,
            quantity_out INTEGER NOT NULL,
            date_returned INTEGER,
            quantity_returned INTEGER NOT NULL DEFAULT 0,
            status TEXT NOT NULL DEFAULT 'outstanding'
          )
        ''');

        raw.execute(
          "INSERT INTO suppliers (id, name, status) VALUES ('sup-v81', 'مورد شحنة 81', 'Active')",
        );
        raw.execute(
          "INSERT INTO customers (id, name, status) VALUES ('cust-v81', 'زبون 81', 'Active')",
        );
        raw.execute(
          "INSERT INTO vegetable_shipments "
          "(id, supplier_id, shipment_number, date, pricing_mode, total_barnika_count, commission_percentage, total_cost, barnika_sold_count, barnika_remaining_count) "
          "VALUES (10, 'sup-v81', 'SHP-V81', 1767218400, 'commission', 100, 8.0, 0.0, 25, 75)",
        );
        raw.execute(
          "INSERT INTO expenses (id, description, amount, date, category, payment_method, created_at) "
          "VALUES ('exp-v81', 'شاي وضيافة', 45.0, 1767218400, 'ضيافة', 'cash', 1767218400)",
        );
        raw.execute(
          "INSERT INTO empty_barnika_tracking (id, customer_id, date_out, quantity_out, quantity_returned, status) "
          "VALUES (5, 'cust-v81', 1767218400, 12, 2, 'partial')",
        );
        raw.execute('PRAGMA user_version = 81');
      } finally {
        raw.dispose();
      }

      // Open with AppDatabase — runs onUpgrade(81, 82)
      final upgradedDb = AppDatabase(NativeDatabase(dbFile));
      try {
        final uvRow =
            await upgradedDb.customSelect('PRAGMA user_version').getSingle();
        expect(uvRow.read<int>('user_version'), 82);

        final shipment = await upgradedDb.vegetableShipmentDao.getById(10);
        expect(shipment, isNotNull);
        expect(shipment!.shipmentNumber, 'SHP-V81');
        expect(shipment.barnikaSoldCount, 25);
        expect(shipment.barnikaRemainingCount, 75);
        expect(shipment.status, VegetableShipmentStatus.open);
        expect(shipment.toppingCount, 0);
        expect(shipment.toppingReason, isNull);
        expect(shipment.closedAt, isNull);

        final expense = await upgradedDb.expenseDao.getExpenseById('exp-v81');
        expect(expense, isNotNull);
        expect(expense!.amount, 45.0);
        expect(expense.scope, ExpenseScope.shop);
        expect(expense.shipmentId, isNull);

        final barnika = await upgradedDb.emptyBarnikaTrackingDao.getById(5);
        expect(barnika, isNotNull);
        expect(barnika!.quantityOut, 12);
        expect(barnika.quantityReturned, 2);
        expect(barnika.invoiceId, isNull);

        final migrationRows = await upgradedDb
            .customSelect(
              "SELECT status FROM _migration_log WHERE step = 'v82_vegetable_market_overhaul'",
            )
            .get();
        expect(migrationRows, isNotEmpty);
        expect(migrationRows.last.read<String>('status'), 'completed');
      } finally {
        await upgradedDb.close();
      }

      // Re-open to verify idempotency.
      final reopenedDb = AppDatabase(NativeDatabase(dbFile));
      try {
        final uvRow =
            await reopenedDb.customSelect('PRAGMA user_version').getSingle();
        expect(uvRow.read<int>('user_version'), 82);
        final shipment = await reopenedDb.vegetableShipmentDao.getById(10);
        expect(shipment?.status, VegetableShipmentStatus.open);
        expect(shipment?.toppingCount, 0);
      } finally {
        await reopenedDb.close();
      }
    });

    test('BackupService round-trips v82 fields and restores pre-v82 backups safely',
        () async {
      final db = AppDatabase(NativeDatabase.memory());
      try {
        await db.customerDao.insertCustomer(
          CustomersCompanion.insert(id: 'cust-bk', name: 'عميل نسخ احتياطي'),
        );
        final invoiceId = await db.into(db.invoices).insert(
              InvoicesCompanion.insert(
                invoiceNumber: const Value('INV-V82-1'),
                customerId: const Value('cust-bk'),
                customerName: const Value('عميل نسخ احتياطي'),
                totalAmount: const Value(500.0),
                paidAmount: const Value(500.0),
                status: const Value('paid'),
              ),
            );
        final shipmentId = await db.vegetableShipmentDao.insertShipment(
          VegetableShipmentsCompanion.insert(
            supplierId: DefaultSupplier.unknownId,
            shipmentNumber: 'SHP-BK-1',
            pricingMode: ShipmentPricingMode.commission,
            totalBarnikaCount: 40,
            commissionPercentage: const Value(10.0),
            totalCost: 0.0,
            barnikaRemainingCount: 38,
            status: const Value(VegetableShipmentStatus.closed),
            toppingCount: const Value(2),
            toppingReason: const Value('تكميل وزن 40 برنيكة'),
            closedAt: Value(DateTime(2026, 11, 13, 18, 0)),
          ),
        );
        await db.expenseDao.insertExpense(
          ExpensesCompanion.insert(
            id: 'tmp',
            description: 'نولون عربية',
            amount: 350.0,
            category: 'نولون',
            shipmentId: Value(shipmentId),
            scope: const Value(ExpenseScope.shipment),
          ),
        );
        await db.emptyBarnikaTrackingDao.insertRecord(
          EmptyBarnikaTrackingCompanion.insert(
            customerId: 'cust-bk',
            dateOut: DateTime(2026, 11, 13),
            quantityOut: 10,
            invoiceId: Value(invoiceId),
          ),
        );

        final backupService = BackupService(db);
        final backupInfo = await backupService.createBackup(
          adminUser(),
          description: 'v82 roundtrip test',
        );

        // Wipe and restore into a fresh DB
        final restoredDb = AppDatabase(NativeDatabase.memory());
        try {
          await BackupService(restoredDb)
              .restoreBackup(adminUser(), backupInfo.filename);

          final shipments = await restoredDb.vegetableShipmentDao.getAll();
          expect(shipments, hasLength(1));
          expect(shipments.single.status, VegetableShipmentStatus.closed);
          expect(shipments.single.toppingCount, 2);
          expect(shipments.single.toppingReason, 'تكميل وزن 40 برنيكة');
          expect(shipments.single.closedAt, isNotNull);

          final shipExpenses =
              await restoredDb.expenseDao.getExpensesByShipment(shipmentId);
          expect(shipExpenses, hasLength(1));
          expect(shipExpenses.single.scope, ExpenseScope.shipment);
          expect(shipExpenses.single.shipmentId, shipmentId);

          final barnikas = await restoredDb.emptyBarnikaTrackingDao.getAll();
          expect(barnikas, hasLength(1));
          expect(barnikas.single.invoiceId, invoiceId);
        } finally {
          await restoredDb.close();
        }

        // Now verify restoring a simulated pre-v82 backup (missing v82 keys)
        final legacyTables = <String, dynamic>{
          'suppliers': [
            {'id': 'sup-old', 'name': 'مورد قديم', 'status': 'Active'},
          ],
          'customers': [
            {'id': 'cust-old', 'name': 'عميل قديم', 'status': 'Active'},
          ],
          'vegetable_shipments': [
            {
              'id': 1,
              'supplier_id': 'sup-old',
              'shipment_number': 'SHP-OLD-1',
              'date': 1767218400,
              'pricing_mode': 'commission',
              'total_barnika_count': 30,
              'commission_percentage': 8.0,
              'total_cost': 0.0,
              'barnika_sold_count': 5,
              'barnika_remaining_count': 25,
            },
          ],
          'expenses': [
            {
              'id': 'exp-old-1',
              'description': 'مصروف قديم',
              'amount': 25.0,
              'date': 1767218400,
              'category': 'عام',
              'payment_method': 'cash',
              'created_at': 1767218400,
            },
          ],
          'empty_barnika_tracking': [
            {
              'id': 1,
              'customer_id': 'cust-old',
              'date_out': 1767218400,
              'quantity_out': 5,
              'quantity_returned': 0,
              'status': 'outstanding',
            },
          ],
        };
        final payload = {
          'version': '2.0.0',
          'created_at': DateTime.now().toIso8601String(),
          'type': 'manual',
          'database': 'pos_offline_desktop',
          'tables': legacyTables,
          'checksum': sha256
              .convert(utf8.encode(jsonEncode(legacyTables)))
              .toString(),
        };
        final archive = Archive()
          ..addFile(
            ArchiveFile(
              'backup_data.json',
              utf8.encode(jsonEncode(payload)).length,
              utf8.encode(jsonEncode(payload)),
            ),
          );
        final zipBytes = ZipEncoder().encode(archive)!;
        final key = encrypt_pkg.Key(deriveAesKey('POS-BACKUP-KEY-2024-SECURE!!!'));
        final iv = encrypt_pkg.IV.fromLength(16);
        final encrypter = encrypt_pkg.Encrypter(
          encrypt_pkg.AES(key, mode: encrypt_pkg.AESMode.cbc),
        );
        final encrypted = [...iv.bytes, ...encrypter.encryptBytes(zipBytes, iv: iv).bytes];

        final backupDir = Directory('${tempDir.path}/data/backups');
        if (!backupDir.existsSync()) backupDir.createSync(recursive: true);
        const legacyName = 'backup_legacy_v81.posbackup';
        File('${backupDir.path}/$legacyName').writeAsBytesSync(encrypted);

        final legacyRestoredDb = AppDatabase(NativeDatabase.memory());
        try {
          await BackupService(legacyRestoredDb)
              .restoreBackup(adminUser(), legacyName);

          final ship = await legacyRestoredDb.vegetableShipmentDao.getById(1);
          expect(ship, isNotNull);
          expect(ship!.status, VegetableShipmentStatus.open);
          expect(ship.toppingCount, 0);

          final exp =
              await legacyRestoredDb.expenseDao.getExpenseById('exp-old-1');
          expect(exp, isNotNull);
          expect(exp!.scope, ExpenseScope.shop);
          expect(exp.shipmentId, isNull);

          final brk =
              await legacyRestoredDb.emptyBarnikaTrackingDao.getById(1);
          expect(brk, isNotNull);
          expect(brk!.invoiceId, isNull);
        } finally {
          await legacyRestoredDb.close();
        }
      } finally {
        await db.close();
      }
    });
  });
}
