import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/services/invoice_service.dart';
import 'package:pos_offline_desktop/core/services/ledger_service.dart';
import 'package:pos_offline_desktop/core/services/vegetable_market_import_service.dart';

/// Orchestrator integration fixes (post-agent handoffs):
/// 1. `LedgerService.editCustomerPayment` recomputes the invoice header from
///    ALL sibling payments (multi-payment invoices), syncs the matching
///    `invoice_payments` row, and rejects overpay edits.
/// 2. Import derives paid/partial/pending from amounts (no status collapse)
///    and writes legacy-styled descriptions for non-canonical IMP numbers.
/// 3. v71 forward migration: accounts dedup + UNIQUE(code), supplier legacy
///    opening-row dedup (auto-created `<uuid>_opening` mirrors only).
/// 4. Admin "مدين" filter rule == ledger truth (debtor set from
///    `getAllCustomerBalances`, balance > 0).
AppDatabase openDb() {
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  return db;
}

Future<void> seedCustomer(AppDatabase db, String id, String name) =>
    db.into(db.customers).insert(CustomersCompanion.insert(id: id, name: name));

Future<int> seedProduct(AppDatabase db) => db.productDao.insertProduct(
      ProductsCompanion.insert(name: 'صنف تكامل', price: 100, quantity: 500),
    );

Future<LedgerTransaction> paymentTxn(
  AppDatabase db,
  int invoiceId, {
  double? credit,
}) async {
  final rows =
      await db.ledgerDao.getTransactionsByReceiptNumber('INV$invoiceId');
  final pays = rows.where((r) => r.origin == 'payment').toList();
  if (credit != null) {
    return pays.firstWhere((r) => (r.credit - credit).abs() < 0.005);
  }
  return pays.first;
}

