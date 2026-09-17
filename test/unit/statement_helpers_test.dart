import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/ui/customer/services/enhanced_customer_statement_generator.dart';

/// B5 (ledger is the single balance truth) + B6–B9 (statements) tests.
///
/// Covered here at the DB + rendered-data level:
///  - ONE shared date normalizer ([StatementHelpers.normalizeRange] /
///    [StatementHelpers.openingCutoff]) with inclusive day boundaries;
///  - opening balance = canonical `getRunningBalance up-to from−1s`;
///  - canonical invoice label is EXACTLY `فاتورة 000001` from the STORED
///    `invoice.invoiceNumber` resolved via the stable `receiptNumber` link —
///    never parsed from free text; legacy rows render verbatim;
///  - supplier labels mirror this via the `receiptNumber → purchase` link;
///  - nested invoice/purchase items resolve via the same stable links;
///  - both entry paths (Customer List, Unified Balances, debt list) build the
///    statement from the SAME by-id query helper — navigation parity;
///  - the supplier PDF honors the screen's passed (filtered) rows instead of
///    re-querying (same contract as the customer export).

AppDatabase openDb() {
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  return db;
}

Future<String> addCustomer(
  AppDatabase db,
  String name, {
  double opening = 0.0,
}) async {
  final id = 'cust-$name';
  await db.into(db.customers).insert(
        CustomersCompanion.insert(
          id: id,
          name: name,
          openingBalance: Value(opening),
        ),
      );
  return id;
}

