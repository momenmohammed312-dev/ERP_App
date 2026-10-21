import '../helpers/license_grant.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/services/business_date_service.dart';
import 'package:pos_offline_desktop/core/services/custody_service.dart';
import 'package:pos_offline_desktop/core/services/invoice_service.dart';

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
    grantLicensedModules();
    db = AppDatabase(NativeDatabase.memory());
    businessDate = BusinessDateService(db);
    custodyService = CustodyService(db);
    invoiceService = InvoiceService(db);
  });

  tearDown(() async {
    await db.close();
    revokeLicensedModules();
  });

  Future<int> seedCashSale(double amount) async {
    final pid = await db.into(db.products).insert(
          ProductsCompanion.insert(
            name: 'منتج كاش',
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

  group('Suite 6: Cash Box, Custody & Day Close Mathematical Model (BUG-012, BUG-013)', () {
    test('1. Full monetary life cycle: Opening + Sales - Expenses - Return = Expected Cash', () async {
      // 1. Open session with 5,000 opening balance
      await businessDate.openSession(openedBy: 'cashier1', openingBalance: 5000);
      expect(await businessDate.getExpectedCash(), closeTo(5000, 0.01));

      // 2. Cash sales +1,000
      final invId = await seedCashSale(1000);
      expect(await businessDate.getExpectedCash(), closeTo(6000, 0.01));

      // 3. General expense paid in cash -350
      await db.expenseDao.insertExpense(
        ExpensesCompanion(
          description: const Value('فاتورة كهرباء'),
          amount: const Value(350),
          category: const Value('utilities'),
          date: Value(DateTime.now()),
        ),
      );
      expect(await businessDate.getExpectedCash(), closeTo(5650, 0.01));

      // 4. Close session with 5650.00 actual cash -> zero discrepancy
      final session = await businessDate.getCurrentSession();
      await businessDate.closeSession(
        sessionId: session!.id,
        actualCash: 5650,
        notes: 'إغلاق مطابق تماماً 5650.00',
      );

      final closed = await businessDate.getCurrentSession();
      expect(closed!.closingBalance, closeTo(5650, 0.01));
      expect(closed.difference, closeTo(0, 0.01));
    });

    test('2. Custody life cycle: Issue 800, Expense 500, Settle & return 300 -> net expense 500 deducted', () async {
      // Open with 2000
      await businessDate.openSession(openedBy: 'cashier1', openingBalance: 2000);

      // Cash sale 1500 -> 3500
      await seedCashSale(1500);

      // Issue custody 800 -> 2700
      final custodyId = await custodyService.createCustody(
        staffId: 'EMP-1',
        staffName: 'مندوب مشتريات',
        amount: 800,
      );
      expect(await businessDate.getExpectedCash(), closeTo(2700, 0.01));

      // Custody expense 500
      await custodyService.addExpense(
        custodyId: custodyId,
        description: 'شراء بضاعة عاجلة',
        amount: 500,
      );

      // Settle custody: returns unused 300 to cash drawer -> 3000
      await custodyService.settleCustody(
        custodyId: custodyId,
        settledBy: 'cashier1',
      );
      expect(await businessDate.getExpectedCash(), closeTo(3000, 0.01));

      // Add general expense 250 -> 2750
      await db.expenseDao.insertExpense(
        ExpensesCompanion(
          description: const Value('شاي وضيافة'),
          amount: const Value(250),
          category: const Value('office'),
          date: Value(DateTime.now()),
        ),
      );
      expect(await businessDate.getExpectedCash(), closeTo(2750, 0.01));

      // Close session with 2750 actual cash -> 0 discrepancy
      final session = await businessDate.getCurrentSession();
      await businessDate.closeSession(
        sessionId: session!.id,
        actualCash: 2750,
        notes: 'إغلاق مطابق تماماً',
      );

      final closed = await businessDate.getCurrentSession();
      expect(closed!.closingBalance, closeTo(2750, 0.01));
      expect(closed.difference, closeTo(0, 0.01));
    });

    test('3. Open custody left unsettled deducts full issued amount at day close', () async {
      await businessDate.openSession(openedBy: 'cashier1', openingBalance: 3000);

      // Issue custody 600, not settled
      await custodyService.createCustody(
        staffId: 'EMP-2',
        staffName: 'عامل صيانة',
        amount: 600,
      );

      expect(await businessDate.getExpectedCash(), closeTo(2400, 0.01));

      final session = await businessDate.getCurrentSession();
      await businessDate.closeSession(
        sessionId: session!.id,
        actualCash: 2400,
        notes: 'إغلاق مع عهدة معلقة',
      );

      final closed = await businessDate.getCurrentSession();
      expect(closed!.closingBalance, closeTo(2400, 0.01));
      expect(closed.difference, closeTo(0, 0.01));
    });

    test('4. Custody cancellation restores full cash amount back to drawer', () async {
      await businessDate.openSession(openedBy: 'cashier1', openingBalance: 1000);

      final cId = await custodyService.createCustody(
        staffId: 'EMP-3',
        staffName: 'سائق',
        amount: 400,
      );
      expect(await businessDate.getExpectedCash(), closeTo(600, 0.01));

      // Cancel custody before use
      await custodyService.cancelCustody(cId);

      // Drawer restored to full 1000
      expect(await businessDate.getExpectedCash(), closeTo(1000, 0.01));
    });
  });
}
