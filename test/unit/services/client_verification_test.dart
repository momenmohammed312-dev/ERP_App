library;
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/models/user_model.dart';
import 'package:pos_offline_desktop/core/services/backup_service.dart';
import 'package:pos_offline_desktop/core/services/custody_service.dart';
import 'package:pos_offline_desktop/core/services/document_date_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late File testDbFile;
  late AppDatabase db;
  late DocumentDateService dateService;

  const testCustomerId = 'CUST-TEST-108';
  const testSupplierId = 'SUPP-TEST-01';
  const testPurchaseId = 'PUR-TEST-001';
  const testPaymentTxId = 'PAY-TEST-001';
  late int seededInvoiceId;

  User adminUser() => User(
        id: 1,
        username: 'admin',
        passwordHash: 'dummy',
        fullName: 'Admin User',
        role: UserRole.admin,
        createdAt: DateTime.now(),
      );

  setUpAll(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    tempDir = await Directory.systemTemp.createTemp('synthetic_verify_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        return tempDir.path;
      },
    );

    testDbFile = File('${tempDir.path}/synthetic_verify.sqlite');
    db = AppDatabase(NativeDatabase(testDbFile));
    dateService = DocumentDateService(db);

    // Seed synthetic data (no real customer data per AGENTS.md 7.2.3)
    await db.into(db.customers).insert(
          CustomersCompanion.insert(
            id: testCustomerId,
            name: 'عميل اختبار قياسي',
            phone: const Value('01000000000'),
          ),
        );

    await db.into(db.suppliers).insert(
          SuppliersCompanion.insert(
            id: testSupplierId,
            name: 'مورد اختبار قياسي',
            phone: const Value('01100000000'),
          ),
        );

    // Earlier customer invoice so chronological re-ordering can be tested
    final earlierInvId = await db.into(db.invoices).insert(
          InvoicesCompanion.insert(
            customerId: const Value(testCustomerId),
            customerName: const Value('عميل اختبار قياسي'),
            totalAmount: const Value(2000.0),
            netAmount: const Value(2000.0),
            paidAmount: const Value(0.0),
            paymentMethod: const Value('credit'),
            date: Value(DateTime(2026, 10, 5, 10, 0)),
          ),
        );
    await db.into(db.ledgerTransactions).insert(
          LedgerTransactionsCompanion.insert(
            id: 'TX-EARLIER-$earlierInvId',
            entityType: 'Customer',
            refId: testCustomerId,
            date: DateTime(2026, 10, 5, 10, 0),
            description: 'فاتورة مبيعات #$earlierInvId',
            debit: const Value(2000.0),
            credit: const Value(0.0),
            origin: 'invoice',
            receiptNumber: Value('INV$earlierInvId'),
          ),
        );

    seededInvoiceId = await db.into(db.invoices).insert(
          InvoicesCompanion.insert(
            customerId: const Value(testCustomerId),
            customerName: const Value('عميل اختبار قياسي'),
            totalAmount: const Value(3500.0),
            netAmount: const Value(3500.0),
            paidAmount: const Value(0.0),
            paymentMethod: const Value('credit'),
            date: Value(DateTime(2026, 10, 12, 14, 0)),
          ),
        );
    await db.into(db.ledgerTransactions).insert(
          LedgerTransactionsCompanion.insert(
            id: 'TX-INV-$seededInvoiceId',
            entityType: 'Customer',
            refId: testCustomerId,
            date: DateTime(2026, 10, 12, 14, 0),
            description: 'فاتورة مبيعات #$seededInvoiceId',
            debit: const Value(3500.0),
            credit: const Value(0.0),
            origin: 'invoice',
            receiptNumber: Value('INV$seededInvoiceId'),
          ),
        );

    // Customer payment transaction
    await db.into(db.ledgerTransactions).insert(
          LedgerTransactionsCompanion.insert(
            id: testPaymentTxId,
            entityType: 'Customer',
            refId: testCustomerId,
            date: DateTime(2026, 10, 15, 16, 0),
            description: 'تحصيل دفعة نقدية',
            debit: const Value(0.0),
            credit: const Value(500.0),
            origin: 'payment',
            receiptNumber: const Value('REC-001'),
          ),
        );

    // Purchase + Supplier Ledger
    await db.into(db.purchases).insert(
          PurchasesCompanion.insert(
            id: testPurchaseId,
            supplierId: const Value(testSupplierId),
            invoiceNumber: testPurchaseId,
            description: 'فاتورة مشتريات تجريبية',
            totalAmount: 15255.0,
            paidAmount: const Value(0.0),
            paymentMethod: const Value('credit'),
            purchaseDate: DateTime(2026, 10, 10, 11, 0),
            createdAt: DateTime(2026, 10, 10, 11, 0),
          ),
        );
    await db.into(db.ledgerTransactions).insert(
          LedgerTransactionsCompanion.insert(
            id: '${testPurchaseId}_ledger',
            entityType: 'Supplier',
            refId: testSupplierId,
            date: DateTime(2026, 10, 10, 11, 0),
            description: 'فاتورة مشتريات #$testPurchaseId',
            debit: const Value(0.0),
            credit: const Value(15255.0),
            origin: 'purchase',
            receiptNumber: const Value(testPurchaseId),
          ),
        );

    // Seed 3 synthetic cash custodies via CustodyService
    final custodyService = CustodyService(db);
    final c1 = await custodyService.createCustody(
      staffId: 'ST1',
      staffName: 'أمين عهدة 1',
      amount: 10000.0,
    );
    await custodyService.cancelCustody(c1);

    final c2 = await custodyService.createCustody(
      staffId: 'ST2',
      staffName: 'أمين عهدة 2',
      amount: 2000.0,
    );
    await custodyService.cancelCustody(c2);

    await custodyService.createCustody(
      staffId: 'ST3',
      staffName: 'أمين عهدة 3',
      amount: 300.0,
    );
  });

  tearDownAll(() async {
    await db.close();
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  group('Task 2: Verification on synthetic database', () {
    test('database opens with schema v79 and contains expected seeded data', () async {
      final versionResult = await db.customSelect('PRAGMA user_version').getSingle();
      final version = versionResult.data['user_version'] as int;
      expect(version, equals(79), reason: 'Current DB schemaVersion must be 79');

      final invoicesCount = await db.customSelect('SELECT COUNT(*) AS c FROM invoices').getSingle();
      expect(invoicesCount.data['c'], greaterThanOrEqualTo(2));

      final purchasesCount = await db.customSelect('SELECT COUNT(*) AS c FROM purchases').getSingle();
      expect(purchasesCount.data['c'], greaterThanOrEqualTo(1));
    });

    test('updateInvoiceDate: moves ledger, preserves balance, re-orders statement, and writes audit', () async {
      final invId = seededInvoiceId;
      final invoiceBefore = await db.invoiceDao.getInvoiceById(invId);
      expect(invoiceBefore, isNotNull);
      final customerId = invoiceBefore!.customerId!;
      final oldDate = invoiceBefore.date;
      final origCreatedAt = invoiceBefore.createdAt;

      // 1. Check initial customer running balance (2000 + 3500 - 500 = 5000)
      final initialBalance = await db.ledgerDao.getCustomerBalance(customerId);
      expect(initialBalance, equals(5000.0));

      // 2. Check initial ledger row for this invoice
      final txBefore = await (db.select(db.ledgerTransactions)
        ..where((t) => t.receiptNumber.equals('INV$invId')))
        .getSingle();
      expect(txBefore.date.year, equals(2026));

      // 3. Move invoice date to Sept 1st, 2026 (earlier than Oct 5 invoice)
      final newDate = DateTime(2026, 9, 1, 12, 0);
      final updateResult = await dateService.updateInvoiceDate(
        invoiceId: invId,
        newDate: newDate,
        userId: '99',
      );

      expect(updateResult.success, isTrue);
      expect(updateResult.oldDate, equals(oldDate));
      expect(updateResult.newDate, equals(newDate));

      // 4. Verify invoice date changed and created_at remained intact
      final invoiceAfter = await db.invoiceDao.getInvoiceById(invId);
      expect(invoiceAfter!.date, equals(newDate));
      expect(invoiceAfter.createdAt, equals(origCreatedAt));

      // 5. Verify ledger transaction moved to newDate
      final txAfter = await (db.select(db.ledgerTransactions)
        ..where((t) => t.receiptNumber.equals('INV$invId')))
        .getSingle();
      expect(txAfter.date, equals(newDate));

      // 6. Verify Customer Final Balance is 100% strictly invariant!
      final finalBalance = await db.ledgerDao.getCustomerBalance(customerId);
      expect(finalBalance, equals(initialBalance));

      // 7. Verify statement chronological order for customer
      final statement = await (db.select(db.ledgerTransactions)
        ..where((t) => t.entityType.equals('Customer') & t.refId.equals(customerId))
        ..orderBy([(t) => OrderingTerm(expression: t.date, mode: OrderingMode.asc)]))
        .get();

      expect(statement.first.receiptNumber, equals('INV$invId'));

      // 8. Verify audit log entry
      final audit = await (db.select(db.auditLog)
        ..where((t) => t.tableNameField.equals('invoices') & t.recordId.equals(invId)))
        .getSingle();
      expect(audit.action, 'DATE_CHANGE');
      expect(audit.userId, 99);
      final newVal = jsonDecode(audit.newValue!) as Map<String, dynamic>;
      expect(newVal['date'], newDate.toIso8601String());
    });

    test('updatePurchaseDate: moves ledger, preserves balance, and writes audit', () async {
      final pBefore = await (db.select(db.purchases)..where((t) => t.id.equals(testPurchaseId))).getSingle();
      final supplierId = pBefore.supplierId!;
      final origCreatedAt = pBefore.createdAt;

      // 1. Check initial supplier balance
      final initialSuppBalance = await db.ledgerDao.getSupplierBalance(supplierId);
      expect(initialSuppBalance, equals(15255.0));

      // 2. Move purchase date
      final newPurchaseDate = DateTime(2026, 9, 20, 10, 0);
      final res = await dateService.updatePurchaseDate(
        purchaseId: testPurchaseId,
        newDate: newPurchaseDate,
        userId: '99',
      );

      expect(res.success, isTrue);

      // 3. Verify purchase row
      final pAfter = await (db.select(db.purchases)..where((t) => t.id.equals(testPurchaseId))).getSingle();
      expect(pAfter.purchaseDate, equals(newPurchaseDate));
      expect(pAfter.createdAt, equals(origCreatedAt));

      // 4. Verify supplier ledger transaction moved
      final suppTx = await (db.select(db.ledgerTransactions)
        ..where((t) => t.id.equals('${testPurchaseId}_ledger')))
        .getSingle();
      expect(suppTx.date, equals(newPurchaseDate));

      // 5. Verify Supplier Final Balance is 100% strictly invariant!
      final finalSuppBalance = await db.ledgerDao.getSupplierBalance(supplierId);
      expect(finalSuppBalance, equals(initialSuppBalance));

      // 6. Verify audit log
      final audit = await (db.select(db.auditLog)
        ..where((t) => t.tableNameField.equals('purchases') & t.details.like('%$testPurchaseId%')))
        .getSingle();
      expect(audit.action, 'DATE_CHANGE');
    });

    test('updatePaymentDate: moves ledger and preserves balance', () async {
      final txBefore = await db.ledgerDao.getTransactionById(testPaymentTxId);
      expect(txBefore, isNotNull);
      final customerId = txBefore!.refId;

      final balanceBefore = await db.ledgerDao.getCustomerBalance(customerId);

      final newPayDate = DateTime(2026, 6, 15, 14, 0);
      final res = await dateService.updatePaymentDate(
        transactionId: testPaymentTxId,
        newDate: newPayDate,
        userId: '99',
      );

      expect(res.success, isTrue);

      final txAfter = await db.ledgerDao.getTransactionById(testPaymentTxId);
      expect(txAfter!.date, equals(newPayDate));

      final balanceAfter = await db.ledgerDao.getCustomerBalance(customerId);
      expect(balanceAfter, equals(balanceBefore));

      final audit = await (db.select(db.auditLog)
        ..where((t) => t.tableNameField.equals('ledger_transactions') & t.details.like('%${txBefore.description}%')))
        .getSingle();
      expect(audit.action, 'DATE_CHANGE');
    });
  });

  group('Task 3: Client Build Verification — cash_custodies in Backup & Restore', () {
    test('confirms cash_custodies has 3 rows, included in backup and restored intact', () async {
      final custodiesPre = await db.select(db.cashCustodies).get();
      expect(custodiesPre.length, equals(3));

      expect(custodiesPre[0].custodyNumber, 'CUST-000001');
      expect(custodiesPre[0].amount, 10000.0);
      expect(custodiesPre[0].status, 'cancelled');

      expect(custodiesPre[1].custodyNumber, 'CUST-000002');
      expect(custodiesPre[1].amount, 2000.0);
      expect(custodiesPre[1].status, 'cancelled');

      expect(custodiesPre[2].custodyNumber, 'CUST-000003');
      expect(custodiesPre[2].amount, 300.0);
      expect(custodiesPre[2].status, 'open');

      final backupService = BackupService(db);
      final backupInfo = await backupService.createBackup(
        adminUser(),
        description: 'Synthetic Verification Backup',
      );

      expect(backupInfo.filename, isNotEmpty);
      expect(backupInfo.size, greaterThan(0));

      final restoreDbFile = File('${tempDir.path}/restore_target.sqlite');
      if (await restoreDbFile.exists()) {
        await restoreDbFile.delete();
      }
      final restoreDb = AppDatabase(NativeDatabase(restoreDbFile));

      final custodiesEmpty = await restoreDb.select(restoreDb.cashCustodies).get();
      expect(custodiesEmpty, isEmpty);

      final restoreService = BackupService(restoreDb);
      await restoreService.restoreBackup(adminUser(), backupInfo.filename);

      final fkViolations = await restoreDb.customSelect('PRAGMA foreign_key_check').get();
      expect(fkViolations, isEmpty, reason: 'PRAGMA foreign_key_check must report 0 violations');

      final custodiesPost = await restoreDb.select(restoreDb.cashCustodies).get();
      expect(custodiesPost.length, equals(3));

      expect(custodiesPost[0].id, equals(custodiesPre[0].id));
      expect(custodiesPost[0].custodyNumber, equals('CUST-000001'));
      expect(custodiesPost[0].amount, equals(10000.0));
      expect(custodiesPost[0].status, equals('cancelled'));

      expect(custodiesPost[1].id, equals(custodiesPre[1].id));
      expect(custodiesPost[1].custodyNumber, equals('CUST-000002'));
      expect(custodiesPost[1].amount, equals(2000.0));
      expect(custodiesPost[1].status, equals('cancelled'));

      expect(custodiesPost[2].id, equals(custodiesPre[2].id));
      expect(custodiesPost[2].custodyNumber, equals('CUST-000003'));
      expect(custodiesPost[2].amount, equals(300.0));
      expect(custodiesPost[2].status, equals('open'));

      await restoreDb.close();
    });
  });
}