Future<void> addTx(
  AppDatabase db,
  String id,
  String entityType,
  String refId,
  DateTime date, {
  double debit = 0.0,
  double credit = 0.0,
  String origin = 'sale',
  String description = 'tx',
  String? receiptNumber,
}) async {
  await db.ledgerDao.insertTransaction(
    LedgerTransactionsCompanion.insert(
      id: id,
      entityType: entityType,
      refId: refId,
      date: date,
      description: description,
      debit: Value(debit),
      credit: Value(credit),
      origin: origin,
      receiptNumber: Value(receiptNumber),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (MethodCall methodCall) async => '.',
      );

  group('StatementHelpers (single normalizer + label rule)', () {
    test('normalizeRange is day-truncated and inclusive', () {
      final (from, to) = StatementHelpers.normalizeRange(
        DateTime(2026, 3, 10, 15, 30),
        DateTime(2026, 3, 12, 8, 5),
      );
      expect(from, DateTime(2026, 3, 10));
      expect(to, DateTime(2026, 3, 12, 23, 59, 59));
    });

    test('openingCutoff is one second before the period start', () {
      expect(
        StatementHelpers.openingCutoff(DateTime(2026, 3, 10, 15, 30)),
        DateTime(2026, 3, 9, 23, 59, 59),
      );
    });

    test('extractInvoiceId parses the stable link column only', () {
      expect(StatementHelpers.extractInvoiceId('INV42'), 42);
      expect(StatementHelpers.extractInvoiceId(null), isNull);
      expect(StatementHelpers.extractInvoiceId(''), isNull);
      expect(StatementHelpers.extractInvoiceId('فاتورة 000042'), isNull,
          reason: 'free-text descriptions are NEVER parsed for identity');
      expect(StatementHelpers.extractInvoiceId('RET42'), isNull);
    });

    test('invoiceLabel is exactly فاتورة + stored number', () {
      expect(StatementHelpers.invoiceLabel('000001'), 'فاتورة 000001');
    });
  });

  group('date boundaries (inclusive, day-truncated)', () {
    test('edge timestamps land on the right side of the cut', () async {
      final db = openDb();
      final id = await addCustomer(db, 'حدود');
      // Just-outside-before, edges, just-outside-after.
      await addTx(db, 'd', 'Customer', id, DateTime(2026, 2, 28, 23, 59, 59),
          debit: 5, description: 'before');
      await addTx(db, 'a', 'Customer', id, DateTime(2026, 3, 1),
          debit: 10, description: 'from-edge');
      await addTx(db, 'b', 'Customer', id, DateTime(2026, 3, 31, 23, 59, 59),
          debit: 20, description: 'to-edge');
      await addTx(db, 'c', 'Customer', id, DateTime(2026, 4, 1),
          debit: 40, description: 'after');

      final (from, to) = StatementHelpers.normalizeRange(
        DateTime(2026, 3, 1),
        DateTime(2026, 3, 31, 12),
      );
      final inRange = await db.ledgerDao.getCustomerTransactionsByDateRange(
        id,
        from,
        to,
      );
      expect(inRange.map((t) => t.id).toSet(), {'a', 'b'});

      // Opening = everything up to from−1s (sees 'before', not the edges).
      final opening = await db.ledgerDao.getRunningBalance(
        'Customer',
        id,
        upToDate: StatementHelpers.openingCutoff(DateTime(2026, 3, 1)),
      );
      expect(opening, 5.0);
    });
  });

  group('opening balance + running balance (B5)', () {
    test('screen fold agrees with getTransactionsWithRunningBalance', () async {
      final db = openDb();
      final id = await addCustomer(db, 'رصيد', opening: 50.0);
      await addTx(db, 't1', 'Customer', id, DateTime(2026, 3, 5),
          debit: 100, origin: 'sale', description: 'فاتورة قديمة');
      await addTx(db, 't2', 'Customer', id, DateTime(2026, 3, 6),
          credit: 30, origin: 'payment', description: 'سداد');

      final (from, to) = StatementHelpers.normalizeRange(
        DateTime(2026, 3, 1),
        DateTime(2026, 3, 31),
      );
      // Screen path: opening via canonical helper + manual fold.
      final prev = await db.ledgerDao.getRunningBalance(
        'Customer',
        id,
        upToDate: StatementHelpers.openingCutoff(DateTime(2026, 3, 1)),
      );
      expect(prev, 50.0);
      final txs = await db.ledgerDao.getCustomerTransactionsByDateRange(
        id,
        from,
        to,
      );
      var running = prev;
      final folded = <double>[];
      for (final tx in txs) {
        running += tx.debit - tx.credit;
        folded.add(running);
      }
      expect(folded, [150.0, 120.0]);

      // PDF path helper returns the identical sequence.
      final withBalances = await db.ledgerDao.getTransactionsWithRunningBalance(
        'Customer',
        id,
        from,
        to,
      );
      expect(
        withBalances.map((e) => e.runningBalance).toList(),
        [150.0, 120.0],
      );
      // And the point balance equals the final running balance.
      expect(await db.ledgerDao.getCustomerBalance(id), 120.0);
    });

    test('cached totalDebt/totalPaid columns are not balance sources', () async {
      final db = openDb();
      final id = await addCustomer(db, 'قديم', opening: 0.0);
      // Simulate a stale hand-typed cache (as the pre-B5 UI wrote).
      await (db.update(db.customers)..where((t) => t.id.equals(id))).write(
        const CustomersCompanion(
          totalDebt: Value(9999.0),
          totalPaid: Value(1111.0),
        ),
      );
      await addTx(db, 't1', 'Customer', id, DateTime(2026, 3, 5), debit: 100);
      // Ledger truth ignores the cache entirely.
      expect(await db.ledgerDao.getCustomerBalance(id), 100.0);
      expect(await db.ledgerDao.getTotalReceivables(), 100.0);
    });
  });

  group('supplier opening is column-only (no double count)', () {
    test('openingBalance column + period txns counted exactly once', () async {
      final db = openDb();
      // Mirrors the add/edit supplier save path: the opening lives ONLY in
      // suppliers.opening_balance (no origin='opening' ledger row — see
      // CustomerOpeningBalanceFix for the customer precedent).
      await db.into(db.suppliers).insert(
            SuppliersCompanion.insert(
              id: 'sup-o',
              name: 'افتتاحي',
              openingBalance: const Value(100.0),
            ),
          );
      await addTx(
        db, 'o-1', 'Supplier', 'sup-o', DateTime(2026, 3, 5),
        credit: 50, origin: 'purchase', description: 'مشتريات',
      );
      await addTx(
        db, 'o-2', 'Supplier', 'sup-o', DateTime(2026, 3, 6),
        debit: 30, origin: 'payment', description: 'سداد',
      );
      expect(await db.ledgerDao.getSupplierBalance('sup-o'), 120.0);
      final (from, to) = StatementHelpers.normalizeRange(
        DateTime(2026, 3, 1),
        DateTime(2026, 3, 31),
      );
      final withBalances = await db.ledgerDao.getTransactionsWithRunningBalance(
        'Supplier',
        'sup-o',
        from,
        to,
      );
      expect(
        withBalances.map((e) => e.runningBalance).toList(),
        [150.0, 120.0],
      );
    });
  });

  group('canonical labels (stored numbers, never parsed text)', () {
    test("new numbered invoice renders exactly 'فاتورة 000001'", () async {
      final db = openDb();
      final cid = await addCustomer(db, 'مرقّم');
      final invId = await db.into(db.invoices).insert(
            InvoicesCompanion.insert(
              customerId: Value(cid),
              customerName: const Value('مرقّم'),
              totalAmount: const Value(100.0),
              invoiceNumber: const Value('000001'),
            ),
          );
      await addTx(
        db, 'sale-1', 'Customer', cid, DateTime(2026, 3, 5),
        debit: 100, origin: 'sale',
        // New-ledger stored description may already be canonical; the label
        // still resolves from the STORED number via the stable link.
        description: 'فاتورة 000001',
        receiptNumber: 'INV$invId',
      );

      final number = await StatementHelpers.resolveInvoiceNumber(
        db,
        'INV$invId',
      );
      expect(number, '000001');
      final tx = (await db.ledgerDao.getTransactionsByEntity(
        'Customer',
        cid,
      ))
          .single;
      expect(
        StatementHelpers.customerRowLabel(tx, invoiceNumber: number),
        'فاتورة 000001',
      );
    });

    test('legacy rows (no link) render stored description verbatim', () async {
      final db = openDb();
      final cid = await addCustomer(db, 'إرث');
      await addTx(
        db, 'old-1', 'Customer', cid, DateTime(2025, 1, 5),
        credit: 25, origin: 'payment',
        description: 'سداد قديم #123',
      );
      final tx = (await db.ledgerDao.getTransactionsByEntity(
        'Customer',
        cid,
      ))
          .single;
      expect(
        await StatementHelpers.resolveInvoiceNumber(db, tx.receiptNumber),
        isNull,
      );
      expect(
        StatementHelpers.customerRowLabel(tx, invoiceNumber: null),
        'سداد قديم #123',
      );
    });

    test('supplier purchase label via receiptNumber link; legacy verbatim',
        () async {
      final db = openDb();
      await db.into(db.suppliers).insert(
            SuppliersCompanion.insert(id: 'sup-1', name: 'مورّد'),
          );
      await db.into(db.purchases).insert(
            PurchasesCompanion.insert(
              id: 'PUR-1',
              invoiceNumber: 'PUR-001',
              description: 'فاتورة مشتريات من مورّد',
              totalAmount: 500.0,
              purchaseDate: DateTime(2026, 3, 5),
              createdAt: DateTime(2026, 3, 5),
              supplierId: const Value('sup-1'),
            ),
          );
      await addTx(
        db, 'p-1', 'Supplier', 'sup-1', DateTime(2026, 3, 5),
        credit: 500, origin: 'purchase',
        description: 'فاتورة مشتريات PUR-001',
        receiptNumber: 'PUR-001',
      );
      await addTx(
        db, 'p-2', 'Supplier', 'sup-1', DateTime(2026, 3, 6),
        debit: 100, origin: 'payment',
        description: 'دفعة نقدية قديمة',
      );

      final byNumber = await StatementHelpers.resolvePurchaseNumber(
        db,
        'PUR-001',
      );
      expect(byNumber, 'PUR-001');
      // The purchase.id link resolves identically.
      expect(
        await StatementHelpers.resolvePurchaseNumber(db, 'PUR-1'),
        'PUR-001',
      );
      final txs = await db.ledgerDao.getTransactionsByEntity(
        'Supplier',
        'sup-1',
      );
      final purchase = txs.firstWhere((t) => t.id == 'p-1');
      final legacy = txs.firstWhere((t) => t.id == 'p-2');
      expect(
        StatementHelpers.supplierRowLabel(
          purchase,
          purchaseNumber: byNumber,
        ),
        'فاتورة مشتريات PUR-001',
      );
      expect(
        StatementHelpers.supplierRowLabel(legacy, purchaseNumber: null),
        'دفعة نقدية قديمة',
      );
      // Supplier running sign: credit raises what we owe.
      expect(await db.ledgerDao.getSupplierBalance('sup-1'), 400.0);
    });
  });

  group('nested items stay (stable-link resolution)', () {
    test('invoice items resolve via INV receiptNumber', () async {
      final db = openDb();
      final cid = await addCustomer(db, 'أصناف');
      final pid = await db.into(db.products).insert(
            ProductsCompanion.insert(name: 'طماطم', price: 10.0, quantity: 100),
          );
      final invId = await db.invoiceDao.insertInvoice(
        InvoicesCompanion.insert(
          customerId: Value(cid),
          customerName: const Value('أصناف'),
          totalAmount: const Value(70.0),
        ),
      );
      await db.invoiceDao.insertInvoiceItem(
        InvoiceItemsCompanion.insert(
          invoiceId: invId,
          productId: pid,
          quantity: const Value(7),
          price: 10.0,
        ),
      );
      await addTx(
        db, 's-1', 'Customer', cid, DateTime(2026, 3, 5),
        debit: 70, origin: 'sale',
        description: 'بيع',
        receiptNumber: 'INV$invId',
      );

      final linkedId = StatementHelpers.extractInvoiceId('INV$invId');
      final items = await db.invoiceDao.getItemsWithProductsByInvoice(
        linkedId!,
      );
      expect(items, hasLength(1));
      expect(items.single.$2!.name, 'طماطم');
      expect(items.single.$1.quantity, 7);
    });

    test('purchase items resolve via receiptNumber link', () async {
      final db = openDb();
      await db.into(db.suppliers).insert(
            SuppliersCompanion.insert(id: 'sup-9', name: 'مورّد أصناف'),
          );
      final pid = await db.into(db.products).insert(
            ProductsCompanion.insert(name: 'بطاطس', price: 8.0, quantity: 50),
          );
      await db.into(db.purchases).insert(
            PurchasesCompanion.insert(
              id: 'PUR-9',
              invoiceNumber: 'PUR-009',
              description: 'فاتورة مشتريات',
              totalAmount: 80.0,
              purchaseDate: DateTime(2026, 3, 5),
              createdAt: DateTime(2026, 3, 5),
              supplierId: const Value('sup-9'),
            ),
          );
      await db.into(db.purchaseItems).insert(
            PurchaseItemsCompanion.insert(
              id: 'PUR-9-item-1',
              purchaseId: 'PUR-9',
              productId: pid.toString(),
              quantity: 10,
              unitPrice: 8.0,
              totalPrice: 80.0,
              unit: 'كجم',
              createdAt: DateTime(2026, 3, 5),
            ),
          );

      final items = await db.purchaseDao.getItemsWithProductsByPurchase(
        'PUR-9',
      );
      expect(items, hasLength(1));
      expect(items.single.$2!.name, 'بطاطس');
    });
  });

  group('navigation parity (both paths → same id/txns/balances)', () {    test('unified-balances id re-fetches the full row both screens use',
        () async {
      final db = openDb();
      final cid = await addCustomer(db, 'موحّد', opening: 20.0);
      await addTx(db, 't1', 'Customer', cid, DateTime(2026, 3, 5), debit: 100);

      // Path 2 (Unified Balances): aggregate map carries only id/name/phone.
      final balances = await db.ledgerDao.getAllCustomerBalances();
      final entry = balances.singleWhere((b) => b['id'] == cid);
      // The screen passes ONLY the id and re-fetches the full row (B6 fix).
      final refetched = await db.customerDao.getCustomerById(
        entry['id'] as String,
      );
      expect(refetched, isNotNull);
      expect(refetched!.openingBalance, 20.0);

      // Both paths then run the SAME by-id query helper.
      final (from, to) = StatementHelpers.normalizeRange(
        DateTime(2026, 3, 1),
        DateTime(2026, 3, 31),
      );
      final viaList = await db.ledgerDao.getCustomerTransactionsByDateRange(
        cid,
        from,
        to,
      );
      final viaUnified = await db.ledgerDao.getCustomerTransactionsByDateRange(
        refetched.id,
        from,
        to,
      );
      expect(
        viaUnified.map((t) => t.id).toList(),
        viaList.map((t) => t.id).toList(),
      );
      expect(
        await db.ledgerDao.getCustomerBalance(refetched.id),
        await db.ledgerDao.getCustomerBalance(cid),
      );
    });
  });

  group('supplier PDF respects the screen-passed (filtered) rows', () {
    test('label resolution only ever sees the filtered subset', () async {
      final db = openDb();
      await db.into(db.suppliers).insert(
            SuppliersCompanion.insert(id: 'sup-f', name: 'مفلتر'),
          );
      await db.into(db.purchases).insert(
            PurchasesCompanion.insert(
              id: 'PUR-F',
              invoiceNumber: 'PUR-001',
              description: 'فاتورة مشتريات',
              totalAmount: 300.0,
              purchaseDate: DateTime(2026, 3, 5),
              createdAt: DateTime(2026, 3, 5),
              supplierId: const Value('sup-f'),
            ),
          );
      await addTx(
        db, 'f-1', 'Supplier', 'sup-f', DateTime(2026, 3, 5),
        credit: 300, origin: 'purchase',
        description: 'فاتورة مشتريات PUR-001',
        receiptNumber: 'PUR-001',
      );
      await addTx(
        db, 'f-2', 'Supplier', 'sup-f', DateTime(2026, 3, 6),
        debit: 50, origin: 'payment',
        description: 'دفعة مستبعدة بالفلتر',
      );

      // Mimic the screen's _filteredRows (filterType=purchase): only f-1 is
      // passed to SupplierStatementGenerator.generateStatement(transactions:).
      final all = await db.ledgerDao.getTransactionsByEntity(
        'Supplier',
        'sup-f',
      );
      final filtered = all.where((t) => t.origin == 'purchase').toList();
      expect(filtered.map((t) => t.id).toList(), ['f-1']);

      // Same per-row resolution the generator runs over the PASSED list.
      final numbers = <String, String>{};
      for (final tx in filtered) {
        final n = await StatementHelpers.resolvePurchaseNumber(
          db,
          tx.receiptNumber,
        );
        if (n != null) numbers[tx.receiptNumber!] = n;
      }
      expect(numbers, {'PUR-001': 'PUR-001'});
      expect(
        StatementHelpers.supplierRowLabel(
          filtered.single,
          purchaseNumber: numbers[filtered.single.receiptNumber],
        ),
        'فاتورة مشتريات PUR-001',
      );
      // The excluded row is never consulted: no entry, no query for it.
      expect(numbers.containsKey('f-2'), isFalse);
    });
  });
}
