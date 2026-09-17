import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:sqlite3/sqlite3.dart';

/// Forward migration v70 (never rewrites V42..V69 or existing numbers).
///
/// Builds a minimal v69 database the way it existed before v70 (days WITHOUT
/// the V42 audit columns, duplicate open days, legacy + canonical invoice
/// numbers, no sequence table), opens it via AppDatabase, and proves:
/// 1. user_version advances 69 → 70.
/// 2. V42 days columns are added only if missing.
/// 3. V44 trigger + V45 partial index exist and actually enforce single-open.
/// 4. Duplicate open days reconcile to the oldest (flag-only, rows kept).
/// 5. Sequence table seeded from max(canonical)+1; existing numbers untouched.
/// 6. Canonical partial unique index exists; duplicates now fail.
/// 7. Migration log records the v70 step; reopen is idempotent.
Future<File> buildV69Db({
  required List<String> invoiceNumbers,
  int openDays = 2,
}) async {
  final dbPath =
      '${Directory.systemTemp.path}/pos_v70_${DateTime.now().microsecondsSinceEpoch}_${invoiceNumbers.length}_${openDays}.db';
  final file = File(dbPath);
  if (file.existsSync()) file.deleteSync();

  // Epoch seconds (drift stores DateTime as unix seconds).
  const tClosed = 1726000000;
  const tOpen1 = 1726086400;
  const tOpen2 = 1726172800;

  final raw = sqlite3.open(dbPath);
  try {
    raw.execute('PRAGMA foreign_keys = OFF');

    raw.execute('''
      CREATE TABLE customers (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL
      )
    ''');

    // Pre-v42 days: no opened_by / closed_by / reopened_at / reopened_by.
    raw.execute('''
      CREATE TABLE days (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date INTEGER NOT NULL,
        is_open INTEGER NOT NULL DEFAULT 0,
        opening_balance REAL DEFAULT 0.0,
        closing_balance REAL,
        notes TEXT,
        created_at INTEGER,
        closed_at INTEGER
      )
    ''');

    raw.execute('''
      CREATE TABLE invoices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoice_number TEXT,
        customer_id TEXT,
        customer_name TEXT,
        total_amount REAL DEFAULT 0.0,
        paid_amount REAL DEFAULT 0.0,
        date INTEGER,
        status TEXT DEFAULT 'pending'
      )
    ''');

    raw.execute(
      "INSERT INTO customers (id, name) VALUES ('cust-1', 'عميل اختبار')",
    );
    raw.execute(
      'INSERT INTO days (date, is_open, opening_balance, created_at) '
      'VALUES ($tClosed, 0, 100.0, $tClosed)',
    );
    for (var i = 0; i < openDays; i++) {
      final t = i == 0 ? tOpen1 : tOpen2;
      raw.execute(
        'INSERT INTO days (date, is_open, opening_balance, created_at) '
        'VALUES ($t, 1, ${500 + i * 100}.0, $t)',
      );
    }
    for (final n in invoiceNumbers) {
      if (n == 'NULL') {
        raw.execute(
          "INSERT INTO invoices (invoice_number, customer_name, status) "
          "VALUES (NULL, 'x', 'draft')",
        );
      } else {
        raw.execute(
          "INSERT INTO invoices (invoice_number, customer_name, status) "
          "VALUES ('$n', 'x', 'completed')",
        );
      }
    }

    raw.execute('PRAGMA user_version = 69');
  } finally {
    raw.dispose();
  }
  return file;
}

Future<int> userVersion(AppDatabase db) async {
  final row = await db.customSelect('PRAGMA user_version').getSingle();
  return row.read<int>('user_version');
}

Future<Set<String>> columnNames(AppDatabase db, String table) async {
  final rows = await db.customSelect('PRAGMA table_info($table)').get();
  return rows.map((r) => r.read<String>('name')).toSet();
}

Future<bool> indexExists(AppDatabase db, String name) async {
  final rows = await db
      .customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'index' AND name = ?",
        variables: [Variable.withString(name)],
      )
      .get();
  return rows.isNotEmpty;
}

