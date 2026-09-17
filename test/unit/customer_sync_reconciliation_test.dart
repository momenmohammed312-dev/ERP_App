import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/dao/customer_dao.dart';

/// B1 (customer identity) + B3 (supplier sync parity) reconciliation tests.
///
/// Rules under test (documented once in `CustomerDao.upsertFromRemote` /
/// `SupplierDao.upsertFromRemote`):
///  - stable-id upsert; unknown ids merge ONLY on unambiguous normalized
///    phone ([normalizePhone]); ambiguous (≥2) → typed conflict, nothing
///    merged, history preserved;
///  - last-write-wins on `updatedAt`, delete-wins-on-tie;
///  - a locally deleted row is NEVER resurrected by stale/unknown-clock data;
///  - suppliers: same outbox/pull pattern, monotonic-delete (no `updatedAt`
///    column exists on `suppliers`, so a remote Active never resurrects a
///    local Inactive).

AppDatabase openDb() {
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  return db;
}

Future<void> addCustomer(
  AppDatabase db,
  String id,
  String name, {
  String? phone,
  DateTime? updatedAt,
  bool isActive = true,
}) async {
  await db.into(db.customers).insert(
        CustomersCompanion.insert(
          id: id,
          name: name,
          phone: Value(phone),
          updatedAt: Value(updatedAt),
          isActive: Value(isActive),
          status: Value(isActive ? 'Active' : 'Inactive'),
        ),
      );
}

Map<String, dynamic> remoteCustomer(
  String syncId, {
  String name = 'Remote',
  String? phone,
  DateTime? updatedAt,
  bool? isActive,
}) {
  final row = <String, dynamic>{
    'sync_id': syncId,
    'name': name,
    'phone': phone,
    'address': null,
    'opening_balance': 0.0,
    if (updatedAt != null)
      'updated_at': updatedAt.toUtc().toIso8601String(),
    if (isActive != null) 'is_active': isActive,
  };
  return row;
}

