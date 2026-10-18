import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/services/invoice_service.dart';
import 'package:pos_offline_desktop/core/services/sales_return_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
  });

  late AppDatabase db;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await db.dayDao.getOrCreateTodayDay(openingBalance: 0, openedBy: 'tester');
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> makeFabricProduct(String name, {double price = 100}) {
    return db.productDao.insertProduct(
      ProductsCompanion.insert(
        name: name,
        price: price,
        quantity: 0,
        costPrice: const Value(60),
      ),
    );
  }

  group('Suite 5: Product Variants E2E (FEAT-020, BUG-010, BUG-011)', () {
    test('1. Variant insertion auto-generates barcode 20000000 + id with no collisions', () async {
      final pid = await makeFabricProduct('قماش فاخر');

      final vid1 = await db.productVariantDao.insertVariant(
        ProductVariantsCompanion.insert(
          productId: pid,
          name: 'أحمر',
          quantity: const Value(15),
        ),
      );

      final vid2 = await db.productVariantDao.insertVariant(
        ProductVariantsCompanion.insert(
          productId: pid,
          name: 'أزرق',
          quantity: const Value(25),
        ),
      );

      final v1 = await db.productVariantDao.getVariantById(vid1);
      final v2 = await db.productVariantDao.getVariantById(vid2);

      expect(v1, isNotNull);
      expect(v2, isNotNull);
      expect(v1!.barcode, equals('${20000000 + vid1}'));
      expect(v2!.barcode, equals('${20000000 + vid2}'));
      expect(v1.barcode, isNot(equals(v2.barcode)));

      // Search by barcode works reliably for barcode scanners
      final found = await db.productVariantDao.getVariantByBarcode('${20000000 + vid1}');
      expect(found, isNotNull);
      expect(found!.name, equals('أحمر'));
    });

    test('2. Independent variant quantities and parent auto-sync on sale', () async {
      final pid = await makeFabricProduct('تيشيرت بولو');

      final vidRed = await db.productVariantDao.insertVariant(
        ProductVariantsCompanion.insert(
          productId: pid,
          name: 'أحمر M',
          quantity: const Value(10),
        ),
      );

      final vidBlue = await db.productVariantDao.insertVariant(
        ProductVariantsCompanion.insert(
          productId: pid,
          name: 'أزرق L',
          quantity: const Value(20),
        ),
      );

      // Parent stock equals sum of active variants: 10 + 20 = 30
      final totalStock = await db.productVariantDao.getTotalQuantityByProduct(pid);
      expect(totalStock, equals(30));
      final parentProd = await db.productDao.getProductById(pid);
      await db.productDao.updateProduct(parentProd!.copyWith(quantity: totalStock));

      // Sell 3 units of red
      final svc = InvoiceService(db);
      final res = await svc.createInvoice(
        customerId: null,
        customerName: 'عميل نقدي',
        paymentMethod: 'cash',
        totalAmount: 300,
        paidAmount: 300,
        status: 'completed',
        items: [
          InvoiceItemParams(productId: pid, quantity: 3, price: 100, variantId: vidRed),
        ],
      );
      expect(res.invoiceId, greaterThan(0));

      // Red deducted by 3 -> 7, Blue intact -> 20, Parent auto-synced -> 27
      final updatedRed = await db.productVariantDao.getVariantById(vidRed);
      final updatedBlue = await db.productVariantDao.getVariantById(vidBlue);
      final updatedParent = await db.productDao.getProductById(pid);

      expect(updatedRed!.quantity, equals(7));
      expect(updatedBlue!.quantity, equals(20));
      expect(updatedParent!.quantity, equals(27));
    });

    test('3. Direct sale of parent with active variants is prevented (integrity guard)', () async {
      final pid = await makeFabricProduct('قميص كلاسيك');
      await db.productVariantDao.insertVariant(
        ProductVariantsCompanion.insert(
          productId: pid,
          name: 'أبيض 42',
          quantity: const Value(5),
        ),
      );

      final svc = InvoiceService(db);
      expect(
        () => svc.createInvoice(
          customerId: null,
          customerName: 'عميل نقدي',
          paymentMethod: 'cash',
          totalAmount: 100,
          paidAmount: 100,
          status: 'completed',
          items: [InvoiceItemParams(productId: pid, quantity: 1, price: 100)],
        ),
        throwsA(predicate((e) => e.toString().contains('اختر الصنف'))),
      );
    });

    test('4. BUG-010: Sales Return restores variant quantity and auto-syncs parent', () async {
      final pid = await makeFabricProduct('عباية حرير');
      final vidBlack = await db.productVariantDao.insertVariant(
        ProductVariantsCompanion.insert(
          productId: pid,
          name: 'أسود مطرز',
          quantity: const Value(10),
        ),
      );

      final parentProd = await db.productDao.getProductById(pid);
      await db.productDao.updateProduct(parentProd!.copyWith(quantity: 10));

      final svc = InvoiceService(db);
      final saleRes = await svc.createInvoice(
        customerId: null,
        customerName: 'عميل نقدي',
        paymentMethod: 'cash',
        totalAmount: 200,
        paidAmount: 200,
        status: 'completed',
        items: [
          InvoiceItemParams(productId: pid, quantity: 2, price: 100, variantId: vidBlack),
        ],
      );

      expect((await db.productVariantDao.getVariantById(vidBlack))!.quantity, equals(8));
      expect((await db.productDao.getProductById(pid))!.quantity, equals(8));

      // Return 1 unit of the variant via processPartialReturn
      final lines = await db.invoiceDao.getItemsByInvoiceId(saleRes.invoiceId);
      final returnSvc = SalesReturnService(db);
      await returnSvc.processPartialReturn(
        invoiceId: saleRes.invoiceId,
        itemReturns: {lines.first.id: 1},
      );

      // Variant quantity restored to 9, and Parent restored to 9
      expect((await db.productVariantDao.getVariantById(vidBlack))!.quantity, equals(9));
      expect((await db.productDao.getProductById(pid))!.quantity, equals(9));
    });

    test('5. BUG-011: Invoice Void restores variant quantity and auto-syncs parent', () async {
      final pid = await makeFabricProduct('طقم صيفي');
      final vidGreen = await db.productVariantDao.insertVariant(
        ProductVariantsCompanion.insert(
          productId: pid,
          name: 'أخضر S',
          quantity: const Value(15),
        ),
      );

      final parentProd = await db.productDao.getProductById(pid);
      await db.productDao.updateProduct(parentProd!.copyWith(quantity: 15));

      final svc = InvoiceService(db);
      final saleRes = await svc.createInvoice(
        customerId: null,
        customerName: 'عميل نقدي',
        paymentMethod: 'cash',
        totalAmount: 400,
        paidAmount: 400,
        status: 'completed',
        items: [
          InvoiceItemParams(productId: pid, quantity: 4, price: 100, variantId: vidGreen),
        ],
      );

      expect((await db.productVariantDao.getVariantById(vidGreen))!.quantity, equals(11));
      expect((await db.productDao.getProductById(pid))!.quantity, equals(11));

      // Void the invoice
      await db.invoiceDao.voidInvoice(saleRes.invoiceId, 'خطأ في البيع', 'tester');

      // Variant restored strictly to 15, Parent restored to 15
      expect((await db.productVariantDao.getVariantById(vidGreen))!.quantity, equals(15));
      expect((await db.productDao.getProductById(pid))!.quantity, equals(15));
    });
  });
}
