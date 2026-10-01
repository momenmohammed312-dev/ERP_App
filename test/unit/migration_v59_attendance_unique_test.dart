import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:sqlite3/sqlite3.dart';

int _seconds(DateTime value) => value.millisecondsSinceEpoch ~/ 1000;

Future<int> _schemaVersion(AppDatabase db) async {
  final row = await db.customSelect('PRAGMA user_version').getSingle();
  return row.read<int>('user_version');
}

Future<void> _expectDuplicateRejected(
  AppDatabase db, {
  required String staffId,
  required int date,
  required int createdAt,
}) async {
  await expectLater(
    db.customStatement(
      '''
      INSERT INTO attendance_table (
        staff_id,
        date,
        check_in_time,
        working_hours,
        status,
        overtime_hours,
        created_at,
        updated_at,
        source
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        staffId,
        date,
        date,
        0.0,
        'present',
        0.0,
        createdAt,
        createdAt,
        'device',
      ],
    ),
    throwsA(anything),
  );
}

void _createV58Fixture(
  File file, {
  required int dayKey,
  required int noonKey,
  required int manualCheckIn,
  required int manualCheckOut,
  required int deviceCheckIn,
  required int otherCheckIn,
  required int otherCheckOut,
  required int createdAt,
}) {
  final raw = sqlite3.open(file.path);
  try {
    raw.execute('PRAGMA foreign_keys = ON');

    raw.execute('''
      CREATE TABLE suppliers (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        phone TEXT,
        address TEXT,
        opening_balance REAL DEFAULT 0.0,
        created_at INTEGER,
        status TEXT DEFAULT 'Active'
      )
    ''');

    raw.execute('''
      CREATE TABLE customers (
        id TEXT NOT NULL PRIMARY KEY,
        name TEXT NOT NULL,
        phone TEXT,
        address TEXT,
        gstin_number TEXT,
        email TEXT,
        opening_balance REAL DEFAULT 0.0,
        total_debt REAL DEFAULT 0.0,
        total_paid REAL DEFAULT 0.0,
        created_at INTEGER,
        updated_at INTEGER,
        notes TEXT,
        is_active INTEGER DEFAULT 1,
        status TEXT DEFAULT 'Active'
      )
    ''');

    raw.execute('''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        price REAL NOT NULL,
        quantity INTEGER NOT NULL DEFAULT 0,
        barneka INTEGER NOT NULL DEFAULT 0,
        cost_price REAL,
        min_stock_level INTEGER DEFAULT 0,
        unit TEXT,
        category TEXT,
        barcode TEXT,
        status TEXT DEFAULT 'Active'
      )
    ''');

    raw.execute('''
      CREATE TABLE invoices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoice_number TEXT,
        customer_id TEXT,
        customer_name TEXT,
        customer_contact TEXT,
        customer_address TEXT,
        payment_method TEXT,
        total_amount REAL DEFAULT 0.0,
        paid_amount REAL DEFAULT 0.0,
        date INTEGER,
        status TEXT DEFAULT 'pending',
        voided_at INTEGER,
        void_reason TEXT,
        voided_by TEXT,
        cash_amount REAL DEFAULT 0.0,
        card_amount REAL DEFAULT 0.0,
        credit_amount REAL DEFAULT 0.0,
        shipment_id INTEGER,
        sync_id TEXT,
        created_at INTEGER,
        updated_at INTEGER
      )
    ''');

    raw.execute('''
      CREATE TABLE invoice_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        invoice_id INTEGER NOT NULL REFERENCES invoices(id),
        product_id INTEGER NOT NULL REFERENCES products(id),
        quantity INTEGER DEFAULT 1,
        ctn INTEGER,
        price REAL NOT NULL,
        discount REAL DEFAULT 0.0,
        commission REAL DEFAULT 0.0,
        unit_cost_at_time REAL,
        shipment_id INTEGER,
        sync_id TEXT,
        created_at INTEGER,
        updated_at INTEGER
      )
    ''');

    raw.execute('''
      CREATE TABLE ledger_transactions (
        id TEXT NOT NULL PRIMARY KEY,
        entity_type TEXT NOT NULL,
        ref_id TEXT NOT NULL,
        date INTEGER NOT NULL,
        description TEXT NOT NULL,
        debit REAL DEFAULT 0.0,
        credit REAL DEFAULT 0.0,
        origin TEXT NOT NULL,
        payment_method TEXT,
        receipt_number TEXT,
        lock_batch TEXT,
        created_at INTEGER NOT NULL
      )
    ''');

    raw.execute('''
      CREATE TABLE cash_sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        opened_by TEXT,
        opened_at INTEGER NOT NULL,
        closed_at INTEGER,
        status TEXT NOT NULL DEFAULT 'closed',
        opening_balance REAL NOT NULL DEFAULT 0.0,
        closing_balance REAL,
        closing_cash REAL,
        difference REAL,
        total_sales REAL NOT NULL DEFAULT 0.0,
        total_expenses REAL NOT NULL DEFAULT 0.0,
        notes TEXT,
        settlement_amount REAL
      )
    ''');

    raw.execute('''
      CREATE TABLE staff_table (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        staff_id TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        national_id TEXT,
        phone TEXT,
        email TEXT,
        address TEXT,
        position TEXT NOT NULL,
        department TEXT,
        employment_type TEXT NOT NULL,
        basic_salary REAL NOT NULL,
        hourly_rate REAL,
        hire_date INTEGER NOT NULL,
        contract_end_date INTEGER,
        status TEXT NOT NULL,
        bank_name TEXT,
        bank_account TEXT,
        emergency_contact TEXT,
        emergency_phone TEXT,
        notes TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        work_schedule_start TEXT,
        work_schedule_end TEXT,
        work_days TEXT,
        weekend_day TEXT,
        use_default_schedule INTEGER NOT NULL DEFAULT 1
      )
    ''');

    raw.execute('''
      CREATE TABLE biometric_devices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        device_code TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        vendor TEXT,
        model TEXT,
        connection_type TEXT NOT NULL,
        ip_address TEXT,
        port INTEGER,
        serial_number TEXT,
        location TEXT,
        auth_token TEXT,
        is_active INTEGER NOT NULL DEFAULT 1,
        last_sync_at INTEGER,
        last_sync_status TEXT,
        last_sync_error TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    raw.execute('''
      CREATE TABLE attendance_table (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        staff_id TEXT NOT NULL,
        date INTEGER NOT NULL,
        check_in_time INTEGER,
        check_out_time INTEGER,
        check_in_location TEXT,
        check_out_location TEXT,
        working_hours REAL,
        status TEXT NOT NULL,
        leave_type TEXT,
        notes TEXT,
        overtime_hours REAL NOT NULL DEFAULT 0,
        approved_by TEXT,
        approved_at INTEGER,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        source TEXT,
        source_device_id INTEGER,
        raw_event_id INTEGER,
        override_reason TEXT
      )
    ''');

    raw.execute('''
      CREATE TABLE attendance_raw_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        device_id INTEGER NOT NULL REFERENCES biometric_devices(id),
        external_user_id TEXT NOT NULL,
        event_time INTEGER NOT NULL,
        event_type TEXT,
        raw_payload TEXT,
        sync_batch_id TEXT,
        dedup_hash TEXT NOT NULL UNIQUE,
        status TEXT NOT NULL,
        matched_staff_id TEXT,
        resulting_attendance_id INTEGER,
        error_message TEXT,
        created_at INTEGER NOT NULL,
        processed_at INTEGER
      )
    ''');

    raw.execute(
      "INSERT INTO biometric_devices (id, device_code, name, connection_type, created_at, updated_at) "
      "VALUES (1, 'BIO-001', 'Migration Device', 'tcp_ip', ?, ?)",
      [createdAt, createdAt],
    );

    raw.execute(
      'INSERT INTO attendance_table '
      '(id, staff_id, date, check_in_time, check_out_time, working_hours, status, '
      'overtime_hours, created_at, updated_at, source) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        1,
        'STAFF-001',
        noonKey,
        manualCheckIn,
        manualCheckOut,
        0.0,
        'present',
        0.0,
        createdAt,
        createdAt,
        'manual',
      ],
    );

    raw.execute(
      'INSERT INTO attendance_table '
      '(id, staff_id, date, check_in_time, status, overtime_hours, '
      'created_at, updated_at, source, source_device_id, raw_event_id) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        2,
        'STAFF-001',
        dayKey,
        deviceCheckIn,
        'present',
        0.0,
        createdAt,
        createdAt,
        'device',
        1,
        10,
      ],
    );

    raw.execute(
      'INSERT INTO attendance_table '
      '(id, staff_id, date, check_in_time, status, overtime_hours, '
      'created_at, updated_at, source, source_device_id, raw_event_id) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        3,
        'STAFF-001',
        noonKey,
        noonKey,
        'present',
        0.0,
        createdAt,
        createdAt,
        'device',
        1,
        11,
      ],
    );

    raw.execute(
      'INSERT INTO attendance_table '
      '(id, staff_id, date, check_in_time, working_hours, status, overtime_hours, '
      'created_at, updated_at, source) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        4,
        'STAFF-001',
        dayKey,
        deviceCheckIn,
        10.5,
        'present',
        2.5,
        createdAt,
        createdAt,
        'device',
      ],
    );

    raw.execute(
      'INSERT INTO attendance_table '
      '(id, staff_id, date, check_in_time, check_out_time, working_hours, status, '
      'overtime_hours, created_at, updated_at, source) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        5,
        'STAFF-002',
        noonKey,
        otherCheckIn,
        otherCheckOut,
        8.0,
        'present',
        0.0,
        createdAt,
        createdAt,
        'manual',
      ],
    );

    raw.execute(
      'INSERT INTO attendance_raw_events '
      '(id, device_id, external_user_id, event_time, event_type, sync_batch_id, '
      'dedup_hash, status, matched_staff_id, resulting_attendance_id, '
      'created_at, processed_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        10,
        1,
        'EXT-001',
        deviceCheckIn,
        'check_in',
        'migration-batch',
        'migration-hash-1',
        'matched',
        'STAFF-001',
        2,
        createdAt,
        createdAt,
      ],
    );

    raw.execute(
      'INSERT INTO attendance_raw_events '
      '(id, device_id, external_user_id, event_time, event_type, sync_batch_id, '
      'dedup_hash, status, matched_staff_id, resulting_attendance_id, '
      'created_at, processed_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        11,
        1,
        'EXT-001',
        noonKey,
        'check_in',
        'migration-batch',
        'migration-hash-2',
        'matched',
        'STAFF-001',
        3,
        createdAt,
        createdAt,
      ],
    );

    raw.execute('PRAGMA user_version = 58');
  } finally {
    raw.dispose();
  }
}

