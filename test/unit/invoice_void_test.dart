import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/services/invoice_service.dart';
import 'package:pos_offline_desktop/core/services/invoice_void_service.dart';
import 'package:pos_offline_desktop/core/services/return_refund_service.dart';
import 'package:pos_offline_desktop/core/services/sales_return_service.dart';

/// إلغاء الفاتورة "كأنها مجتش" — العكس لازم يكون متماثل.
///
/// كل اختبار هنا بيتأكد إن حاجة واحدة من دول **مش** بتتحصل:
/// مخزون مكرر • قيد محاسبي معلّق • دفعات باقية • فاتورة ظاهرة في التقارير.
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

  Future<void> seedCustomer(AppDatabase db, String id, {double opening = 0}) =>
      db.into(db.customers).insert(
            CustomersCompanion.insert(
              id: id,
              name: 'عميل $id',
              openingBalance: Value(opening),
            ),
          );

  /// بيع حقيقي عبر InvoiceService — عشان القيود تكون زي ما الكاشير بيعمل.
  Future<int> seedSale(
    AppDatabase db, {
    String customerId = 'cash',
    String paymentMethod = 'credit',
    double paid = 0,
    List<(int productId, int qty)> lines = const [],
  }) async {
    final result = await InvoiceService(db).createInvoice(
      customerId: customerId,
      customerName: customerId == 'cash' ? 'عميل نقدي' : 'عميل آجل',
      paymentMethod: paymentMethod,
      totalAmount:
          lines.fold<double>(0, (s, l) => s + l.$2 * 100),
      paidAmount: paid,
      status: paid > 0 ? 'partial' : 'pending',
      items: [
        for (final l in lines)
          InvoiceItemParams(
            productId: l.$1,
            quantity: l.$2,
            price: 100,
          ),
      ],
    );
    return result.invoiceId;
  }

  group('InvoiceVoidService — العكس المتماثل', () {
    test('restores stock, kills ledger + payments, hides the invoice', () async {
      final db = await openDb();
      await seedCustomer(db, 'V1', opening: 0);
      final productId = await seedProduct(db, 'صنف', 50);

      final invoiceId = await seedSale(
        db,
        customerId: 'V1',
        lines: [(productId, 4)],
      );

      // المخزون نقص 4 عند البيع.
      var p = await db.productDao.getProductById(productId);
      expect(p!.quantity, 46);

      // قيد البيع موجود.
      expect(
        (await db.ledgerDao.getTransactionsByReceiptNumber('INV$invoiceId')).length,
        1,
      );

      final preview = await InvoiceVoidService(db).preview(invoiceId);
      expect(preview.invoiceNumber.isNotEmpty, isTrue);
      expect(preview.itemCount, 1);
      expect(preview.totalAmount, 400.0);
      expect(preview.returnCount, 0);

      await InvoiceVoidService(db).voidInvoice(
        invoiceId: invoiceId,
        reason: VoidReasons.inputError,
        notes: 'اختبار',
        voidedBy: 'manager1',
      );

      // 1) المخزون رجع.
      p = await db.productDao.getProductById(productId);
      expect(p!.quantity, 50);

      // 2) القيود اتشالت.
      expect(
        await db.ledgerDao.getTransactionsByReceiptNumber('INV$invoiceId'),
        isEmpty,
      );

      // 3) رصيد العميل رجع صفر.
      expect(await db.ledgerDao.getCustomerBalance('V1'), 0.0);

      // 4) الدفعات اتشالت.
      expect(await db.invoicePaymentsDao.getPaymentsForInvoice(invoiceId), isEmpty);

      // 5) الفاتورة ملغاة ومختفية من التقارير.
      final inv =
          await (db.select(db.invoices)..where((t) => t.id.equals(invoiceId)))
              .getSingle();
      expect(inv.status, 'voided');
      expect(inv.voidReason, VoidReasons.inputError);
      expect(inv.voidedBy, 'manager1');
      expect(inv.voidedAt, isNotNull);
      expect(inv.netAmount, 0.0);
      expect(inv.returnedAmount, 0.0);
      expect(inv.updatedAt, isNotNull);
    });

    test('voiding is idempotent — second call throws, stock not doubled',
        () async {
      final db = await openDb();
      await seedCustomer(db, 'V2');
      final productId = await seedProduct(db, 'صنف', 50);
      final invoiceId = await seedSale(db, customerId: 'V2', lines: [(productId, 3)]);

      final svc = InvoiceVoidService(db);
      await svc.voidInvoice(
        invoiceId: invoiceId,
        reason: VoidReasons.inputError,
        voidedBy: 'manager1',
      );

      await expectLater(
        svc.voidInvoice(
          invoiceId: invoiceId,
          reason: VoidReasons.inputError,
          voidedBy: 'manager1',
        ),
        throwsException,
      );

      // المخزون 50 مش 53 — second call رُفض قبل أي كتابة.
      final p = await db.productDao.getProductById(productId);
      expect(p!.quantity, 50);
    });

    test('voids an invoice that has a partial return — full reversal', () async {
      final db = await openDb();
      await seedCustomer(db, 'V3');
      final productId = await seedProduct(db, 'صنف', 50);
      final invoiceId = await seedSale(db, customerId: 'V3', lines: [(productId, 5)]);

      final items = await db.invoiceDao.getItemsByInvoiceId(invoiceId);
      final returnId = await SalesReturnService(db).processPartialReturn(
        invoiceId: invoiceId,
        itemReturns: {items.first.id: 2},
        processedBy: 'cashier1',
      );

      // بعد المرتجع: المخزون 47 والعميل مدين 300.
      var p = await db.productDao.getProductById(productId);
      expect(p!.quantity, 47);
      expect(await db.ledgerDao.getCustomerBalance('V3'), 300.0);
      expect(
        await db.salesReturnsDao.getReturnsForInvoice(invoiceId),
        hasLength(1),
      );

      final preview = await InvoiceVoidService(db).preview(invoiceId);
      expect(preview.returnCount, 1);
      expect(preview.refundCount, 0);

      // ⚠️ الإلغاء لازم **ينجح** مع المرتجع، ويعكس كل حاجة.
      await InvoiceVoidService(db).voidInvoice(
        invoiceId: invoiceId,
        reason: VoidReasons.inputError,
        voidedBy: 'manager1',
      );

      // المخزون رجع 50 — مش 52 (عكس المرتجع + عكس البيع).
      p = await db.productDao.getProductById(productId);
      expect(p!.quantity, 50);

      // الرصيد رجع صفر.
      expect(await db.ledgerDao.getCustomerBalance('V3'), 0.0);

      // المرتجع وأصنافه وقيده العكسي اتشالوا كلهم.
      expect(await db.salesReturnsDao.getReturnsForInvoice(invoiceId), isEmpty);
      expect(await db.salesReturnsDao.getItemsForReturn(returnId), isEmpty);
      expect(
        await db.ledgerDao.getTransactionsByReceiptNumber('RET$returnId'),
        isEmpty,
      );
    });

    test('voids an invoice with a return + cash refund — refund reversed',
        () async {
      final db = await openDb();
      await seedCustomer(db, 'V3R');
      final productId = await seedProduct(db, 'صنف', 50);
      final invoiceId = await seedSale(db, customerId: 'V3R', lines: [(productId, 5)]);

      final items = await db.invoiceDao.getItemsByInvoiceId(invoiceId);
      final returnId = await SalesReturnService(db).processPartialReturn(
        invoiceId: invoiceId,
        itemReturns: {items.first.id: 2},
        processedBy: 'cashier1',
      );
      final refund = await ReturnRefundService(db).refund(
        returnId: returnId,
        amount: 200,
        method: RefundMethod.cash,
        processedBy: 'cashier1',
      );

      // قيد الكاش بتاع الاسترداد موجود.
      expect(
        (await db.ledgerDao
                .getTransactionsByReceiptNumber('RREF${refund.refundId}'))
            .length,
        1,
      );

      final preview = await InvoiceVoidService(db).preview(invoiceId);
      expect(preview.returnCount, 1);
      expect(preview.refundCount, 1);
      expect(preview.cashRefundAmount, 200.0);

      await InvoiceVoidService(db).voidInvoice(
        invoiceId: invoiceId,
        reason: VoidReasons.duplicate,
        voidedBy: 'manager1',
      );

      // قيد الاسترداد النقدي اتشال + سجل الاسترداد اتشال مع المرتجع.
      expect(
        await db.ledgerDao.getTransactionsByReceiptNumber('RREF${refund.refundId}'),
        isEmpty,
      );
      expect(await db.returnRefundsDao.getRefundsForReturn(returnId), isEmpty);

      final p = await db.productDao.getProductById(productId);
      expect(p!.quantity, 50);
      expect(await db.ledgerDao.getCustomerBalance('V3R'), 0.0);
      expect(await db.invoicePaymentsDao.getPaymentsForInvoice(invoiceId), isEmpty);
    });

    test('empty reason is rejected', () async {
      final db = await openDb();
      await seedCustomer(db, 'V4');
      final productId = await seedProduct(db, 'صنف', 10);
      final invoiceId = await seedSale(db, customerId: 'V4', lines: [(productId, 1)]);

      await expectLater(
        InvoiceVoidService(db).voidInvoice(
          invoiceId: invoiceId,
          reason: '   ',
          voidedBy: 'manager1',
        ),
        throwsException,
      );

      final inv =
          await (db.select(db.invoices)..where((t) => t.id.equals(invoiceId)))
              .getSingle();
      expect(inv.status, isNot('voided'));
    });

    test('a cash invoice with no ledger still voids cleanly', () async {
      final db = await openDb();
      final productId = await seedProduct(db, 'صنف', 20);
      final invoiceId = await seedSale(
        db,
        customerId: 'cash',
        paymentMethod: 'cash',
        paid: 200,
        lines: [(productId, 2)],
      );

      expect(
        await db.ledgerDao.getTransactionsByReceiptNumber('INV$invoiceId'),
        isEmpty,
      );

      await InvoiceVoidService(db).voidInvoice(
        invoiceId: invoiceId,
        reason: VoidReasons.testInvoice,
        voidedBy: 'manager1',
      );

      final p = await db.productDao.getProductById(productId);
      expect(p!.quantity, 20);
      final inv =
          await (db.select(db.invoices)..where((t) => t.id.equals(invoiceId)))
              .getSingle();
      expect(inv.status, 'voided');
    });

    test('a paid invoice has both its sale and payment rows reversed',
        () async {
      final db = await openDb();
      await seedCustomer(db, 'V6');
      final productId = await seedProduct(db, 'صنف', 30);
      final invoiceId = await seedSale(
        db,
        customerId: 'V6',
        paymentMethod: 'credit',
        paid: 400,
        lines: [(productId, 4)],
      );

      // صفين: بيع + سداد.
      final rows = await db.ledgerDao.getTransactionsByReceiptNumber('INV$invoiceId');
      expect(rows.length, 2);
      // الرصيد بعد السداد = 0.
      expect(await db.ledgerDao.getCustomerBalance('V6'), 0.0);

      await InvoiceVoidService(db).voidInvoice(
        invoiceId: invoiceId,
        reason: VoidReasons.duplicate,
        voidedBy: 'manager1',
      );

      expect(
        await db.ledgerDao.getTransactionsByReceiptNumber('INV$invoiceId'),
        isEmpty,
      );
      expect(await db.ledgerDao.getCustomerBalance('V6'), 0.0);
    });

    test('void is written to the audit log (السجل بيفضل للأرشيف)', () async {
      final db = await openDb();
      await seedCustomer(db, 'V7');
      final productId = await seedProduct(db, 'صنف', 10);
      final invoiceId = await seedSale(db, customerId: 'V7', lines: [(productId, 1)]);

      await InvoiceVoidService(db).voidInvoice(
        invoiceId: invoiceId,
        reason: VoidReasons.inputError,
        notes: 'ضغطت غلط',
        voidedBy: 'manager1',
      );

      final logs = await db.auditDao.getAuditLogs(tableName: 'invoices');
      final voidLog = logs.where((l) => l.action == 'VOID').toList();
      expect(voidLog.length, 1);
      expect(voidLog.first.recordId, invoiceId);
      expect(voidLog.first.details, contains('manager1'));
      expect(voidLog.first.details, contains(VoidReasons.inputError));
      expect(voidLog.first.details, contains('ضغطت غلط'));
    });

    test('missing invoice throws instead of silently doing nothing', () async {
      final db = await openDb();
      await expectLater(
        InvoiceVoidService(db).preview(999999),
        throwsException,
      );
      await expectLater(
        InvoiceVoidService(db).voidInvoice(
          invoiceId: 999999,
          reason: VoidReasons.inputError,
          voidedBy: 'manager1',
        ),
        throwsException,
      );
    });

    test('partial stock restore only touches lines that exist', () async {
      final db = await openDb();
      await seedCustomer(db, 'V9');
      final productId = await seedProduct(db, 'صنف', 30);
      final invoiceId = await seedSale(db, customerId: 'V9', lines: [(productId, 2)]);

      // العميل مدين من فاتورة تانية كمان — الإلغاء لازم يمس فاتورته بس.
      await InvoiceService(db).createInvoice(
        customerId: 'V9',
        customerName: 'عميل آجل',
        paymentMethod: 'credit',
        totalAmount: 100,
        paidAmount: 0,
        status: 'pending',
        items: [
          InvoiceItemParams(
              productId: await seedProduct(db, 'صنف تاني', 100),
              quantity: 1,
              price: 100),
        ],
      );

      await InvoiceVoidService(db).voidInvoice(
        invoiceId: invoiceId,
        reason: VoidReasons.inputError,
        voidedBy: 'manager1',
      );

      final p = await db.productDao.getProductById(productId);
      expect(p!.quantity, 30); // رجع 2
      expect(await db.ledgerDao.getCustomerBalance('V9'), 100.0);
    });
  });
}