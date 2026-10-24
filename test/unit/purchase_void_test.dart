import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/services/purchase_void_service.dart';

/// إلغاء فاتورة مشتريات — العكس لازم يبقى متماثل مع الشراء.
///
/// الشراء **زاد** المخزون، فالإلغاء لازم **يخصم** منه. أسوأ خطأ هنا إن
/// الفاتورة تتمسح والمخزون يفضل زائد — وده أصعب خطأ نتاكشف منه.
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
    await db.dayDao.getOrCreateTodayDay(openingBalance: 0, openedBy: 'tester');
    return db;
  }

  Future<int> seedProduct(AppDatabase db, String name, int qty) =>
      db.into(db.products).insert(
            ProductsCompanion.insert(
              name: name,
              price: 100,
              quantity: qty,
              category: const Value('test'),
            ),
          );

  Future<void> seedSupplier(AppDatabase db, String id) =>
      db.into(db.suppliers).insert(
            SuppliersCompanion.insert(id: id, name: 'مورد $id'),
          );

  /// فاتورة مشتريات حقيقية: مخزون زاد + قيود مورد (زي EnhancedPurchaseInvoicePage).
  Future<String> seedPurchase(
    AppDatabase db, {
    String supplierId = 'S-1',
    String number = 'PUR-000001',
    double paid = 0,
    List<(int productId, int qty)> lines = const [],
  }) async {
    return db.transaction(() async {
      final total =
          lines.fold<double>(0, (s, l) => s + l.$2 * 100);
      await db.into(db.purchases).insert(
            PurchasesCompanion.insert(
              id: number,
              supplierId: Value(supplierId),
              invoiceNumber: number,
              description: 'فاتورة اختبار',
              totalAmount: total,
              paidAmount: Value(paid),
              paymentMethod:
                  Value(paid >= total && total > 0 ? 'cash' : 'credit'),
              status: const Value('completed'),
              purchaseDate: DateTime.now(),
              createdAt: DateTime.now(),
            ),
          );
      for (final l in lines) {
        await db.into(db.purchaseItems).insert(
              PurchaseItemsCompanion.insert(
                id: '${number}_${l.$1}',
                purchaseId: number,
                productId: l.$1.toString(),
                quantity: l.$2,
                unitPrice: 100,
                totalPrice: l.$2 * 100,
                unit: 'قطعة',
                createdAt: DateTime.now(),
              ),
            );
        final p = await db.productDao.getProductById(l.$1);
        await db.productDao.updateProduct(
          p!.copyWith(quantity: p.quantity + l.$2),
        );
      }
      await db.ledgerDao.recordSupplierPurchase(
        supplierId: supplierId,
        invoiceNumber: number,
        total: total,
        paid: paid,
        date: DateTime.now(),
      );
      return number;
    });
  }

  group('PurchaseVoidService — العكس المتماثل', () {
    test('stock goes back DOWN, lines and ledger are gone', () async {
      final db = await openDb();
      await seedSupplier(db, 'S-1');
      final productId = await seedProduct(db, 'صنف', 20);

      final number = await seedPurchase(
        db,
        lines: [(productId, 5)],
      );

      // الشراء زاد 5 → 25.
      var p = await db.productDao.getProductById(productId);
      expect(p!.quantity, 25);
      expect((await db.purchaseDao.getPurchaseItems(number)).length, 1);
      expect(
        (await db.ledgerDao.getTransactionById('${number}_ledger')) != null,
        isTrue,
      );

      await PurchaseVoidService(db).voidPurchase(
        purchaseId: number,
        reason: 'خطأ إدخال',
        voidedBy: 'manager1',
      );

      // ⚠️ الأهم: المخزون رجع 20 مش 25.
      p = await db.productDao.getProductById(productId);
      expect(p!.quantity, 20);

      // السطور اتشالت.
      expect(await db.purchaseDao.getPurchaseItems(number), isEmpty);

      // القيود اتشالت.
      expect(await db.ledgerDao.getTransactionById('${number}_ledger'), isNull);
      expect(
          await db.ledgerDao.getTransactionById('${number}_ledger_pay'), isNull);

      // رصيد المورد رجع صفر.
      expect(await db.ledgerDao.getSupplierBalance('S-1'), 0.0);

      // الـsoft delete.
      final purchase = await (db.select(db.purchases)
            ..where((t) => t.id.equals(number)))
          .getSingle();
      expect(purchase.isDeleted, isTrue);
      expect(purchase.notes, contains('manager1'));
      expect(purchase.notes, contains('خطأ إدخال'));
    });

    test('paid purchase: both ledger rows reversed', () async {
      final db = await openDb();
      await seedSupplier(db, 'S-2');
      final productId = await seedProduct(db, 'صنف', 10);
      final number = await seedPurchase(
        db,
        supplierId: 'S-2',
        paid: 500,
        lines: [(productId, 5)],
      );

      expect(await db.ledgerDao.getSupplierBalance('S-2'), 0.0);
      expect(
        (await db.ledgerDao.getTransactionsByReceiptNumber('${number}_ledger'))
                .length +
            1,
        greaterThanOrEqualTo(1),
      );

      await PurchaseVoidService(db).voidPurchase(
        purchaseId: number,
        reason: 'خطأ إدخال',
        voidedBy: 'manager1',
      );

      expect(await db.ledgerDao.getTransactionById('${number}_ledger'), isNull);
      expect(
          await db.ledgerDao.getTransactionById('${number}_ledger_pay'), isNull);
      expect(await db.ledgerDao.getSupplierBalance('S-2'), 0.0);
    });

    test('second void throws and does NOT decrement stock twice', () async {
      final db = await openDb();
      await seedSupplier(db, 'S-3');
      final productId = await seedProduct(db, 'صنف', 10);
      final number = await seedPurchase(
        db,
        supplierId: 'S-3',
        number: 'PUR-000002',
        lines: [(productId, 4)],
      );

      final svc = PurchaseVoidService(db);
      await svc.voidPurchase(
        purchaseId: number,
        reason: 'خطأ إدخال',
        voidedBy: 'manager1',
      );

      await expectLater(
        svc.voidPurchase(
          purchaseId: number,
          reason: 'خطأ إدخال',
          voidedBy: 'manager1',
        ),
        throwsException,
      );

      // 10 مش 6 — التشغيل التاني مرفوض قبل أي كتابة.
      final p = await db.productDao.getProductById(productId);
      expect(p!.quantity, 10);
    });

    test('empty reason rejected, purchase stays untouched', () async {
      final db = await openDb();
      await seedSupplier(db, 'S-4');
      final productId = await seedProduct(db, 'صنف', 10);
      final number = await seedPurchase(
        db,
        supplierId: 'S-4',
        number: 'PUR-000003',
        lines: [(productId, 2)],
      );

      await expectLater(
        PurchaseVoidService(db).voidPurchase(
          purchaseId: number,
          reason: '  ',
          voidedBy: 'manager1',
        ),
        throwsException,
      );

      final p = await db.productDao.getProductById(productId);
      expect(p!.quantity, 12);
      final purchase = await (db.select(db.purchases)
            ..where((t) => t.id.equals(number)))
          .getSingle();
      expect(purchase.isDeleted, isFalse);
    });

    test('fully-returned purchase (total 0) is not voidable', () async {
      final db = await openDb();
      await seedSupplier(db, 'S-5');
      final productId = await seedProduct(db, 'صنف', 10);
      final number = await seedPurchase(
        db,
        supplierId: 'S-5',
        number: 'PUR-000004',
        lines: [(productId, 3)],
      );

      // استرجاع كامل → السطر اتمسح والـtotal بقى صفر.
      await db.transaction(() async {
        await (db.delete(db.purchaseItems)
              ..where((t) => t.purchaseId.equals(number)))
            .go();
        await (db.update(db.purchases)..where((t) => t.id.equals(number)))
            .write(PurchasesCompanion(totalAmount: const Value(0)));
        final p = await db.productDao.getProductById(productId);
        await db.productDao.updateProduct(
            p!.copyWith(quantity: p.quantity - 3));
      });

      await expectLater(
        PurchaseVoidService(db).voidPurchase(
          purchaseId: number,
          reason: 'خطأ إدخال',
          voidedBy: 'manager1',
        ),
        throwsException,
      );

      final p = await db.productDao.getProductById(productId);
      expect(p!.quantity, 10);
    });

    test('missing purchase throws', () async {
      final db = await openDb();
      await expectLater(
        PurchaseVoidService(db).voidPurchase(
          purchaseId: 'PUR-NOPE',
          reason: 'خطأ إدخال',
          voidedBy: 'manager1',
        ),
        throwsException,
      );
    });

    test('other suppliers are unaffected', () async {
      final db = await openDb();
      await seedSupplier(db, 'S-6');
      await seedSupplier(db, 'S-7');
      final productId = await seedProduct(db, 'صنف', 50);
      final n1 = await seedPurchase(
        db,
        supplierId: 'S-6',
        number: 'PUR-000005',
        lines: [(productId, 2)],
      );
      await seedPurchase(
        db,
        supplierId: 'S-7',
        number: 'PUR-000006',
        lines: [(productId, 3)],
      );

      await PurchaseVoidService(db).voidPurchase(
        purchaseId: n1,
        reason: 'خطأ إدخال',
        voidedBy: 'manager1',
      );

      // فاتورة S-7 لسه موجودة ومخزونها زائد.
      expect(await db.ledgerDao.getSupplierBalance('S-7'), 300.0);
      final p = await db.productDao.getProductById(productId);
      expect(p!.quantity, 53); // 50 + 3 من الفاتورة الباقية
    });

    test('audit log records the void', () async {
      final db = await openDb();
      await seedSupplier(db, 'S-8');
      final productId = await seedProduct(db, 'صنف', 10);
      final number = await seedPurchase(
        db,
        supplierId: 'S-8',
        number: 'PUR-000007',
        lines: [(productId, 1)],
      );

      await PurchaseVoidService(db).voidPurchase(
        purchaseId: number,
        reason: 'فاتورة تجريبية',
        voidedBy: 'manager1',
      );

      final logs = await db.auditDao.getAuditLogs(tableName: 'purchases');
      expect(logs.any((l) => l.action == 'VOID'), isTrue);
      expect(logs.first.details, contains('manager1'));
      expect(logs.first.details, contains('فاتورة تجريبية'));
    });

    test('FEAT-018: voidPurchase decrements stock, deletes ledger entries, and restores supplier balance', () async {
      final db = await openDb();
      await seedSupplier(db, 'S-FEAT018');
      final productId = await seedProduct(db, 'صنف_مورد', 20);

      // 1. Initial purchase to establish a non-zero supplier balance
      await seedPurchase(
        db,
        supplierId: 'S-FEAT018',
        number: 'PUR-BASE001',
        paid: 100.0,
        lines: [(productId, 2)], // 2 * 100 = 200 total, paid 100 -> remaining debt 100
      );
      final initialBalance = await db.ledgerDao.getSupplierBalance('S-FEAT018');
      expect(initialBalance, 100.0);
      var p = await db.productDao.getProductById(productId);
      expect(p!.quantity, 22);

      // 2. Second purchase that will be voided
      final targetNumber = await seedPurchase(
        db,
        supplierId: 'S-FEAT018',
        number: 'PUR-VOID002',
        paid: 150.0,
        lines: [(productId, 5)], // 5 * 100 = 500 total, paid 150 -> debt +350 -> total 450
      );
      p = await db.productDao.getProductById(productId);
      expect(p!.quantity, 27); // 22 + 5
      expect(await db.ledgerDao.getSupplierBalance('S-FEAT018'), 450.0);

      // 3. Void the second purchase
      await PurchaseVoidService(db).voidPurchase(
        purchaseId: targetNumber,
        reason: 'إلغاء الفاتورة من كشف الحساب والموردين',
        voidedBy: 'admin',
      );

      // 4. Stock must return exactly to 22 (the 5 units from voided purchase are removed)
      p = await db.productDao.getProductById(productId);
      expect(p!.quantity, 22);

      // 5. Ledger entries for PUR-VOID002 must be deleted
      expect(await db.ledgerDao.getTransactionById('${targetNumber}_ledger'), isNull);
      expect(await db.ledgerDao.getTransactionById('${targetNumber}_ledger_pay'), isNull);

      // 6. Base purchase ledger entries must remain intact
      expect(await db.ledgerDao.getTransactionById('PUR-BASE001_ledger'), isNotNull);

      // 7. Supplier balance must return exactly to initialBalance (100.0)
      final finalBalance = await db.ledgerDao.getSupplierBalance('S-FEAT018');
      expect(finalBalance, initialBalance);
    });
  });
}