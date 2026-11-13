import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/tables/expenses_table.dart';
import 'package:pos_offline_desktop/core/database/tables/supplier_table.dart';
import 'package:pos_offline_desktop/core/database/tables/vegetable_shipments_table.dart';
import 'package:pos_offline_desktop/core/services/invoice_service.dart';
import 'package:pos_offline_desktop/core/services/invoice_void_service.dart';
import 'package:pos_offline_desktop/core/services/shipment_allocation_service.dart';
import 'package:pos_offline_desktop/core/services/shipment_settlement_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (MethodCall methodCall) async => '.',
      );

  late AppDatabase db;
  late ShipmentSettlementService settlementService;
  late ShipmentAllocationService allocationService;
  late InvoiceService invoiceService;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    settlementService = ShipmentSettlementService(db);
    allocationService = ShipmentAllocationService(
      db.vegetableShipmentDao,
      db.emptyBarnikaTrackingDao,
    );
    invoiceService = InvoiceService(db);

    await db.dayDao.openDay(openingBalance: 0, openedBy: 'tester');
    await db.into(db.suppliers).insert(
          SuppliersCompanion.insert(id: 'SUP-A', name: 'المزارع أحمد'),
        );
    await db.customerDao.insertCustomer(
      CustomersCompanion.insert(id: 'CUST-1', name: 'عميل جملة'),
    );
    await db.into(db.products).insert(
          ProductsCompanion.insert(
            id: const Value(1),
            name: 'طماطم',
            price: 0,
            quantity: 1000,
          ),
        );
  });

  tearDown(() => db.close());

  Future<int> createCommissionShipment({
    String supplierId = 'SUP-A',
    String number = 'SHP-100',
    int total = 50,
    double commissionPct = 10.0,
  }) {
    return db.vegetableShipmentDao.insertShipment(
      VegetableShipmentsCompanion.insert(
        supplierId: supplierId,
        shipmentNumber: number,
        pricingMode: ShipmentPricingMode.commission,
        totalBarnikaCount: total,
        commissionPercentage: Value(commissionPct),
        totalCost: 0,
        barnikaRemainingCount: total,
      ),
    );
  }

  group('ShipmentSettlementService', () {
    test(
      'computes totalSales (cash+credit) - commission% - shipmentExpenses, ignoring shop expenses and topping crates',
      () async {
        final shipmentId = await createCommissionShipment(
          number: 'SHP-COMM-1',
          total: 50,
          commissionPct: 10.0,
        );

        // 20 crates sold cash @ 100 = 2000
        await invoiceService.createInvoice(
          customerId: 'CUST-1',
          customerName: 'عميل جملة',
          paymentMethod: 'cash',
          totalAmount: 2000,
          paidAmount: 2000,
          cashAmount: 2000,
          status: 'paid',
          primaryShipmentId: shipmentId,
          items: [
            InvoiceItemParams(
              productId: 1,
              quantity: 20,
              price: 100,
              shipmentId: shipmentId,
            ),
          ],
        );

        // 25 crates sold credit @ 120 = 3000
        await invoiceService.createInvoice(
          customerId: 'CUST-1',
          customerName: 'عميل جملة',
          paymentMethod: 'credit',
          totalAmount: 3000,
          paidAmount: 0,
          creditAmount: 3000,
          status: 'pending',
          primaryShipmentId: shipmentId,
          items: [
            InvoiceItemParams(
              productId: 1,
              quantity: 25,
              price: 120,
              shipmentId: shipmentId,
            ),
          ],
        );

        // 5 crates used for topping-up (with supplier knowledge) -> supplier NOT charged/paid for these
        await allocationService.recordTopping(
          shipmentId: shipmentId,
          additionalToppingCount: 5,
          reason: 'تكميل وزن',
        );

        // Shipment expense (نولون) -> deducted from supplier settlement
        await db.expenseDao.insertExpense(
          ExpensesCompanion.insert(
            id: 'exp-ship-1',
            description: 'نولون عربية',
            amount: 400,
            category: 'نولون',
            shipmentId: Value(shipmentId),
            scope: const Value(ExpenseScope.shipment),
          ),
        );

        // Shop expense -> must NOT be deducted from supplier settlement
        await db.expenseDao.insertExpense(
          ExpensesCompanion.insert(
            id: 'exp-shop-1',
            description: 'شاي وأكل',
            amount: 150,
            category: 'ضيافة',
            scope: const Value(ExpenseScope.shop),
          ),
        );

        final stmt = await settlementService.getShipmentStatement(shipmentId);

        expect(stmt.soldCount, 45);
        expect(stmt.toppingCount, 5);
        expect(stmt.remainingCount, 0);
        expect(stmt.cashSales, closeTo(2000, 0.01));
        expect(stmt.creditSales, closeTo(3000, 0.01));
        expect(stmt.totalSales, closeTo(5000, 0.01));
        expect(stmt.commissionAmount, closeTo(500, 0.01));
        expect(stmt.shipmentExpenses, closeTo(400, 0.01));
        // 5000 - 500 - 400 = 4100
        expect(stmt.netSupplierDue, closeTo(4100, 0.01));
        expect(stmt.isClosed, isFalse);

        // Before closing, no supplier ledger credit has been posted yet
        expect(await db.ledgerDao.getSupplierBalance('SUP-A'), 0.0);
      },
    );

    test('excludes voided invoices from shipment statement', () async {
      final shipmentId = await createCommissionShipment(
        number: 'SHP-VOID-1',
        total: 30,
        commissionPct: 10.0,
      );

      final res1 = await invoiceService.createInvoice(
        customerId: 'CUST-1',
        customerName: 'عميل جملة',
        paymentMethod: 'cash',
        totalAmount: 1000,
        paidAmount: 1000,
        cashAmount: 1000,
        status: 'paid',
        items: [
          InvoiceItemParams(
            productId: 1,
            quantity: 10,
            price: 100,
            shipmentId: shipmentId,
          ),
        ],
      );
      await invoiceService.createInvoice(
        customerId: 'CUST-1',
        customerName: 'عميل جملة',
        paymentMethod: 'cash',
        totalAmount: 500,
        paidAmount: 500,
        cashAmount: 500,
        status: 'paid',
        items: [
          InvoiceItemParams(
            productId: 1,
            quantity: 5,
            price: 100,
            shipmentId: shipmentId,
          ),
        ],
      );

      await InvoiceVoidService(db).voidInvoice(
        invoiceId: res1.invoiceId,
        reason: VoidReasons.inputError,
        voidedBy: 'tester',
      );

      final stmt = await settlementService.getShipmentStatement(shipmentId);
      expect(stmt.soldCount, 5);
      expect(stmt.totalSales, closeTo(500, 0.01));
      expect(stmt.commissionAmount, closeTo(50, 0.01));
      expect(stmt.netSupplierDue, closeTo(450, 0.01));
    });

    test(
      'supports default unknown supplier, reassigning before close, atomic close ledger posting, and supplier payment',
      () async {
        // Arrive without specifying supplier -> defaults to 'unknown_supplier'
        final shipmentId = await db.vegetableShipmentDao.insertShipment(
          VegetableShipmentsCompanion.insert(
            supplierId: '',
            shipmentNumber: 'SHP-UNK-1',
            pricingMode: ShipmentPricingMode.commission,
            totalBarnikaCount: 20,
            commissionPercentage: const Value(8.0),
            totalCost: 0,
            barnikaRemainingCount: 20,
          ),
        );

        final created = await db.vegetableShipmentDao.getById(shipmentId);
        expect(created!.supplierId, DefaultSupplier.unknownId);
        final unknownSupp =
            await db.supplierDao.getSupplierById(DefaultSupplier.unknownId);
        expect(unknownSupp!.name, DefaultSupplier.unknownName);

        await invoiceService.createInvoice(
          customerId: 'CUST-1',
          customerName: 'عميل جملة',
          paymentMethod: 'credit',
          totalAmount: 1000,
          paidAmount: 0,
          creditAmount: 1000,
          status: 'pending',
          items: [
            InvoiceItemParams(
              productId: 1,
              quantity: 10,
              price: 100,
              shipmentId: shipmentId,
            ),
          ],
        );

        // Reassign supplier before closing
        final reassigned = await settlementService.reassignSupplier(
          shipmentId: shipmentId,
          newSupplierId: 'SUP-A',
        );
        expect(reassigned.supplierId, 'SUP-A');

        // Close shipment -> net due = 1000 - 80 = 920
        final closedStmt = await settlementService.closeShipment(
          shipmentId: shipmentId,
          closedAt: DateTime(2026, 3, 1, 18, 0),
        );
        expect(closedStmt.isClosed, isTrue);
        expect(closedStmt.shipment.closedAt, isNotNull);
        expect(closedStmt.netSupplierDue, closeTo(920, 0.01));
        expect(closedStmt.remainingForShipment, closeTo(920, 0.01));
        expect(await db.ledgerDao.getSupplierBalance('SUP-A'), closeTo(920, 0.01));

        // Double-close must throw StateError (prevents double-posting)
        await expectLater(
          settlementService.closeShipment(shipmentId: shipmentId),
          throwsA(isA<StateError>()),
        );

        // Cannot reassign supplier after close
        await expectLater(
          settlementService.reassignSupplier(
            shipmentId: shipmentId,
            newSupplierId: DefaultSupplier.unknownId,
          ),
          throwsA(isA<StateError>()),
        );

        // Record partial payment to supplier for this shipment
        await settlementService.recordSupplierPayment(
          supplierId: 'SUP-A',
          amount: 500,
          shipmentId: shipmentId,
          notes: 'دفعة أولى للمورد',
        );

        final afterPayStmt =
            await settlementService.getShipmentStatement(shipmentId);
        expect(afterPayStmt.paidForShipment, closeTo(500, 0.01));
        expect(afterPayStmt.remainingForShipment, closeTo(420, 0.01));
        expect(await db.ledgerDao.getSupplierBalance('SUP-A'), closeTo(420, 0.01));
      },
    );
  });
}
