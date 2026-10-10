import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/services/sales_return_service.dart';
import 'package:pos_offline_desktop/core/services/return_refund_service.dart';

/// استرداد (فلوس المرتجع) — الفصل بين "البضاعة رجعت" و "الفلوس خرجت".
///
/// قبل v78 كان مرتجع العميل النقدي بيرجّع المخزون بس والفلوس بتختفي: مفيش
/// سجل للاسترداد، ولا قيد في الـledger، ولا أثر في رصيد اليوم. وكل اختبار
/// هنا بيتأكد إن واحدة من دول مش بتكسر.
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

  Future<int> seedProduct(AppDatabase db, String name, double price, int qty) =>
      db.into(db.products).insert(
            ProductsCompanion.insert(
              name: name,
              price: price,
              quantity: qty,
              category: const Value('test'),
            ),
          );

  Future<void> seedCustomer(AppDatabase db, String id, {double opening = 0}) async {
    await db.into(db.customers).insert(
      CustomersCompanion.insert(
        id: id,
        name: 'عميل $id',
        openingBalance: Value(opening),
      ),
    );
  }

  /// فاتورة آجلة (customerId حقيقي) أو نقدية (customerId = 'cash').
  Future<int> seedInvoice(
    AppDatabase db, {
    required String number,
    String customerId = 'cash',
    String paymentMethod = 'cash',
    double paid = 0,
    List<(int productId, int qty, double price, double discount)> lines =
        const [],
  }) async {
    final invoiceId = await db.into(db.invoices).insert(
          InvoicesCompanion.insert(
            invoiceNumber: Value(number),
            customerId: Value(customerId),
            customerName: const Value('عميل'),
            paymentMethod: Value(paymentMethod),
            paidAmount: Value(paid),
            status: const Value('completed'),
          ),
        );
    double total = 0;
    for (final l in lines) {
      total += l.$2 * (l.$3 - (l.$4 / (l.$2 == 0 ? 1 : l.$2)));
      await db.into(db.invoiceItems).insert(
            InvoiceItemsCompanion.insert(
              invoiceId: invoiceId,
              productId: l.$1,
              quantity: Value(l.$2),
              price: l.$3,
              discount: Value(l.$4),
            ),
          );
    }
    await (db.update(db.invoices)..where((t) => t.id.equals(invoiceId)))
        .write(InvoicesCompanion(totalAmount: Value(total)));
    return invoiceId;
  }

  /// بيع + مرتجع كامل الصنف عشان نوصل لمرتجع بقيمة معروفة.
  Future<(int, int)> seedReturn(
    AppDatabase db, {
    required String customerId,
    String paymentMethod = 'credit',
    double price = 100,
    int qty = 1,
    String number = 'INV-1',
  }) async {
    final productId = await seedProduct(db, 'صنف', price, 50);
    final invoiceId = await seedInvoice(
      db,
      number: number,
      customerId: customerId,
      paymentMethod: paymentMethod,
      lines: [(productId, qty, price, 0)],
    );
    final items = await db.invoiceDao.getItemsByInvoiceId(invoiceId);
    final returnId = await SalesReturnService(db).processPartialReturn(
      invoiceId: invoiceId,
      itemReturns: {items.first.id: qty},
      processedBy: 'tester',
    );
    return (returnId, productId);
  }

  group('ReturnRefundService — القيود والحماية', () {
    test('cash refund writes a Cash ledger credit (نقد خرج من الصندوق)',
        () async {
      final db = await openDb();
      await seedCustomer(db, 'C1');
      final (returnId, _) = await seedReturn(db, customerId: 'C1');

      final result = await ReturnRefundService(db).refund(
        returnId: returnId,
        amount: 100,
        method: RefundMethod.cash,
        processedBy: 'cashier1',
      );

      expect(result.refundId, greaterThan(0));
      expect(result.returnOutstanding, 0.0);

      final ledger = await db.ledgerDao.getAllTransactions();
      final cashRows =
          ledger.where((t) => t.entityType == 'Cash' && t.origin == 'refund');
      expect(cashRows.length, 1);
      expect(cashRows.first.credit, 100.0);
      expect(cashRows.first.debit, 0.0);
      expect(cashRows.first.paymentMethod, 'cash');

      // المرتجع نفسه للعميل الآجل بيكتب قيد عكسي (origin='reversal') — وده
      // موجود من الخدمة القديمة ومش المفروض يتكرر هنا.
      final reversals =
          ledger.where((t) => t.origin == 'reversal' && t.credit == 100.0);
      expect(reversals.length, 1);
    });

    test('credit_balance refund is a record only — the return already credited',
        () async {
      final db = await openDb();
      await seedCustomer(db, 'C2', opening: 500);
      final (returnId, _) = await seedReturn(db, customerId: 'C2');

      // العميل مدين 500 من فاتورة قديمة.
      await db.ledgerDao.insertTransaction(
        LedgerTransactionsCompanion.insert(
          id: 'tx-sale-1',
          entityType: 'Customer',
          refId: 'C2',
          date: DateTime.now(),
          description: 'فاتورة',
          debit: const Value(500),
          credit: const Value(0),
          origin: 'sale',
        ),
      );
      // الرصيد = opening(500) + sale debit(500) - reversal credit(100)
      expect(await db.ledgerDao.getCustomerBalance('C2'), 900.0);

      final before = await db.ledgerDao.getCustomerBalance('C2');

      await ReturnRefundService(db).refund(
        returnId: returnId,
        amount: 100,
        method: RefundMethod.creditBalance,
        processedBy: 'cashier1',
      );

      // ⚠️ الرصيد ما يتغيرش — لو اتغير هنا كان العميل اتحسب له مرتين
      // (مرّة في قيد المرتجع reversal ومرة في قيد الاسترداد).
      expect(await db.ledgerDao.getCustomerBalance('C2'), before);

      // مفيش صف ledger جديد خالص (credit / original = سجل بس).
      final ledger = await db.ledgerDao.getAllTransactions();
      expect(ledger.where((t) => t.origin == 'refund').isEmpty, isTrue);

      // بس السجل اتسجل في return_refunds + حالة التسوية اتحدّثت.
      final rows = await db.returnRefundsDao.getRefundsForReturn(returnId);
      expect(rows.length, 1);
      expect(rows.first.method, RefundMethod.creditBalance);

      final ret = await (db.select(db.salesReturns)
            ..where((t) => t.id.equals(returnId)))
          .getSingle();
      expect(ret.refundedAmount, 100.0);
      expect(ret.settlementStatus, 'credited');

      // رصيد العميل مالوش علاقة بالصندوق خالص.
      expect(ledger.where((t) => t.entityType == 'Cash').isEmpty, isTrue);
    });

    test('partial refunds accumulate and can span methods', () async {
      final db = await openDb();
      await seedCustomer(db, 'C3');
      final (returnId, _) = await seedReturn(db, customerId: 'C3', price: 200);

      final svc = ReturnRefundService(db);

      final first = await svc.refund(
        returnId: returnId,
        amount: 60,
        method: RefundMethod.cash,
        processedBy: 'cashier1',
      );
      expect(first.returnOutstanding, closeTo(140, 0.01));

      final second = await svc.refund(
        returnId: returnId,
        amount: 140,
        method: RefundMethod.creditBalance,
        processedBy: 'cashier1',
      );
      expect(second.returnOutstanding, 0.0);

      final rows = await db.returnRefundsDao.getRefundsForReturn(returnId);
      expect(rows.length, 2);
      expect(rows.first.method, RefundMethod.cash);
      expect(rows.first.amount, 60.0);
      expect(rows.last.method, RefundMethod.creditBalance);
      expect(rows.last.amount, 140.0);

      final ret = await (db.select(db.salesReturns)
            ..where((t) => t.id.equals(returnId)))
          .getSingle();
      expect(ret.refundedAmount, 200.0);
      expect(ret.settlementStatus, 'credited');
    });

    test('settlementStatus is partially_refunded while money is still due',
        () async {
      final db = await openDb();
      await seedCustomer(db, 'C4');
      final (returnId, _) = await seedReturn(db, customerId: 'C4');

      await ReturnRefundService(db).refund(
        returnId: returnId,
        amount: 40,
        method: RefundMethod.cash,
        processedBy: 'cashier1',
      );

      final ret = await (db.select(db.salesReturns)
            ..where((t) => t.id.equals(returnId)))
          .getSingle();
      expect(ret.refundedAmount, 40.0);
      expect(ret.settlementStatus, 'partially_refunded');
      expect(ret.totalAmount, 100.0);
    });

    test('over-refund throws with zero side effects', () async {
      final db = await openDb();
      await seedCustomer(db, 'C5');
      final (returnId, _) = await seedReturn(db, customerId: 'C5');

      await expectLater(
        ReturnRefundService(db).refund(
          returnId: returnId,
          amount: 150,
          method: RefundMethod.cash,
          processedBy: 'cashier1',
        ),
        throwsException,
      );

      expect(await db.returnRefundsDao.getRefundsForReturn(returnId), isEmpty);
      // القيد العكسي بتاع المرتجع موجود (من الخدمة القديمة) — بس مفيش
      // صف ledger جديد من الاسترداد.
      expect(
        (await db.ledgerDao.getAllTransactions()).where((t) => t.origin == 'refund'),
        isEmpty,
      );
      final ret = await (db.select(db.salesReturns)
            ..where((t) => t.id.equals(returnId)))
          .getSingle();
      expect(ret.refundedAmount, 0.0);
    });

    test('second refund beyond the remainder throws', () async {
      final db = await openDb();
      await seedCustomer(db, 'C6');
      final (returnId, _) = await seedReturn(db, customerId: 'C6');

      final svc = ReturnRefundService(db);
      await svc.refund(
        returnId: returnId,
        amount: 70,
        method: RefundMethod.cash,
        processedBy: 'cashier1',
      );

      await expectLater(
        svc.refund(
          returnId: returnId,
          amount: 50,
          method: RefundMethod.cash,
          processedBy: 'cashier1',
        ),
        throwsException,
      );
      expect(
        (await db.returnRefundsDao.getRefundsForReturn(returnId)).length,
        1,
      );
    });

    test('credit refund is rejected on a cash invoice (مفيش عميل مسجّل)',
        () async {
      final db = await openDb();
      final (returnId, _) = await seedReturn(
        db,
        customerId: 'cash',
        paymentMethod: 'cash',
      );

      await expectLater(
        ReturnRefundService(db).refund(
          returnId: returnId,
          amount: 100,
          method: RefundMethod.creditBalance,
          processedBy: 'cashier1',
        ),
        throwsException,
      );
      expect(await db.returnRefundsDao.getRefundsForReturn(returnId), isEmpty);
    });

    test('zero and negative amounts are rejected', () async {
      final db = await openDb();
      await seedCustomer(db, 'C7');
      final (returnId, _) = await seedReturn(db, customerId: 'C7');
      final svc = ReturnRefundService(db);

      await expectLater(
        svc.refund(
          returnId: returnId,
          amount: 0,
          method: RefundMethod.cash,
          processedBy: 'cashier1',
        ),
        throwsException,
      );
      await expectLater(
        svc.refund(
          returnId: returnId,
          amount: -50,
          method: RefundMethod.cash,
          processedBy: 'cashier1',
        ),
        throwsException,
      );
    });

    test('unknown method is rejected', () async {
      final db = await openDb();
      await seedCustomer(db, 'C8');
      final (returnId, _) = await seedReturn(db, customerId: 'C8');

      await expectLater(
        ReturnRefundService(db).refund(
          returnId: returnId,
          amount: 10,
          method: 'bitcoin',
          processedBy: 'cashier1',
        ),
        throwsException,
      );
    });

    test('refundRemaining pays exactly the outstanding amount', () async {
      final db = await openDb();
      await seedCustomer(db, 'C9');
      final (returnId, _) = await seedReturn(db, customerId: 'C9', price: 300);

      final svc = ReturnRefundService(db);
      await svc.refund(
        returnId: returnId,
        amount: 100,
        method: RefundMethod.cash,
        processedBy: 'cashier1',
      );

      final rest = await svc.refundRemaining(
        returnId: returnId,
        method: RefundMethod.cash,
        processedBy: 'cashier1',
      );
      expect(rest.amount, 200.0);
      expect(rest.returnOutstanding, 0.0);

      // مفيش دفعة تالتة.
      await expectLater(
        svc.refundRemaining(
          returnId: returnId,
          method: RefundMethod.cash,
          processedBy: 'cashier1',
        ),
        throwsException,
      );
    });

    test('voided refund no longer counts (soft delete for audit)', () async {
      final db = await openDb();
      await seedCustomer(db, 'C10');
      final (returnId, _) = await seedReturn(db, customerId: 'C10');
      final svc = ReturnRefundService(db);

      final r = await svc.refund(
        returnId: returnId,
        amount: 100,
        method: RefundMethod.cash,
        processedBy: 'cashier1',
      );

      await db.returnRefundsDao.voidRefund(r.refundId, 'خطأ في الإدخال', 'manager');

      // الصف لسه موجود للأرشيف بس بأثر صفري.
      final all = await db.select(db.returnRefunds).get();
      expect(all.length, 1);
      expect(all.first.isVoided, isTrue);

      expect(
        await db.returnRefundsDao.getRefundedAmountForReturn(returnId),
        0.0,
      );
      expect(
        await db.returnRefundsDao.getOutstandingForReturn(returnId),
        100.0,
      );
      expect(
        await db.returnRefundsDao.getCashRefundsBetween(
          DateTime(2000),
          DateTime(2100),
        ),
        0.0,
      );
    });
  });

  group('الاسترداد وصندوق اليوم', () {
    test('getCashRefundsBetween only counts cash (رصيد العميل مش منه)', () async {
      final db = await openDb();
      await seedCustomer(db, 'D1');
      final (r1, _) = await seedReturn(
        db,
        customerId: 'D1',
        price: 100,
        number: 'INV-1',
      );
      final (r2, _) = await seedReturn(
        db,
        customerId: 'D1',
        price: 300,
        number: 'INV-2',
      );
      await seedProduct(db, 'صنف تاني', 1, 1); // مخزون مختلف للسطر الثاني

      final svc = ReturnRefundService(db);
      await svc.refund(
        returnId: r1,
        amount: 100,
        method: RefundMethod.cash,
        processedBy: 'c',
      );
      await svc.refund(
        returnId: r2,
        amount: 300,
        method: RefundMethod.creditBalance,
        processedBy: 'c',
      );

      final cash = await db.returnRefundsDao
          .getCashRefundsBetween(DateTime(2000), DateTime(2100));
      expect(cash, 100.0); // الـcredit مستثنى
    });

    test('cash refunds respect the date window', () async {
      final db = await openDb();
      await seedCustomer(db, 'D2');
      final (returnId, _) = await seedReturn(db, customerId: 'D2');

      await ReturnRefundService(db).refund(
        returnId: returnId,
        amount: 100,
        method: RefundMethod.cash,
        processedBy: 'c',
      );

      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);
      expect(
        await db.returnRefundsDao
            .getCashRefundsBetween(startOfDay, DateTime(2100)),
        100.0,
      );
      expect(
        await db.returnRefundsDao
            .getCashRefundsBetween(DateTime(1990), startOfDay),
        0.0,
      );
    });
  });

  group('SalesReturnService v78', () {
    test('invoice net is tracked without touching the original header', () async {
      final db = await openDb();
      await seedCustomer(db, 'N1');
      final productId = await seedProduct(db, 'صنف', 100, 50);
      final invoiceId = await seedInvoice(
        db,
        number: 'INV-N1',
        customerId: 'N1',
        lines: [(productId, 4, 100, 0)], // إجمالي 400
      );
      final items = await db.invoiceDao.getItemsByInvoiceId(invoiceId);

      await SalesReturnService(db).processPartialReturn(
        invoiceId: invoiceId,
        itemReturns: {items.first.id: 2},
        processedBy: 'tester',
      );

      final inv =
          await (db.select(db.invoices)..where((t) => t.id.equals(invoiceId)))
              .getSingle();
      // الهيدر الأصلي ما اتغيرش.
      expect(inv.totalAmount, 400.0);
      // بس الصافي اتسجل.
      expect(inv.returnedAmount, 200.0);
      expect(inv.netAmount, 200.0);
    });

    test('damaged items do NOT go back into stock', () async {
      final db = await openDb();
      await seedCustomer(db, 'N2');
      final productId = await seedProduct(db, 'صنف تالف', 100, 50);
      final invoiceId = await seedInvoice(
        db,
        number: 'INV-N2',
        customerId: 'N2',
        lines: [(productId, 4, 100, 0)],
      );
      final items = await db.invoiceDao.getItemsByInvoiceId(invoiceId);

      final returnId = await SalesReturnService(db).processPartialReturn(
        invoiceId: invoiceId,
        itemReturns: {items.first.id: 2},
        restockConditions: {
          items.first.id: SalesReturnService.restockDamaged,
        },
        processedBy: 'tester',
      );

      // المخزون زي ما هو — التالف مايرجعش للبيع.
      final product =
          await (db.select(db.products)..where((t) => t.id.equals(productId)))
              .getSingle();
      expect(product.quantity, 50);

      final ret = await (db.select(db.salesReturns)
            ..where((t) => t.id.equals(returnId)))
          .getSingle();
      expect(ret.restockedAmount, 0.0);
      // بس المرتجع لسه مسجّل بقيمته.
      expect(ret.totalAmount, 200.0);

      final retItems =
          await db.salesReturnsDao.getItemsForReturn(returnId);
      expect(retItems.first.restockCondition, SalesReturnService.restockDamaged);
      expect(retItems.first.restockedQty, 0);
      expect(retItems.first.quantity, 2);
    });

    test('sellable items DO go back into stock and are counted', () async {
      final db = await openDb();
      await seedCustomer(db, 'N3');
      final productId = await seedProduct(db, 'صنف سليم', 100, 50);
      final invoiceId = await seedInvoice(
        db,
        number: 'INV-N3',
        customerId: 'N3',
        lines: [(productId, 4, 100, 0)],
      );
      final items = await db.invoiceDao.getItemsByInvoiceId(invoiceId);

      final returnId = await SalesReturnService(db).processPartialReturn(
        invoiceId: invoiceId,
        itemReturns: {items.first.id: 2},
        restockConditions: {
          items.first.id: SalesReturnService.restockSellable,
        },
        processedBy: 'tester',
      );

      final product =
          await (db.select(db.products)..where((t) => t.id.equals(productId)))
              .getSingle();
      expect(product.quantity, 52);

      final ret = await (db.select(db.salesReturns)
            ..where((t) => t.id.equals(returnId)))
          .getSingle();
      expect(ret.restockedAmount, 200.0);

      final retItems = await db.salesReturnsDao.getItemsForReturn(returnId);
      expect(retItems.first.restockedQty, 2);
    });

    test('new return starts pending settlement and a unique return number',
        () async {
      final db = await openDb();
      await seedCustomer(db, 'N4');
      final productId = await seedProduct(db, 'صنف', 100, 50);
      final invoiceId = await seedInvoice(
        db,
        number: 'INV-N4',
        customerId: 'N4',
        lines: [(productId, 10, 100, 0)],
      );
      final items = await db.invoiceDao.getItemsByInvoiceId(invoiceId);

      final numbers = <String>{};
      for (var i = 1; i <= 5; i++) {
        final id = await SalesReturnService(db).processPartialReturn(
          invoiceId: invoiceId,
          itemReturns: {items.first.id: 1},
          processedBy: 'tester',
        );
        final ret = await (db.select(db.salesReturns)
              ..where((t) => t.id.equals(id)))
            .getSingle();
        expect(ret.settlementStatus, 'pending');
        expect(ret.refundedAmount, 0.0);
        expect(ret.syncId, isNotNull);
        numbers.add(ret.returnNumber);
      }
      // 5 مرتجعات في نفس اللحظة تقريباً => أرقام مختلفة (تصادم الـ%100000 القديم).
      expect(numbers.length, 5);
    });

    test('zero-quantity line does not produce NaN (حارس القسمة على صفر)',
        () async {
      final db = await openDb();
      await seedCustomer(db, 'N5');
      final productId = await seedProduct(db, 'صنف', 100, 50);
      final invoiceId = await db.into(db.invoices).insert(
            InvoicesCompanion.insert(
              invoiceNumber: const Value('INV-N5'),
              customerId: const Value('N5'),
              status: const Value('completed'),
            ),
          );
      await db.into(db.invoiceItems).insert(
            InvoiceItemsCompanion.insert(
              invoiceId: invoiceId,
              productId: productId,
              quantity: const Value(0),
              price: 100,
              discount: const Value(10),
            ),
          );
      final items = await db.invoiceDao.getItemsByInvoiceId(invoiceId);

      // الكمية 0 => المتاح 0 => لازم يرمي رسالة "تم إرجاعه بالكامل" مش NaN.
      await expectLater(
        SalesReturnService(db).processPartialReturn(
          invoiceId: invoiceId,
          itemReturns: {items.first.id: 1},
        ),
        throwsException,
      );

      final all = await db.select(db.salesReturns).get();
      expect(all, isEmpty);
    });
  });
}