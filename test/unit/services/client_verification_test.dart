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
import 'package:pos_offline_desktop/core/services/document_date_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late File clientTestDbFile;
  late AppDatabase db;
  late DocumentDateService dateService;

  User adminUser() => User(
        id: 1,
        username: 'admin',
        passwordHash: 'dummy',
        fullName: 'Admin User',
        role: UserRole.admin,
        createdAt: DateTime.now(),
      );

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('client_verify_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        return tempDir.path;
      },
    );

    // Ensure pristine copy of client_test.sqlite from client_copy.sqlite
    final originalCopy = File('C:/Users/Momen/.gemini/antigravity/brain/3ead978d-5788-4619-a7fc-26a583c7442b/scratch/client_copy.sqlite');
    clientTestDbFile = File('scratch/client_test.sqlite');
    if (!clientTestDbFile.parent.existsSync()) {
      clientTestDbFile.parent.createSync(recursive: true);
    }
    if (originalCopy.existsSync()) {
      originalCopy.copySync(clientTestDbFile.path);
    }

    db = AppDatabase(NativeDatabase(clientTestDbFile));
    dateService = DocumentDateService(db);
  });

  tearDownAll(() async {
    await db.close();
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  group('Task 2: Verification on scratch/client_test.sqlite', () {
    test('client_test.sqlite opens with schema v78 and contains expected data', () async {
      final versionResult = await db.customSelect('PRAGMA user_version').getSingle();
      final version = versionResult.data['user_version'] as int;
      expect(version, equals(78), reason: 'Client DB schemaVersion must be 78');

      final invoicesCount = await db.customSelect('SELECT COUNT(*) AS c FROM invoices').getSingle();
      expect(invoicesCount.data['c'], greaterThan(100));

      final purchasesCount = await db.customSelect('SELECT COUNT(*) AS c FROM purchases').getSingle();
      expect(purchasesCount.data['c'], greaterThan(20));
    });

    test('updateInvoiceDate on real invoice 108: moves ledger, preserves balance, re-orders statement, and writes audit', () async {
      const invId = 108;
      final invoiceBefore = await db.invoiceDao.getInvoiceById(invId);
      expect(invoiceBefore, isNotNull);
      final customerId = invoiceBefore!.customerId!;
      final oldDate = invoiceBefore.date;
      final origCreatedAt = invoiceBefore.createdAt;

      // 1. Check initial customer running balance
      final initialBalance = await db.ledgerDao.getCustomerBalance(customerId);
      expect(initialBalance, equals(581790.0));

      // 2. Check initial ledger row for this invoice
      final txBefore = await (db.select(db.ledgerTransactions)
        ..where((t) => t.receiptNumber.equals('INV$invId')))
        .getSingle();
      expect(txBefore.date.year, equals(2026));

      // 3. Move invoice date to Sept 1st, 2026 (earlier than its previous date and all other invoices for this customer)
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

      // Invoice 108 transaction is now first because newDate is Oct 1, 2026 (earlier than Oct 2, 9, etc.)
      expect(statement.first.receiptNumber, equals('INV108'));

      // 8. Verify audit log entry
      final audit = await (db.select(db.auditLog)
        ..where((t) => t.tableNameField.equals('invoices') & t.recordId.equals(invId)))
        .getSingle();
      expect(audit.action, 'DATE_CHANGE');
      expect(audit.userId, 99);
      final newVal = jsonDecode(audit.newValue!) as Map<String, dynamic>;
      expect(newVal['date'], newDate.toIso8601String());
    });

    test('updatePurchaseDate on real purchase PUR-1789557648253: moves ledger, preserves balance, and writes audit', () async {
      const purchaseId = 'PUR-1789557648253';
      final pBefore = await (db.select(db.purchases)..where((t) => t.id.equals(purchaseId))).getSingle();
      final supplierId = pBefore.supplierId!;
      final oldPurchaseDate = pBefore.purchaseDate;
      final origCreatedAt = pBefore.createdAt;

      // 1. Check initial supplier balance
      final initialSuppBalance = await db.ledgerDao.getSupplierBalance(supplierId);
      expect(initialSuppBalance, equals(15255.0));

      // 2. Move purchase date
      final newPurchaseDate = DateTime(2026, 9, 20, 10, 0);
      final res = await dateService.updatePurchaseDate(
        purchaseId: purchaseId,
        newDate: newPurchaseDate,
        userId: '99',
      );

      expect(res.success, isTrue);

      // 3. Verify purchase row
      final pAfter = await (db.select(db.purchases)..where((t) => t.id.equals(purchaseId))).getSingle();
      expect(pAfter.purchaseDate, equals(newPurchaseDate));
      expect(pAfter.createdAt, equals(origCreatedAt));

      // 4. Verify supplier ledger transaction moved
      final suppTx = await (db.select(db.ledgerTransactions)
        ..where((t) => t.id.equals('${purchaseId}_ledger')))
        .getSingle();
      expect(suppTx.date, equals(newPurchaseDate));

      // 5. Verify Supplier Final Balance is 100% strictly invariant!
      final finalSuppBalance = await db.ledgerDao.getSupplierBalance(supplierId);
      expect(finalSuppBalance, equals(initialSuppBalance));

      // 6. Verify audit log
      final audit = await (db.select(db.auditLog)
        ..where((t) => t.tableNameField.equals('purchases') & t.details.like('%$purchaseId%')))
        .getSingle();
      expect(audit.action, 'DATE_CHANGE');
    });

    test('updatePaymentDate on real payment transaction: moves ledger and preserves balance', () async {
      const txId = '1785871778404_985682_pay';
      final txBefore = await db.ledgerDao.getTransactionById(txId);
      expect(txBefore, isNotNull);
      final customerId = txBefore!.refId;

      final balanceBefore = await db.ledgerDao.getCustomerBalance(customerId);

      final newPayDate = DateTime(2026, 6, 15, 14, 0);
      final res = await dateService.updatePaymentDate(
        transactionId: txId,
        newDate: newPayDate,
        userId: '99',
      );

      expect(res.success, isTrue);

      final txAfter = await db.ledgerDao.getTransactionById(txId);
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
    test('confirms cash_custodies has 3 rows in client DB, included in backup and restored intact', () async {
      // 1. Confirm 3 rows in client DB
      final custodiesPre = await db.select(db.cashCustodies).get();
      expect(custodiesPre.length, equals(3), reason: 'Client DB must contain exactly 3 cash_custodies');

      expect(custodiesPre[0].custodyNumber, 'CUST-000001');
      expect(custodiesPre[0].amount, 10000.0);
      expect(custodiesPre[0].status, 'cancelled');

      expect(custodiesPre[1].custodyNumber, 'CUST-000002');
      expect(custodiesPre[1].amount, 2000.0);
      expect(custodiesPre[1].status, 'cancelled');

      expect(custodiesPre[2].custodyNumber, 'CUST-000003');
      expect(custodiesPre[2].amount, 300.0);
      expect(custodiesPre[2].status, 'open');

      // 2. Perform full Backup using BackupService
      final backupService = BackupService(db);
      final backupInfo = await backupService.createBackup(
        adminUser(),
        description: 'Client DB Verification Backup',
      );

      expect(backupInfo.filename, isNotEmpty);
      expect(backupInfo.size, greaterThan(0));

      // 3. Open a clean target database for restore
      final restoreDbFile = File('${tempDir.path}/restore_target.sqlite');
      if (await restoreDbFile.exists()) {
        await restoreDbFile.delete();
      }
      final restoreDb = AppDatabase(NativeDatabase(restoreDbFile));

      // Verify restore target DB starts with 0 custodies
      final custodiesEmpty = await restoreDb.select(restoreDb.cashCustodies).get();
      expect(custodiesEmpty, isEmpty);

      // 4. Restore the backup into restoreDb
      final restoreService = BackupService(restoreDb);
      await restoreService.restoreBackup(adminUser(), backupInfo.filename);

      // 5. Run PRAGMA foreign_key_check to verify relational integrity
      final fkViolations = await restoreDb.customSelect('PRAGMA foreign_key_check').get();
      expect(fkViolations, isEmpty, reason: 'PRAGMA foreign_key_check must report 0 violations');

      // 6. Assert all 3 cash_custodies rows are restored completely and accurately!
      final custodiesPost = await restoreDb.select(restoreDb.cashCustodies).get();
      expect(custodiesPost.length, equals(3), reason: 'All 3 cash_custodies must be recovered');

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
