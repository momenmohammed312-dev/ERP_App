import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/tables/vegetable_shipments_table.dart';
import 'package:pos_offline_desktop/core/services/invoice_number_service.dart';
import 'package:pos_offline_desktop/core/services/invoice_service.dart';

/// Global numbering contract (schema v70+).
///
/// Proves against real DB effects:
/// 1. Fresh DB allocates 000001 → 000002; caller-supplied numbers ignored.
/// 2. Restart persistence: reopen DB → next is 000003.
/// 3. Concurrent creates → N distinct sequential numbers, zero duplicates.
/// 4. Legacy rows (INV<ms>/DRAFT_/SALE-…) coexist; new rows stay canonical.
/// 5. Edit preserves; void preserves + never recycles.
/// 6. Duplicate canonical insert fails (partial unique index).
/// 7. preserveInvoiceNumber path: canonical kept + sequence bumped;
///    legacy kept; garbage rejected.
/// 8. New sale/payment/commission ledger rows use the format helpers.
/// 9. Drafts persist with NULL number (no DRAFT_ persisted numbers).
AppDatabase openDb() {
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  return db;
}

/// System accounts for AccountingService (INSERT OR IGNORE — beforeOpen may
/// have seeded them already).
Future<void> seedAccounts(AppDatabase db) async {
  const codes = [
    ['1000', 'الصندوق', 'asset', 'debit'],
    ['1010', 'البنك', 'asset', 'debit'],
    ['1100', 'ذمم العملاء', 'asset', 'debit'],
    ['1200', 'المخزون', 'asset', 'debit'],
    ['4000', 'إيرادات المبيعات', 'revenue', 'credit'],
    ['4100', 'مردودات المبيعات', 'revenue', 'debit'],
    ['5000', 'تكلفة البضاعة', 'expense', 'debit'],
  ];
  for (final c in codes) {
    await db.customStatement(
      'INSERT OR IGNORE INTO accounts (id, code, name, type, normal_balance, '
      'is_system, is_active, created_at) VALUES '
      "('seed-${c[0]}', '${c[0]}', '${c[1]}', '${c[2]}', '${c[3]}', 1, 1, 1)",
    );
  }
}

Future<int> makeProduct(AppDatabase db, {int qty = 100}) {
  return db.productDao.insertProduct(
    ProductsCompanion.insert(
      name: 'صنف اختبار',
      price: 100,
      quantity: qty,
      costPrice: const Value(60),
    ),
  );
}

Future<CreateInvoiceResult> mkInvoice(
  AppDatabase db,
  int pid, {
  double total = 100,
  double paid = 100,
  String? customerId,
  String status = 'completed',
  String paymentMethod = 'cash',
  int qty = 1,
}) {
  return InvoiceService(db).createInvoice(
    customerId: customerId,
    customerName: customerId == null ? 'نقدي' : 'عميل آجل',
    paymentMethod: paymentMethod,
    totalAmount: total,
    paidAmount: paid,
    cashAmount: customerId == null ? paid : 0,
    status: status,
    items: [InvoiceItemParams(productId: pid, quantity: qty, price: total)],
  );
}

Future<List<String>> ledgerDescriptions(AppDatabase db) async {
  final rows = await db
      .customSelect('SELECT description FROM ledger_transactions')
      .get();
  return rows.map((r) => r.read<String>('description')).toList();
}

