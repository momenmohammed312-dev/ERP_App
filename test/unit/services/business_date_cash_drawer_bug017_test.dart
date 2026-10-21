import 'dart:io';
import '../../helpers/license_grant.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/services/business_date_service.dart';
import 'package:pos_offline_desktop/core/services/custody_service.dart';
import 'package:pos_offline_desktop/core/services/document_date_service.dart';
import 'package:pos_offline_desktop/core/services/invoice_service.dart';
import 'package:pos_offline_desktop/core/services/return_refund_service.dart';
import 'package:pos_offline_desktop/core/services/sales_return_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (MethodCall methodCall) async => '.',
  );

  group('BUG-017: Cash Drawer Session Window, Payment Methods & Overpaid Invoices', () {
    late AppDatabase db;
    late BusinessDateService businessDate;
    late DocumentDateService documentDate;
    late InvoiceService invoiceService;
    late CustodyService custodyService;
    late SalesReturnService returnService;
    late ReturnRefundService refundService;

    setUp(() async {
      grantLicensedModules();
      db = AppDatabase(NativeDatabase.memory());
      businessDate = BusinessDateService(db);
      documentDate = DocumentDateService(db);
      invoiceService = InvoiceService(db);
      custodyService = CustodyService(db);
      returnService = SalesReturnService(db);
      refundService = ReturnRefundService(db);
    });

    tearDown(() async {
      await db.close();
      revokeLicensedModules();
    });

    test('Case 1 (C1/C2): Modifying document date via DocumentDateService does not alter cash drawer expected balance', () async {
      // 1. فتح جلسة برصيد افتتاحي 1000.0
      await businessDate.openSession(openedBy: 'cashier1', openingBalance: 1000.0);
      expect(await businessDate.getExpectedCash(), closeTo(1000.0, 0.01));

      // 2. إنشاء فاتورة نقدية بمبلغ 500.0
      final pid = await db.into(db.products).insert(
        ProductsCompanion.insert(
          name: 'منتج تجريبي 1',
          price: 500.0,
          quantity: 100,
          costPrice: const Value(250.0),
        ),
      );
      final invRes = await invoiceService.createInvoice(
        customerId: null,
        customerName: 'عميل نقدي',
        paymentMethod: 'cash',
        totalAmount: 500.0,
        paidAmount: 500.0,
        cashAmount: 500.0,
        status: 'paid',
        items: [InvoiceItemParams(productId: pid, quantity: 1, price: 500.0)],
      );

      // 3. إنشاء مصروف نقدي بمبلغ 100.0
      final expense = await db.expenseDao.insertExpense(
        ExpensesCompanion(
          description: const Value('مصروف صيانة كاش'),
          amount: const Value(100.0),
          category: const Value('maintenance'),
          paymentMethod: const Value('cash'),
          date: Value(DateTime.now()),
        ),
      );

      // 4. إنشاء مرتجع واسترداد نقدي بمبلغ 50.0
      final lines = await returnService.getReturnableLines(invRes.invoiceId);
      final retId = await returnService.processPartialReturn(
        invoiceId: invRes.invoiceId,
        itemReturns: {lines.first.invoiceItem.id: 1},
        processedBy: 'cashier1',
      );
      await refundService.refund(
        returnId: retId,
        amount: 50.0,
        method: RefundMethod.cash,
        processedBy: 'cashier1',
      );

      // 5. صرف عهدة نقدية بمبلغ 200.0
      final custodyId = await custodyService.createCustody(
        staffId: 'STAFF-1',
        staffName: 'عامل',
        amount: 200.0,
      );

      // المعادلة: 1000 افتتاحي + 500 مبيعات - 100 مصروف - 50 مرتجع - 200 عهدة = 1150.0
      final expectedBefore = await businessDate.getExpectedCash();
      expect(expectedBefore, closeTo(1150.0, 0.01));

      // 6. استخدام DocumentDateService لتغيير تاريخ الفاتورة والمصروف والمرتجع والعهدة إلى 5 أيام في الماضي
      final pastDate = DateTime.now().subtract(const Duration(days: 5));
      await documentDate.updateInvoiceDate(invoiceId: invRes.invoiceId, newDate: pastDate);
      await documentDate.updateExpenseDate(expenseId: expense.id, newDate: pastDate);
      await documentDate.updateSalesReturnDate(returnId: retId, newDate: pastDate);
      await (db.update(db.returnRefunds)..where((t) => t.returnId.equals(retId))).write(
        ReturnRefundsCompanion(refundDate: Value(pastDate)),
      );
      await documentDate.updateCustodyDate(custodyId: custodyId, newDate: pastDate);

      // 7. التحقق من أن getExpectedCash() و closeSession() ما زالا يحسبان 1150.0 بالضبط
      final expectedAfter = await businessDate.getExpectedCash();
      expect(expectedAfter, closeTo(1150.0, 0.01), reason: 'Expected cash must remain 1150.0 after document date change');

      final session = await businessDate.getCurrentSession();
      await businessDate.closeSession(
        sessionId: session!.id,
        actualCash: 1150.0,
        notes: 'إغلاق مطابق بعد تعديل تواريخ المستندات',
      );

      final closedSession = await businessDate.getCurrentSession();
      expect(closedSession!.closingBalance, closeTo(1150.0, 0.01));
      expect(closedSession.difference, closeTo(0.0, 0.01));
    });

    test('Case 2 (C8): Non-cash payment methods & split payments do not corrupt cash drawer', () async {
      await businessDate.openSession(openedBy: 'cashier1', openingBalance: 1000.0);

      final pid = await db.into(db.products).insert(
        ProductsCompanion.insert(
          name: 'منتج دفع إلكتروني',
          price: 100.0,
          quantity: 200,
          costPrice: const Value(50.0),
        ),
      );

      // 1. فاتورة بطريقة دفع 'visa': لا تضيف شيئاً لدرج الكاش
      await invoiceService.createInvoice(
        customerId: null,
        customerName: 'عميل فيزا',
        paymentMethod: 'visa',
        totalAmount: 400.0,
        paidAmount: 400.0,
        cashAmount: 0.0,
        cardAmount: 400.0,
        status: 'paid',
        items: [InvoiceItemParams(productId: pid, quantity: 4, price: 100.0)],
      );
      expect(await businessDate.getExpectedCash(), closeTo(1000.0, 0.01),
          reason: 'Visa invoice must not add anything to cash drawer');

      // 2. فاتورة بطريقة دفع 'transfer': لا تضيف شيئاً لدرج الكاش
      await invoiceService.createInvoice(
        customerId: null,
        customerName: 'عميل تحويل',
        paymentMethod: 'transfer',
        totalAmount: 300.0,
        paidAmount: 300.0,
        cashAmount: 0.0,
        status: 'paid',
        items: [InvoiceItemParams(productId: pid, quantity: 3, price: 100.0)],
      );
      expect(await businessDate.getExpectedCash(), closeTo(1000.0, 0.01),
          reason: 'Bank transfer invoice must not add anything to cash drawer');

      // 3. فاتورة بطريقة دفع 'split': تضيف فقط cashAmount (250.0) للدرج
      await invoiceService.createInvoice(
        customerId: null,
        customerName: 'عميل دفع مختلط',
        paymentMethod: 'split',
        totalAmount: 600.0,
        paidAmount: 600.0,
        cashAmount: 250.0,
        cardAmount: 350.0,
        status: 'paid',
        items: [InvoiceItemParams(productId: pid, quantity: 6, price: 100.0)],
      );
      // 1000 + 250 = 1250.0
      expect(await businessDate.getExpectedCash(), closeTo(1250.0, 0.01),
          reason: 'Split invoice must only add cashAmount to cash drawer');

      // 4. مصروف بطريقة دفع 'bank': لا يخصم من درج الكاش
      await db.expenseDao.insertExpense(
        ExpensesCompanion(
          description: const Value('تحويل إيجار بنكي'),
          amount: const Value(500.0),
          category: const Value('rent'),
          paymentMethod: const Value('bank'),
          date: Value(DateTime.now()),
        ),
      );
      expect(await businessDate.getExpectedCash(), closeTo(1250.0, 0.01),
          reason: 'Bank expense must not be deducted from cash drawer');

      // 5. مصروف بطريقة دفع 'visa': لا يخصم من درج الكاش
      await db.expenseDao.insertExpense(
        ExpensesCompanion(
          description: const Value('شراء مستلزمات ببطاقة فيزا'),
          amount: const Value(200.0),
          category: const Value('supplies'),
          paymentMethod: const Value('visa'),
          date: Value(DateTime.now()),
        ),
      );
      expect(await businessDate.getExpectedCash(), closeTo(1250.0, 0.01),
          reason: 'Visa expense must not be deducted from cash drawer');

      // 6. مصروف بطريقة دفع 'cash': يخصم من درج الكاش
      await db.expenseDao.insertExpense(
        ExpensesCompanion(
          description: const Value('ضيافة نقدية'),
          amount: const Value(100.0),
          category: const Value('hospitality'),
          paymentMethod: const Value('cash'),
          date: Value(DateTime.now()),
        ),
      );
      // 1250 - 100 = 1150.0
      expect(await businessDate.getExpectedCash(), closeTo(1150.0, 0.01),
          reason: 'Cash expense must be deducted from cash drawer');
    });

    test('Case 3 (Overpaid Invoice Fix): Overpaid client invoice #1 status is repaired to paid', () async {
      final clientFixture = File('scratch/client_copy.sqlite');
      expect(clientFixture.existsSync(), isTrue, reason: 'client_copy.sqlite fixture must exist');

      final tempDbFile = File('scratch/temp_client_bug017.sqlite');
      if (tempDbFile.existsSync()) tempDbFile.deleteSync();
      clientFixture.copySync(tempDbFile.path);

      final clientDb = AppDatabase(NativeDatabase(tempDbFile));
      try {
        // قراءة الفاتورة رقم 1 بعد فتح قاعدة البيانات وتشغيل الترقية وإصلاح البيانات
        final inv1 = await clientDb.invoiceDao.getInvoiceById(1);
        expect(inv1, isNotNull);
        expect(inv1!.totalAmount, closeTo(63550.0, 0.01));
        expect(inv1.paidAmount, closeTo(125800.0, 0.01));
        expect(inv1.status, 'paid', reason: 'Invoice with paid_amount >= total_amount must be repaired to status paid');
      } finally {
        await clientDb.close();
        if (tempDbFile.existsSync()) tempDbFile.deleteSync();
      }
    });
  });
}