void main() {
  // ─────────────────────────────────────────────────────────────────────────
  // DEFERRED (v72, 2026-09-28) — this whole suite is intentionally skipped.
  //
  // The v59 attendance-integrity migration is FROZEN and its uniqueness
  // constraint is NOT reinstated:
  //
  //   * it hard-DELETED every duplicate attendance row it decided to drop,
  //     which can destroy punches the moment keeper selection is wrong;
  //   * UNIQUE(staff_id, date) turns two rows for the same staff/date - which a
  //     device sync and a file import can legitimately produce - into a
  //     SqliteException, so the second punch is lost.
  //
  // schemaVersion is now 72 and `_runV59AttendanceIntegrity` is never called.
  // These tests assert behaviour that must NOT come back, so they are kept for
  // audit rather than rewritten to match the new schema.
  //
  // TO RE-ENABLE: keeper selection must first be validated against a COPY of
  // the real customer database, and this needs its own reviewed change plus a
  // proof that no already-paid payroll period references the rows removed.
  // ─────────────────────────────────────────────────────────────────────────
  // ignore: avoid_print
  print(
    'SKIPPED: migration_v59_attendance_unique_test.dart — the v59 destructive '
    'dedupe and UNIQUE(staff_id, date) are frozen by the v72 restoration. '
    'See the note above this main().',
  );

  TestWidgetsFlutterBinding.ensureInitialized();

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (MethodCall methodCall) async {
          final dir = Directory.systemTemp.createTempSync('attendance_v59_');
          return dir.path;
        },
      );

  test(
    'fresh v59 schema includes attendance backup audit',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final auditTable = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
            variables: [
              Variable.withString('attendance_v59_duplicate_backup'),
            ],
          )
          .getSingle();
      expect(
        auditTable.read<String>('name'),
        'attendance_v59_duplicate_backup',
      );

      final attendanceIndex = await db
          .customSelect(
            "SELECT sql FROM sqlite_master WHERE type = 'index' AND name = ?",
            variables: [Variable.withString('idx_attendance_staff_date')],
          )
          .getSingle();
      expect(
        attendanceIndex.read<String>('sql').toLowerCase(),
        contains('unique'),
      );
    },
    skip: 'Frozen by v72 — the v59 dedupe is destructive and must not return. '
        'See the note above main().',
  );

  test(
    'migration v58 to v59 normalizes and deduplicates attendance',
    () async {
    const staffId = 'STAFF-001';
    const otherStaffId = 'STAFF-002';
    final day = DateTime(2026, 1, 15);
    final dayKey = _seconds(day);
    final noonKey = _seconds(DateTime(2026, 1, 15, 12));
    final manualCheckIn = _seconds(DateTime(2026, 1, 15, 9));
    final manualCheckOut = _seconds(DateTime(2026, 1, 15, 18));
    final deviceCheckIn = _seconds(DateTime(2026, 1, 15, 8));
    final otherCheckIn = _seconds(DateTime(2026, 1, 15, 9));
    final otherCheckOut = _seconds(DateTime(2026, 1, 15, 17));
    final createdAt = dayKey;
    final tempDir = Directory.systemTemp.createTempSync(
      'attendance_v59_fixture_',
    );
    final file = File(
      '${tempDir.path}${Platform.pathSeparator}attendance_v59.db',
    );

    try {
      _createV58Fixture(
        file,
        dayKey: dayKey,
        noonKey: noonKey,
        manualCheckIn: manualCheckIn,
        manualCheckOut: manualCheckOut,
        deviceCheckIn: deviceCheckIn,
        otherCheckIn: otherCheckIn,
        otherCheckOut: otherCheckOut,
        createdAt: createdAt,
      );

      final db = AppDatabase(NativeDatabase(file));
      try {
        expect(await _schemaVersion(db), 59);

        final grouped = await db
            .customSelect(
              'SELECT staff_id, date, COUNT(*) AS row_count '
              'FROM attendance_table GROUP BY staff_id, date',
            )
            .get();
        expect(grouped, hasLength(2));
        expect(grouped.every((row) => row.read<int>('row_count') == 1), isTrue);
        expect(
          grouped.map((row) => row.read<int>('date')),
          everyElement(dayKey),
        );

        final rows = await db.select(db.attendanceTable).get();
        expect(rows, hasLength(2));
        final protected = rows.singleWhere((row) => row.staffId == staffId);
        final unaffected = rows.singleWhere(
          (row) => row.staffId == otherStaffId,
        );

        expect(protected.date, day);
        expect(protected.checkInTime, DateTime(2026, 1, 15, 9));
        expect(protected.checkOutTime, DateTime(2026, 1, 15, 18));
        expect(protected.source, 'manual');
        expect(protected.workingHours, 10.5);
        expect(protected.overtimeHours, 2.5);
        expect(unaffected.date, day);
        expect(unaffected.checkInTime, DateTime(2026, 1, 15, 9));
        expect(unaffected.checkOutTime, DateTime(2026, 1, 15, 17));
        expect(unaffected.source, 'manual');

        final rawRows = await db.select(db.attendanceRawEvents).get();
        final repointed = rawRows
            .where((row) => row.id == 10 || row.id == 11)
            .toList();
        expect(repointed, hasLength(2));
        expect(
          repointed.map((row) => row.resultingAttendanceId),
          everyElement(protected.id),
        );

        final backupCount = await db
            .customSelect(
              'SELECT COUNT(*) AS loser_count '
              'FROM attendance_v59_duplicate_backup',
            )
            .getSingle();
        expect(backupCount.read<int>('loser_count'), 4);

        final backupRows = await db
            .customSelect(
              'SELECT original_id, payload_json '
              'FROM attendance_v59_duplicate_backup',
            )
            .get();
        final keeperPayload =
            jsonDecode(
                  backupRows
                      .singleWhere(
                        (row) => row.read<int>('original_id') == protected.id,
                      )
                      .read<String>('payload_json'),
                )
                as Map<String, dynamic>;
        expect(keeperPayload['workingHours'], 0.0);
        expect(keeperPayload['overtimeHours'], 0.0);

        final indexRows = await db
            .customSelect(
              "SELECT sql FROM sqlite_master "
              "WHERE type = 'index' AND tbl_name = 'attendance_table'",
            )
            .get();
        expect(
          indexRows.any((row) {
            final sql = row.data['sql']?.toString().toLowerCase() ?? '';
            return sql.contains('unique') &&
                sql.contains('staff_id') &&
                sql.contains('date');
          }),
          isTrue,
        );

        await _expectDuplicateRejected(
          db,
          staffId: staffId,
          date: dayKey,
          createdAt: createdAt,
        );
        expect((await db.select(db.attendanceTable).get()), hasLength(2));
      } finally {
        await db.close();
      }

      final reopened = AppDatabase(NativeDatabase(file));
      try {
        expect(await _schemaVersion(reopened), 59);
        final integrity = await reopened
            .customSelect('PRAGMA integrity_check')
            .getSingle();
        expect(integrity.read<String>('integrity_check'), 'ok');
        expect(
          (await reopened.select(reopened.attendanceTable).get()),
          hasLength(2),
        );
        await _expectDuplicateRejected(
          reopened,
          staffId: staffId,
          date: dayKey,
          createdAt: createdAt,
        );
        await reopened.customStatement(
          'DROP TABLE attendance_v59_duplicate_backup',
        );
      } finally {
        await reopened.close();
      }

      final repaired = AppDatabase(NativeDatabase(file));
      try {
        final auditTable = await repaired
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
              variables: [
                Variable.withString('attendance_v59_duplicate_backup'),
              ],
            )
            .getSingle();
        expect(
          auditTable.read<String>('name'),
          'attendance_v59_duplicate_backup',
        );
      } finally {
        await repaired.close();
      }
    } finally {
      if (file.existsSync()) {
        file.deleteSync();
      }
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    }
    },
    skip: 'Frozen by v72 — the v59 dedupe is destructive and must not return. '
        'See the note above main().',
  );
}