Future<bool> triggerExists(AppDatabase db, String name) async {
  final rows = await db
      .customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'trigger' AND name = ?",
        variables: [Variable.withString(name)],
      )
      .get();
  return rows.isNotEmpty;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (MethodCall methodCall) async {
          final dir = Directory.systemTemp.createTempSync('drift_test_');
          return dir.path;
        },
      );

  group('v70 forward migration + repair', () {
    test('repairs days, reconciles dupes, seeds sequence, keeps numbers',
        () async {
      final file = await buildV69Db(
        invoiceNumbers: const [
          'INV1760000000000',
          'DRAFT_999',
          '000003',
          '000007',
          'SALE-2026-0001',
          'NULL',
        ],
      );
      final db = AppDatabase(NativeDatabase(file));
      try {
        // 1. Version advances.
        expect(await userVersion(db), 71);

        // 2. V42 columns repaired.
        final dayCols = await columnNames(db, 'days');
        expect(
          dayCols,
          containsAll(['opened_by', 'closed_by', 'reopened_at', 'reopened_by']),
        );

        // 3. Trigger + backstop index exist.
        expect(await triggerExists(db, 'trg_prevent_multi_open'), isTrue);
        expect(await indexExists(db, 'idx_days_one_open'), isTrue);

        // 4. Duplicate opens reconciled: exactly 1 left (oldest, id 2 —
        //    id 1 is the closed row), all 3 rows preserved.
        final openRows = await db
            .customSelect('SELECT id FROM days WHERE is_open = 1')
            .get();
        expect(openRows.length, 1);
        expect(openRows.first.read<int>('id'), 2);
        final totalDays = await db
            .customSelect('SELECT COUNT(*) AS c FROM days')
            .getSingle();
        expect(totalDays.read<int>('c'), 3);

        // 5. Sequence seeded from max(canonical)+1 = 8.
        final seq = await db
            .customSelect(
              'SELECT next_value FROM invoice_number_sequence WHERE id = 1',
            )
            .getSingle();
        expect(seq.read<int>('next_value'), 8);

        // 6. Canonical partial unique index exists.
        expect(
          await indexExists(db, 'idx_invoices_canonical_number'),
          isTrue,
        );

        // 7. Existing numbers byte-identical (never rewritten).
        final nums = await db
            .customSelect('SELECT invoice_number AS n FROM invoices ORDER BY id')
            .get();
        expect(
          nums.map((r) => r.data['n']).toList(),
          ['INV1760000000000', 'DRAFT_999', '000003', '000007',
            'SALE-2026-0001', null],
        );

        // 8. Migration log records v70 completion.
        final log = await db
            .customSelect(
              "SELECT status FROM _migration_log WHERE version = 70 "
              "AND step = 'v70_repair_numbering' ORDER BY id DESC LIMIT 1",
            )
            .getSingle();
        expect(log.read<String>('status'), 'completed');

        // 9. Guards are live: second open day + dup canonical both fail.
        await expectLater(
          db.customStatement(
            'INSERT INTO days (date, is_open, opening_balance, created_at) '
            'VALUES (1726259200, 1, 0, 1726259200)',
          ),
          throwsA(anything),
        );
        await expectLater(
          db.customStatement(
            "INSERT INTO invoices (invoice_number, status) VALUES ('000003', 'completed')",
          ),
          throwsA(anything),
        );
        // …while legacy duplicates and NULLs still insert fine.
        await db.customStatement(
          "INSERT INTO invoices (invoice_number, status) VALUES ('INV1760000000000-dup', 'completed')",
        );
        await db.customStatement(
          "INSERT INTO invoices (invoice_number, status) VALUES (NULL, 'draft')",
        );
      } finally {
        await db.close();
        if (file.existsSync()) file.deleteSync();
      }
    });

    test('sequence seeds at 1 when no canonical rows exist', () async {
      final file = await buildV69Db(
        invoiceNumbers: const ['INV1', 'DRAFT_2'],
        openDays: 0,
      );
      final db = AppDatabase(NativeDatabase(file));
      try {
        expect(await userVersion(db), 71);
        final seq = await db
            .customSelect(
              'SELECT next_value FROM invoice_number_sequence WHERE id = 1',
            )
            .getSingle();
        expect(seq.read<int>('next_value'), 1);

        // Zero or one open days: nothing reconciled, nothing broken.
        final openRows = await db
            .customSelect('SELECT COUNT(*) AS c FROM days WHERE is_open = 1')
            .getSingle();
        expect(openRows.read<int>('c'), 0);
      } finally {
        await db.close();
        if (file.existsSync()) file.deleteSync();
      }
    });

    test('reopen is idempotent (no double-repair, version stable)', () async {
      final file = await buildV69Db(
        invoiceNumbers: const ['000003'],
      );
      var db = AppDatabase(NativeDatabase(file));
      try {
        expect(await userVersion(db), 71);
      } finally {
        await db.close();
      }

      db = AppDatabase(NativeDatabase(file));
      try {
        expect(await userVersion(db), 71);
        final openRows = await db
            .customSelect('SELECT id FROM days WHERE is_open = 1')
            .get();
        expect(openRows.length, 1);
        expect(openRows.first.read<int>('id'), 2);
        final seq = await db
            .customSelect(
              'SELECT next_value FROM invoice_number_sequence WHERE id = 1',
            )
            .getSingle();
        // Seeded once from max(canonical)+1 = 4; reopen must not reseed.
        expect(seq.read<int>('next_value'), 4);
      } finally {
        await db.close();
        if (file.existsSync()) file.deleteSync();
      }
    });
  });
}
