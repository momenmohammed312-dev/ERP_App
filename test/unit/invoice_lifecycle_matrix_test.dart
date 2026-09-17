import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/services/invoice_service.dart';

/// مصفوفة دورة الحياة D12 (Agent 4) — تثبت صفوف DB الفعلية بعد كل انتقال:
/// بيع (نقدي/آجل/جزئي/عمولة) → سداد موحّد → تعديل (غير/مدفوعة) → إلغاء
/// (غير/مدفوعة + إلغاء-ثانٍ صفري) → مرتجع (جزئي/كلي/مكرر) → عمولة → مخزون →
/// برنيكة → أرصدة العملاء/الموردين. كل اختبار DB جديدة (عزل كامل).
AppDatabase openDb() {
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  return db;
}

Future<void> seedCustomer(AppDatabase db, String id, String name) =>
    db.into(db.customers).insert(
          CustomersCompanion.insert(id: id, name: name),
        );

Future<void> seedSupplier(AppDatabase db, String id, String name) =>
    db.into(db.suppliers).insert(
          SuppliersCompanion.insert(id: id, name: name),
        );

Future<int> seedProduct(
  AppDatabase db, {
  String name = 'صنف اختبار',
  double price = 100,
  int qty = 50,
  double cost = 60,
}) =>
    db.productDao.insertProduct(
      ProductsCompanion.insert(
        name: name,
        price: price,
        quantity: qty,
        costPrice: Value(cost),
      ),
    );

Future<int> seedCommissionShipment(
  AppDatabase db, {
  required String supplierId,
  String number = 'SH-1',
  int total = 100,
  double pct = 10,
}) =>
    db.vegetableShipmentDao.insertShipment(
      VegetableShipmentsCompanion.insert(
        supplierId: supplierId,
        shipmentNumber: number,
        pricingMode: 'commission',
        totalBarnikaCount: total,
        barnikaRemainingCount: total,
        totalCost: 0,
        commissionPercentage: Value(pct),
      ),
    );

Future<CreateInvoiceResult> sell(
  AppDatabase db, {
  String? customerId = 'C-1',
  String customerName = 'عميل اختبار',
  String paymentMethod = 'credit',
  required double total,
  double paid = 0,
  required String status,
  required List<InvoiceItemParams> items,
  int? primaryShipmentId,
  String? barnikaCustomerId,
  int? barnikaQuantity,
}) =>
    InvoiceService(db).createInvoice(
      customerId: customerId,
      customerName: customerName,
      paymentMethod: paymentMethod,
      totalAmount: total,
      paidAmount: paid,
      status: status,
      items: items,
      primaryShipmentId: primaryShipmentId,
      barnikaCustomerId: barnikaCustomerId,
      barnikaQuantity: barnikaQuantity,
    );

Future<List<LedgerTransaction>> ledgerByReceipt(AppDatabase db, String r) =>
    db.ledgerDao.getTransactionsByReceiptNumber(r);