void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('InvoiceNumberService pure helpers', () {
    test('format zero-pads to 6 digits', () {
      expect(InvoiceNumberService.format(1), '000001');
      expect(InvoiceNumberService.format(42), '000042');
      expect(InvoiceNumberService.format(999999), '999999');
    });

    test('isCanonical accepts only 6 digits', () {
      expect(InvoiceNumberService.isCanonical('000001'), isTrue);
      expect(InvoiceNumberService.isCanonical('999999'), isTrue);
      expect(InvoiceNumberService.isCanonical(null), isFalse);
      expect(InvoiceNumberService.isCanonical(''), isFalse);
      expect(InvoiceNumberService.isCanonical('12345'), isFalse);
      expect(InvoiceNumberService.isCanonical('0002453'), isFalse);
      expect(InvoiceNumberService.isCanonical('INV1760000000000'), isFalse);
      expect(InvoiceNumberService.isCanonical('DRAFT_1'), isFalse);
      expect(InvoiceNumberService.isCanonical(' 000001'), isFalse);
    });

    test('description helpers use the canonical number verbatim', () {
      expect(InvoiceNumberService.saleDescription('000001'), 'فاتورة 000001');
      expect(InvoiceNumberService.paymentDescription('000001'), 'سداد 000001');
      expect(
        InvoiceNumberService.commissionDescription('000001'),
        'عمولة 000001',
      );
    });
  });

  group('sequential allocation', () {
    test('fresh DB: 000001 then 000002', () async {
      final db = openDb();
      await seedAccounts(db);
      final pid = await makeProduct(db);

      final a = await mkInvoice(db, pid);
      final b = await mkInvoice(db, pid);

      expect(a.invoice.invoiceNumber, '000001');
      expect(b.invoice.invoiceNumber, '000002');
    });

    test('caller-supplied invoiceNumber is ignored without preserve flag',
        () async {
      final db = openDb();
      await seedAccounts(db);
      final pid = await makeProduct(db);

      final res = await InvoiceService(db).createInvoice(
        customerId: null,
        customerName: 'نقدي',
        paymentMethod: 'cash',
        totalAmount: 100,
        paidAmount: 100,
        cashAmount: 100,
        status: 'completed',
        invoiceNumber: 'ZZZ-9',
        items: [InvoiceItemParams(productId: pid, quantity: 1, price: 100)],
      );
      expect(res.invoice.invoiceNumber, '000001');
    });

    test('restart persistence: reopen DB continues at 000003', () async {
      final dir = await Directory.systemTemp.createTemp('inv_num_restart_');
      final file = File('${dir.path}/pos.db');
      try {
        var db = AppDatabase(NativeDatabase(file));
        await seedAccounts(db);
        final pid = await makeProduct(db, qty: 1000);
        await mkInvoice(db, pid);
        await mkInvoice(db, pid);
        await db.close();

        db = AppDatabase(NativeDatabase(file));
        final pid2 = await makeProduct(db, qty: 1000);
        final c = await mkInvoice(db, pid2);
        expect(c.invoice.invoiceNumber, '000003');
        await db.close();
      } finally {
        if (file.existsSync()) file.deleteSync();
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      }
    });

    test('concurrent creates: N distinct sequential numbers, no duplicates',
        () async {
      final db = openDb();
      await seedAccounts(db);
      final pid = await makeProduct(db, qty: 1000);

      const n = 8;
      final results = await Future.wait(
        List.generate(n, (_) => mkInvoice(db, pid)),
      );
      final numbers =
          results.map((r) => r.invoice.invoiceNumber!).toList()..sort();

      expect(numbers.toSet().length, n, reason: 'zero duplicates');
      expect(
        numbers,
        List.generate(n, (i) => InvoiceNumberService.format(i + 1)),
      );
    });
  });

  group('legacy coexistence + preserve path', () {
    Future<void> seedLegacy(AppDatabase db) async {
      for (final num in const [
        'INV1760000000000',
        'DRAFT_999',
        'SALE-2026-0001',
        '000007',
      ]) {
        await db.invoiceDao.insertInvoice(
          InvoicesCompanion.insert(
            invoiceNumber: Value(num),
            customerName: const Value('قديم'),
            customerContact: const Value(''),
            date: Value(DateTime.now()),
            totalAmount: const Value(10),
            paidAmount: const Value(10),
            paymentMethod: const Value('cash'),
            status: const Value('completed'),
          ),
        );
      }
    }

    test('legacy rows coexist; new rows continue after max canonical',
        () async {
      final db = openDb();
      await seedAccounts(db);
      final pid = await makeProduct(db);
      await seedLegacy(db);

      final res = await mkInvoice(db, pid);
      expect(res.invoice.invoiceNumber, '000008');

      // Legacy numbers untouched.
      final legacy = await db.invoiceDao.getInvoiceByNumber('INV1760000000000');
      expect(legacy, isNotNull);
      final draft = await db.invoiceDao.getInvoiceByNumber('DRAFT_999');
      expect(draft, isNotNull);
    });

    test('duplicate canonical insert fails (partial unique index)', () async {
      final db = openDb();
      await seedAccounts(db);
      final pid = await makeProduct(db);
      await mkInvoice(db, pid); // 000001

      expect(
        () => db.invoiceDao.insertInvoice(
          InvoicesCompanion.insert(
            invoiceNumber: const Value('000001'),
            customerName: const Value('مكرر'),
            customerContact: const Value(''),
            date: Value(DateTime.now()),
            totalAmount: const Value(5),
            paidAmount: const Value(5),
            paymentMethod: const Value('cash'),
            status: const Value('completed'),
          ),
        ),
        throwsA(anything),
      );
    });

    test('preserve canonical: kept + sequence bumped past it', () async {
      final db = openDb();
      await seedAccounts(db);
      final pid = await makeProduct(db);

      final kept = await InvoiceService(db).createInvoice(
        customerId: null,
        customerName: 'نقدي',
        paymentMethod: 'cash',
        totalAmount: 50,
        paidAmount: 50,
        cashAmount: 50,
        status: 'completed',
        invoiceNumber: '000010',
        preserveInvoiceNumber: true,
        items: [InvoiceItemParams(productId: pid, quantity: 1, price: 50)],
      );
      expect(kept.invoice.invoiceNumber, '000010');

      final next = await mkInvoice(db, pid);
      expect(next.invoice.invoiceNumber, '000011');
    });

    test('preserve legacy id: kept, sequence unaffected', () async {
      final db = openDb();
      await seedAccounts(db);
      final pid = await makeProduct(db);

      final kept = await InvoiceService(db).createInvoice(
        customerId: null,
        customerName: 'نقدي',
        paymentMethod: 'cash',
        totalAmount: 50,
        paidAmount: 50,
        cashAmount: 50,
        status: 'completed',
        invoiceNumber: 'INV12345',
        preserveInvoiceNumber: true,
        items: [InvoiceItemParams(productId: pid, quantity: 1, price: 50)],
      );
      expect(kept.invoice.invoiceNumber, 'INV12345');

      final next = await mkInvoice(db, pid);
      expect(next.invoice.invoiceNumber, '000001');
    });

    test('preserve with empty/invalid value throws', () async {
      final db = openDb();
      await seedAccounts(db);
      final pid = await makeProduct(db);

      Future<CreateInvoiceResult> bad(String? number) =>
          InvoiceService(db).createInvoice(
            customerId: null,
            customerName: 'نقدي',
            paymentMethod: 'cash',
            totalAmount: 50,
            paidAmount: 50,
            cashAmount: 50,
            status: 'completed',
            invoiceNumber: number,
            preserveInvoiceNumber: true,
            items: [InvoiceItemParams(productId: pid, quantity: 1, price: 50)],
          );

      await expectLater(bad(''), throwsA(anything));
      await expectLater(bad(null), throwsA(anything));
      await expectLater(bad('?!'), throwsA(anything));
    });
  });

  group('edit / void / drafts', () {
    test('edit preserves the number', () async {
      final db = openDb();
      await seedAccounts(db);
      final pid = await makeProduct(db);
      final svc = InvoiceService(db);

      final created = await mkInvoice(db, pid, total: 100, paid: 100);
      expect(created.invoice.invoiceNumber, '000001');

      final updated = await svc.editInvoice(
        invoiceId: created.invoiceId,
        customerId: null,
        customerName: 'نقدي',
        paymentMethod: 'cash',
        totalAmount: 200,
        paidAmount: 200,
        cashAmount: 200,
        status: 'completed',
        items: [InvoiceItemParams(productId: pid, quantity: 2, price: 100)],
      );
      expect(updated.invoiceNumber, '000001');

      // Sequence kept moving only for creates: next create is 000002.
      final next = await mkInvoice(db, pid);
      expect(next.invoice.invoiceNumber, '000002');
    });

    test('void preserves the number and never recycles it', () async {
      final db = openDb();
      await seedAccounts(db);
      final pid = await makeProduct(db);
      final svc = InvoiceService(db);

      final a = await mkInvoice(db, pid);
      expect(a.invoice.invoiceNumber, '000001');
      await svc.voidInvoice(a.invoiceId, 'اختبار', 'admin');

      final voided = await svc.getInvoiceById(a.invoiceId);
      expect(voided!.status, 'voided');
      expect(voided.invoiceNumber, '000001');

      final b = await mkInvoice(db, pid);
      expect(b.invoice.invoiceNumber, '000002');
    });

    test('drafts persist with NULL number (no DRAFT_ numbers)', () async {
      final db = openDb();
      await seedAccounts(db);

      final draftId = await db.invoiceDao.insertInvoice(
        InvoicesCompanion.insert(
          customerName: const Value('مسودة'),
          customerContact: const Value(''),
          date: Value(DateTime.now()),
          totalAmount: const Value(100),
          paidAmount: const Value(0),
          paymentMethod: const Value('cash'),
          status: const Value('draft'),
        ),
      );
      final draft = await db.invoiceDao.getInvoiceById(draftId);
      expect(draft!.invoiceNumber, isNull);

      final pid = await makeProduct(db);
      final posted = await mkInvoice(db, pid);
      expect(posted.invoice.invoiceNumber, '000001');
    });
  });

  group('ledger descriptions + flavor independence', () {
    test('new sale/payment rows use the format helpers', () async {
      final db = openDb();
      await seedAccounts(db);
      final pid = await makeProduct(db);
      await db.customerDao.insertCustomer(
        CustomersCompanion.insert(id: 'C-1', name: 'عميل آجل'),
      );

      final res = await mkInvoice(
        db,
        pid,
        total: 200,
        paid: 50,
        customerId: 'C-1',
        paymentMethod: 'credit',
        status: 'partial',
      );
      final n = res.invoice.invoiceNumber!;
      expect(InvoiceNumberService.isCanonical(n), isTrue);

      final descs = await ledgerDescriptions(db);
      expect(descs, contains(InvoiceNumberService.saleDescription(n)));
      expect(descs, contains(InvoiceNumberService.paymentDescription(n)));
      // No historical timestamp-style wording for the new invoice.
      expect(descs.any((d) => d.contains('INV${res.invoiceId}')), isFalse);
    });

    test('new commission row uses the format helper', () async {
      final db = openDb();
      await seedAccounts(db);
      final pid = await makeProduct(db, qty: 50);
      await db.into(db.suppliers).insert(
            SuppliersCompanion.insert(id: 'SUP-1', name: 'مورّد'),
          );
      final shipId = await db.vegetableShipmentDao.insertShipment(
        VegetableShipmentsCompanion.insert(
          supplierId: 'SUP-1',
          shipmentNumber: 'S-1',
          date: Value(DateTime(2026, 1, 1)),
          pricingMode: ShipmentPricingMode.commission,
          totalBarnikaCount: 10,
          commissionPercentage: const Value(10),
          totalCost: 0,
          barnikaRemainingCount: 10,
        ),
      );

      final res = await InvoiceService(db).createInvoice(
        customerId: null,
        customerName: 'نقدي',
        paymentMethod: 'cash',
        totalAmount: 200,
        paidAmount: 200,
        cashAmount: 200,
        status: 'completed',
        items: [
          InvoiceItemParams(
            productId: pid,
            quantity: 2,
            price: 100,
            shipmentId: shipId,
          ),
        ],
      );
      final n = res.invoice.invoiceNumber!;

      final descs = await ledgerDescriptions(db);
      expect(descs, contains(InvoiceNumberService.commissionDescription(n)));
    });

    test('numbering is flavor-independent (pure 6-digit, no flavor input)',
        () async {
      final db = openDb();
      await seedAccounts(db);
      final pid = await makeProduct(db);

      // No flavor flag is set up or consulted anywhere in this flow.
      final res = await mkInvoice(db, pid);
      expect(res.invoice.invoiceNumber, matches(RegExp(r'^\d{6}$')));
    });
  });
}
