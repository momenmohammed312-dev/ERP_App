import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/services/invoice_service.dart';
import 'package:pos_offline_desktop/core/services/invoice_void_service.dart';
import 'package:pos_offline_desktop/core/services/purchase_void_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (MethodCall methodCall) async => '.',
      );

  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.dayDao.getOrCreateTodayDay(openingBalance: 0, openedBy: 'tester');
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> seedProduct(String name, int qty, {double price = 100}) =>
      db.into(db.products).insert(
            ProductsCompanion.insert(
              name: name,
              price: price,
              quantity: qty,
              category: const Value('test'),
            ),
          );

  Future<void> seedCustomer(String id, {double opening = 0}) =>
      db.into(db.customers).insert(
            CustomersCompanion.insert(
              id: id,
              name: 'عميل $id',
              openingBalance: Value(opening),
            ),
          );

  Future<void> seedSupplier(String id) =>
      db.into(db.suppliers).insert(
            SuppliersCompanion.insert(id: id, name: 'مورد $id'),
          );

  /// فاتورة مشتريات مع مخزون وقيود المورد
  Future<String> seedPurchase({
    String supplierId = 'S-1',
    String number = 'PUR-000001',
    double paid = 0,
    List<(int productId, int qty)> lines = const [],
  }) async {
    return db.transaction(() async {
      final total = lines.fold<double>(0, (s, l) => s + l.$2 * 100);
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

  group('Suite 3: Universal Void/Delete Invoices & Purchases (FEAT-018)', () {
    test('1. Void Sales Invoice completely restores inventory and clears ledger', () async {
      final p1 = await seedProduct('تيشيرت', 50);
      await seedCustomer('C1');

      final result = await InvoiceService(db).createInvoice(
        customerId: 'C1',
        customerName: 'عميل C1',
        paymentMethod: 'credit',
        totalAmount: 200,
        paidAmount: 0,
        status: 'pending',
        items: [
          InvoiceItemParams(productId: p1, quantity: 2, price: 100),
        ],
      );

      // Verify stock was decremented
      var productAfterSale = await db.productDao.getProductById(p1);
      expect(productAfterSale!.quantity, equals(48));

      // Customer debt recorded
      expect(await db.ledgerDao.getCustomerBalance('C1'), equals(200.0));

      // Void the sales invoice
      await InvoiceVoidService(db).voidInvoice(
        invoiceId: result.invoiceId,
        reason: VoidReasons.inputError,
        notes: 'إلغاء تجريبي للاختبار',
        voidedBy: 'مدير النظام',
      );

      // Verify stock is strictly restored to 50
      final productAfterVoid = await db.productDao.getProductById(p1);
      expect(productAfterVoid!.quantity, equals(50));

      // Customer balance reversed to 0
      expect(await db.ledgerDao.getCustomerBalance('C1'), equals(0.0));

      // Verify invoice marked as voided
      final invoice = await (db.select(db.invoices)..where((tbl) => tbl.id.equals(result.invoiceId))).getSingle();
      expect(invoice.status, equals('voided'));
      expect(invoice.voidReason, equals(VoidReasons.inputError));
      expect(invoice.voidedBy, equals('مدير النظام'));
      expect(invoice.voidedAt, isNotNull);
      expect(invoice.netAmount, equals(0.0));
    });

    test('2. Void Purchase Invoice deducts stock added by purchase and reverses supplier balance', () async {
      final p1 = await seedProduct('قماش قطني', 10);
      await seedSupplier('S-1');

      final purchaseId = await seedPurchase(
        supplierId: 'S-1',
        number: 'PUR-0001',
        lines: [(p1, 20)],
      );

      // Verify initial post-purchase stock: 10 + 20 = 30
      var prod = await db.productDao.getProductById(p1);
      expect(prod!.quantity, equals(30));

      // Verify supplier balance is 2000
      expect(await db.ledgerDao.getSupplierBalance('S-1'), equals(2000.0));

      // Void the purchase invoice
      await PurchaseVoidService(db).voidPurchase(
        purchaseId: purchaseId,
        reason: 'خطأ في التوريد تم إلغاؤها',
        voidedBy: 'أمين المخزن',
      );

      // Verify stock deducted back to 10
      prod = await db.productDao.getProductById(p1);
      expect(prod!.quantity, equals(10));

      // Verify items removed and ledger reversed
      expect(await db.purchaseDao.getPurchaseItems(purchaseId), isEmpty);
      expect(await db.ledgerDao.getSupplierBalance('S-1'), equals(0.0));

      // Verify purchase status is soft deleted
      final purchase = await (db.select(db.purchases)..where((tbl) => tbl.id.equals(purchaseId))).getSingle();
      expect(purchase.isDeleted, isTrue);
      expect(purchase.notes, contains('أمين المخزن'));
      expect(purchase.notes, contains('خطأ في التوريد تم إلغاؤها'));
    });

    test('3. Voiding already-voided sales invoice is rejected idempotently without double restock', () async {
      final p1 = await seedProduct('كوتشي', 10);
      final result = await InvoiceService(db).createInvoice(
        customerId: null,
        customerName: 'عميل نقدي',
        paymentMethod: 'cash',
        totalAmount: 100,
        paidAmount: 100,
        status: 'paid',
        items: [InvoiceItemParams(productId: p1, quantity: 1, price: 100)],
      );

      // First void succeeds
      await InvoiceVoidService(db).voidInvoice(
        invoiceId: result.invoiceId,
        reason: VoidReasons.inputError,
        voidedBy: 'tester',
      );

      var pAfterFirstVoid = await db.productDao.getProductById(p1);
      expect(pAfterFirstVoid!.quantity, equals(10));

      // Second void must throw Exception('الفاتورة ملغاة بالفعل') and NOT restock again
      expect(
        () => InvoiceVoidService(db).voidInvoice(
          invoiceId: result.invoiceId,
          reason: VoidReasons.inputError,
          voidedBy: 'tester',
        ),
        throwsA(isA<Exception>()),
      );

      // Verify quantity is still 10, not 11
      var pAfterSecondVoid = await db.productDao.getProductById(p1);
      expect(pAfterSecondVoid!.quantity, equals(10));
    });
  });
}
