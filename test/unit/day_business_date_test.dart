import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/services/business_date_service.dart';

/// Single authoritative day state (`days` table) + guarded sessions.
///
/// Proves:
/// 1. `isBusinessDayOpen()` is true iff ANY days row is open (badge + gate).
/// 2. `openSession` throws (Arabic, stale-aware) BEFORE creating anything —
///    no partial day/session/ledger rows on the second open.
/// 3. `closeSession` closes the OPEN row (even a stale one), not "today".
/// 4. Day-close failure rolls back the session close (atomicity).
/// 5. `reopenDay` refuses when another day is open (V45 index = backstop).
/// 6. A second open cash session is forbidden; legacy multiples throw loudly
///    via `assertSingleOpenSession` while `getCurrentSession` keeps
///    latest-wins for display.
AppDatabase openDb() {
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  return db;
}

int unixSeconds(DateTime dt) => dt.millisecondsSinceEpoch ~/ 1000;

Future<int> sessionCount(AppDatabase db) async {
  final row = await db
      .customSelect('SELECT COUNT(*) AS c FROM cash_sessions')
      .getSingle();
  return row.read<int>('c');
}

Future<int> dayCount(AppDatabase db) async {
  final row =
      await db.customSelect('SELECT COUNT(*) AS c FROM days').getSingle();
  return row.read<int>('c');
}

