import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/tables/customer_containers_table.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (MethodCall methodCall) async => '.',
      );

  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('barneka: sales-by-customer + container upsert', () async {
    final pid = await db.productDao.insertProduct(
      ProductsCompanion.insert(
        name: 'طماطم',
        price: 10,
        quantity: 100,
        barneka: const Value(true),
      ),
    );

    final cid = 'cust1';
    await db.customerDao.insertCustomer(
      CustomersCompanion.insert(
        id: cid,
        name: 'أحمد',
        isActive: const Value(true),
      ),
    );

    final iid = await db.invoiceDao.insertInvoice(
      InvoicesCompanion.insert(
        customerId: Value(cid),
        customerName: const Value('أحمد'),
        totalAmount: const Value(70),
        paidAmount: const Value(70),
        date: Value(DateTime.now()),
        status: const Value('completed'),
      ),
    );

    await db.invoiceDao.insertInvoiceItem(
      InvoiceItemsCompanion.insert(
        invoiceId: iid,
        productId: pid,
        quantity: const Value(7),
        price: 10,
      ),
    );

    final sales = await db.invoiceDao.getProductSalesByCustomer(
      pid,
      DateTime(2000),
      DateTime.now().add(const Duration(days: 1)),
    );

    print('SALES = $sales');
    expect(sales.length, 1, reason: 'should find one customer with sales');
    expect(sales.first.customerId, cid);
    expect(sales.first.totalQty, 7, reason: 'should sum 7 units');

    await db.customerContainerDao.upsert(
      CustomerContainersCompanion(
        productId: Value(pid),
        customerId: Value(cid),
        quantityOut: const Value(7),
        quantityReturned: const Value(2),
        updatedAt: Value(DateTime.now()),
      ),
    );

    final rec = await db.customerContainerDao.getByProductAndCustomer(pid, cid);
    expect(rec != null, isTrue);
    expect(rec!.quantityOut, 7);
    expect(rec.quantityReturned, 2);

    final product = await db.productDao.getProductById(pid);
    expect(product?.barneka, isTrue);
  });

  test('barneka: walk-in sale (null customerId) is excluded', () async {
    final pid = await db.productDao.insertProduct(
      ProductsCompanion.insert(
        name: 'خيار',
        price: 5,
        quantity: 50,
        barneka: const Value(true),
      ),
    );

    final iid = await db.invoiceDao.insertInvoice(
      InvoicesCompanion.insert(
        customerName: const Value('نقدي'),
        totalAmount: const Value(5),
        paidAmount: const Value(5),
        date: Value(DateTime.now()),
        status: const Value('completed'),
      ),
    );

    await db.invoiceDao.insertInvoiceItem(
      InvoiceItemsCompanion.insert(
        invoiceId: iid,
        productId: pid,
        quantity: const Value(3),
        price: 5,
      ),
    );

    final sales = await db.invoiceDao.getProductSalesByCustomer(
      pid,
      DateTime(2000),
      DateTime.now().add(const Duration(days: 1)),
    );

    print('WALKIN SALES = $sales');
    expect(sales.length, 1,
        reason: 'walk-in (null customer) sales are now grouped under the نقدي bucket');
    expect(sales.first.customerId, kWalkInCustomerId);
    expect(sales.first.totalQty, 3);
  });
}
