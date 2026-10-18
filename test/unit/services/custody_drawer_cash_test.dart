import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/services/business_date_service.dart';
import 'package:pos_offline_desktop/core/services/custody_service.dart';
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

  late AppDatabase db;
  late BusinessDateService businessDate;
  late CustodyService custodyService;
  late InvoiceService invoiceService;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    businessDate = BusinessDateService(db);
    custodyService = CustodyService(db);
    invoiceService = InvoiceService(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> cashSale(double amount) async {
    final pid = await db.into(db.products).insert(
          ProductsCompanion.insert(
            name: 'منتج تجريبي',
            price: amount,
            quantity: 100,
            costPrice: Value(amount / 2),
            category: const Value('test'),
          ),
        );
    final result = await invoiceService.createInvoice(
      customerId: null,
      customerName: 'عميل نقدي',
      paymentMethod: 'cash',
      totalAmount: amount,
      paidAmount: amount,
      status: 'paid',
      items: [
        InvoiceItemParams(
          productId: pid,
          quantity: 1,
          price: amount,
          unitCostAtTime: amount / 2,
        ),
      ],
    );
    return result.invoiceId;
  }

  group('[MONEY] BUG-4: حركات العُهد وإغلاق اليومية والدرج', () {
    test('1. صرف عهدة وتسويتها مع مصروف (1000 -> 800 بعد مصروف 200 وتسوية رد 300)',
        () async {
      await businessDate.openSession(openedBy: 'tester', openingBalance: 1000);

      final custodyId = await custodyService.createCustody(
        staffId: 'ST1',
        staffName: 'مندوب',
        amount: 500,
      );

      // قبل التسوية: خرج 500 فالمتوقع 500
      expect(await businessDate.getExpectedCash(), closeTo(500, 0.01));

      // صرف 200 من العهدة
      await custodyService.addExpense(
        custodyId: custodyId,
        description: 'بنزين',
        amount: 200,
      );

      // تسوية العهدة ورد المتبقي (300) إلى الخزينة
      await custodyService.settleCustody(
        custodyId: custodyId,
        settledBy: 'tester',
      );

      // المتوقع: 1000 افتتاحي - (500 صرف - 300 رد) = 800
      final expected = await businessDate.getExpectedCash();
      expect(expected, closeTo(800, 0.01));

      // إغلاق الجلسة
      final session = await businessDate.getCurrentSession();
      await businessDate.closeSession(
        sessionId: session!.id,
        actualCash: 800,
        notes: 'تسوية مطابقة',
      );

      final closed = await businessDate.getCurrentSession();
      expect(closed!.closingBalance, closeTo(800, 0.01));
      expect(closed.difference, closeTo(0, 0.01));
    });

    test('2. عهدة مفتوحة لم تُسوَّ (1000 -> 500 بعد صرف 500)', () async {
      await businessDate.openSession(openedBy: 'tester', openingBalance: 1000);

      await custodyService.createCustody(
        staffId: 'ST2',
        staffName: 'مسؤول مشتريات',
        amount: 500,
      );

      // خرج 500 ولم يُرد شيء -> الدرج الفعلي 500 والمتوقع 500
      expect(await businessDate.getExpectedCash(), closeTo(500, 0.01));

      final session = await businessDate.getCurrentSession();
      await businessDate.closeSession(
        sessionId: session!.id,
        actualCash: 500,
        notes: 'إغلاق مع عهدة مفتوحة',
      );

      final closed = await businessDate.getCurrentSession();
      expect(closed!.closingBalance, closeTo(500, 0.01));
      expect(closed.difference, closeTo(0, 0.01));
    });

    test('3. إلغاء عهدة (1000 -> 1000 بعد صرف 500 ثم إلغائها واسترداد كامل المبلغ)',
        () async {
      await businessDate.openSession(openedBy: 'tester', openingBalance: 1000);

      final custodyId = await custodyService.createCustody(
        staffId: 'ST3',
        staffName: 'موظف',
        amount: 500,
      );

      expect(await businessDate.getExpectedCash(), closeTo(500, 0.01));

      // إلغاء العهدة ورد 500 كاملة للصندوق
      await custodyService.cancelCustody(custodyId);

      // المتوقع يعود 1000 كما كان
      expect(await businessDate.getExpectedCash(), closeTo(1000, 0.01));
    });

    test('4. يوم فيه استرداد نقدي لمرتجع + حركة عهدة معاً', () async {
      await businessDate.openSession(openedBy: 'tester', openingBalance: 1000);

      // بيع نقدي 600
      final invId = await cashSale(600);

      // استرداد نقدي لمرتجع 200
      final returns = SalesReturnService(db);
      final refunds = ReturnRefundService(db);
      final lines = await returns.getReturnableLines(invId);
      final retId = await returns.processPartialReturn(
        invoiceId: invId,
        itemReturns: {lines.first.invoiceItem.id: 1},
        processedBy: 'tester',
      );
      await refunds.refund(
        returnId: retId,
        amount: 200,
        method: RefundMethod.cash,
        processedBy: 'tester',
      );

      // صرف عهدة 300 وتسويتها بمصروف 100 ورد 200
      final custodyId = await custodyService.createCustody(
        staffId: 'ST4',
        staffName: 'عامل',
        amount: 300,
      );
      await custodyService.addExpense(
        custodyId: custodyId,
        description: 'نقل',
        amount: 100,
      );
      await custodyService.settleCustody(
        custodyId: custodyId,
        settledBy: 'tester',
      );

      // الحسبة:
      // افتتاحي 1000 + مبيعات 600 - مرتجع 200 - عهدة صافي (300 - 200 = 100) = 1300
      final expected = await businessDate.getExpectedCash();
      expect(expected, closeTo(1300, 0.01));
    });

    test('5. يوم بلا عُهد: النتيجة لا تتغير وتطابق المعادلة القياسية', () async {
      await businessDate.openSession(openedBy: 'tester', openingBalance: 1000);
      await cashSale(400);
      await db.expenseDao.insertExpense(ExpensesCompanion(
        description: const Value('مصروف عام'),
        amount: const Value(150),
        category: const Value('general'),
        date: Value(DateTime.now()),
      ));

      // 1000 + 400 - 150 = 1250
      expect(await businessDate.getExpectedCash(), closeTo(1250, 0.01));
    });

    test(
        '[BUG-4 Confirmed Fixed] صافي مصروفات العهدة يخصم من الكاش المتوقع (نسخة integration suite)',
        () async {
      await businessDate.openSession(openedBy: 'tester', openingBalance: 1000);

      final custodyId = await custodyService.createCustody(
        staffId: 'ST1',
        staffName: 'مندوب',
        amount: 500,
      );
      await custodyService.addExpense(
        custodyId: custodyId,
        description: 'بنزين',
        amount: 200,
      );
      await custodyService.settleCustody(
        custodyId: custodyId,
        settledBy: 'tester',
      );

      // الدرج فعلياً: 1000 - 500 + 300 = 800
      final expected = await businessDate.getExpectedCash();
      expect(expected, closeTo(800, 0.01));
    });
  });
}
