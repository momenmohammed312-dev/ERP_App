import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/services/business_date_service.dart';
import 'package:pos_offline_desktop/core/services/document_date_service.dart';
import 'package:pos_offline_desktop/core/services/invoice_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late DocumentDateService dateService;
  late InvoiceService invoiceService;
  late BusinessDateService businessDateService;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    dateService = DocumentDateService(db);
    invoiceService = InvoiceService(db);
    businessDateService = BusinessDateService(db);

    await db.into(db.categories).insert(
      CategoriesCompanion.insert(categoryName: 'عام'),
    );

    await db.into(db.products).insert(
      ProductsCompanion.insert(
        name: 'منتج تجريبي',
        price: 50.0,
        quantity: 100,
        costPrice: const Value(30.0),
      ),
    );

    await db.into(db.customers).insert(
      CustomersCompanion.insert(
        id: 'C100',
        name: 'عميل تجريبي',
      ),
    );

    await db.into(db.suppliers).insert(
      SuppliersCompanion.insert(
        id: 'S100',
        name: 'مورد تجريبي',
      ),
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('Suite 4: Document Dates (Default + Custom + Retro + Closed Day) (FEAT-019)', () {
    test('1. Default date matches current business date when not explicitly provided', () async {
      await businessDateService.openSession(openedBy: 'cashier', openingBalance: 500);

      final result = await invoiceService.createInvoice(
        customerId: 'C100',
        customerName: 'عميل C100',
        paymentMethod: 'cash',
        totalAmount: 100.0,
        paidAmount: 100.0,
        status: 'paid',
        items: [InvoiceItemParams(productId: 1, quantity: 2, price: 50.0)],
      );

      final inv = await db.invoiceDao.getInvoiceById(result.invoiceId);
      expect(inv, isNotNull);
      final today = DateTime.now();
      expect(inv!.date.year, equals(today.year));
      expect(inv.date.month, equals(today.month));
      expect(inv.date.day, equals(today.day));
    });

    test('2. Custom past date at invoice creation syncs ledger transactions and payments', () async {
      final pastDate = DateTime(2026, 7, 15, 11, 30);

      final result = await invoiceService.createInvoice(
        customerId: 'C100',
        customerName: 'عميل C100',
        paymentMethod: 'cash',
        totalAmount: 150.0,
        paidAmount: 150.0,
        status: 'paid',
        invoiceDate: pastDate,
        splitPayments: [SplitPaymentEntry(method: 'cash', amount: 150.0)],
        items: [InvoiceItemParams(productId: 1, quantity: 3, price: 50.0)],
      );

      final inv = await db.invoiceDao.getInvoiceById(result.invoiceId);
      expect(inv!.date, equals(pastDate));

      // Verify ledger transactions have the past date
      final txs = await (db.select(db.ledgerTransactions)
            ..where((t) => t.receiptNumber.equals('INV${result.invoiceId}')))
          .get();
      expect(txs, isNotEmpty);
      for (final tx in txs) {
        expect(tx.date, equals(pastDate));
      }

      // Verify invoice payments have the past date
      final payments = await (db.select(db.invoicePayments)
            ..where((t) => t.invoiceId.equals(result.invoiceId)))
          .get();
      expect(payments, isNotEmpty);
      for (final p in payments) {
        expect(p.paidAt, equals(pastDate));
      }
    });

    test('3. Retroactive date update updates invoice, ledger, and logs audit record', () async {
      final initialDate = DateTime(2026, 8, 10, 10, 0);
      final newDate = DateTime(2026, 8, 25, 17, 0);

      final result = await invoiceService.createInvoice(
        customerId: 'C100',
        customerName: 'عميل C100',
        paymentMethod: 'credit',
        totalAmount: 200.0,
        paidAmount: 0.0,
        status: 'pending',
        invoiceDate: initialDate,
        items: [InvoiceItemParams(productId: 1, quantity: 4, price: 50.0)],
      );

      final updateRes = await dateService.updateInvoiceDate(
        invoiceId: result.invoiceId,
        newDate: newDate,
        userId: 'admin_1',
      );

      expect(updateRes.success, isTrue);
      expect(updateRes.oldDate, equals(initialDate));
      expect(updateRes.newDate, equals(newDate));

      // Verify invoice row has new date but keeps original created_at
      final updatedInv = await db.invoiceDao.getInvoiceById(result.invoiceId);
      expect(updatedInv!.date, equals(newDate));

      // Verify ledger transactions updated to new date
      final ledgerTxs = await (db.select(db.ledgerTransactions)
            ..where((t) => t.receiptNumber.equals('INV${result.invoiceId}')))
          .get();
      expect(ledgerTxs, isNotEmpty);
      for (final tx in ledgerTxs) {
        expect(tx.date, equals(newDate));
      }

      // Verify audit log entry
      final audits = await (db.select(db.auditLog)
            ..where((t) => t.action.equals('DATE_CHANGE') & t.recordId.equals(result.invoiceId)))
          .get();
      expect(audits, isNotEmpty);
      expect(audits.first.tableNameField, equals('invoices'));
    });

    test('4. Closed day detection correctly flags closed days for UI warnings', () async {
      final testDate = DateTime(2026, 6, 1, 10, 0);

      // No day record -> not closed
      expect(await dateService.isDateInClosedDay(testDate), isFalse);

      // Open day inserted -> not closed
      await db.into(db.days).insert(
        DaysCompanion.insert(
          date: DateTime(2026, 6, 1, 8, 0),
          isOpen: const Value(true),
        ),
      );
      expect(await dateService.isDateInClosedDay(testDate), isFalse);

      // Day closed -> true
      await (db.update(db.days)..where((t) => t.date.equals(DateTime(2026, 6, 1, 8, 0))))
          .write(DaysCompanion(isOpen: const Value(false), closedAt: Value(DateTime(2026, 6, 1, 23, 0))));

      expect(await dateService.isDateInClosedDay(testDate), isTrue);
    });

    test('5. mergeWithCurrentTime accurately merges date component with source time', () {
      final selectedDate = DateTime(2025, 3, 15);
      final sourceTime = DateTime(2026, 10, 19, 14, 30, 45);

      final merged = DocumentDateService.mergeWithCurrentTime(selectedDate, sourceTime);
      expect(merged.year, equals(2025));
      expect(merged.month, equals(3));
      expect(merged.day, equals(15));
      expect(merged.hour, equals(14));
      expect(merged.minute, equals(30));
      expect(merged.second, equals(45));
    });

    test('6. editInvoice with date change syncs invoice date, payments, and movements', () async {
      final initialDate = DateTime(2026, 9, 10, 10, 0);
      final newDate = DateTime(2026, 9, 25, 15, 30);

      final result = await invoiceService.createInvoice(
        customerId: 'C100',
        customerName: 'عميل C100',
        paymentMethod: 'cash',
        totalAmount: 100.0,
        paidAmount: 100.0,
        status: 'paid',
        invoiceDate: initialDate,
        splitPayments: [SplitPaymentEntry(method: 'cash', amount: 100.0)],
        items: [InvoiceItemParams(productId: 1, quantity: 2, price: 50.0)],
      );

      final edited = await invoiceService.editInvoice(
        invoiceId: result.invoiceId,
        customerId: 'C100',
        customerName: 'عميل C100',
        paymentMethod: 'cash',
        totalAmount: 100.0,
        paidAmount: 100.0,
        status: 'paid',
        invoiceDate: newDate,
        items: [InvoiceItemParams(productId: 1, quantity: 2, price: 50.0)],
      );

      expect(edited.date, equals(newDate));

      // Verify invoice payments have new date
      final payments = await (db.select(db.invoicePayments)
            ..where((t) => t.invoiceId.equals(result.invoiceId)))
          .get();
      expect(payments, isNotEmpty);
      for (final p in payments) {
        expect(p.paidAt, equals(newDate));
      }

      // Verify ledger transactions have new date
      final txs = await (db.select(db.ledgerTransactions)
            ..where((t) => t.receiptNumber.equals('INV${result.invoiceId}')))
          .get();
      expect(txs, isNotEmpty);
      for (final tx in txs) {
        expect(tx.date, equals(newDate));
      }

      // Verify inventory movements have new date
      final movements = await (db.select(db.inventoryMovements)
            ..where((t) => t.reference.equals('INV${result.invoiceId}') | t.reference.equals(result.invoiceId.toString())))
          .get();
      for (final m in movements) {
        expect(m.movementDate, equals(newDate));
      }
    });
  });
}
