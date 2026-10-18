import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/services/invoice_service.dart';
import 'package:pos_offline_desktop/core/services/invoice_void_service.dart';
import 'package:pos_offline_desktop/core/services/sales_return_service.dart';

/// اختبارات أصناف المنتج (ألوان/فئات) — schema v79.
///
/// تثبت:
/// 1. إدخال صنف + توليد باركود تلقائي بقاعدة 20000000 (بلا تصادم مع المنتجات).
/// 2. بيع صنف يخصم من الصنف فقط + كمية الأب = مجموع الأصناف (atomic).
/// 3. منع البيع عند الكمية غير الكافية برسالة واضحة.
/// 4. منع بيع الأب مباشرة عندما له أصناف (حماية الـ invariant).
/// 5. المسار القديم (منتج بلا أصناف) يعمل كما كان.
/// 6. الإلغاء (void) والمرتجع يسترجعان مخزون الصنف + مجموع الأب.
/// 7. البحث بباركود الصنف (للمسح في الكاشير).
Future<AppDatabase> openDb() async {
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  await db.dayDao.getOrCreateTodayDay(openingBalance: 0, openedBy: 'tester');
  return db;
}

Future<int> makeFabricProduct(AppDatabase db) {
  return db.productDao.insertProduct(
    ProductsCompanion.insert(
      name: 'قماش X',
      price: 100,
      quantity: 0,
      costPrice: const Value(60),
    ),
  );
}

