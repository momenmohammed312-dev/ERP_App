import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/models/user_model.dart';
import 'package:pos_offline_desktop/core/services/customer_merge_service.dart';

/// B2 tests: admin customer merge moves FULL history in one transaction,
/// deactivates the source with a merged_into note (no schema change), writes
/// audit rows, and is idempotent.

AppDatabase openDb() {
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  return db;
}

User testUser(UserRole role, {int? id, String name = 'u'}) => User(
      id: id,
      username: name,
      passwordHash: 'x',
      fullName: name,
      role: role,
      createdAt: DateTime.utc(2026, 1, 1),
    );

Future<void> addCustomer(AppDatabase db, String id, String name) async {
  await db.into(db.customers).insert(
        CustomersCompanion.insert(id: id, name: name),
      );
}

Future<void> addLedger(
  AppDatabase db,
  String id,
  String refId, {
  double debit = 0,
  double credit = 0,
}) async {
  await db.ledgerDao.insertTransaction(
    LedgerTransactionsCompanion.insert(
      id: id,
      entityType: 'Customer',
      refId: refId,
      date: DateTime.utc(2026, 2, 1),
      description: 'tx $id',
      debit: Value(debit),
      credit: Value(credit),
      origin: 'sale',
    ),
  );
}

Future<int> addInvoice(AppDatabase db, String customerId) async {
  return db.into(db.invoices).insert(
        InvoicesCompanion.insert(
          customerId: Value(customerId),
          customerName: const Value('SOURCE'),
          totalAmount: const Value(100),
        ),
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (MethodCall methodCall) async => '.',
      );

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('CustomerMergeService', () {
    test('full history follows target incl. ledger + invoices', () async {
      final db = openDb();
      final svc = CustomerMergeService(db);
      await addCustomer(db, 'src', 'Source');
      await addCustomer(db, 'tgt', 'Target');
      await addInvoice(db, 'src');
      await addInvoice(db, 'src');
      await addLedger(db, 'l1', 'src', debit: 100);
      await addLedger(db, 'l2', 'src', credit: 40);
      await addLedger(db, 'l3', 'tgt', debit: 10);

      // Product + containers (source and target share one product → sum).
      final prodId = await db.into(db.products).insert(
            ProductsCompanion.insert(
              name: 'برنيكة',
              quantity: 100,
              price: 5.0,
            ),
          );
      await db.into(db.customerContainers).insert(
            CustomerContainersCompanion.insert(
              productId: prodId,
              customerId: 'src',
              quantityOut: const Value(5),
              quantityReturned: const Value(1),
            ),
          );
      await db.into(db.customerContainers).insert(
            CustomerContainersCompanion.insert(
              productId: prodId,
              customerId: 'tgt',
              quantityOut: const Value(2),
              quantityReturned: const Value(2),
            ),
          );
      // Barnika tracking + sales return (needs a parent invoice).
      await db.into(db.emptyBarnikaTracking).insert(
            EmptyBarnikaTrackingCompanion.insert(
              customerId: 'src',
              dateOut: DateTime.utc(2026, 2, 2),
              quantityOut: 3,
            ),
          );
      final invId = await addInvoice(db, 'src');
      await db.into(db.salesReturns).insert(
            SalesReturnsCompanion.insert(
              returnNumber: 'RET-1',
              originalInvoiceId: invId,
              customerId: const Value('src'),
              customerName: 'Source',
              returnDate: DateTime.utc(2026, 2, 3),
              totalAmount: 20.0,
              returnReason: 'other',
            ),
          );

      await svc.mergeCustomers(
        sourceId: 'src',
        targetId: 'tgt',
        performedBy: testUser(UserRole.admin, id: 1, name: 'admin'),
      );

      // Invoices reassigned (+ snapshots refreshed to target).
      final invoices = await (db.select(db.invoices)
            ..where((t) => t.customerId.equals('tgt')))
          .get();
      expect(invoices.length, 3);
      expect(invoices.every((i) => i.customerName == 'Target'), isTrue);

      // Ledger rows reassigned 1:2 (no amounts recomputed).
      final tgtTx = await db.ledgerDao.getTransactionsByEntity(
        'Customer',
        'tgt',
      );
      expect(tgtTx.length, 3);
      final srcTx = await db.ledgerDao.getTransactionsByEntity(
        'Customer',
        'src',
      );
      expect(srcTx, isEmpty);

      // Containers summed on PK collision: 5+2 out, 1+2 returned.
      final merged = await (db.select(db.customerContainers)
            ..where(
              (t) =>
                  t.productId.equals(prodId) & t.customerId.equals('tgt'),
            ))
          .getSingle();
      expect(merged.quantityOut, 7);
      expect(merged.quantityReturned, 3);
      final srcContainers = await (db.select(db.customerContainers)
            ..where((t) => t.customerId.equals('src')))
          .get();
      expect(srcContainers, isEmpty);

      // Barnika + returns follow.
      final barnika = await (db.select(db.emptyBarnikaTracking)
            ..where((t) => t.customerId.equals('tgt')))
          .get();
      expect(barnika.length, 1);
      final returns = await (db.select(db.salesReturns)
            ..where((t) => t.customerId.equals('tgt')))
          .get();
      expect(returns.length, 1);
      expect(returns.single.customerName, 'Target');

      // Source inactive with merged_into note (no schema change).
      final src = await db.customerDao.getCustomerById('src');
      expect(src!.isActive, isFalse);
      expect(src.status, 'Inactive');
      expect(src.notes, contains('merged_into=tgt'));

      // Audit rows exist (existing AuditDao mechanism).
      final audits = await db.auditDao.getAuditLogs(tableName: 'customers');
      expect(
        audits.where((a) => a.action == 'customer_merge').length,
        1,
      );
      expect(
        audits
            .where((a) => a.action == 'customer_merge_source_deactivated')
            .length,
        1,
      );
      expect(audits.first.details, contains('src'));
      expect(audits.first.details, contains('tgt'));
    });

    test('re-run is safe (idempotent)', () async {
      final db = openDb();
      final svc = CustomerMergeService(db);
      await addCustomer(db, 'src', 'Source');
      await addCustomer(db, 'tgt', 'Target');
      await addInvoice(db, 'src');
      await addLedger(db, 'l1', 'src', debit: 100);

      final admin = testUser(UserRole.admin, id: 1);
      await svc.mergeCustomers(
        sourceId: 'src',
        targetId: 'tgt',
        performedBy: admin,
      );
      // Second run must not throw, duplicate, or lose rows.
      await svc.mergeCustomers(
        sourceId: 'src',
        targetId: 'tgt',
        performedBy: admin,
      );

      final tgtTx = await db.ledgerDao.getTransactionsByEntity(
        'Customer',
        'tgt',
      );
      expect(tgtTx.length, 1);
      final invoices = await (db.select(db.invoices)
            ..where((t) => t.customerId.equals('tgt')))
          .get();
      expect(invoices.length, 1);
      final src = await db.customerDao.getCustomerById('src');
      expect(src!.isActive, isFalse);
    });

    test('admin-only: manager/cashier/null rejected, guards hold', () async {
      final db = openDb();
      final svc = CustomerMergeService(db);
      await addCustomer(db, 'src', 'Source');
      await addCustomer(db, 'tgt', 'Target');

      await expectLater(
        svc.mergeCustomers(
          sourceId: 'src',
          targetId: 'tgt',
          performedBy: testUser(UserRole.manager),
        ),
        throwsA(isA<CustomerMergeException>()),
      );
      await expectLater(
        svc.mergeCustomers(
          sourceId: 'src',
          targetId: 'tgt',
          performedBy: testUser(UserRole.cashier),
        ),
        throwsA(isA<CustomerMergeException>()),
      );
      await expectLater(
        svc.mergeCustomers(
          sourceId: 'src',
          targetId: 'tgt',
          performedBy: null,
        ),
        throwsA(isA<CustomerMergeException>()),
      );
      await expectLater(
        svc.mergeCustomers(
          sourceId: 'src',
          targetId: 'src',
          performedBy: testUser(UserRole.admin),
        ),
        throwsA(isA<CustomerMergeException>()),
      );
      await expectLater(
        svc.mergeCustomers(
          sourceId: 'missing',
          targetId: 'tgt',
          performedBy: testUser(UserRole.admin),
        ),
        throwsA(isA<CustomerMergeException>()),
      );
      // Inactive target rejected — nothing moved.
      await db.customerDao.deleteCustomer('tgt');
      await expectLater(
        svc.mergeCustomers(
          sourceId: 'src',
          targetId: 'tgt',
          performedBy: testUser(UserRole.admin),
        ),
        throwsA(isA<CustomerMergeException>()),
      );
      final src = await db.customerDao.getCustomerById('src');
      expect(src!.isActive, isTrue);
    });
  });
}