void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('editCustomerPayment multi-payment recompute', () {
    test('edits one of two payments: header = siblings + new amount',
        () async {
      final db = openDb();
      await seedCustomer(db, 'C-9', 'عميل متعدد الدفعات');
      final p = await seedProduct(db);
      final created = await InvoiceService(db).createInvoice(
        customerId: 'C-9',
        customerName: 'عميل متعدد الدفعات',
        paymentMethod: 'credit',
        totalAmount: 1000,
        paidAmount: 300,
        status: 'partial',
        items: [InvoiceItemParams(productId: p, quantity: 10, price: 100)],
      );
      final id = created.invoiceId;
      await InvoiceService(db).recordInvoicePayment(
        invoiceId: id,
        amount: 200,
        paymentMethod: 'cash',
      );
      var inv = await db.invoiceDao.getInvoiceById(id);
      expect(inv!.paidAmount, 500);

      final second = await paymentTxn(db, id, credit: 200);
      await LedgerService(db).editCustomerPayment(
        transactionId: second.id,
        newAmount: 400,
        date: DateTime.now(),
        paymentMethod: 'cash',
      );

      inv = await db.invoiceDao.getInvoiceById(id);
      expect(inv!.paidAmount, 700);
      expect(inv.status, 'partial');
      final edited =
          await db.ledgerDao.getTransactionById(second.id);
      expect(edited!.credit, 400);
      // invoice_payments split rows follow the ledger edit (300 + 400).
      final paySum = await db.invoicePaymentsDao.getTotalPaidForInvoice(id);
      expect(paySum, 700);
    });

    test('overpay edit throws and writes nothing', () async {
      final db = openDb();
      await seedCustomer(db, 'C-10', 'عميل تجاوز');
      final p = await seedProduct(db);
      final created = await InvoiceService(db).createInvoice(
        customerId: 'C-10',
        customerName: 'عميل تجاوز',
        paymentMethod: 'credit',
        totalAmount: 500,
        paidAmount: 400,
        status: 'partial',
        items: [InvoiceItemParams(productId: p, quantity: 5, price: 100)],
      );
      final id = created.invoiceId;
      final pay = await paymentTxn(db, id);
      await expectLater(
        LedgerService(db).editCustomerPayment(
          transactionId: pay.id,
          newAmount: 600,
          date: DateTime.now(),
          paymentMethod: 'cash',
        ),
        throwsException,
      );
      final inv = await db.invoiceDao.getInvoiceById(id);
      expect(inv!.paidAmount, 400);
      expect(inv.status, 'partial');
    });
  });

  group('import status derivation + legacy descriptions', () {
    test('deriveImportStatus: pending/partial/paid', () {
      expect(
        VegetableMarketImportService.deriveImportStatus(total: 1000, paid: 0),
        'pending',
      );
      expect(
        VegetableMarketImportService.deriveImportStatus(total: 1000, paid: 400),
        'partial',
      );
      expect(
        VegetableMarketImportService.deriveImportStatus(
            total: 1000, paid: 1000),
        'paid',
      );
      expect(
        VegetableMarketImportService.deriveImportStatus(
            total: 1000, paid: 999.995),
        'paid',
      );
    });

    test('partial import sale keeps partial status + legacy wording',
        () async {
      final db = openDb();
      final payload = jsonEncode({
        'customers': [],
        'sales': [
          {
            'customerId': 'C-IMP',
            'customerName': 'عميل استيراد',
            'date': '2026-09-01T10:00:00.000',
            'quantity': 4,
            'pricePerUnit': 250.0,
            'totalAmount': 1000.0,
            'paidAmount': 400.0,
            'cashAmount': 400.0,
            'creditAmount': 600.0,
            'paymentMethod': 'credit',
          },
        ],
      });
      await VegetableMarketImportService(db).importFromJsonString(payload);

      final invoices = await (db.select(db.invoices)).get();
      expect(invoices.length, 1);
      expect(invoices.first.status, 'partial');
      expect(invoices.first.paidAmount, 400);
      final num = invoices.first.invoiceNumber!;
      expect(num.startsWith('IMP-'), isTrue);

      final rows = await db.ledgerDao
          .getTransactionsByReceiptNumber('INV${invoices.first.id}');
      final sale = rows.firstWhere((r) => r.origin == 'sale');
      final pay = rows.firstWhere((r) => r.origin == 'payment');
      // Legacy wording for non-canonical numbers (never 'فاتورة IMP-...').
      expect(sale.description, 'بيع #$num');
      expect(pay.description, 'دفع #$num');
      expect(
        rows.any((r) => r.description.startsWith('فاتورة IMP-')),
        isFalse,
      );
      final payRows = await db.invoicePaymentsDao
          .getPaymentsForInvoice(invoices.first.id);
      expect(payRows.length, 1);
      expect(payRows.first.amount, 400);
    });
  });

  group('v71 forward migration', () {
    test('dedups accounts, enforces UNIQUE(code), dedups supplier openings',
        () async {
      final path =
          '${Directory.systemTemp.path}/pos_v71_${DateTime.now().microsecondsSinceEpoch}.db';
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
      final raw = sqlite3.open(path);
      try {
        raw.execute('PRAGMA foreign_keys = OFF');
        raw.execute('''
          CREATE TABLE accounts (
            id TEXT PRIMARY KEY,
            code TEXT NOT NULL,
            name TEXT NOT NULL,
            type TEXT NOT NULL,
            normal_balance TEXT NOT NULL,
            parent_id TEXT,
            is_system INTEGER NOT NULL DEFAULT 0,
            is_active INTEGER NOT NULL DEFAULT 1,
            created_at INTEGER NOT NULL
          )
        ''');
        raw.execute('''
          CREATE TABLE suppliers (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            phone TEXT,
            address TEXT,
            opening_balance REAL DEFAULT 0.0,
            created_at INTEGER,
            status TEXT DEFAULT 'Active'
          )
        ''');
        raw.execute('''
          CREATE TABLE ledger_transactions (
            id TEXT PRIMARY KEY,
            entity_type TEXT NOT NULL,
            ref_id TEXT NOT NULL,
            date INTEGER NOT NULL,
            description TEXT NOT NULL,
            origin TEXT NOT NULL,
            credit REAL DEFAULT 0.0,
            debit REAL DEFAULT 0.0,
            created_at INTEGER NOT NULL
          )
        ''');
        raw.execute('''
          CREATE TABLE journal_lines (
            id TEXT PRIMARY KEY,
            account_id TEXT NOT NULL
          )
        ''');
        // Duplicate system code: survivor must be the is_system row (A-OLD).
        raw.execute(
          "INSERT INTO accounts (id, code, name, type, normal_balance, is_system, is_active, created_at) "
          "VALUES ('A-OLD', '1000', 'الصندوق', 'asset', 'debit', 1, 1, 1000)",
        );
        raw.execute(
          "INSERT INTO accounts (id, code, name, type, normal_balance, is_system, is_active, created_at) "
          "VALUES ('A-DUP', '1000', 'صندوق مكرر', 'asset', 'debit', 0, 1, 2000)",
        );
        raw.execute(
          "INSERT INTO journal_lines (id, account_id) VALUES ('J-1', 'A-DUP')",
        );
        // Supplier with legacy dual-written opening (column + mirror txn).
        raw.execute(
          "INSERT INTO suppliers (id, name, opening_balance, created_at, status) "
          "VALUES ('S-1', 'مورد افتتاحي', 500.0, 1726000000, 'Active')",
        );
        raw.execute(
          "INSERT INTO ledger_transactions (id, entity_type, ref_id, date, description, origin, credit, debit, created_at) "
          "VALUES ('abc-123_opening', 'Supplier', 'S-1', 1726000000, 'رصيد افتتاحي', 'opening', 500.0, 0.0, 1726000000)",
        );
        // Manual opening row without the auto pattern — must be kept.
        raw.execute(
          "INSERT INTO ledger_transactions (id, entity_type, ref_id, date, description, origin, credit, debit, created_at) "
          "VALUES ('manual-1', 'Supplier', 'S-1', 1726000000, 'يدوي', 'opening', 120.0, 0.0, 1726000000)",
        );
        // Orphan auto-pattern row (supplier gone) — must be kept.
        raw.execute(
          "INSERT INTO ledger_transactions (id, entity_type, ref_id, date, description, origin, credit, debit, created_at) "
          "VALUES ('gone-9_opening', 'Supplier', 'S-GONE', 1726000000, 'يتيم', 'opening', 50.0, 0.0, 1726000000)",
        );
        raw.execute('PRAGMA user_version = 70');
      } finally {
        raw.dispose();
      }

      final db = AppDatabase(NativeDatabase(file));
      try {
        final ver = await db
            .customSelect('PRAGMA user_version')
            .getSingle();
        expect(ver.read<int>('user_version'), 71);

        // One row per code; survivor is the system row; journal repointed.
        final accs = await db.customSelect(
          "SELECT id FROM accounts WHERE code = '1000'",
        ).get();
        expect(accs.length, 1);
        expect(accs.first.read<String>('id'), 'A-OLD');
        final jl = await db.customSelect(
          "SELECT account_id AS a FROM journal_lines WHERE id = 'J-1'",
        ).getSingle();
        expect(jl.read<String>('a'), 'A-OLD');
        final idx = await db.customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'index' "
          "AND name = 'idx_accounts_code'",
        ).get();
        expect(idx.isNotEmpty, isTrue);

        // Mirror opening removed; manual + orphan kept.
        final txs = await db.customSelect(
          "SELECT id FROM ledger_transactions WHERE entity_type = 'Supplier' "
          "AND origin = 'opening' ORDER BY id",
        ).get();
        expect(
          txs.map((r) => r.read<String>('id')).toList(),
          ['gone-9_opening', 'manual-1'],
        );
        // Supplier balance now counts the opening exactly once (500 + 120).
        expect(await db.ledgerDao.getSupplierBalance('S-1'), 620.0);

        // Migration log records v71 completion.
        final log = await db.customSelect(
          "SELECT status FROM _migration_log WHERE version = 71 "
          "AND step = 'v71_accounts_supplier_opening' "
          "ORDER BY id DESC LIMIT 1",
        ).getSingle();
        expect(log.read<String>('status'), 'completed');
      } finally {
        await db.close();
        if (file.existsSync()) file.deleteSync();
      }
    });
  });

  group('admin debtor filter rule == ledger truth', () {
    test('debtor set from balances matches per-customer sign', () async {
      final db = openDb();
      await seedCustomer(db, 'C-D1', 'مدين');
      await seedCustomer(db, 'C-D2', 'مسدد');
      final p = await seedProduct(db);
      Future<void> sell(String cid, double total, double paid) =>
          InvoiceService(db).createInvoice(
            customerId: cid,
            customerName: cid,
            paymentMethod: 'credit',
            totalAmount: total,
            paidAmount: paid,
            status: paid >= total ? 'paid' : 'partial',
            items: [InvoiceItemParams(productId: p, quantity: 1, price: total)],
          );
      await sell('C-D1', 800, 100);
      await sell('C-D2', 500, 500);

      // Exact rule used by the admin 'مدين' filter.
      final balances = await db.ledgerDao.getAllCustomerBalances();
      final debtorIds = {
        for (final b in balances)
          if (((b['balance'] as num?)?.toDouble() ?? 0.0) > 0.005)
            b['id'] as String,
      };
      expect(debtorIds, contains('C-D1'));
      expect(debtorIds, isNot(contains('C-D2')));
      expect(await db.ledgerDao.getCustomerBalance('C-D1'), 700.0);
      expect(await db.ledgerDao.getCustomerBalance('C-D2'), 0.0);
    });
  });
}
