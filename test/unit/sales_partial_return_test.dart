import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/services/sales_return_service.dart';

/// المبيعات المرتجع الجزئي (بيع مستهلك partial return):
/// - كل سطر ييتحسب له alreadyReturned والمتاح المناظر؛
/// - الإرجاع جزء من صنف يرجع المخزون فقط ولا يقلّص هيدر الفاتورة الأصلية؛
/// - الإرجاع فوق المتاح يرمي استثناء بدون أي side effect؛
/// - العميل الآجل بياخد قيد عكسي في الـledger.
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

  Future<void> seedCustomer(AppDatabase db, String id) async {
    await db.into(db.customers).insert(
      CustomersCompanion.insert(id: id, name: 'عميل'),
    );
  }

  Future<void> seedInvoice(
    AppDatabase db, {
    required String number,
    required String customerId,
    required List<(int productId, int qty, double price)> lines,
  }) async {
    final invoiceId = await db.into(db.invoices).insert(
          InvoicesCompanion.insert(
            invoiceNumber: Value(number),
            customerId: Value(customerId),
            status: const Value('completed'),
          ),
        );
    double total = 0;
    for (final l in lines) {
      total += l.$2 * l.$3;
      await db.into(db.invoiceItems).insert(
            InvoiceItemsCompanion.insert(
              invoiceId: invoiceId,
              productId: l.$1,
              quantity: Value(l.$2),
              price: l.$3,
            ),
          );
    }
    await (db.update(db.invoices)..where((t) => t.id.equals(invoiceId)))
        .write(InvoicesCompanion(totalAmount: Value(total)));
  }

  test('getReturnableLines reports alreadyReturned and available', () async {
    final db = await openDb();
    final a = await seedProduct(db, 'A', 100, 50);
    await seedCustomer(db, 'C-1');
    await seedInvoice(
      db,
      number: 'INV-000001',
      customerId: 'C-1',
      lines: [(a, 10, 100.0)],
    );
    final invoice = await db.invoiceDao.getInvoiceByNumber('INV-000001');
    final svc = SalesReturnService(db);
    final lines = await svc.getReturnableLines(invoice!.id);
    expect(lines.length, 1);
    expect(lines.first.available, 10);
    expect(lines.first.alreadyReturned, 0);

    await svc.processPartialReturn(
      invoiceId: invoice.id,
      itemReturns: {lines.first.invoiceItem.id: 4},
    );

    final after = await svc.getReturnableLines(invoice.id);
    expect(after.first.alreadyReturned, 4);
    expect(after.first.available, 6);
  });

  test('partial return restores stock only; original header unchanged',
      () async {
    final db = await openDb();
    final a = await seedProduct(db, 'A', 100, 50);
    final b = await seedProduct(db, 'B', 50, 20);
    await seedCustomer(db, 'C-2');
    await seedInvoice(
      db,
      number: 'INV-000002',
      customerId: 'C-2',
      lines: [(a, 10, 100.0), (b, 4, 50.0)],
    );
    final invoice = await db.invoiceDao.getInvoiceByNumber('INV-000002');
    final svc = SalesReturnService(db);
    final lines = await svc.getReturnableLines(invoice!.id);
    final aLine = lines.firstWhere((l) => l.invoiceItem.productId == a);
    final bLine = lines.firstWhere((l) => l.invoiceItem.productId == b);

    // إرجاع 2 من أ + 1 من ب = 200 + 50 = 250
    final returnId = await svc.processPartialReturn(
      invoiceId: invoice.id,
      itemReturns: {aLine.invoiceItem.id: 2, bLine.invoiceItem.id: 1},
      reason: 'customer_request',
      notes: 'اختبار جزئي',
    );
    expect(returnId, greaterThan(0));

    // المخزون رجع
    final pa = await db.productDao.getProductById(a);
    final pb = await db.productDao.getProductById(b);
    expect(pa!.quantity, 52);
    expect(pb!.quantity, 21);

    // هيدر الفاتورة الأصلية مش بيتقلّص (مسك سجل البيع الأصلي)
    final after = await db.invoiceDao.getInvoiceById(invoice.id);
    expect(after!.totalAmount, 1200.0);

    // سجل المرتجع
    final ret = await db.salesReturnsDao.getReturnById(returnId);
    expect(ret!.totalAmount, 250.0);
    expect(ret.originalInvoiceId, invoice.id);

    final items = await db.salesReturnsDao.getItemsForReturn(returnId);
    expect(items.length, 2);
    final aItem = items.firstWhere((i) => i.productId == a);
    expect(aItem.quantity, 2);
    expect(aItem.discount, 0.0);
  });

  test('over-return throws with zero side effects', () async {
    final db = await openDb();
    final a = await seedProduct(db, 'A', 100, 50);
    await seedCustomer(db, 'C-3');
    await seedInvoice(
      db,
      number: 'INV-000003',
      customerId: 'C-3',
      lines: [(a, 5, 100.0)],
    );
    final invoice = await db.invoiceDao.getInvoiceByNumber('INV-000003');
    final svc = SalesReturnService(db);
    final lines = await svc.getReturnableLines(invoice!.id);
    await expectLater(
      svc.processPartialReturn(
        invoiceId: invoice.id,
        itemReturns: {lines.first.invoiceItem.id: 6},
      ),
      throwsException,
    );
    // لا رجوع مخزون ولا سجل مرتجع
    final pa = await db.productDao.getProductById(a);
    expect(pa!.quantity, 50);
    final rets = await db.salesReturnsDao.getReturnsForInvoice(invoice.id);
    expect(rets, isEmpty);
  });

  test('credit customer gets a ledger reversal entry', () async {
    final db = await openDb();
    final a = await seedProduct(db, 'A', 100, 50);
    await seedCustomer(db, 'C-4');
    await seedInvoice(
      db,
      number: 'INV-000004',
      customerId: 'C-4',
      lines: [(a, 10, 100.0)],
    );
    final invoice = await db.invoiceDao.getInvoiceByNumber('INV-000004');
    final svc = SalesReturnService(db);
    final lines = await svc.getReturnableLines(invoice!.id);
    await svc.processPartialReturn(
      invoiceId: invoice.id,
      itemReturns: {lines.first.invoiceItem.id: 3},
    );
    final txs = await db.ledgerDao.getTransactionsByEntity('Customer', 'C-4');
    final revs = txs.where((t) => t.origin == 'reversal').toList();
    expect(revs.length, 1);
    expect(revs.first.credit, 300.0);
  });
}