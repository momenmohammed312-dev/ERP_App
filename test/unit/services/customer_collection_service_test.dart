import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/tables/empty_barnika_tracking_table.dart';
import 'package:pos_offline_desktop/core/database/tables/vegetable_shipments_table.dart';
import 'package:pos_offline_desktop/core/services/customer_collection_service.dart';
import 'package:pos_offline_desktop/core/services/invoice_service.dart';
import 'package:pos_offline_desktop/core/services/invoice_void_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (MethodCall methodCall) async => '.',
      );

  late AppDatabase db;
  late CustomerCollectionService collectionService;
  late InvoiceService invoiceService;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    collectionService = CustomerCollectionService(db);
    invoiceService = InvoiceService(db);

    await db.dayDao.openDay(openingBalance: 0, openedBy: 'tester');
    await db.into(db.suppliers).insert(
          SuppliersCompanion.insert(id: 'SUP-1', name: 'مورد ١'),
        );
    await db.customerDao.insertCustomer(
      CustomersCompanion.insert(id: 'CUST-1', name: 'محل النصر'),
    );
    await db.into(db.products).insert(
          ProductsCompanion.insert(
            id: const Value(1),
            name: 'بطاطس',
            price: 0,
            quantity: 1000,
          ),
        );
  });

  tearDown(() => db.close());

  group('CustomerCollectionService FIFO + Discount', () {
    test('distributes cash payment FIFO across oldest unpaid invoices', () async {
      final inv1 = await invoiceService.createInvoice(
        customerId: 'CUST-1',
        customerName: 'محل النصر',
        paymentMethod: 'credit',
        totalAmount: 500,
        paidAmount: 0,
        creditAmount: 500,
        status: 'pending',
        invoiceDate: DateTime(2026, 2, 1),
        items: [InvoiceItemParams(productId: 1, quantity: 5, price: 100)],
      );
      final inv2 = await invoiceService.createInvoice(
        customerId: 'CUST-1',
        customerName: 'محل النصر',
        paymentMethod: 'credit',
        totalAmount: 400,
        paidAmount: 0,
        creditAmount: 400,
        status: 'pending',
        invoiceDate: DateTime(2026, 2, 2),
        items: [InvoiceItemParams(productId: 1, quantity: 4, price: 100)],
      );

      expect(await db.ledgerDao.getCustomerBalance('CUST-1'), closeTo(900, 0.01));

      final res = await collectionService.collectPayment(
        customerId: 'CUST-1',
        paidAmount: 650,
        date: DateTime(2026, 2, 5),
      );

      expect(res.allocations.length, 2);
      expect(res.allocations[0].invoiceId, inv1.invoiceId);
      expect(res.allocations[0].appliedPaid, closeTo(500, 0.01));
      expect(res.allocations[0].newStatus, 'paid');

      expect(res.allocations[1].invoiceId, inv2.invoiceId);
      expect(res.allocations[1].appliedPaid, closeTo(150, 0.01));
      expect(res.allocations[1].newStatus, 'partial');
      expect(res.allocations[1].remainingOnInvoice, closeTo(250, 0.01));

      expect(res.newCustomerBalance, closeTo(250, 0.01));
      expect(await db.ledgerDao.getCustomerBalance('CUST-1'), closeTo(250, 0.01));
    });

    test('applies settlement discount to invoices and customer ledger without counting discount as cash', () async {
      final inv1 = await invoiceService.createInvoice(
        customerId: 'CUST-1',
        customerName: 'محل النصر',
        paymentMethod: 'credit',
        totalAmount: 500,
        paidAmount: 0,
        creditAmount: 500,
        status: 'pending',
        invoiceDate: DateTime(2026, 2, 1),
        items: [InvoiceItemParams(productId: 1, quantity: 5, price: 100)],
      );

      final collectDate = DateTime(2026, 2, 5, 14, 0);
      final res = await collectionService.collectPayment(
        customerId: 'CUST-1',
        paidAmount: 470,
        discountAmount: 30,
        date: collectDate,
      );

      expect(res.totalCredited, closeTo(500, 0.01));
      expect(res.newCustomerBalance, closeTo(0, 0.01));
      expect(res.allocations.single.newStatus, 'paid');
      expect(res.allocations.single.appliedPaid, closeTo(470, 0.01));
      expect(res.allocations.single.appliedDiscount, closeTo(30, 0.01));

      final updatedInv = await db.invoiceDao.getInvoiceById(inv1.invoiceId);
      expect(updatedInv!.status, 'paid');
      expect(updatedInv.paidAmount, closeTo(500, 0.01));
      expect(updatedInv.creditAmount, closeTo(0, 0.01));

      // Cash collections sum ONLY real cash (470), NOT the 30 discount.
      final cashTotal = await db.invoicePaymentsDao.getTotalByMethodAndDateRange(
        'cash',
        DateTime(2026, 2, 5),
        DateTime(2026, 2, 5, 23, 59, 59),
      );
      expect(cashTotal, closeTo(470, 0.01));
    });

    test('reduces opening balance even when no unpaid invoices exist', () async {
      await db.customerDao.insertCustomer(
        CustomersCompanion.insert(
          id: 'CUST-OPEN',
          name: 'عميل رصيد افتتاحي',
          openingBalance: const Value(800.0),
        ),
      );

      final res = await collectionService.collectPayment(
        customerId: 'CUST-OPEN',
        paidAmount: 300,
        discountAmount: 50,
      );

      expect(res.allocations, isEmpty);
      expect(res.unallocatedCredit, closeTo(350, 0.01));
      expect(res.newCustomerBalance, closeTo(450, 0.01));
    });
  });

  group('InvoiceService + EmptyBarnikaTracking atomic integration', () {
    test(
      'creates atomic barnika custody + immediate return, prevents overselling, and voids cleanly',
      () async {
        final shipmentId = await db.vegetableShipmentDao.insertShipment(
          VegetableShipmentsCompanion.insert(
            supplierId: 'SUP-1',
            shipmentNumber: 'SHP-INV-1',
            pricingMode: ShipmentPricingMode.commission,
            totalBarnikaCount: 15,
            commissionPercentage: const Value(10.0),
            totalCost: 0,
            barnikaRemainingCount: 15,
          ),
        );

        // Sale 1: 10 crates out, 4 immediately returned -> 6 outstanding custody
        final res1 = await invoiceService.createInvoice(
          customerId: 'CUST-1',
          customerName: 'محل النصر',
          paymentMethod: 'credit',
          totalAmount: 1000,
          paidAmount: 0,
          creditAmount: 1000,
          status: 'pending',
          primaryShipmentId: shipmentId,
          emptyBarnikaReturnedCount: 4,
          items: [
            InvoiceItemParams(
              productId: 1,
              quantity: 10,
              price: 100,
              shipmentId: shipmentId,
            ),
          ],
        );

        expect(
          await db.emptyBarnikaTrackingDao.getCustomerOutstandingBalance('CUST-1'),
          6,
        );
        final rows1 =
            await db.emptyBarnikaTrackingDao.getByInvoiceId(res1.invoiceId);
        expect(rows1.single.quantityOut, 10);
        expect(rows1.single.quantityReturned, 4);
        expect(rows1.single.status, EmptyBarnikaStatus.partial);

        // No premature supplier debit row from invoice creation
        expect(await db.ledgerDao.getSupplierBalance('SUP-1'), 0.0);

        // Oversell 6 when only 5 remaining -> rolls back invoice + stock + barnika custody
        await expectLater(
          invoiceService.createInvoice(
            customerId: 'CUST-1',
            customerName: 'محل النصر',
            paymentMethod: 'cash',
            totalAmount: 600,
            paidAmount: 600,
            status: 'paid',
            items: [
              InvoiceItemParams(
                productId: 1,
                quantity: 6,
                price: 100,
                shipmentId: shipmentId,
              ),
            ],
          ),
          throwsA(isA<Exception>()),
        );

        // Remaining shipment crates and customer barnika balance unchanged after rollback
        final shipAfterFailed = await db.vegetableShipmentDao.getById(shipmentId);
        expect(shipAfterFailed!.barnikaRemainingCount, 5);
        expect(
          await db.emptyBarnikaTrackingDao.getCustomerOutstandingBalance('CUST-1'),
          6,
        );

        // Voiding res1 reverses shipment counts and removes invoice-linked barnika custody
        await InvoiceVoidService(db).voidInvoice(
          invoiceId: res1.invoiceId,
          reason: VoidReasons.inputError,
          voidedBy: 'tester',
        );

        final shipAfterVoid = await db.vegetableShipmentDao.getById(shipmentId);
        expect(shipAfterVoid!.barnikaSoldCount, 0);
        expect(shipAfterVoid.barnikaRemainingCount, 15);
        expect(
          await db.emptyBarnikaTrackingDao.getCustomerOutstandingBalance('CUST-1'),
          0,
        );
      },
    );

    test('sale returning more barnikas than current order settles older custody FIFO', () async {
      final shipmentId = await db.vegetableShipmentDao.insertShipment(
        VegetableShipmentsCompanion.insert(
          supplierId: 'SUP-1',
          shipmentNumber: 'SHP-FIFO-RET',
          pricingMode: ShipmentPricingMode.commission,
          totalBarnikaCount: 20,
          commissionPercentage: const Value(10.0),
          totalCost: 0,
          barnikaRemainingCount: 20,
        ),
      );

      // Day 1: 5 crates out, 0 returned
      await invoiceService.createInvoice(
        customerId: 'CUST-1',
        customerName: 'محل النصر',
        paymentMethod: 'cash',
        totalAmount: 500,
        paidAmount: 500,
        status: 'paid',
        invoiceDate: DateTime(2026, 2, 1),
        items: [
          InvoiceItemParams(
            productId: 1,
            quantity: 5,
            price: 100,
            shipmentId: shipmentId,
          ),
        ],
      );

      // Day 2: 3 crates out, 6 returned (3 from today + 3 from Day 1) -> net 2 left
      await invoiceService.createInvoice(
        customerId: 'CUST-1',
        customerName: 'محل النصر',
        paymentMethod: 'cash',
        totalAmount: 300,
        paidAmount: 300,
        status: 'paid',
        invoiceDate: DateTime(2026, 2, 2),
        emptyBarnikaReturnedCount: 6,
        items: [
          InvoiceItemParams(
            productId: 1,
            quantity: 3,
            price: 100,
            shipmentId: shipmentId,
          ),
        ],
      );

      expect(
        await db.emptyBarnikaTrackingDao.getCustomerOutstandingBalance('CUST-1'),
        2,
      );
    });
  });
}
