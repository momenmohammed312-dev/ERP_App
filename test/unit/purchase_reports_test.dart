import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/services/invoice_number_formatter.dart';

/// Item 5 data layer (the PDF layouts themselves need platform channels and
/// are code-reviewed, not headless-tested):
/// - purchases report: date-range rows, supplier names, totals, short numbers;
/// - all-suppliers statement: per-supplier opening/period/closing + totals.
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

  Future<void> seedPurchase(
    AppDatabase db, {
    required String id,
    required String number,
    required String supplierId,
    required double total,
    double paid = 0,
    required DateTime date,
  }) async {
    await db.into(db.purchases).insert(
          PurchasesCompanion.insert(
            id: id,
            invoiceNumber: number,
            description: 'test',
            totalAmount: total,
            purchaseDate: date,
            createdAt: date,
            supplierId: Value(supplierId),
            paidAmount: Value(paid),
            status: const Value('completed'),
          ),
        );
    await db.ledgerDao.recordSupplierPurchase(
      supplierId: supplierId,
      invoiceNumber: number,
      total: total,
      paid: paid,
      date: date,
    );
  }

  group('purchases report data', () {
    test('date range, names, totals and short numbers', () async {
      final db = await openDb();
      await db.into(db.suppliers).insert(
            SuppliersCompanion.insert(id: 'S-A', name: 'ألفا'),
          );
      await db.into(db.suppliers).insert(
            SuppliersCompanion.insert(id: 'S-B', name: 'بيتا'),
          );
      await seedPurchase(
        db,
        id: 'P-1',
        number: 'PUR-000001',
        supplierId: 'S-A',
        total: 1000,
        paid: 200,
        date: DateTime(2026, 9, 10),
      );
      await seedPurchase(
        db,
        id: 'P-2',
        number: 'PUR-000002',
        supplierId: 'S-B',
        total: 500,
        date: DateTime(2026, 9, 20),
      );

      final range = await db.purchaseDao.getPurchasesByDateRange(
        DateTime(2026, 9, 1),
        DateTime(2026, 9, 15, 23, 59, 59),
      );
      expect(range.length, 1);
      expect(range.first.invoiceNumber, 'PUR-000001');
      // Display layer shows short numbers, never raw ids.
      expect(
        displayInvoiceNumber(range.first.invoiceNumber, null),
        'PUR-000001',
      );

      final all = await db.purchaseDao.getPurchasesByDateRange(
        DateTime(2026, 9, 1),
        DateTime(2026, 9, 30, 23, 59, 59),
      );
      expect(all.length, 2);
      final grand = all.fold<double>(0, (s, p) => s + p.totalAmount);
      expect(grand, 1500.0);
      final names = <String, String>{};
      for (final p in all) {
        names[p.supplierId!] =
            (await db.supplierDao.getSupplierById(p.supplierId!))!.name;
      }
      expect(names, {'S-A': 'ألفا', 'S-B': 'بيتا'});
    });
  });

  group('all-suppliers statement data', () {
    test('per-supplier opening/period/closing + grand totals', () async {
      final db = await openDb();
      await db.into(db.suppliers).insert(
            SuppliersCompanion.insert(id: 'S-A', name: 'ألفا'),
          );
      await db.into(db.suppliers).insert(
            SuppliersCompanion.insert(
              id: 'S-B',
              name: 'بيتا',
              openingBalance: const Value(100.0),
            ),
          );
      await seedPurchase(
        db,
        id: 'P-1',
        number: 'PUR-000001',
        supplierId: 'S-A',
        total: 1000,
        paid: 200,
        date: DateTime(2026, 9, 10),
      );

      final from = DateTime(2026, 9, 1);
      final to = DateTime(2026, 9, 30, 23, 59, 59);
      double gOpen = 0, gCredit = 0, gDebit = 0, gClose = 0;
      final rows = <Map<String, double>>[];
      for (final s in await db.supplierDao.getActiveSuppliers()) {
        final opening = await db.ledgerDao.getRunningBalance(
          'Supplier',
          s.id,
          upToDate: from.subtract(const Duration(seconds: 1)),
        );
        final txs = await db.ledgerDao.getTransactionsByDateRange(
          'Supplier',
          s.id,
          from,
          to,
        );
        final credit = txs.fold<double>(0, (sum, t) => sum + t.credit);
        final debit = txs.fold<double>(0, (sum, t) => sum + t.debit);
        final closing = await db.ledgerDao.getRunningBalance(
          'Supplier',
          s.id,
          upToDate: to,
        );
        rows.add({
          'opening': opening,
          'credit': credit,
          'debit': debit,
          'closing': closing,
        });
        gOpen += opening;
        gCredit += credit;
        gDebit += debit;
        gClose += closing;
      }

      expect(rows.length, 2);
      // A: 0 + 1000 − 200 = 800. B: opening 100, no activity.
      expect(gOpen, 100.0);
      expect(gCredit, 1000.0);
      expect(gDebit, 200.0);
      expect(gClose, 900.0);
      // Grand closing reconciles with the ledger truth.
      final unified = await db.ledgerDao.getAllSupplierBalances();
      final unifiedTotal = unified.fold<double>(
        0,
        (s, m) => s + ((m['balance'] as num?)?.toDouble() ?? 0),
      );
      expect(unifiedTotal, gClose);
    });
  });
}