void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ProductVariantDao', () {
    test('إدخال صنف + باركود تلقائي 20000000 + بحث بالباركود', () async {
      final db = await openDb();
      final pid = await makeFabricProduct(db);

      final vid = await db.productVariantDao.insertVariant(
        ProductVariantsCompanion.insert(
          productId: pid,
          name: 'أحمر',
          quantity: const Value(10),
        ),
      );

      final v = await db.productVariantDao.getVariantById(vid);
      expect(v, isNotNull);
      expect(v!.barcode, '${20000000 + vid}');
      // السعر الفارغ = null (يُحل لسعر الأب وقت البيع)
      expect(v.price, isNull);

      final byBarcode = await db.productVariantDao.getVariantByBarcode(
        '${20000000 + vid}',
      );
      expect(byBarcode?.id, vid);

      final total = await db.productVariantDao.getTotalQuantityByProduct(pid);
      expect(total, 10);
    });

    test('الأب = مجموع الأصناف بعد الإدخال اليدوي للمجموع', () async {
      final db = await openDb();
      final pid = await makeFabricProduct(db);
      await db.productVariantDao.insertVariant(
        ProductVariantsCompanion.insert(
          productId: pid,
          name: 'أحمر',
          quantity: const Value(7),
        ),
      );
      await db.productVariantDao.insertVariant(
        ProductVariantsCompanion.insert(
          productId: pid,
          name: 'أزرق',
          quantity: const Value(3),
          price: const Value(120),
          barcode: const Value('V-BLUE-1'),
        ),
      );
      expect(
        await db.productVariantDao.getTotalQuantityByProduct(pid),
        10,
      );
      final variants = await db.productVariantDao.getVariantsByProduct(pid);
      expect(variants.length, 2);
      // السعر المستقل محفوظ، والباركود اليدوي لم يُستبدل
      expect(
        variants.firstWhere((e) => e.name == 'أزرق').price,
        120,
      );
      expect(
        variants.firstWhere((e) => e.name == 'أزرق').barcode,
        'V-BLUE-1',
      );
    });
  });

  group('InvoiceService مع الأصناف', () {
    test('بيع صنف: خصم من الصنف + الأب = المجموع + variantId محفوظ', () async {
      final db = await openDb();
      final pid = await makeFabricProduct(db);
      final red = await db.productVariantDao.insertVariant(
        ProductVariantsCompanion.insert(
          productId: pid,
          name: 'أحمر',
          quantity: const Value(10),
        ),
      );
      await db.productVariantDao.insertVariant(
        ProductVariantsCompanion.insert(
          productId: pid,
          name: 'أزرق',
          quantity: const Value(5),
        ),
      );
      // المجموع الابتدائي للأب
      final parent0 = await db.productDao.getProductById(pid);
      await db.productDao.updateProduct(
        parent0!.copyWith(
          quantity: await db.productVariantDao.getTotalQuantityByProduct(pid),
        ),
      );

      final svc = InvoiceService(db);
      final res = await svc.createInvoice(
        customerId: null,
        customerName: 'نقدي',
        paymentMethod: 'cash',
        totalAmount: 200,
        paidAmount: 200,
        cashAmount: 200,
        status: 'completed',
        items: [
          InvoiceItemParams(
            productId: pid,
            quantity: 4,
            price: 100,
            variantId: red,
          ),
        ],
      );
      expect(res.invoiceId, greaterThan(0));

      final redAfter = await db.productVariantDao.getVariantById(red);
      expect(redAfter!.quantity, 6);
      final parentAfter = await db.productDao.getProductById(pid);
      expect(parentAfter!.quantity, 11); // 6 + 5

      final lines = await db.invoiceDao.getItemsByInvoiceId(res.invoiceId);
      expect(lines.length, 1);
      expect(lines.first.variantId, red);
    });

    test('كمية غير كافية للصنف → منع برسالة واضحة', () async {
      final db = await openDb();
      final pid = await makeFabricProduct(db);
      final red = await db.productVariantDao.insertVariant(
        ProductVariantsCompanion.insert(
          productId: pid,
          name: 'أحمر',
          quantity: const Value(2),
        ),
      );

      final svc = InvoiceService(db);
      expect(
        () => svc.createInvoice(
          customerId: null,
          customerName: 'نقدي',
          paymentMethod: 'cash',
          totalAmount: 500,
          paidAmount: 500,
          cashAmount: 500,
          status: 'completed',
          items: [
            InvoiceItemParams(
              productId: pid,
              quantity: 5,
              price: 100,
              variantId: red,
            ),
          ],
        ),
        throwsA(
          predicate(
            (e) => e.toString().contains('غير كافية') && e.toString().contains('أحمر'),
          ),
        ),
      );
      // لا خصم جزئي: الكمية كما هي
      expect((await db.productVariantDao.getVariantById(red))!.quantity, 2);
    });

    test('بيع الأب مباشرة وله أصناف → منع (حماية المجموع)', () async {
      final db = await openDb();
      final pid = await makeFabricProduct(db);
      await db.productVariantDao.insertVariant(
        ProductVariantsCompanion.insert(
          productId: pid,
          name: 'أحمر',
          quantity: const Value(10),
        ),
      );

      final svc = InvoiceService(db);
      expect(
        () => svc.createInvoice(
          customerId: null,
          customerName: 'نقدي',
          paymentMethod: 'cash',
          totalAmount: 100,
          paidAmount: 100,
          cashAmount: 100,
          status: 'completed',
          items: [InvoiceItemParams(productId: pid, quantity: 1, price: 100)],
        ),
        throwsA(predicate((e) => e.toString().contains('اختر الصنف'))),
      );
    });

    test('منتج بلا أصناف: المسار القديم يعمل (خصم + clamp عند الصفر)', () async {
      final db = await openDb();
      final pid = await db.productDao.insertProduct(
        ProductsCompanion.insert(
          name: 'سكر',
          price: 50,
          quantity: 3,
          costPrice: const Value(40),
        ),
      );

      final svc = InvoiceService(db);
      final res = await svc.createInvoice(
        customerId: null,
        customerName: 'نقدي',
        paymentMethod: 'cash',
        totalAmount: 250,
        paidAmount: 250,
        cashAmount: 250,
        status: 'completed',
        items: [InvoiceItemParams(productId: pid, quantity: 5, price: 50)],
      );
      expect(res.invoiceId, greaterThan(0));
      expect((await db.productDao.getProductById(pid))!.quantity, 0);
      final lines = await db.invoiceDao.getItemsByInvoiceId(res.invoiceId);
      expect(lines.first.variantId, isNull);
    });

    test('إلغاء فاتورة صنف يسترجع الصنف + مجموع الأب', () async {
      final db = await openDb();
      final pid = await makeFabricProduct(db);
      final red = await db.productVariantDao.insertVariant(
        ProductVariantsCompanion.insert(
          productId: pid,
          name: 'أحمر',
          quantity: const Value(10),
        ),
      );
      final parent0 = await db.productDao.getProductById(pid);
      await db.productDao.updateProduct(parent0!.copyWith(quantity: 10));

      final svc = InvoiceService(db);
      final res = await svc.createInvoice(
        customerId: null,
        customerName: 'نقدي',
        paymentMethod: 'cash',
        totalAmount: 300,
        paidAmount: 300,
        cashAmount: 300,
        status: 'completed',
        items: [
          InvoiceItemParams(productId: pid, quantity: 3, price: 100, variantId: red),
        ],
      );
      expect((await db.productVariantDao.getVariantById(red))!.quantity, 7);

      await db.invoiceDao.voidInvoice(res.invoiceId, 'اختبار', 'admin');
      expect((await db.productVariantDao.getVariantById(red))!.quantity, 10);
      expect((await db.productDao.getProductById(pid))!.quantity, 10);
    });

    test('مرتجع صنف يسترجع الصنف + مجموع الأب', () async {
      final db = await openDb();
      final pid = await makeFabricProduct(db);
      final red = await db.productVariantDao.insertVariant(
        ProductVariantsCompanion.insert(
          productId: pid,
          name: 'أحمر',
          quantity: const Value(10),
        ),
      );
      final parent0 = await db.productDao.getProductById(pid);
      await db.productDao.updateProduct(parent0!.copyWith(quantity: 10));

      final svc = InvoiceService(db);
      final res = await svc.createInvoice(
        customerId: null,
        customerName: 'نقدي',
        paymentMethod: 'cash',
        totalAmount: 200,
        paidAmount: 200,
        cashAmount: 200,
        status: 'completed',
        items: [
          InvoiceItemParams(productId: pid, quantity: 2, price: 100, variantId: red),
        ],
      );
      expect((await db.productVariantDao.getVariantById(red))!.quantity, 8);

      final lines = await db.invoiceDao.getItemsByInvoiceId(res.invoiceId);
      final returnSvc = SalesReturnService(db);
      await returnSvc.processPartialReturn(
        invoiceId: res.invoiceId,
        itemReturns: {lines.first.id: 1},
      );
      expect((await db.productVariantDao.getVariantById(red))!.quantity, 9);
      expect((await db.productDao.getProductById(pid))!.quantity, 9);
    });

    test('BUG-010: SalesReturnService.processPartialReturn restores variant quantity and syncs parent', () async {
      final db = await openDb();
      final pid = await makeFabricProduct(db);
      final red = await db.productVariantDao.insertVariant(
        ProductVariantsCompanion.insert(
          productId: pid,
          name: 'أحمر',
          quantity: const Value(10),
        ),
      );
      final parent0 = await db.productDao.getProductById(pid);
      await db.productDao.updateProduct(parent0!.copyWith(quantity: 10));

      final svc = InvoiceService(db);
      final res = await svc.createInvoice(
        customerId: null,
        customerName: 'نقدي',
        paymentMethod: 'cash',
        totalAmount: 300,
        paidAmount: 300,
        cashAmount: 300,
        status: 'completed',
        items: [
          InvoiceItemParams(productId: pid, quantity: 3, price: 100, variantId: red),
        ],
      );
      expect((await db.productVariantDao.getVariantById(red))!.quantity, 7);
      expect((await db.productDao.getProductById(pid))!.quantity, 7);

      final lines = await db.invoiceDao.getItemsByInvoiceId(res.invoiceId);
      final returnSvc = SalesReturnService(db);
      await returnSvc.processPartialReturn(
        invoiceId: res.invoiceId,
        itemReturns: {lines.first.id: 2},
      );

      expect((await db.productVariantDao.getVariantById(red))!.quantity, 9);
      expect((await db.productDao.getProductById(pid))!.quantity, 9);

      // Verify variant_id in sales_return_items table
      final returnItems = await db.select(db.salesReturnItems).get();
      expect(returnItems.first.variantId, red);
    });

    test('BUG-011: InvoiceVoidService.voidInvoice restores variant quantity and syncs parent', () async {
      final db = await openDb();
      final pid = await makeFabricProduct(db);
      final red = await db.productVariantDao.insertVariant(
        ProductVariantsCompanion.insert(
          productId: pid,
          name: 'أحمر',
          quantity: const Value(10),
        ),
      );
      final parent0 = await db.productDao.getProductById(pid);
      await db.productDao.updateProduct(parent0!.copyWith(quantity: 10));

      final svc = InvoiceService(db);
      final res = await svc.createInvoice(
        customerId: null,
        customerName: 'نقدي',
        paymentMethod: 'cash',
        totalAmount: 400,
        paidAmount: 400,
        cashAmount: 400,
        status: 'completed',
        items: [
          InvoiceItemParams(productId: pid, quantity: 4, price: 100, variantId: red),
        ],
      );
      expect((await db.productVariantDao.getVariantById(red))!.quantity, 6);
      expect((await db.productDao.getProductById(pid))!.quantity, 6);

      final voidSvc = InvoiceVoidService(db);
      await voidSvc.voidInvoice(
        invoiceId: res.invoiceId,
        reason: 'إلغاء تجريبي',
        voidedBy: 'admin',
      );

      expect((await db.productVariantDao.getVariantById(red))!.quantity, 10);
      expect((await db.productDao.getProductById(pid))!.quantity, 10);
    });
  });
}