void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('BusinessDateService — authoritative day state', () {
    test('fresh DB: day closed, no session', () async {
      final db = openDb();
      final svc = BusinessDateService(db);

      expect(await svc.isBusinessDayOpen(), isFalse);
      expect(await svc.getCurrentSession(), isNull);
      expect(await svc.isSessionOpen(), isFalse);
    });

    test('openSession creates day + session + ledger opening atomically',
        () async {
      final db = openDb();
      final svc = BusinessDateService(db);

      await svc.openSession(openedBy: 'admin', openingBalance: 500);

      expect(await svc.isBusinessDayOpen(), isTrue);
      expect(await svc.isSessionOpen(), isTrue);
      expect(await sessionCount(db), 1);
      expect(await dayCount(db), 1);

      final openings = await db
          .customSelect(
            "SELECT COUNT(*) AS c FROM ledger_transactions WHERE origin = 'opening'",
          )
          .getSingle();
      expect(openings.read<int>('c'), 1);
    });

    test('second openSession throws same-date error and creates nothing',
        () async {
      final db = openDb();
      final svc = BusinessDateService(db);
      await svc.openSession(openedBy: 'admin', openingBalance: 500);

      expect(
        () => svc.openSession(openedBy: 'admin', openingBalance: 100),
        throwsA(
          predicate(
            (e) =>
                e.toString().contains('يوجد يوم مفتوح بالفعل') &&
                !e.toString().contains('بتاريخ قديم'),
          ),
        ),
      );

      // Nothing partial: still exactly one day, one session, one opening.
      expect(await sessionCount(db), 1);
      expect(await dayCount(db), 1);
      final openings = await db
          .customSelect(
            "SELECT COUNT(*) AS c FROM ledger_transactions WHERE origin = 'opening'",
          )
          .getSingle();
      expect(openings.read<int>('c'), 1);
    });

    test('openSession with stale open day reports the old date', () async {
      final db = openDb();
      final svc = BusinessDateService(db);
      final yesterday = DateTime.now().subtract(const Duration(days: 2));

      await db.customInsert(
        'INSERT INTO days (date, is_open, opening_balance, created_at) '
        'VALUES (?, ?, ?, ?)',
        variables: [
          Variable.withDateTime(yesterday),
          Variable.withBool(true),
          Variable.withReal(100),
          Variable.withDateTime(yesterday),
        ],
      );

      expect(await svc.isBusinessDayOpen(), isTrue);
      expect(
        () => svc.openSession(openedBy: 'admin', openingBalance: 50),
        throwsA(predicate((e) => e.toString().contains('بتاريخ قديم'))),
      );
      expect(await sessionCount(db), 0);
      expect(await dayCount(db), 1);
    });

    test('closeSession closes the OPEN (stale) row, not today', () async {
      final db = openDb();
      final svc = BusinessDateService(db);
      final yesterday = DateTime.now().subtract(const Duration(days: 2));

      await db.customInsert(
        'INSERT INTO days (date, is_open, opening_balance, created_at) '
        'VALUES (?, ?, ?, ?)',
        variables: [
          Variable.withDateTime(yesterday),
          Variable.withBool(true),
          Variable.withReal(100),
          Variable.withDateTime(yesterday),
        ],
      );
      // Session opened now (no day guard inside openCashSession by design —
      // the BusinessDateService guard is the single gate).
      final session = await db.cashSessionDao.openCashSession(
        openedBy: 'admin',
        openingBalance: 100,
      );

      await svc.closeSession(sessionId: session.id, actualCash: 120);

      expect(await svc.isBusinessDayOpen(), isFalse);
      expect(await svc.isSessionOpen(), isFalse);
      // The stale row (id 1) is the one that closed; no new day row appeared.
      final stale = await db.customSelect(
        'SELECT is_open FROM days WHERE id = 1',
      ).getSingle();
      expect(stale.read<int>('is_open'), 0);
      expect(await dayCount(db), 1);
    });

    test('closeSession failure rolls back the session close (atomic)',
        () async {
      final db = openDb();
      final svc = BusinessDateService(db);
      await svc.openSession(openedBy: 'admin', openingBalance: 500);
      final session = await svc.getCurrentSession();

      // Sabotage the day-close step mid-transaction: without `days`, the
      // authoritative close must fail — and the session must stay open.
      await db.customStatement('DROP TABLE days');

      await expectLater(
        svc.closeSession(sessionId: session!.id, actualCash: 500),
        throwsA(anything),
      );

      final status = await db
          .customSelect('SELECT status FROM cash_sessions WHERE id = 1')
          .getSingle();
      expect(status.read<String>('status'), 'open');
    });

    test('closeSession on missing/closed session throws, day untouched',
        () async {
      final db = openDb();
      final svc = BusinessDateService(db);
      await svc.openSession(openedBy: 'admin', openingBalance: 500);

      await expectLater(
        svc.closeSession(sessionId: 9999, actualCash: 1),
        throwsA(anything),
      );
      expect(await svc.isBusinessDayOpen(), isTrue);

      final session = await svc.getCurrentSession();
      await svc.closeSession(sessionId: session!.id, actualCash: 500);
      await expectLater(
        svc.closeSession(sessionId: session.id, actualCash: 500),
        throwsA(predicate((e) => e.toString().contains('already closed'))),
      );
    });

    test('reopenDay refuses while another day is open', () async {
      final db = openDb();

      await db.dayDao.openDay(openingBalance: 100, openedBy: 'admin');
      final open = await db.dayDao.getOpenDay();
      // A second, already-closed row.
      final closedId = await db.customInsert(
        'INSERT INTO days (date, is_open, opening_balance, created_at) '
        'VALUES (?, ?, ?, ?)',
        variables: [
          Variable.withDateTime(DateTime.now()),
          Variable.withBool(false),
          Variable.withReal(0),
          Variable.withDateTime(DateTime.now()),
        ],
      );

      expect(
        () => db.dayDao.reopenDay(dayId: closedId, reopenedBy: 'admin'),
        throwsA(predicate((e) => e.toString().contains('يوجد يوم مفتوح'))),
      );

      // After closing the open day, reopen works.
      await db.dayDao.closeDay(
        dayId: open!['id'] as int,
        closingBalance: 100,
        closedBy: 'admin',
      );
      await db.dayDao.reopenDay(dayId: closedId, reopenedBy: 'admin');
      final nowOpen = await db.dayDao.getOpenDay();
      expect(nowOpen!['id'], closedId);
    });

    test('second openCashSession is forbidden', () async {
      final db = openDb();
      await db.cashSessionDao.openCashSession(openedBy: 'a');

      expect(
        () => db.cashSessionDao.openCashSession(openedBy: 'b'),
        throwsA(predicate((e) => e.toString().contains('مفتوحة بالفعل'))),
      );
      expect((await db.cashSessionDao.getOpenSessions()).length, 1);
    });

    test('legacy multiple open sessions throw loudly, latest still readable',
        () async {
      final db = openDb();
      final nowSec = unixSeconds(DateTime.now());
      // Bypass the guard with raw SQL to simulate pre-v70 duplicates.
      await db.customStatement(
        "INSERT INTO cash_sessions (opened_by, opened_at, status, opening_balance) "
        'VALUES (\'a\', $nowSec, \'open\', 0)',
      );
      await db.customStatement(
        "INSERT INTO cash_sessions (opened_by, opened_at, status, opening_balance) "
        'VALUES (\'b\', ${nowSec + 1}, \'open\', 0)',
      );

      expect(
        () => db.cashSessionDao.assertSingleOpenSession(),
        throwsA(predicate((e) => e.toString().contains('جلسات صندوق مفتوحة'))),
      );
      // Latest-wins read kept for display only.
      final current = await db.cashSessionDao.getCurrentSession();
      expect(current, isNotNull);

      // openSession refuses to hide the multiples.
      final svc = BusinessDateService(db);
      expect(
        () => svc.openSession(openedBy: 'c', openingBalance: 10),
        throwsA(predicate((e) => e.toString().contains('جلسات صندوق مفتوحة'))),
      );
    });

    test('badge/gate read days, not the session (no silent divergence)',
        () async {
      final db = openDb();
      final svc = BusinessDateService(db);

      // Day open, session closed/absent: authority says OPEN.
      await db.dayDao.openDay(openingBalance: 10, openedBy: 'admin');
      expect(await svc.isBusinessDayOpen(), isTrue);
      expect(await svc.isSessionOpen(), isFalse);

      // Day closed, stale open session row: authority says CLOSED.
      final open = await db.dayDao.getOpenDay();
      await db.dayDao.closeDay(
        dayId: open!['id'] as int,
        closingBalance: 10,
        closedBy: 'admin',
      );
      await db.cashSessionDao.openCashSession(openedBy: 'admin');
      expect(await svc.isBusinessDayOpen(), isFalse);
      expect(await svc.isSessionOpen(), isTrue);
    });
  });
}
