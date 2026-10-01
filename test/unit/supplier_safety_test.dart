import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/dao/supplier_dao.dart';
import 'package:pos_offline_desktop/core/services/vegetable_market_import_service.dart';

/// Item 4 — safe supplier lifecycle:
/// - identity normalization + duplicate conflicts (never auto-merge);
/// - deactivate (soft delete) hides from lists/balances, keeps history;
/// - import reconciles by id/identity, skips ambiguous, never resurrects.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (MethodCall methodCall) async => '.',
      );

  Future<AppDatabase> openDb() async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    return db;
  }

  Future<String> addSupplier(
    AppDatabase db,
    String name, {
    String? phone,
    String status = 'Active',
  }) async {
    final row = await db.supplierDao.insertSupplier(
      SuppliersCompanion.insert(
        id: const Uuid().v4(),
        name: name,
        phone: Value(phone),
        status: Value(status),
      ),
    );
    return row.id;
  }

  group('identity normalization', () {
    test('names collapse whitespace/case, phones collapse to digits', () {
      expect(
        SupplierDao.normalizeSupplierName('  Messi  SPORTS '),
        'messi sports',
      );
      expect(SupplierDao.normalizeSupplierPhone('+20 100-234 5678'), isNot(
        SupplierDao.normalizeSupplierPhone('+201002345679'),
      ));
      expect(
        SupplierDao.normalizeSupplierPhone('0100 234 5678'),
        SupplierDao.normalizeSupplierPhone('1002345678'),
      );
      expect(SupplierDao.normalizeSupplierPhone(null), '');
      expect(SupplierDao.normalizeSupplierPhone(''), '');
    });
  });

  group('duplicate conflicts', () {
    test('same name (+matching/absent phone) conflicts; nothing merged',
        () async {
      final db = await openDb();
      await addSupplier(db, 'messi', phone: '01002345678');

      var hits = await db.supplierDao.findDuplicateSuppliers(
        name: '  MESSI ',
        phone: '0100-234-5678',
      );
      expect(hits.length, 1);

      hits = await db.supplierDao.findDuplicateSuppliers(name: 'messi');
      expect(hits.length, 1);

      // Same name + genuinely different phone: no conflict claimed.
      hits = await db.supplierDao.findDuplicateSuppliers(
        name: 'messi',
        phone: '01119998888',
      );
      expect(hits, isEmpty);

      // Excluding self never conflicts.
      final all = await db.supplierDao.getAllSuppliers();
      final mine = all.firstWhere((s) => s.name == 'messi');
      final excludingSelf = await db.supplierDao.findDuplicateSuppliers(
        name: 'messi',
        phone: '01002345678',
        excludeId: mine.id,
      );
      expect(excludingSelf, isEmpty);

      // Count unchanged: finder never writes.
      expect((await db.supplierDao.getAllSuppliers()).length, 1);
    });
  });

  group('soft delete visibility', () {
    test('deactivate hides from active list, count and unified, keeps rows',
        () async {
      final db = await openDb();
      final id = await addSupplier(db, 'messi');
      await db.ledgerDao.recordSupplierPurchase(
        supplierId: id,
        invoiceNumber: 'PUR-000001',
        total: 500,
        paid: 0,
        date: DateTime(2026, 9, 1),
      );
      expect(
        (await db.ledgerDao.getAllSupplierBalances()).length,
        1,
      );

      await db.supplierDao.deactivateSupplier(id);

      expect(await db.supplierDao.getActiveSuppliers(), isEmpty);
      // Unified balances no longer list inactive suppliers...
      expect(await db.ledgerDao.getAllSupplierBalances(), isEmpty);
      // ...but the master row and its ledger history survive intact.
      expect((await db.supplierDao.getAllSuppliers()).length, 1);
      expect(await db.ledgerDao.getSupplierBalance(id), 500.0);
      final txs = await db.ledgerDao.getTransactionsByEntity(
        'Supplier',
        id,
      );
      expect(txs.length, 1);
    });
  });

  group('import reconciliation', () {
    Future<void> importSuppliers(
      AppDatabase db,
      List<Map<String, dynamic>> suppliers,
    ) =>
        VegetableMarketImportService(db).importFromJsonString(
          jsonEncode({'suppliers': suppliers}),
        );

    test('same id reuses row; same name updates in place; no duplicates',
        () async {
      final db = await openDb();
      final id = await addSupplier(db, 'messi', phone: '0100');

      await importSuppliers(db, [
        {'id': id, 'name': 'messi', 'phone': '0100', 'status': 'Active'},
        {
          'id': 'other-uuid',
          'name': '  MESSI ',
          'phone': '0100',
          'status': 'Active',
        },
      ]);

      final all = await db.supplierDao.getAllSuppliers();
      expect(all.length, 1);
      expect(all.first.id, id);
    });

    test('ambiguous matches are skipped, never merged', () async {
      final db = await openDb();
      await addSupplier(db, 'messi', phone: '0100');
      await addSupplier(db, 'messi', phone: '0111');

      await importSuppliers(db, [
        {'id': 'new-uuid', 'name': 'messi', 'status': 'Active'},
      ]);

      expect((await db.supplierDao.getAllSuppliers()).length, 2);
    });

    test('import never resurrects a deactivated supplier', () async {
      final db = await openDb();
      final id = await addSupplier(db, 'messi');
      await db.supplierDao.deactivateSupplier(id);

      await importSuppliers(db, [
        {'id': id, 'name': 'messi', 'status': 'Active'},
      ]);

      final row = await db.supplierDao.getSupplierById(id);
      expect(row!.status, 'Inactive');
      expect(await db.supplierDao.getActiveSuppliers(), isEmpty);
    });
  });
}
