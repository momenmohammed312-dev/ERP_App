import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/services/purchase_edit_service.dart';
import 'package:pos_offline_desktop/core/services/purchase_return_service.dart';

/// Supplier purchase edit + return (Item 3):
/// - edit rewrites lines/stock/header/ledger atomically, number preserved;
/// - orphan lines (product deleted since) stay verbatim;
/// - returns are capped per line, restore stock, post reversals.
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

  Future<int> seedProduct(
    AppDatabase db,
    String name,
    double price,
    int qty,
  ) =>
      db.into(db.products).insert(
            ProductsCompanion.insert(
              name: name,
              price: price,
              quantity: qty,
              category: const Value('test'),
            ),
          );

  Future<void> seedSupplier(AppDatabase db) => db.into(db.suppliers).insert(
        SuppliersCompanion.insert(id: 'S-9', name: 'مورد'),
      );

  /// Mimics the create flow: purchase row + lines + stock + ledger pair.
  Future<void> seedPurchase(
    AppDatabase db, {
    required String id,
    required String number,
    required List<(int productId, int qty, double price)> lines,
    double paid = 0,
  }) async {
    double total = 0;
    for (final l in lines) {
      total += l.$2 * l.$3;
    }
    await db.into(db.purchases).insert(
          PurchasesCompanion.insert(
            id: id,
            invoiceNumber: number,
            description: 'test',
            totalAmount: total,
            purchaseDate: DateTime(2026, 9, 1),
            createdAt: DateTime(2026, 9, 1),
            supplierId: const Value('S-9'),
            paidAmount: Value(paid),
            status: Value(paid >= total ? 'paid' : 'pending'),
          ),
        );
    for (final l in lines) {
      await db.into(db.purchaseItems).insert(
            PurchaseItemsCompanion.insert(
              id: '${number}_${l.$1}',
              purchaseId: number,
              productId: l.$1.toString(),
              quantity: l.$2,
              unitPrice: l.$3,
              totalPrice: l.$2 * l.$3,
              unit: 'قطعة',
              createdAt: DateTime(2026, 9, 1),
            ),
          );
      final p = await db.productDao.getProductById(l.$1);
      await db.productDao.updateProduct(
        p!.copyWith(quantity: p.quantity + l.$2),
      );
    }
    await db.ledgerDao.recordSupplierPurchase(
      supplierId: 'S-9',
      invoiceNumber: number,
      total: total,
      paid: paid,
      date: DateTime(2026, 9, 1),
    );
  }

  Future<double> stockOf(AppDatabase db, int id) async =>
      (await db.productDao.getProductById(id))!.quantity.toDouble();

  Future<Purchase> purchaseOf(AppDatabase db, String id) async =>
      (await (db.select(db.purchases)..where((t) => t.id.equals(id)))
          .getSingle());

  group('PurchaseEditService', () {
    test('rewrites lines, stock, header and ledger; number kept', () async {
      final db = await openDb();
      await seedSupplier(db);
      final a = await seedProduct(db, 'A', 50, 100);
      final b = await seedProduct(db, 'B', 100, 50);
      final c = await seedProduct(db, 'C', 100, 30);
      // A×10@50 + B×5@100 = 1000, paid 200.
      // Stock now: A=110, B=55, C=30.
      await seedPurchase(
        db,
        id: 'PX-1',
        number: 'PUR-000021',
        lines: [(a, 10, 50.0), (b, 5, 100.0)],
        paid: 200,
      );

      // Edit to A×4@50 + C×2@100 = 400, paid stays 200.
      await PurchaseEditService(db).applyEdit(
        purchaseId: 'PX-1',
        invoiceNumber: 'PUR-000021',
        supplierId: 'S-9',
        total: 400,
        paid: 200,
        paymentMethod: 'credit',
        lines: [
          PurchaseEditLine(productId: a, quantity: 4, unit: 'قطعة', unitPrice: 50),
          PurchaseEditLine(productId: c, quantity: 2, unit: 'قطعة', unitPrice: 100),
        ],
      );

      // Stock: undo old purchase qty, apply new (purchases add stock).
      expect(await stockOf(db, a), 104.0); // 110-10+4
      expect(await stockOf(db, b), 50.0); // 55-5, line removed
      expect(await stockOf(db, c), 32.0); // 30+2
      // Header: number kept, totals rewritten, status partial.
      final p = await purchaseOf(db, 'PX-1');
      expect(p.invoiceNumber, 'PUR-000021');
      expect(p.totalAmount, 400.0);
      expect(p.paidAmount, 200.0);
      expect(p.status, 'partial');
      // Ledger: exactly one rewritten pair.
      final txs = await db.ledgerDao.getTransactionsByEntity('Supplier',
        'S-9');
      expect(txs.length, 2);
      expect(await db.ledgerDao.getSupplierBalance('S-9'), 200.0);
    });

    test('orphan lines stay verbatim (product deleted since)', () async {
      final db = await openDb();
      await seedSupplier(db);
      final a = await seedProduct(db, 'A', 50, 100);
      final b = await seedProduct(db, 'B', 100, 50);
      await seedPurchase(
        db,
        id: 'PX-2',
        number: 'PUR-000022',
        lines: [(a, 2, 50.0), (b, 1, 100.0)],
      );
      // Delete product B outright: its line becomes an orphan.
      await db.productDao.deleteProduct(
        (await db.productDao.getProductById(b))!,
      );

      await PurchaseEditService(db).applyEdit(
        purchaseId: 'PX-2',
        invoiceNumber: 'PUR-000022',
        supplierId: 'S-9',
        total: 250, // 100 (A×2 new... see below) + 100 orphan frozen
        paid: 0,
        paymentMethod: 'cash',
        lines: [
          PurchaseEditLine(productId: a, quantity: 3, unit: 'قطعة', unitPrice: 50),
        ],
      );

      // Orphan row untouched (qty 1, value 100 counted in header total).
      // Lines are keyed by invoice NUMBER (not row id).
      final lines = await db.purchaseDao.getPurchaseItems('PUR-000022');
      expect(lines.length, 2);
      final p = await purchaseOf(db, 'PX-2');
      expect(p.totalAmount, 250.0);
      // A stock: undo old (+2 → 100), apply new (+3) = 103.
      expect(await stockOf(db, a), 103.0);
    });
  });

  group('PurchaseReturnService', () {
    test('partial return shrinks lines, stock, header and posts reversal',
        () async {
      final db = await openDb();
      await seedSupplier(db);
      final a = await seedProduct(db, 'A', 100, 10);
      await seedPurchase(
        db,
        id: 'PX-3',
        number: 'PUR-000023',
        lines: [(a, 10, 100.0)],
      );
      // Stock after purchase: 20.
      final lineId = 'PUR-000023_$a';
      final value = await PurchaseReturnService(db).processReturn(
        purchaseId: 'PX-3',
        itemReturns: {lineId: 3},
      );
      expect(value, 300.0);
      expect(await stockOf(db, a), 17.0);
      final p = await purchaseOf(db, 'PX-3');
      expect(p.totalAmount, 700.0);
      expect(p.status, 'pending');
      expect(await db.ledgerDao.getSupplierBalance('S-9'), 700.0);
      final revs = await db.ledgerDao.getTransactionsByEntity('Supplier',
        'S-9');
      expect(revs.any((t) => t.origin == 'reversal' && t.debit == 300.0),
          isTrue);
    });

    test('over-return throws with zero side effects', () async {
      final db = await openDb();
      await seedSupplier(db);
      final a = await seedProduct(db, 'A', 100, 10);
      await seedPurchase(
        db,
        id: 'PX-4',
        number: 'PUR-000024',
        lines: [(a, 4, 100.0)],
      );
      await expectLater(
        PurchaseReturnService(db).processReturn(
          purchaseId: 'PX-4',
          itemReturns: {'PUR-000024_$a': 5},
        ),
        throwsException,
      );
      expect(await stockOf(db, a), 14.0);
      expect((await purchaseOf(db, 'PX-4')).totalAmount, 400.0);
      expect(await db.ledgerDao.getSupplierBalance('S-9'), 400.0);
    });

    test('repeat return after full return is a safe no-op', () async {
      final db = await openDb();
      await seedSupplier(db);
      final a = await seedProduct(db, 'A', 100, 10);
      await seedPurchase(
        db,
        id: 'PX-5',
        number: 'PUR-000025',
        lines: [(a, 2, 100.0)],
        paid: 200,
      );
      final lineId = 'PUR-000025_$a';
      expect(
        await PurchaseReturnService(
          db,
        ).processReturn(purchaseId: 'PX-5', itemReturns: {lineId: 2}),
        200.0,
      );
      // Line gone; second attempt with empty map does nothing.
      expect(
        await PurchaseReturnService(
          db,
        ).processReturn(purchaseId: 'PX-5', itemReturns: {}),
        0.0,
      );
      final txs = await db.ledgerDao.getTransactionsByEntity('Supplier',
        'S-9');
      final reversals = txs.where((t) => t.origin == 'reversal').toList();
      expect(reversals.length, 1);
      expect((await purchaseOf(db, 'PX-5')).totalAmount, 0.0);
    });
  });
}