Map<String, dynamic> remoteSupplier(
  String syncId, {
  String name = 'مورّد',
  bool? isActive,
}) {
  return <String, dynamic>{
    'sync_id': syncId,
    'name': name,
    'phone': null,
    'address': null,
    'opening_balance': 0.0,
    if (isActive != null) 'is_active': isActive,
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (MethodCall methodCall) async => '.',
      );

  group('normalizePhone', () {
    test('formatting/country-prefix variants canonicalize identically', () {
      expect(normalizePhone('0101 234-5678'), '1012345678');
      expect(normalizePhone('+20 101 234 5678'), '1012345678');
      expect(normalizePhone('00201012345678'), '1012345678');
      expect(normalizePhone('(010) 1234-5678'), '1012345678');
      expect(normalizePhone('01012345678'), '1012345678');
    });

    test('empty/null never matches (callers skip it)', () {
      expect(normalizePhone(null), isEmpty);
      expect(normalizePhone(''), isEmpty);
      expect(normalizePhone('  --  '), isEmpty);
    });
  });

  group('reconcileRemoteCustomer', () {
    test('unambiguous phone match merges, row id unchanged', () async {
      final db = openDb();
      final t0 = DateTime.utc(2026, 1, 1);
      final t1 = DateTime.utc(2026, 2, 1);
      await addCustomer(db, 'local-1', 'Local', phone: '01012345678', updatedAt: t0);
      await db.ledgerDao.insertTransaction(
        LedgerTransactionsCompanion.insert(
          id: 'ledger-1',
          entityType: 'Customer',
          refId: 'local-1',
          date: t0,
          description: 'old sale',
          debit: const Value(100.0),
          origin: 'sale',
        ),
      );

      final result = await db.customerDao.reconcileRemoteCustomer(
        remoteCustomer('remote-9', name: 'Renamed', phone: '+20 101 234 5678', updatedAt: t1),
      );

      expect(result.outcome, CustomerSyncOutcome.mergedByPhone);
      expect(result.customerId, 'local-1');
      // Adopted fields, same row: history (ledger refId) still resolves.
      final kept = await db.customerDao.getCustomerById('local-1');
      expect(kept!.name, 'Renamed');
      final tx = await db.ledgerDao.getTransactionsByEntity('Customer', 'local-1');
      expect(tx.length, 1);
      // No duplicate row created under the remote id.
      expect(await db.customerDao.getCustomerById('remote-9'), isNull);
    });

    test('ambiguous phone (>=2 candidates) does NOT merge', () async {
      final db = openDb();
      final t0 = DateTime.utc(2026, 1, 1);
      final t1 = DateTime.utc(2026, 2, 1);
      await addCustomer(db, 'a', 'First', phone: '01012345678', updatedAt: t0);
      await addCustomer(db, 'b', 'Second', phone: '0101-234-5678', updatedAt: t0);

      final result = await db.customerDao.reconcileRemoteCustomer(
        remoteCustomer('remote-9', name: 'Intruder', phone: '01012345678', updatedAt: t1),
      );

      expect(result.outcome, CustomerSyncOutcome.conflict);
      expect(result.isConflict, isTrue);
      expect(result.conflictIds.toSet(), {'a', 'b'});
      // Nothing changed: all history + names preserved.
      expect((await db.customerDao.getCustomerById('a'))!.name, 'First');
      expect((await db.customerDao.getCustomerById('b'))!.name, 'Second');
      expect(await db.customerDao.getCustomerById('remote-9'), isNull);
    });

    test('no stable id and no phone inserts nothing', () async {
      final db = openDb();
      final before = await db.customerDao.getAllCustomers();
      final result = await db.customerDao.reconcileRemoteCustomer(
        remoteCustomer('', name: 'Ghost', updatedAt: DateTime.utc(2026, 2, 1)),
      );
      expect(result.outcome, CustomerSyncOutcome.skippedStale);
      expect(await db.customerDao.getAllCustomers(), hasLength(before.length));
    });

    test('stale remote does not overwrite newer local row', () async {
      final db = openDb();
      await addCustomer(db, 'c1', 'Local', updatedAt: DateTime.utc(2026, 5, 1));
      final result = await db.customerDao.reconcileRemoteCustomer(
        remoteCustomer('c1', name: 'Stale', updatedAt: DateTime.utc(2026, 1, 1)),
      );
      expect(result.outcome, CustomerSyncOutcome.skippedStale);
      expect((await db.customerDao.getCustomerById('c1'))!.name, 'Local');
    });
  });

  group('soft-delete replication (delete-wins-on-tie)', () {
    test('tie: active local + deleted remote stays deleted', () async {
      final db = openDb();
      final t = DateTime.utc(2026, 3, 1, 12);
      await addCustomer(db, 'c1', 'A', updatedAt: t);
      await db.customerDao.upsertFromRemote(
        remoteCustomer('c1', name: 'A', updatedAt: t, isActive: false),
      );
      final row = await db.customerDao.getCustomerById('c1');
      expect(row!.isActive, isFalse);
    });

    test('tie: deleted local + active remote stays deleted', () async {
      final db = openDb();
      final t = DateTime.utc(2026, 3, 1, 12);
      await addCustomer(db, 'c1', 'A', updatedAt: t, isActive: false);
      await db.customerDao.upsertFromRemote(
        remoteCustomer('c1', name: 'A', updatedAt: t, isActive: true),
      );
      final row = await db.customerDao.getCustomerById('c1');
      expect(row!.isActive, isFalse);
    });

    test('clockless remote never resurrects a local delete', () async {
      final db = openDb();
      await addCustomer(
        db, 'c1', 'A',
        updatedAt: DateTime.utc(2026, 4, 1), isActive: false,
      );
      // Remote carries no updated_at at all (legacy row).
      await db.customerDao.upsertFromRemote(
        remoteCustomer('c1', name: 'A', isActive: true),
      );
      final row = await db.customerDao.getCustomerById('c1');
      expect(row!.isActive, isFalse);
      expect(row.name, 'A');
    });

    test('legacy remote without activity flag keeps local flag either way',
        () async {
      final db = openDb();
      await addCustomer(db, 'c1', 'A', updatedAt: DateTime.utc(2026, 1, 1));
      await addCustomer(
        db, 'c2', 'B',
        updatedAt: DateTime.utc(2026, 1, 1), isActive: false,
      );
      final newer = DateTime.utc(2026, 2, 1);
      // No 'is_active'/'status' keys at all.
      await db.customerDao.upsertFromRemote(
        remoteCustomer('c1', name: 'A2', updatedAt: newer)..remove('is_active'),
      );
      await db.customerDao.upsertFromRemote(
        remoteCustomer('c2', name: 'B2', updatedAt: newer)..remove('is_active'),
      );
      expect((await db.customerDao.getCustomerById('c1'))!.isActive, isTrue);
      expect((await db.customerDao.getCustomerById('c2'))!.isActive, isFalse);
      expect((await db.customerDao.getCustomerById('c1'))!.name, 'A2');
    });
  });

  group('supplier sync parity (B3)', () {
    test('stable-UUID upsert: insert then update by id', () async {
      final db = openDb();
      await db.supplierDao.upsertFromRemote(remoteSupplier('s1', name: 'One'));
      expect((await db.supplierDao.getSupplierById('s1'))!.name, 'One');
      await db.supplierDao.upsertFromRemote(
        remoteSupplier('s1', name: 'One Renamed'),
      );
      final row = await db.supplierDao.getSupplierById('s1');
      expect(row!.name, 'One Renamed');
      expect(row.status, 'Active');
    });

    test('remote delete is always applied (monotonic delete)', () async {
      final db = openDb();
      await db.into(db.suppliers).insert(
            SuppliersCompanion.insert(id: 's1', name: 'Active Supplier'),
          );
      await db.supplierDao.upsertFromRemote(
        remoteSupplier('s1', isActive: false),
      );
      expect(
        (await db.supplierDao.getSupplierById('s1'))!.status,
        'Inactive',
      );
    });

    test('remote Active never resurrects a locally deactivated row', () async {
      final db = openDb();
      await db.into(db.suppliers).insert(
            SuppliersCompanion.insert(id: 's1', name: 'Old'),
          );
      await db.supplierDao.deactivateSupplier('s1');
      await db.supplierDao.upsertFromRemote(
        remoteSupplier('s1', name: 'Old', isActive: true),
      );
      // Fields may refresh, but the delete stands.
      expect(
        (await db.supplierDao.getSupplierById('s1'))!.status,
        'Inactive',
      );
    });

    test('unknown flag keeps local activity, updates other fields', () async {
      final db = openDb();
      await db.into(db.suppliers).insert(
            SuppliersCompanion.insert(id: 's1', name: 'Old'),
          );
      await db.supplierDao.upsertFromRemote(remoteSupplier('s1', name: 'New'));
      final row = await db.supplierDao.getSupplierById('s1');
      expect(row!.name, 'New');
      expect(row.status, 'Active');
    });

    test('deleteSupplier is soft (row + history preserved)', () async {
      final db = openDb();
      await db.into(db.suppliers).insert(
            SuppliersCompanion.insert(id: 's1', name: 'Keep Me'),
          );
      await db.ledgerDao.insertTransaction(
        LedgerTransactionsCompanion.insert(
          id: 'stx-1',
          entityType: 'Supplier',
          refId: 's1',
          date: DateTime.utc(2026, 1, 5),
          description: 'purchase',
          credit: const Value(250.0),
          origin: 'purchase',
        ),
      );
      await db.supplierDao.deleteSupplier('s1');
      final row = await db.supplierDao.getSupplierById('s1');
      expect(row, isNotNull);
      expect(row!.status, 'Inactive');
      expect(
        await db.ledgerDao.getTransactionsByEntity('Supplier', 's1'),
        hasLength(1),
      );
      // Active lists/counts hide it.
      expect(await db.supplierDao.getActiveSuppliers(), isEmpty);
      expect(await db.supplierDao.watchSuppliersCount().first, 0);
    });

    test('insert guard mirrors customer active-name check', () async {
      final db = openDb();
      await db.supplierDao.insertSupplier(
        SuppliersCompanion.insert(id: 's1', name: 'مورّد'),
      );
      await expectLater(
        db.supplierDao.insertSupplier(
          SuppliersCompanion.insert(id: 's2', name: 'مورّد'),
        ),
        throwsA(isA<Exception>()),
      );
      // Inactive names are reusable.
      await db.supplierDao.deactivateSupplier('s1');
      await db.supplierDao.insertSupplier(
        SuppliersCompanion.insert(id: 's3', name: 'مورّد'),
      );
      expect((await db.supplierDao.getSupplierById('s3'))!.status, 'Active');
    });
  });
}
