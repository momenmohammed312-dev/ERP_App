import 'dart:convert';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/services/document_date_service.dart';
import 'package:pos_offline_desktop/core/services/invoice_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late DocumentDateService dateService;
  late InvoiceService invoiceService;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    dateService = DocumentDateService(db);
    invoiceService = InvoiceService(db);

    // Seed basic category, product, customer and supplier
    await db.into(db.categories).insert(
      CategoriesCompanion.insert(
        categoryName: 'عام',
      ),
    );

    await db.into(db.products).insert(
      ProductsCompanion.insert(
        name: 'طماطم',
        price: 25.0,
        quantity: 100,
        costPrice: const Value(18.0),
        unit: const Value('kg'),
      ),
    );

    await db.into(db.customers).insert(
      CustomersCompanion.insert(
        id: 'cust_1',
        name: 'عميل تجريبي',
        phone: const Value('01000000000'),
      ),
    );

    await db.into(db.suppliers).insert(
      SuppliersCompanion.insert(
        id: 'supp_1',
        name: 'مورد تجريبي',
        phone: const Value('01111111111'),
      ),
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('DocumentDateService — Basic Logic & Closed Days', () {
    test('mergeWithCurrentTime combines selected date with source time', () {
      final selectedDate = DateTime(2025, 5, 20);
      final timeSource = DateTime(2026, 10, 14, 15, 45, 30, 500);

      final merged = DocumentDateService.mergeWithCurrentTime(selectedDate, timeSource);

      expect(merged.year, 2025);
      expect(merged.month, 5);
      expect(merged.day, 20);
      expect(merged.hour, 15);
      expect(merged.minute, 45);
      expect(merged.second, 30);
    });

    test('isDateInClosedDay returns true when day is closed and false otherwise', () async {
      final targetDate = DateTime(2026, 9, 15, 10, 0);

      // Initially no day record exists -> not closed
      expect(await dateService.isDateInClosedDay(targetDate), isFalse);

      // Insert an open day
      await db.into(db.days).insert(
        DaysCompanion.insert(
          date: DateTime(2026, 9, 15, 8, 0),
          isOpen: const Value(true),
        ),
      );
      expect(await dateService.isDateInClosedDay(targetDate), isFalse);

      // Close the day
      await (db.update(db.days)..where((t) => t.date.equals(DateTime(2026, 9, 15, 8, 0))))
          .write(DaysCompanion(isOpen: const Value(false), closedAt: Value(DateTime(2026, 9, 15, 22, 0))));

      expect(await dateService.isDateInClosedDay(targetDate), isTrue);
    });
  });

  group('Invoice Creation with Custom Dates', () {
    test('create invoice with past date preserves date and records real created_at', () async {
      final pastDate = DateTime(2026, 8, 1, 14, 30);

      final result = await invoiceService.createInvoice(
        customerId: 'cust_1',
        customerName: 'عميل تجريبي',
        paymentMethod: 'cash',
        totalAmount: 250.0,
        paidAmount: 250.0,
        cashAmount: 250.0,
        status: 'active',
        invoiceDate: pastDate,
        splitPayments: [SplitPaymentEntry(method: 'cash', amount: 250.0)],
        items: [
          InvoiceItemParams(productId: 1, quantity: 10, price: 25.0),
        ],
      );

      final inv = await db.invoiceDao.getInvoiceById(result.invoiceId);
      expect(inv != null, isTrue);
      expect(inv!.date, equals(pastDate));
      expect(inv.createdAt!.isAfter(DateTime(2026, 10, 1)), isTrue);

      // Verify ledger transactions have the past date
      final txs = await (db.select(db.ledgerTransactions)
        ..where((t) => t.receiptNumber.equals('INV${result.invoiceId}')))
        .get();
      expect(txs.isNotEmpty, isTrue);
      for (final tx in txs) {
        expect(tx.date, equals(pastDate));
      }

      // Verify invoice payments have the past date
      final payments = await (db.select(db.invoicePayments)
        ..where((t) => t.invoiceId.equals(result.invoiceId)))
        .get();
      expect(payments.isNotEmpty, isTrue);
      for (final p in payments) {
        expect(p.paidAt, equals(pastDate));
      }
    });

    test('create invoice with future date sets date correctly', () async {
      final futureDate = DateTime(2027, 1, 15, 11, 0);

      final result = await invoiceService.createInvoice(
        customerId: 'cust_1',
        customerName: 'عميل تجريبي',
        paymentMethod: 'credit',
        totalAmount: 500.0,
        paidAmount: 0.0,
        creditAmount: 500.0,
        status: 'active',
        invoiceDate: futureDate,
        items: [
          InvoiceItemParams(productId: 1, quantity: 20, price: 25.0),
        ],
      );

      final inv = await db.invoiceDao.getInvoiceById(result.invoiceId);
      expect(inv != null, isTrue);
      expect(inv!.date, equals(futureDate));

      final txs = await (db.select(db.ledgerTransactions)
        ..where((t) => t.receiptNumber.equals('INV${result.invoiceId}')))
        .get();
      expect(txs.first.date, equals(futureDate));
    });
  });

  group('updateInvoiceDate — Atomic Move & Audit', () {
    test('updates invoice date, ledger, payments, inventory, and writes audit log', () async {
      final initialDate = DateTime(2026, 9, 10, 10, 0);
      final newDate = DateTime(2026, 9, 25, 16, 30);

      final createResult = await invoiceService.createInvoice(
        customerId: 'cust_1',
        customerName: 'عميل تجريبي',
        paymentMethod: 'partial',
        totalAmount: 1000.0,
        paidAmount: 400.0,
        cashAmount: 400.0,
        creditAmount: 600.0,
        status: 'active',
        invoiceDate: initialDate,
        splitPayments: [SplitPaymentEntry(method: 'cash', amount: 400.0)],
        items: [
          InvoiceItemParams(productId: 1, quantity: 40, price: 25.0),
        ],
      );
      final invId = createResult.invoiceId;

      // Add a dummy inventory movement for this invoice
      await db.into(db.inventoryMovements).insert(
        InventoryMovementsCompanion.insert(
          productId: 1,
          quantity: -40,
          previousQuantity: 100,
          newQuantity: 60,
          unitCost: 18.0,
          totalValue: 720.0,
          movementType: 'sale',
          referenceType: 'sale_invoice',
          movementDate: initialDate,
          createdAt: initialDate,
          updatedAt: initialDate,
          reference: 'INV$invId',
        ),
      );

      final origInvoice = await db.invoiceDao.getInvoiceById(invId);
      final origCreatedAt = origInvoice!.createdAt;

      // Perform update
      final updateResult = await dateService.updateInvoiceDate(
        invoiceId: invId,
        newDate: newDate,
        userId: '42',
      );

      expect(updateResult.success, isTrue);
      expect(updateResult.oldDate, equals(initialDate));
      expect(updateResult.newDate, equals(newDate));
      expect(updateResult.isClosedDay, isFalse);

      // 1. Verify invoice row
      final updatedInv = await db.invoiceDao.getInvoiceById(invId);
      expect(updatedInv!.date, equals(newDate));
      expect(updatedInv.createdAt, equals(origCreatedAt)); // created_at must not change
      expect(updatedInv.updatedAt != null, isTrue);

      // 2. Verify ledger transactions
      final ledgerRows = await (db.select(db.ledgerTransactions)
        ..where((t) => t.receiptNumber.equals('INV$invId')))
        .get();
      expect(ledgerRows.length, 2); // 1 sale (1000), 1 pay (400)
      for (final tx in ledgerRows) {
        expect(tx.date, equals(newDate));
      }

      // 3. Verify invoice_payments
      final payRows = await (db.select(db.invoicePayments)
        ..where((t) => t.invoiceId.equals(invId)))
        .get();
      expect(payRows.isNotEmpty, isTrue);
      for (final p in payRows) {
        expect(p.paidAt, equals(newDate));
      }

      // 4. Verify inventory_movements
      final movement = await (db.select(db.inventoryMovements)
        ..where((t) => t.reference.equals('INV$invId')))
        .getSingle();
      expect(movement.movementDate, equals(newDate));

      // 5. Verify audit_log
      final auditEntries = await (db.select(db.auditLog)
        ..where((t) => t.action.equals('DATE_CHANGE') & t.recordId.equals(invId)))
        .get();
      expect(auditEntries.length, 1);
      final audit = auditEntries.first;
      expect(audit.tableNameField, 'invoices');
      expect(audit.userId, 42);
      expect(audit.details, contains('تعديل تاريخ فاتورة مبيعات'));

      final oldVal = jsonDecode(audit.oldValue!) as Map<String, dynamic>;
      final newVal = jsonDecode(audit.newValue!) as Map<String, dynamic>;
      expect(oldVal['date'], initialDate.toIso8601String());
      expect(newVal['date'], newDate.toIso8601String());
      expect(newVal['day_closed_warning'], isFalse);
    });

    test('detects closed day and marks warning in audit log', () async {
      final closedDate = DateTime(2026, 8, 20, 12, 0);

      // Create closed day in days table
      await db.into(db.days).insert(
        DaysCompanion.insert(
          date: DateTime(2026, 8, 20),
          isOpen: const Value(false),
          closedAt: Value(DateTime(2026, 8, 20, 20, 0)),
        ),
      );

      final createResult = await invoiceService.createInvoice(
        customerId: 'cust_1',
        customerName: 'عميل تجريبي',
        paymentMethod: 'credit',
        totalAmount: 100.0,
        paidAmount: 0.0,
        creditAmount: 100.0,
        status: 'active',
        invoiceDate: DateTime(2026, 8, 25),
        items: [
          InvoiceItemParams(productId: 1, quantity: 4, price: 25.0),
        ],
      );

      final updateResult = await dateService.updateInvoiceDate(
        invoiceId: createResult.invoiceId,
        newDate: closedDate,
      );

      expect(updateResult.isClosedDay, isTrue);

      final audit = await (db.select(db.auditLog)
        ..where((t) => t.action.equals('DATE_CHANGE') & t.recordId.equals(createResult.invoiceId)))
        .getSingle();
      final newVal = jsonDecode(audit.newValue!) as Map<String, dynamic>;
      expect(newVal['day_closed_warning'], isTrue);
      expect(audit.details, contains('تحذير: يوم مغلق'));
    });
  });

  group('Customer & Supplier Balance Invariance and Statement Ordering', () {
    test('customer final balance remains identical after moving invoice dates', () async {
      // Create 3 invoices over time
      final d1 = DateTime(2026, 9, 1);
      final d2 = DateTime(2026, 9, 10);
      final d3 = DateTime(2026, 9, 20);

      final inv1 = await invoiceService.createInvoice(
        customerId: 'cust_1',
        customerName: 'عميل تجريبي',
        paymentMethod: 'credit',
        totalAmount: 500.0,
        paidAmount: 0.0,
        status: 'active',
        invoiceDate: d1,
        items: [InvoiceItemParams(productId: 1, quantity: 20, price: 25.0)],
      );

      final inv2 = await invoiceService.createInvoice(
        customerId: 'cust_1',
        customerName: 'عميل تجريبي',
        paymentMethod: 'partial',
        totalAmount: 1000.0,
        paidAmount: 300.0,
        cashAmount: 300.0,
        status: 'active',
        invoiceDate: d2,
        items: [InvoiceItemParams(productId: 1, quantity: 40, price: 25.0)],
      );

      final inv3 = await invoiceService.createInvoice(
        customerId: 'cust_1',
        customerName: 'عميل تجريبي',
        paymentMethod: 'credit',
        totalAmount: 250.0,
        paidAmount: 0.0,
        status: 'active',
        invoiceDate: d3,
        items: [InvoiceItemParams(productId: 1, quantity: 10, price: 25.0)],
      );

      // Customer debt: 500 + (1000 - 300) + 250 = 1450
      final balanceBefore = await db.ledgerDao.getCustomerBalance('cust_1');
      expect(balanceBefore, equals(1450.0));

      // Move inv1 forward past inv2 (to Sep 15)
      await dateService.updateInvoiceDate(
        invoiceId: inv1.invoiceId,
        newDate: DateTime(2026, 9, 15),
      );

      // Move inv3 backward before inv1 (to Aug 15)
      await dateService.updateInvoiceDate(
        invoiceId: inv3.invoiceId,
        newDate: DateTime(2026, 8, 15),
      );

      // Move inv2 date
      await dateService.updateInvoiceDate(
        invoiceId: inv2.invoiceId,
        newDate: DateTime(2026, 9, 30),
      );

      // Final balance must be 100% strictly invariant!
      final balanceAfter = await db.ledgerDao.getCustomerBalance('cust_1');
      expect(balanceAfter, equals(balanceBefore));
    });

    test('customer statement chronological ordering adapts while preserving final balance', () async {
      // Insert 3 ledger transactions manually with clear dates
      // Tx A: 2026-07-01 -> Debit 100
      // Tx B: 2026-07-10 -> Debit 200
      // Tx C: 2026-07-20 -> Credit 150
      await db.ledgerDao.insertTransaction(
        LedgerTransactionsCompanion.insert(
          id: 'tx_a',
          entityType: 'Customer',
          refId: 'cust_1',
          date: DateTime(2026, 7, 1),
          description: 'Tx A',
          debit: const Value(100.0),
          credit: const Value(0.0),
          origin: 'sale',
          receiptNumber: const Value('INV101'),
        ),
      );

      await db.ledgerDao.insertTransaction(
        LedgerTransactionsCompanion.insert(
          id: 'tx_b',
          entityType: 'Customer',
          refId: 'cust_1',
          date: DateTime(2026, 7, 10),
          description: 'Tx B',
          debit: const Value(200.0),
          credit: const Value(0.0),
          origin: 'sale',
          receiptNumber: const Value('INV102'),
        ),
      );

      await db.ledgerDao.insertTransaction(
        LedgerTransactionsCompanion.insert(
          id: 'tx_c',
          entityType: 'Customer',
          refId: 'cust_1',
          date: DateTime(2026, 7, 20),
          description: 'Tx C',
          debit: const Value(0.0),
          credit: const Value(150.0),
          origin: 'payment',
          receiptNumber: const Value('PAY101'),
        ),
      );

      // Before move: query statement
      var statement = await (db.select(db.ledgerTransactions)
        ..where((t) => t.entityType.equals('Customer') & t.refId.equals('cust_1'))
        ..orderBy([(t) => OrderingTerm(expression: t.date, mode: OrderingMode.asc)]))
        .get();

      expect(statement.map((t) => t.id).toList(), ['tx_a', 'tx_b', 'tx_c']);

      // Move Tx B to 2026-07-25 (after Tx C)
      await dateService.updatePaymentDate(
        transactionId: 'tx_b',
        newDate: DateTime(2026, 7, 25),
      );

      // After move: query statement again
      statement = await (db.select(db.ledgerTransactions)
        ..where((t) => t.entityType.equals('Customer') & t.refId.equals('cust_1'))
        ..orderBy([(t) => OrderingTerm(expression: t.date, mode: OrderingMode.asc)]))
        .get();

      // Order has changed cleanly to [tx_a, tx_c, tx_b]
      expect(statement.map((t) => t.id).toList(), ['tx_a', 'tx_c', 'tx_b']);

      // Running balance checks:
      // At July 5 (between A and C): only Tx A exists -> balance 100
      final balanceJuly5 = await db.ledgerDao.getRunningBalance('Customer', 'cust_1', upToDate: DateTime(2026, 7, 5));
      expect(balanceJuly5, 100.0);

      // Final balance is 100 - 150 + 200 = 150
      final finalBalance = await db.ledgerDao.getCustomerBalance('cust_1');
      expect(finalBalance, 150.0);
    });
  });

  group('updatePurchaseDate & Other Documents', () {
    test('updatePurchaseDate moves purchase date, supplier ledger and inventory', () async {
      final pDate1 = DateTime(2026, 8, 1);
      final pDate2 = DateTime(2026, 8, 28);
      const purchaseId = 'PUR_001';
      const invNum = 'PINV-1001';

      // Insert purchase
      await db.into(db.purchases).insert(
        PurchasesCompanion.insert(
          id: purchaseId,
          supplierId: const Value('supp_1'),
          invoiceNumber: invNum,
          description: 'شراء طماطم',
          totalAmount: 1000.0,
          paidAmount: const Value(400.0),
          purchaseDate: pDate1,
          createdAt: pDate1,
        ),
      );

      // Insert supplier ledger entries
      await db.ledgerDao.insertTransaction(
        LedgerTransactionsCompanion.insert(
          id: '${invNum}_ledger',
          entityType: 'Supplier',
          refId: 'supp_1',
          date: pDate1,
          description: 'فاتورة مشتريات $invNum',
          debit: const Value(0.0),
          credit: const Value(1000.0),
          origin: 'purchase',
          receiptNumber: const Value(invNum),
        ),
      );

      await db.ledgerDao.insertTransaction(
        LedgerTransactionsCompanion.insert(
          id: '${invNum}_ledger_pay',
          entityType: 'Supplier',
          refId: 'supp_1',
          date: pDate1,
          description: 'سداد $invNum',
          debit: const Value(400.0),
          credit: const Value(0.0),
          origin: 'payment',
          receiptNumber: const Value(invNum),
        ),
      );

      // Insert inventory movement
      await db.into(db.inventoryMovements).insert(
        InventoryMovementsCompanion.insert(
          productId: 1,
          quantity: 100,
          previousQuantity: 0,
          newQuantity: 100,
          unitCost: 10.0,
          totalValue: 1000.0,
          movementType: 'purchase',
          referenceType: 'purchase_invoice',
          movementDate: pDate1,
          createdAt: pDate1,
          updatedAt: pDate1,
          reference: invNum,
        ),
      );

      final suppBalanceBefore = await db.ledgerDao.getSupplierBalance('supp_1');
      expect(suppBalanceBefore, equals(600.0)); // 1000 - 400

      // Update purchase date
      final res = await dateService.updatePurchaseDate(
        purchaseId: purchaseId,
        newDate: pDate2,
        userId: '1',
      );

      expect(res.success, isTrue);

      final pAfter = await (db.select(db.purchases)..where((t) => t.id.equals(purchaseId))).getSingle();
      expect(pAfter.purchaseDate, equals(pDate2));
      expect(pAfter.createdAt, equals(pDate1)); // intact

      final txs = await (db.select(db.ledgerTransactions)..where((t) => t.receiptNumber.equals(invNum))).get();
      for (final tx in txs) {
        expect(tx.date, equals(pDate2));
      }

      final movement = await (db.select(db.inventoryMovements)..where((t) => t.reference.equals(invNum))).getSingle();
      expect(movement.movementDate, equals(pDate2));

      // Supplier balance remains invariant
      final suppBalanceAfter = await db.ledgerDao.getSupplierBalance('supp_1');
      expect(suppBalanceAfter, equals(suppBalanceBefore));

      // Audit log entry
      final audit = await (db.select(db.auditLog)..where((t) => t.tableNameField.equals('purchases'))).getSingle();
      expect(audit.action, 'DATE_CHANGE');
    });

    test('updateExpenseDate updates expense and associated ledger atomically', () async {
      final eDate1 = DateTime(2026, 9, 1);
      final eDate2 = DateTime(2026, 9, 18);
      const expenseId = 'EXP_101';

      await db.into(db.expenses).insert(
        ExpensesCompanion.insert(
          id: expenseId,
          category: 'نثريات',
          amount: 150.0,
          date: Value(eDate1),
          description: 'شاي وسكر',
          receiptNumber: const Value('REC_101'),
          createdAt: Value(eDate1),
        ),
      );

      await db.ledgerDao.insertTransaction(
        LedgerTransactionsCompanion.insert(
          id: 'tx_exp_101',
          entityType: 'Expense',
          refId: expenseId,
          date: eDate1,
          description: 'شاي وسكر',
          debit: const Value(0.0),
          credit: const Value(150.0),
          origin: 'expense',
          receiptNumber: const Value('REC_101'),
        ),
      );

      final res = await dateService.updateExpenseDate(
        expenseId: expenseId,
        newDate: eDate2,
      );

      expect(res.success, isTrue);

      final expAfter = await db.expenseDao.getExpenseById(expenseId);
      expect(expAfter!.date, equals(eDate2));

      final txAfter = await db.ledgerDao.getTransactionById('tx_exp_101');
      expect(txAfter!.date, equals(eDate2));
    });

    test('updateCustodyDate updates custody and associated ledger atomically', () async {
      final cDate1 = DateTime(2026, 9, 5);
      final cDate2 = DateTime(2026, 9, 22);

      final cId = await db.into(db.cashCustodies).insert(
        CashCustodiesCompanion.insert(
          custodyNumber: 'CUST-0099',
          staffId: 'STAFF001',
          staffName: 'موظف تجريبي',
          amount: 500.0,
          remainingAmount: 500.0,
          status: const Value('open'),
          date: cDate1,
          createdAt: Value(cDate1),
        ),
      );

      await db.ledgerDao.insertTransaction(
        LedgerTransactionsCompanion.insert(
          id: 'tx_custody_$cId',
          entityType: 'Custody',
          refId: cId.toString(),
          date: cDate1,
          description: 'عهدة CUST-0099',
          debit: const Value(500.0),
          credit: const Value(0.0),
          origin: 'custody',
        ),
      );

      final res = await dateService.updateCustodyDate(
        custodyId: cId,
        newDate: cDate2,
      );

      expect(res.success, isTrue);

      final custodyAfter = await db.custodyDao.getCustodyById(cId);
      expect(custodyAfter!.date, equals(cDate2));

      final txAfter = await db.ledgerDao.getTransactionById('tx_custody_$cId');
      expect(txAfter!.date, equals(cDate2));
    });

    test('updateSalesReturnDate updates return and associated ledger atomically', () async {
      final rDate1 = DateTime(2026, 9, 7);
      final rDate2 = DateTime(2026, 9, 24);

      final inv = await invoiceService.createInvoice(
        customerId: 'cust_1',
        customerName: 'عميل',
        paymentMethod: 'cash',
        totalAmount: 120.0,
        paidAmount: 120.0,
        status: 'active',
        items: [InvoiceItemParams(productId: 1, quantity: 4, price: 30.0)],
      );

      final retId = await db.into(db.salesReturns).insert(
        SalesReturnsCompanion.insert(
          returnNumber: 'RET-0001',
          originalInvoiceId: inv.invoiceId,
          customerName: 'عميل',
          returnDate: rDate1,
          totalAmount: 120.0,
          returnReason: 'تالف',
          createdAt: Value(rDate1),
        ),
      );

      await db.ledgerDao.insertTransaction(
        LedgerTransactionsCompanion.insert(
          id: 'tx_ret_$retId',
          entityType: 'Customer',
          refId: 'cust_1',
          date: rDate1,
          description: 'مرتجع RET-0001',
          debit: const Value(0.0),
          credit: const Value(120.0),
          origin: 'sales_return',
          receiptNumber: Value('RET$retId'),
        ),
      );

      final res = await dateService.updateSalesReturnDate(
        returnId: retId,
        newDate: rDate2,
      );

      expect(res.success, isTrue);

      final retAfter = await db.salesReturnsDao.getReturnById(retId);
      expect(retAfter!.returnDate, equals(rDate2));

      final txAfter = await db.ledgerDao.getTransactionById('tx_ret_$retId');
      expect(txAfter!.date, equals(rDate2));
    });
  });
}
