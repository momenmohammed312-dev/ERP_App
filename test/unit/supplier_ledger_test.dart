import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';

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