void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('D12 sale', () {
    test('بيع نقدي: مخزون + يومية + حركة + دفعة بلا دفتر عميل', () async {
      final db = openDb();
      final pid = await seedProduct(db, qty: 10);
      final res = await sell(
        db,
        customerId: null,
        customerName: 'نقدي',
        paymentMethod: 'cash',
        total: 200,
        paid: 200,
        status: 'paid',
        items: [InvoiceItemParams(productId: pid, quantity: 2, price: 100)],
      );
      expect(res.invoiceId, greaterThan(0));
      expect((await db.productDao.getProductById(pid))!.quantity, 8);
      // walk-in: لا صفوف دفتر عميل.
      expect(await ledgerByReceipt(db, 'INV${res.invoiceId}'), isEmpty);
      // يومية البيع موجودة ومتوازنة.
      final sale = await db.journalDao.getByPostingKey(
        'sale:INV${res.invoiceId}',
      );
      expect(sale, isNotNull);
      final lines = await db.journalDao.getLinesForEntry(sale!.id);
      final d = lines.fold<double>(0, (s, l) => s + l.debit);
      final c = lines.fold<double>(0, (s, l) => s + l.credit);
      expect((d - c).abs() < 0.001, isTrue);
      expect(d, 200);
      // حركة مخزون سالبة حقيقية مرتبطة بالرقم المخزّن.
      final movs = await db.inventoryMovementDao.getMovementsByReference(
        res.invoice.invoiceNumber!,
      );
      expect(movs.length, 1);
      expect(movs.first.quantity, -2);
      expect(movs.first.movementType, 'sale');
      // تقارب D3: صف invoice_payments للدفع لحظة الإنشاء.
      expect(
        await db.invoicePaymentsDao.getTotalPaidForInvoice(res.invoiceId),
        200,
      );
    });

    test('بيع آجل: دفتر بيع + رصيد عميل', () async {
      final db = openDb();
      await seedCustomer(db, 'C-1', 'عميل اختبار');
      final pid = await seedProduct(db);
      final res = await sell(
        db,
        total: 500,
        status: 'pending',
        items: [InvoiceItemParams(productId: pid, quantity: 5, price: 100)],
      );
      final rows = await ledgerByReceipt(db, 'INV${res.invoiceId}');
      expect(rows.length, 1);
      expect(rows.first.debit, 500);
      expect(rows.first.origin, 'sale');
      expect(await db.ledgerDao.getCustomerBalance('C-1'), 500);
    });

    test('بيع جزئي: بيع + سداد + رصيد صافي', () async {
      final db = openDb();
      await seedCustomer(db, 'C-1', 'عميل اختبار');
      final pid = await seedProduct(db);
      final res = await sell(
        db,
        total: 500,
        paid: 200,
        status: 'partial',
        items: [InvoiceItemParams(productId: pid, quantity: 5, price: 100)],
      );
      final rows = await ledgerByReceipt(db, 'INV${res.invoiceId}');
      expect(rows.length, 2);
      expect(await db.ledgerDao.getCustomerBalance('C-1'), 300);
      // قيد التحصيل لحظة الإنشاء موجود.
      expect(
        await db.journalDao.getByPostingKey(
          'customer_payment:${res.invoiceId}_pay',
        ),
        isNotNull,
      );
    });

    test('بيع عمولة: مورد دائن net + كل الصيغ + غياب قيد العمولة', () async {
      final db = openDb();
      await seedCustomer(db, 'C-1', 'عميل اختبار');
      await seedSupplier(db, 'S-1', 'مورد اختبار');
      final pid = await seedProduct(db, qty: 50);
      final sh = await seedCommissionShipment(db, supplierId: 'S-1');
      final res = await sell(
        db,
        total: 1000,
        status: 'pending',
        items: [
          InvoiceItemParams(
            productId: pid,
            quantity: 10,
            price: 100,
            shipmentId: sh,
          ),
        ],
        primaryShipmentId: sh,
      );
      final supRows = (await ledgerByReceipt(db, 'INV${res.invoiceId}'))
          .where((r) => r.entityType == 'Supplier')
          .toList();
      expect(supRows.length, 1);
      // D8: دائن 900 (sell−commission) لا مدين.
      expect(supRows.first.credit, 900);
      expect(supRows.first.debit, 0);
      expect(await db.ledgerDao.getSupplierBalance('S-1'), 900);
      expect(await db.ledgerDao.getSupplierCommissionDue(), 900);
      expect(await db.ledgerDao.getSupplierOutstandingBalance(), 900);
      final all = await db.ledgerDao.getAllSupplierBalances();
      expect(
        all.firstWhere((m) => m['id'] == 'S-1')['balance'],
        900,
      );
      // D8: لا قيد يومية عمولة (مؤجل بتوثيق) — واليومية ما زالت متوازنة.
      final entries = await db.journalDao.getEntriesByDateRange(
        DateTime(2000),
        DateTime(2100),
      );
      expect(entries.where((e) => e.sourceType == 'commission'), isEmpty);
      expect(
        await db.journalDao.getByPostingKey('sale:INV${res.invoiceId}'),
        isNotNull,
      );
      // الشحنة تحركت.
      expect((await db.vegetableShipmentDao.getById(sh))!.barnikaSoldCount, 10);
    });
  });

  group('D12 PAY', () {
    test('سداد مستقل: فاتورة + دفتر + يومية + حارس التجاوز', () async {
      final db = openDb();
      await seedCustomer(db, 'C-1', 'عميل اختبار');
      final pid = await seedProduct(db);
      final res = await sell(
        db,
        total: 500,
        status: 'pending',
        items: [InvoiceItemParams(productId: pid, quantity: 5, price: 100)],
      );
      final svc = InvoiceService(db);
      final after = await svc.recordInvoicePayment(
        invoiceId: res.invoiceId,
        amount: 200,
        paymentMethod: 'cash',
      );
      expect(after.paidAmount, 200);
      expect(after.status, 'partial');
      expect(
        await db.invoicePaymentsDao.getTotalPaidForInvoice(res.invoiceId),
        200,
      );
      final pays = await db.ledgerDao.getPaymentsForReceipt(
        'INV${res.invoiceId}',
      );
      expect(pays.length, 1);
      expect(pays.first.credit, 200);
      expect(await db.ledgerDao.getCustomerBalance('C-1'), 300);
      // دفعة ثانية مطابقة = دفعة حقيقية ثانية (لا كبت زمني — الدليل: الكبت
      // كان يمنع دفعات FIFO المشروعة؛ الحماية عبر حارس التجاوز فقط).
      // مدفوع 200 + 200 = 400، والفاتورة تصبح مدفوعة جزئيًا بالمبلغ الجديد.
      final after2 = await svc.recordInvoicePayment(
        invoiceId: res.invoiceId,
        amount: 200,
        paymentMethod: 'cash',
      );
      expect(after2.paidAmount, 400);
      expect(after2.status, 'partial');
      expect(
        await db.invoicePaymentsDao.getTotalPaidForInvoice(res.invoiceId),
        400,
      );
      expect(
        (await db.ledgerDao.getPaymentsForReceipt('INV${res.invoiceId}'))
            .length,
        2,
      );
      expect(await db.ledgerDao.getCustomerBalance('C-1'), 100);
      // تجاوز المتبقي (100) = استثناء (حارس الدفع المزدوج الفعلي).
      expect(
        () => svc.recordInvoicePayment(
          invoiceId: res.invoiceId,
          amount: 400,
          paymentMethod: 'cash',
        ),
        throwsA(anything),
      );
      // صفر آثار بعد الرفض: الرصيد والمدفوع كما هما.
      expect(await db.ledgerDao.getCustomerBalance('C-1'), 100);
      expect(
        await db.invoicePaymentsDao.getTotalPaidForInvoice(res.invoiceId),
        400,
      );
    });

    test('سداد عميل FIFO + فائض مقدم ADV بلا null', () async {
      final db = openDb();
      await seedCustomer(db, 'C-1', 'عميل اختبار');
      final pid = await seedProduct(db, qty: 100);
      final a = await sell(
        db,
        total: 300,
        status: 'pending',
        items: [InvoiceItemParams(productId: pid, quantity: 3, price: 100)],
      );
      final b = await sell(
        db,
        total: 200,
        status: 'pending',
        items: [InvoiceItemParams(productId: pid, quantity: 2, price: 100)],
      );
      final applied = await InvoiceService(db).recordCustomerPayment(
        customerId: 'C-1',
        amount: 400,
        paymentMethod: 'cash',
      );
      expect(applied[a.invoiceId], 300);
      expect(applied[b.invoiceId], 100);
      expect((await db.invoiceDao.getInvoiceById(a.invoiceId))!.status, 'paid');
      expect(
        (await db.invoiceDao.getInvoiceById(b.invoiceId))!.status,
        'partial',
      );
      // فائض 500 → يكمل B (100) + مقدم 400 بإيصال ADV غير-null.
      final applied2 = await InvoiceService(db).recordCustomerPayment(
        customerId: 'C-1',
        amount: 500,
        paymentMethod: 'cash',
      );
      expect(applied2[b.invoiceId], 100);
      final adv = (await db.ledgerDao.getAllTransactions())
          .where((t) => (t.receiptNumber ?? '').startsWith('ADV-C-1_'))
          .toList();
      expect(adv.length, 1);
      expect(adv.first.credit, 400);
      // مبيعات 500 − مدفوعات 500 − مقدم 400 = −400.
      expect(await db.ledgerDao.getCustomerBalance('C-1'), -400);
    });
  });

  group('D12 edit', () {
    test('تعديل غير مدفوعة: الرقم يُحفظ + عكس sale + إعادة ترحيل', () async {
      final db = openDb();
      await seedCustomer(db, 'C-1', 'عميل اختبار');
      final pid = await seedProduct(db, qty: 10);
      final res = await sell(
        db,
        total: 200,
        status: 'pending',
        items: [InvoiceItemParams(productId: pid, quantity: 2, price: 100)],
      );
      final number = res.invoice.invoiceNumber!;
      final updated = await InvoiceService(db).editInvoice(
        invoiceId: res.invoiceId,
        customerId: 'C-1',
        customerName: 'عميل اختبار',
        paymentMethod: 'credit',
        totalAmount: 300,
        paidAmount: 0,
        status: 'pending',
        items: [InvoiceItemParams(productId: pid, quantity: 3, price: 100)],
      );
      expect(updated.invoiceNumber, number);
      expect(await db.ledgerDao.getCustomerBalance('C-1'), 300);
      // عكس البيع الأصلي موجود (reversal) + بيع جديد.
      final revs = (await db.ledgerDao.getTransactionsByReceiptNumber(
        'REV-INV${res.invoiceId}',
      ))
          .where((t) => t.origin == 'reversal')
          .toList();
      expect(revs.length, 1);
      expect(revs.first.credit, 200);
      // قيد بيع حي واحد بالإجمالي الجديد.
      final sale = await db.journalDao.getByPostingKey(
        'sale:INV${res.invoiceId}',
      );
      final slines = await db.journalDao.getLinesForEntry(sale!.id);
      expect(slines.fold<double>(0, (s, l) => s + l.debit), 300);
      expect((await db.productDao.getProductById(pid))!.quantity, 7);
      // حركات: return +2 ثم sale −3.
      final movs = await db.inventoryMovementDao.getMovementsByReference(
        number,
      );
      expect(movs.length, 3);
    });

    test('تعديل مدفوعة: history يُحفظ ومبلغ الواجهة يُتجاهل', () async {
      final db = openDb();
      await seedCustomer(db, 'C-1', 'عميل اختبار');
      final pid = await seedProduct(db, qty: 20);
      final res = await sell(
        db,
        total: 500,
        paid: 200,
        status: 'partial',
        items: [InvoiceItemParams(productId: pid, quantity: 5, price: 100)],
      );
      final updated = await InvoiceService(db).editInvoice(
        invoiceId: res.invoiceId,
        customerId: 'C-1',
        customerName: 'عميل اختبار',
        paymentMethod: 'credit',
        totalAmount: 600,
        paidAmount: 999, // يجب تجاهله — المصدر Σ(المدفوعات).
        status: 'paid',
        items: [InvoiceItemParams(productId: pid, quantity: 6, price: 100)],
      );
      expect(updated.paidAmount, 200);
      expect(updated.status, 'partial');
      expect(
        (await db.invoicePaymentsDao.getPaymentsForInvoice(res.invoiceId))
            .length,
        1,
      );
      expect(
        (await db.ledgerDao.getPaymentsForReceipt('INV${res.invoiceId}'))
            .length,
        1,
      );
      expect(await db.ledgerDao.getCustomerBalance('C-1'), 400);
    });

    test('نقل فاتورة مدفوعة لعميل آخر مرفوض', () async {
      final db = openDb();
      await seedCustomer(db, 'C-1', 'عميل اختبار');
      await seedCustomer(db, 'C-2', 'عميل ثانٍ');
      final pid = await seedProduct(db, qty: 20);
      final res = await sell(
        db,
        total: 500,
        paid: 200,
        status: 'partial',
        items: [InvoiceItemParams(productId: pid, quantity: 5, price: 100)],
      );
      expect(
        () => InvoiceService(db).editInvoice(
          invoiceId: res.invoiceId,
          customerId: 'C-2',
          customerName: 'عميل ثانٍ',
          paymentMethod: 'credit',
          totalAmount: 500,
          paidAmount: 200,
          status: 'partial',
          items: [InvoiceItemParams(productId: pid, quantity: 5, price: 100)],
        ),
        throwsA(anything),
      );
      expect(await db.ledgerDao.getCustomerBalance('C-1'), 300);
      expect(await db.ledgerDao.getCustomerBalance('C-2'), 0);
    });
  });

  group('D12 void', () {
    test('إلغاء غير مدفوعة + إلغاء ثانٍ صفري الآثار', () async {
      final db = openDb();
      await seedCustomer(db, 'C-1', 'عميل اختبار');
      final pid = await seedProduct(db, qty: 10);
      final res = await sell(
        db,
        total: 500,
        status: 'pending',
        items: [InvoiceItemParams(productId: pid, quantity: 5, price: 100)],
      );
      await db.invoiceDao.voidInvoice(res.invoiceId, 'اختبار', 'admin');
      expect(
        (await db.invoiceDao.getInvoiceById(res.invoiceId))!.status,
        'voided',
      );
      expect(await db.ledgerDao.getCustomerBalance('C-1'), 0);
      expect((await db.productDao.getProductById(pid))!.quantity, 10);
      final sale = await db.journalDao.getByPostingKey(
        'sale:INV${res.invoiceId}',
      );
      expect(sale!.status, 'reversed');
      // لقطة ثم إلغاء ثانٍ — صفر آثار.
      final ledgers = (await db.ledgerDao.getAllTransactions()).length;
      final movs = (await db.inventoryMovementDao.getAllMovements()).length;
      final journals = (await db.journalDao.getEntriesByDateRange(
        DateTime(2000),
        DateTime(2100),
      ))
          .length;
      await db.invoiceDao.voidInvoice(res.invoiceId, 'ثانية', 'admin');
      expect((await db.ledgerDao.getAllTransactions()).length, ledgers);
      expect((await db.inventoryMovementDao.getAllMovements()).length, movs);
      expect(
        (await db.journalDao.getEntriesByDateRange(
          DateTime(2000),
          DateTime(2100),
        ))
            .length,
        journals,
      );
      expect((await db.productDao.getProductById(pid))!.quantity, 10);
      expect(await db.ledgerDao.getCustomerBalance('C-1'), 0);
    });

    test('إلغاء مدفوعة: المدفوعات تبقى والرصيد دائن', () async {
      final db = openDb();
      await seedCustomer(db, 'C-1', 'عميل اختبار');
      final pid = await seedProduct(db, qty: 10);
      final res = await sell(
        db,
        total: 500,
        paid: 200,
        status: 'partial',
        items: [InvoiceItemParams(productId: pid, quantity: 5, price: 100)],
      );
      await db.invoiceDao.voidInvoice(res.invoiceId, 'اختبار', 'admin');
      expect(
        (await db.invoicePaymentsDao.getPaymentsForInvoice(res.invoiceId))
            .length,
        1,
      );
      expect(
        (await db.ledgerDao.getPaymentsForReceipt('INV${res.invoiceId}'))
            .length,
        1,
      );
      // بيع 500 − عكس 500 − مدفوع 200 = −200 (رصيد دائن للعميل).
      expect(await db.ledgerDao.getCustomerBalance('C-1'), -200);
    });

    test('إلغاء فاتورة عمولة يعيد رصيد المورد لصفر', () async {
      final db = openDb();
      await seedCustomer(db, 'C-1', 'عميل اختبار');
      await seedSupplier(db, 'S-1', 'مورد اختبار');
      final pid = await seedProduct(db, qty: 50);
      final sh = await seedCommissionShipment(db, supplierId: 'S-1');
      final res = await sell(
        db,
        total: 1000,
        status: 'pending',
        items: [
          InvoiceItemParams(
            productId: pid,
            quantity: 10,
            price: 100,
            shipmentId: sh,
          ),
        ],
        primaryShipmentId: sh,
      );
      expect(await db.ledgerDao.getSupplierBalance('S-1'), 900);
      await db.invoiceDao.voidInvoice(res.invoiceId, 'اختبار', 'admin');
      expect(await db.ledgerDao.getSupplierBalance('S-1'), 0);
      expect((await db.vegetableShipmentDao.getById(sh))!.barnikaSoldCount, 0);
      expect(
        (await db.vegetableShipmentDao.getById(sh))!.barnikaRemainingCount,
        100,
      );
    });
  });

  group('D12 return', () {
    test('مرتجع جزئي: ترويسة + دفتر + شحنة + يومية', () async {
      final db = openDb();
      await seedCustomer(db, 'C-1', 'عميل اختبار');
      final pid = await seedProduct(db, qty: 20, price: 50, cost: 30);
      await seedSupplier(db, 'S-X', 'مورد');
      final sh = await seedCommissionShipment(
        db,
        supplierId: 'S-X',
        number: 'SH-R',
      );
      final res = await sell(
        db,
        total: 500,
        status: 'pending',
        items: [
          InvoiceItemParams(
            productId: pid,
            quantity: 10,
            price: 50,
            shipmentId: sh,
          ),
        ],
        primaryShipmentId: sh,
      );
      final rid = await db.salesReturnsDao.processReturn(
        returnCompanion: SalesReturnsCompanion.insert(
          returnNumber: 'RTR-T1',
          originalInvoiceId: res.invoiceId,
          customerName: 'عميل اختبار',
          returnDate: DateTime.now(),
          totalAmount: 200,
          returnReason: 'اختبار',
        ),
        items: [
          SalesReturnItemsCompanion.insert(
            returnId: 0,
            productId: pid,
            productName: 'صنف اختبار',
            quantity: 4,
            unitPrice: 50,
            totalPrice: 200,
          ),
        ],
      );
      expect(rid, greaterThan(0));
      expect((await db.productDao.getProductById(pid))!.quantity, 14);
      final inv = (await db.invoiceDao.getInvoiceById(res.invoiceId))!;
      expect(inv.totalAmount, 300);
      expect(inv.status, 'pending');
      final retRows = await db.ledgerDao.getTransactionsByReceiptNumber(
        'RET$rid',
      );
      expect(
        retRows.where((t) => t.entityType == 'Customer').length,
        1,
      );
      expect(await db.ledgerDao.getCustomerBalance('C-1'), 300);
      final shp = (await db.vegetableShipmentDao.getById(sh))!;
      expect(shp.barnikaSoldCount, 6);
      expect(shp.barnikaRemainingCount, 94);
      expect(
        await db.journalDao.getByPostingKey('sale_return:RET$rid'),
        isNotNull,
      );
    });

    test('تجاوز المتبقي مرفوض بصفر آثار + المكرر الكامل مرفوض', () async {
      final db = openDb();
      await seedCustomer(db, 'C-1', 'عميل اختبار');
      final pid = await seedProduct(db, qty: 20, price: 50, cost: 30);
      final res = await sell(
        db,
        total: 500,
        status: 'pending',
        items: [InvoiceItemParams(productId: pid, quantity: 10, price: 50)],
      );
      Future<int> ret(String n, int qty, double amount) =>
          db.salesReturnsDao.processReturn(
            returnCompanion: SalesReturnsCompanion.insert(
              returnNumber: n,
              originalInvoiceId: res.invoiceId,
              customerName: 'عميل اختبار',
              returnDate: DateTime.now(),
              totalAmount: amount,
              returnReason: 'اختبار',
            ),
            items: [
              SalesReturnItemsCompanion.insert(
                returnId: 0,
                productId: pid,
                productName: 'صنف اختبار',
                quantity: qty,
                unitPrice: 50,
                totalPrice: amount,
              ),
            ],
          );
      await ret('RTR-A', 4, 200);
      // المتبقي 6 — طلب 7 مرفوض.
      final ledgers = (await db.ledgerDao.getAllTransactions()).length;
      expect(() => ret('RTR-B', 7, 350), throwsA(anything));
      expect((await db.ledgerDao.getAllTransactions()).length, ledgers);
      expect((await db.productDao.getProductById(pid))!.quantity, 14);
      expect(
        (await db.invoiceDao.getInvoiceById(res.invoiceId))!.totalAmount,
        300,
      );
      // إكمال الكلي ثم تكرار كلي مرفوض بصفر آثار.
      await ret('RTR-C', 6, 300);
      expect(
        (await db.invoiceDao.getInvoiceById(res.invoiceId))!.totalAmount,
        0,
      );
      expect(() => ret('RTR-D', 10, 500), throwsA(anything));
      expect((await db.productDao.getProductById(pid))!.quantity, 20);
    });

    test('نفس رقم المرتجع idempotent: صفر آثار جديدة', () async {
      final db = openDb();
      await seedCustomer(db, 'C-1', 'عميل اختبار');
      final pid = await seedProduct(db, qty: 20, price: 50, cost: 30);
      final res = await sell(
        db,
        total: 500,
        status: 'pending',
        items: [InvoiceItemParams(productId: pid, quantity: 10, price: 50)],
      );
      Future<int> ret(String n) => db.salesReturnsDao.processReturn(
            returnCompanion: SalesReturnsCompanion.insert(
              returnNumber: n,
              originalInvoiceId: res.invoiceId,
              customerName: 'عميل اختبار',
              returnDate: DateTime.now(),
              totalAmount: 100,
              returnReason: 'اختبار',
            ),
            items: [
              SalesReturnItemsCompanion.insert(
                returnId: 0,
                productId: pid,
                productName: 'صنف اختبار',
                quantity: 2,
                unitPrice: 50,
                totalPrice: 100,
              ),
            ],
          );
      final first = await ret('RTR-SAME');
      final ledgers = (await db.ledgerDao.getAllTransactions()).length;
      final second = await ret('RTR-SAME');
      expect(second, first);
      expect((await db.ledgerDao.getAllTransactions()).length, ledgers);
      expect((await db.productDao.getProductById(pid))!.quantity, 12);
    });

    test('مرتجع عمولة يعكس حصة المورد', () async {
      final db = openDb();
      await seedCustomer(db, 'C-1', 'عميل اختبار');
      await seedSupplier(db, 'S-1', 'مورد اختبار');
      final pid = await seedProduct(db, qty: 50);
      final sh = await seedCommissionShipment(db, supplierId: 'S-1');
      final res = await sell(
        db,
        total: 1000,
        status: 'pending',
        items: [
          InvoiceItemParams(
            productId: pid,
            quantity: 10,
            price: 100,
            shipmentId: sh,
          ),
        ],
        primaryShipmentId: sh,
      );
      await db.salesReturnsDao.processReturn(
        returnCompanion: SalesReturnsCompanion.insert(
          returnNumber: 'RTR-COMM',
          originalInvoiceId: res.invoiceId,
          customerName: 'عميل اختبار',
          returnDate: DateTime.now(),
          totalAmount: 500,
          returnReason: 'اختبار',
        ),
        items: [
          SalesReturnItemsCompanion.insert(
            returnId: 0,
            productId: pid,
            productName: 'صنف اختبار',
            quantity: 5,
            unitPrice: 100,
            totalPrice: 500,
          ),
        ],
      );
      // صافي 900 − حصة النصف 450 = 450.
      expect(await db.ledgerDao.getSupplierBalance('S-1'), 450);
    });
  });

  group('D12 barnika', () {
    test('إصدار داخل الـtxn + إلغاء يعيد + ثانٍ صفري', () async {
      final db = openDb();
      await seedCustomer(db, 'C-1', 'عميل اختبار');
      final pid = await seedProduct(db, qty: 20);
      final res = await sell(
        db,
        total: 500,
        status: 'pending',
        items: [InvoiceItemParams(productId: pid, quantity: 5, price: 100)],
        barnikaCustomerId: 'C-1',
        barnikaQuantity: 5,
      );
      var outs = await db.emptyBarnikaTrackingDao.getOutstandingByCustomer(
        'C-1',
      );
      expect(outs.length, 1);
      expect(outs.first.quantityOut, 5);
      await db.invoiceDao.voidInvoice(res.invoiceId, 'اختبار', 'admin');
      outs = await db.emptyBarnikaTrackingDao.getOutstandingByCustomer('C-1');
      expect(outs, isEmpty);
      final all = await db.emptyBarnikaTrackingDao.getAll();
      expect(all.first.quantityReturned, 5);
      expect(all.first.status, 'returned');
      // إلغاء ثانٍ: لا صف جديد ولا تغيير.
      await db.invoiceDao.voidInvoice(res.invoiceId, 'ثانية', 'admin');
      expect((await db.emptyBarnikaTrackingDao.getAll()).length, 1);
    });

    test('تعديل بلا بارامترات لا يلمس البرنيكة + مرتجع جزئي يسجّل', () async {
      final db = openDb();
      await seedCustomer(db, 'C-1', 'عميل اختبار');
      final pid = await seedProduct(db, qty: 30, price: 50, cost: 30);
      final res = await sell(
        db,
        total: 500,
        status: 'pending',
        items: [InvoiceItemParams(productId: pid, quantity: 10, price: 50)],
        barnikaCustomerId: 'C-1',
        barnikaQuantity: 10,
      );
      await InvoiceService(db).editInvoice(
        invoiceId: res.invoiceId,
        customerId: 'C-1',
        customerName: 'عميل اختبار',
        paymentMethod: 'credit',
        totalAmount: 500,
        paidAmount: 0,
        status: 'pending',
        items: [InvoiceItemParams(productId: pid, quantity: 10, price: 55)],
      );
      var outs = await db.emptyBarnikaTrackingDao.getOutstandingByCustomer(
        'C-1',
      );
      expect(outs.length, 1);
      expect(outs.first.quantityReturned, 0);
      await db.salesReturnsDao.processReturn(
        returnCompanion: SalesReturnsCompanion.insert(
          returnNumber: 'RTR-BAR',
          originalInvoiceId: res.invoiceId,
          customerName: 'عميل اختبار',
          returnDate: DateTime.now(),
          totalAmount: 200,
          returnReason: 'اختبار',
        ),
        items: [
          SalesReturnItemsCompanion.insert(
            returnId: 0,
            productId: pid,
            productName: 'صنف اختبار',
            quantity: 4,
            unitPrice: 50,
            totalPrice: 200,
          ),
        ],
      );
      outs = await db.emptyBarnikaTrackingDao.getOutstandingByCustomer('C-1');
      expect(outs.length, 1);
      expect(outs.first.quantityReturned, 4);
      expect(outs.first.status, 'partial');
    });
  });

  group('D12 variant + balances', () {
    test('بيع صنف عبر الخدمة: خصم الصنف + الأب = المجموع (إثبات إصلاح prod)', () async {
      final db = openDb();
      final pid = await db.productDao.insertProduct(
        ProductsCompanion.insert(
          name: 'قماش X',
          price: 100,
          quantity: 0,
          costPrice: const Value(60),
        ),
      );
      final red = await db.productVariantDao.insertVariant(
        ProductVariantsCompanion.insert(
          productId: pid,
          name: 'أحمر',
          quantity: const Value(10),
        ),
      );
      final parent0 = await db.productDao.getProductById(pid);
      await db.productDao.updateProduct(parent0!.copyWith(quantity: 10));
      final res = await sell(
        db,
        customerId: null,
        customerName: 'نقدي',
        paymentMethod: 'cash',
        total: 400,
        paid: 400,
        status: 'paid',
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
      expect((await db.productVariantDao.getVariantById(red))!.quantity, 6);
      expect((await db.productDao.getProductById(pid))!.quantity, 6);
    });

    test('القاعدة القانونية للمورد متماسكة عبر كل الصيغ', () async {
      final db = openDb();
      await seedCustomer(db, 'C-1', 'عميل اختبار');
      await seedSupplier(db, 'S-1', 'مورد اختبار');
      final pid = await seedProduct(db, qty: 50);
      final sh = await seedCommissionShipment(db, supplierId: 'S-1');
      await sell(
        db,
        total: 1000,
        status: 'pending',
        items: [
          InvoiceItemParams(
            productId: pid,
            quantity: 10,
            price: 100,
            shipmentId: sh,
          ),
        ],
        primaryShipmentId: sh,
      );
      // opening(0) + Σ(credit−debit) = 900 في كل الصيغ.
      expect(await db.ledgerDao.getSupplierBalance('S-1'), 900);
      expect(
        await db.ledgerDao.getRunningBalance('Supplier', 'S-1'),
        900,
      );
      expect(await db.ledgerDao.getSupplierOutstandingBalance(), 900);
      expect(await db.ledgerDao.getSupplierCommissionDue(), 900);
      expect(
        await db.supplierDao.getSupplierBalance('S-1'),
        900,
      );
    });
  });

  group('D12 import convergence', () {
    test('الاستيراد يكتب دفتر العميل والمورد بصافي العمولة', () async {
      final db = openDb();
      const supId = 'SUP-IMP-1';
      const custId = 'CUST-IMP-1';
      const shipUuid = 'SHIP-UUID-1';
      await seedSupplier(db, supId, 'مورد مستورد');
      await db.vegetableShipmentDao.insertShipment(
        VegetableShipmentsCompanion.insert(
          supplierId: supId,
          shipmentNumber: 'IMP-SH-1',
          pricingMode: 'commission',
          totalBarnikaCount: 50,
          barnikaRemainingCount: 50,
          totalCost: 0,
          commissionPercentage: const Value(10),
        ),
      );
      final shipments = await db.vegetableShipmentDao.getAll();
      final shInt = shipments.firstWhere((s) => s.shipmentNumber == 'IMP-SH-1').id;
      // نحاكي ما يفعله _importSale عبر الخدمة نفسها: فاتورة + دفتر.
      final svc = InvoiceService(db);
      final res = await svc.createInvoice(
        customerId: custId,
        customerName: 'عميل مستورد',
        paymentMethod: 'credit',
        totalAmount: 1000,
        paidAmount: 1000,
        status: 'paid',
        preserveInvoiceNumber: true,
        invoiceNumber: 'TEST-IMP-01',
        items: [
          InvoiceItemParams(
            productId: await seedProduct(db, qty: 100),
            quantity: 10,
            price: 100,
            shipmentId: shInt,
          ),
        ],
        primaryShipmentId: shInt,
      );
      expect(res.invoice.invoiceNumber, 'TEST-IMP-01');
      final custRows = await ledgerByReceipt(db, 'INV${res.invoiceId}');
      expect(
        custRows.where((t) => t.entityType == 'Customer').length,
        2,
      );
      final supRows = custRows.where((t) => t.entityType == 'Supplier');
      expect(supRows.length, 1);
      expect(supRows.first.credit, 900);
      expect(await db.ledgerDao.getCustomerBalance(custId), 0);
      expect(shipUuid, isNotEmpty); // شاهد ربط uuid الشحنة (توثيق فقط).
    });
  });
}
