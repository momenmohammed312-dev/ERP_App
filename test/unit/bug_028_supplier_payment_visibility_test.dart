import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/utils/app_utils.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('BUG-028: Supplier Payment Visibility & Ledger Consistency', () {
    test('Supplier payment transactions appear alongside purchases with correct metadata', () async {
      const supplierId = 'SUP_TEST_001';

      // 1. Add supplier
      await db.supplierDao.insertSupplier(
        SuppliersCompanion.insert(
          id: supplierId,
          name: 'مورد اختبار',
          createdAt: Value(DateTime.now()),
        ),
      );

      // 2. Add purchase invoice
      await db.into(db.purchases).insert(
        PurchasesCompanion.insert(
          id: 'PUR-001',
          supplierId: const Value(supplierId),
          invoiceNumber: 'ش-004',
          description: 'فاتورة شراء تجريبية',
          totalAmount: 500.0,
          paidAmount: const Value(0.0),
          purchaseDate: DateTime(2026, 10, 20),
          createdAt: DateTime(2026, 10, 20),
        ),
      );

      // 3. Record payment to supplier via ledger (origin: 'payment', debit: 120.0)
      const paymentTxId = 'PAY_TEST_120';
      await db.ledgerDao.insertTransaction(
        LedgerTransactionsCompanion.insert(
          id: paymentTxId,
          entityType: 'Supplier',
          refId: supplierId,
          date: DateTime(2026, 10, 25),
          description: 'سداد دفعة نقدية للمورد',
          debit: const Value(120.0),
          credit: const Value(0.0),
          origin: 'payment',
          paymentMethod: const Value('cash'),
          createdAt: Value(DateTime(2026, 10, 25)),
        ),
      );

      // 4. Query purchases
      final purchasesResult = await db
          .customSelect(
            '''
        SELECT p.id, p.invoice_number, p.purchase_date, p.total_amount, 
               p.paid_amount, p.payment_method, p.status, p.is_deleted
        FROM purchases p
        WHERE p.supplier_id = ?
        ORDER BY p.purchase_date DESC
        ''',
            variables: [Variable.withString(supplierId)],
          )
          .get();

      final purchaseItems = purchasesResult.map((row) {
        final d = row.data;
        final pDate = parseDate(d['purchase_date']);
        return {
          'id': d['id']?.toString() ?? '',
          'type': 'purchase',
          'invoice_number': d['invoice_number']?.toString(),
          'date': pDate,
          'total_amount': (d['total_amount'] as num?)?.toDouble() ?? 0.0,
          'paid_amount': (d['paid_amount'] as num?)?.toDouble() ?? 0.0,
          'status': d['status']?.toString() ?? 'pending',
          'description': 'فاتورة ${d['invoice_number'] ?? 'غير محدد'}',
        };
      }).toList();

      // 5. Query payments
      final paymentsResult = await db
          .customSelect(
            '''
        SELECT id, date, description, debit, credit, origin, payment_method, receipt_number
        FROM ledger_transactions
        WHERE entity_type = 'Supplier' AND ref_id = ? AND (origin = 'payment' OR origin = 'reversal')
        ORDER BY date DESC
        ''',
            variables: [Variable.withString(supplierId)],
          )
          .get();

      final paymentItems = paymentsResult.map((row) {
        final d = row.data;
        final debit = (d['debit'] as num?)?.toDouble() ?? 0.0;
        final credit = (d['credit'] as num?)?.toDouble() ?? 0.0;
        final amount = debit > 0 ? debit : credit;
        final pDate = parseDate(d['date']);

        return {
          'id': d['id']?.toString() ?? '',
          'type': 'payment',
          'invoice_number': d['receipt_number']?.toString(),
          'date': pDate,
          'total_amount': amount,
          'paid_amount': amount,
          'status': 'paid',
          'description': d['description']?.toString() ?? 'سداد دفعة للمورد',
        };
      }).toList();

      final combined = [...purchaseItems, ...paymentItems];
      combined.sort((a, b) => (b['date'] as DateTime).compareTo(a['date'] as DateTime));

      // Verifications
      expect(combined.length, equals(2));
      // First transaction is the payment on 25th
      expect(combined[0]['type'], equals('payment'));
      expect(combined[0]['id'], equals(paymentTxId));
      expect(combined[0]['total_amount'], equals(120.0));
      expect(combined[0]['description'], equals('سداد دفعة نقدية للمورد'));

      // Second transaction is the purchase on 20th
      expect(combined[1]['type'], equals('purchase'));
      expect(combined[1]['id'], equals('PUR-001'));
      expect(combined[1]['total_amount'], equals(500.0));
    });

    test('Supplier payment update and delete correctly maintains ledger integrity', () async {
      const supplierId = 'SUP_TEST_002';
      await db.supplierDao.insertSupplier(
        SuppliersCompanion.insert(
          id: supplierId,
          name: 'مورد 2',
          createdAt: Value(DateTime.now()),
        ),
      );

      const paymentTxId = 'PAY_TEST_002';
      await db.ledgerDao.insertTransaction(
        LedgerTransactionsCompanion.insert(
          id: paymentTxId,
          entityType: 'Supplier',
          refId: supplierId,
          date: DateTime(2026, 10, 25),
          description: 'دفعة سداد أولية',
          debit: const Value(150.0),
          credit: const Value(0.0),
          origin: 'payment',
          paymentMethod: const Value('cash'),
          createdAt: Value(DateTime(2026, 10, 25)),
        ),
      );

      // Verify initial balance (-150 because we paid in advance / debit)
      final initialBalance = await db.ledgerDao.getSupplierBalance(supplierId);
      expect(initialBalance, equals(-150.0));

      // Update payment to 200.0
      await (db.update(db.ledgerTransactions)
            ..where((t) => t.id.equals(paymentTxId)))
          .write(
        const LedgerTransactionsCompanion(
          debit: Value(200.0),
          description: Value('دفعة سداد معدلة'),
        ),
      );

      final updatedTx = await db.ledgerDao.getTransactionById(paymentTxId);
      expect(updatedTx?.debit, equals(200.0));
      expect(updatedTx?.description, equals('دفعة سداد معدلة'));

      final updatedBalance = await db.ledgerDao.getSupplierBalance(supplierId);
      expect(updatedBalance, equals(-200.0));

      // Delete payment
      await db.ledgerDao.deleteTransaction(paymentTxId);
      final deletedTx = await db.ledgerDao.getTransactionById(paymentTxId);
      expect(deletedTx, isNull);

      final finalBalance = await db.ledgerDao.getSupplierBalance(supplierId);
      expect(finalBalance, equals(0.0));
    });
  });
}
