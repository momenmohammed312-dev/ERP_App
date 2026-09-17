import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/supplier_ledger_backfill.dart';

/// Supplier ledger root cause (zero-cards bug + inverted pay):
/// - EVERY purchase posts due (credit) + optional payment (debit),
///   whatever the payment method — cash purchases used to post nothing.
/// - Paying a supplier is a DEBIT (reduces what we owe).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (MethodCall methodCall) async => '.',
      );

  Future<AppDatabase> seedDb() async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.into(db.suppliers).insert(
          SuppliersCompanion.insert(id: 'S-1', name: 'مورد'),
        );
    return db;
  }

  group('recordSupplierPurchase', () {
    Future<void> seedPurchase(
      AppDatabase db, {
      required String id,
      required String number,
      double total = 1000,
      double paid = 0,
      String status = 'completed',
      String? supplierId = 'S-1',
    }) =>
        db.into(db.purchases).insert(
              PurchasesCompanion.insert(
                id: id,
                invoiceNumber: number,
                description: 'test',
                totalAmount: total,
                purchaseDate: DateTime(2026, 9, 1),
                createdAt: DateTime(2026, 9, 1),
                supplierId: Value(supplierId),
                paidAmount: Value(paid),
                status: Value(status),
              ),
            );

    test('repairs missing pairs, completes old singles, skips the rest',
        () async {
      final db = await seedDb();
      // A. cash purchase with no ledger rows at all (the zero-cards case).
      await seedPurchase(db, id: 'P-A', number: 'PUR-000010', total: 15129);
      // B. old-style single due row (credit = remaining).
      await seedPurchase(
        db,
        id: 'P-B',
        number: 'PUR-000011',
        total: 1000,
        paid: 200,
      );
      await db.ledgerDao.insertTransaction(
        LedgerTransactionsCompanion.insert(
          id: 'PUR-000011_ledger',
          entityType: 'Supplier',
          refId: 'S-1',
          date: DateTime(2026, 9, 1),
          description: 'شراء آجل: فاتورة PUR-000011',
          debit: const Value(0.0),
          credit: const Value(800.0),
          origin: 'purchase',
        ),
      );
      // C. already paired (new flow) — untouched.
      await seedPurchase(
        db,
        id: 'P-C',
        number: 'PUR-000012',
        total: 500,
        paid: 500,
      );
      await db.ledgerDao.recordSupplierPurchase(
        supplierId: 'S-1',
        invoiceNumber: 'PUR-000012',
        total: 500,
        paid: 500,
        date: DateTime(2026, 9, 1),
      );
      // D. voided + supplierless rows are skipped.
      await seedPurchase(
        db,
        id: 'P-D',
        number: 'PUR-000013',
        status: 'cancelled',
      );
      await seedPurchase(
        db,
        id: 'P-E',
        number: 'PUR-000014',
        supplierId: null,
      );

      // beforeOpen auto-ran the backfill on the then-empty DB and marked it
      // completed — clear the marker to simulate a first start that already
      // holds legacy purchases (the production upgrade path).
      await db.customUpdate(
        "DELETE FROM _migration_log WHERE step = 'supplier_ledger_backfill'",
      );

      await SupplierLedgerBackfill.run(db);

      // A repaired: full pair, balance counts it.
      // A=15129 + B completed pair (800-200) + C net 0.
      expect(await db.ledgerDao.getSupplierBalance('S-1'), 15729.0);
      final payB = await db.ledgerDao.getTransactionById(
        'PUR-000011_ledger_pay',
      );
      expect(payB, isNotNull);
      expect(payB!.debit, 200.0);
      // Marker recorded.
      final log = await db
          .customSelect(
            "SELECT status FROM _migration_log WHERE step = 'supplier_ledger_backfill' ORDER BY id DESC LIMIT 1",
          )
          .getSingle();
      expect(log.read<String>('status'), 'completed');

      // Second run is a no-op (guarded by the marker).
      await SupplierLedgerBackfill.run(db);
      final logCount = await db
          .customSelect(
            "SELECT COUNT(*) AS c FROM _migration_log WHERE step = 'supplier_ledger_backfill' AND status = 'completed'",
          )
          .getSingle();
      expect(logCount.read<int>('c'), 1);
      expect(await db.ledgerDao.getSupplierBalance('S-1'), 15729.0);
    });
  });

  group('recordSupplierPurchase', () {
    test('credit purchase posts due only; balance = total', () async {
      final db = await seedDb();
      await db.ledgerDao.recordSupplierPurchase(
        supplierId: 'S-1',
        invoiceNumber: 'PUR-000001',
        total: 15129,
        paid: 0,
        date: DateTime(2026, 9, 17),
      );
      expect(await db.ledgerDao.getSupplierBalance('S-1'), 15129.0);
    });

    test('cash fully-paid purchase nets to zero (not blind)', () async {
      final db = await seedDb();
      await db.ledgerDao.recordSupplierPurchase(
        supplierId: 'S-1',
        invoiceNumber: 'PUR-000002',
        total: 500,
        paid: 500,
        date: DateTime(2026, 9, 17),
      );
      expect(await db.ledgerDao.getSupplierBalance('S-1'), 0.0);
      // Both legs exist (auditability), they cancel out.
      final rows = await db.ledgerDao.getTransactionsByEntity(
        'Supplier',
        'S-1',
      );
      expect(rows.length, 2);
    });

    test('partial purchase then payment reduces what we owe', () async {
      final db = await seedDb();
      await db.ledgerDao.recordSupplierPurchase(
        supplierId: 'S-1',
        invoiceNumber: 'PUR-000003',
        total: 1000,
        paid: 200,
        date: DateTime(2026, 9, 17),
      );
      expect(await db.ledgerDao.getSupplierBalance('S-1'), 800.0);

      // Supplier payment dialog writes a DEBIT (used to be credit,
      // which grew the debt instead of shrinking it).
      await db.ledgerDao.insertTransaction(
        LedgerTransactionsCompanion.insert(
          id: 'pay-1',
          entityType: 'Supplier',
          refId: 'S-1',
          date: DateTime(2026, 9, 17),
          description: 'سداد دفعة للمورد',
          debit: const Value(300.0),
          credit: const Value(0.0),
          origin: 'payment',
          paymentMethod: const Value('cash'),
        ),
      );
      expect(await db.ledgerDao.getSupplierBalance('S-1'), 500.0);
    });
  });
}
