import 'package:drift/drift.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';

class BusinessDateService {
  final AppDatabase db;

  BusinessDateService(this.db);

  /// Single authoritative day-state read: true when ANY `days` row has
  /// `is_open = 1` (same-date or stale). Both the cashier badge and the
  /// invoice gate must use this method so the two can never diverge.
  Future<bool> isBusinessDayOpen() => db.dayDao.isDayOpen();

  /// The authoritative open day row (oldest first), or null when closed.
  Future<Map<String, Object?>?> getOpenDay() => db.dayDao.getOpenDay();

  /// Opens a new business day: one `days` row + one cash session + the ledger
  /// opening entry, all in a single transaction. Any failure rolls everything
  /// back and propagates (never swallowed, never reported as success).
  ///
  /// Guards run BEFORE creating anything: when an open day already exists the
  /// error distinguishes a stale-date day from a same-date one.
  Future<void> openSession({
    required String openedBy,
    required double openingBalance,
  }) async {
    // Fail loudly on legacy duplicate open sessions instead of hiding them.
    await db.cashSessionDao.assertSingleOpenSession();

    // Days are authoritative: the day guard comes before the session guard.
    final openDay = await db.dayDao.getOpenDay();
    if (openDay != null) {
      throw Exception(await _openDayConflictMessage());
    }

    final openSessions = await db.cashSessionDao.getOpenSessions();
    if (openSessions.isNotEmpty) {
      throw Exception('توجد جلسة صندوق مفتوحة بالفعل — أغلقها أولاً');
    }

    return db.transaction(() async {
      // 1. Create Cash Session record (re-guarded inside: throws on 2nd open)
      final session = await db.cashSessionDao.openCashSession(
        openedBy: openedBy,
        openingBalance: openingBalance,
      );

      // 2. Open the authoritative day row (re-guarded inside; failure here
      //    rolls back the session row too — no rethrow swallowed).
      await db.dayDao.openDay(
        openingBalance: openingBalance,
        openedBy: openedBy,
      );

      // 3. Record opening balance in General Ledger
      await db.ledgerDao.insertTransaction(
        LedgerTransactionsCompanion.insert(
          id: '${DateTime.now().millisecondsSinceEpoch}_session_open_${session.id}',
          entityType: 'Cash',
          refId: 'session_${session.id}',
          date: DateTime.now(),
          description: 'فتح صندوق - رصيد افتتاحي (جلسة #${session.id})',
          debit: Value(openingBalance),
          credit: const Value(0.0),
          origin: 'opening',
          paymentMethod: const Value('cash'),
        ),
      );
    });
  }

  /// Arabic conflict message for [openSession]: names the stale open date when
  /// the open day is not from today. Compares integer day-bounds in Dart
  /// (drift stores DateTime as unix seconds; the `date` column name collides
  /// with SQLite's date() function, so no SQL date math is used here).
  Future<String> _openDayConflictMessage() async {
    try {
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day);
      final s = start.millisecondsSinceEpoch ~/ 1000;
      final row = await db
          .customSelect(
            'SELECT date AS d FROM days WHERE is_open = 1 '
            'AND (date < ? OR date >= ?) ORDER BY id ASC LIMIT 1',
            variables: [Variable.withInt(s), Variable.withInt(s + 86400)],
          )
          .getSingleOrNull();
      final v = row?.data['d'];
      DateTime? dt;
      if (v is int) {
        dt = DateTime.fromMillisecondsSinceEpoch(v * 1000);
      } else if (v is DateTime) {
        dt = v;
      }
      if (dt != null) {
        final ds = '${dt.year.toString().padLeft(4, '0')}-'
            '${dt.month.toString().padLeft(2, '0')}-'
            '${dt.day.toString().padLeft(2, '0')}';
        return 'يوجد يوم مفتوح بتاريخ قديم ($ds) — أغلقه أولاً قبل فتح يوم جديد';
      }
    } catch (_) {
      // Fall through to the generic message; the guard itself still throws.
    }
    return 'يوجد يوم مفتوح بالفعل — أغلقه أولاً قبل فتح يوم جديد';
  }

  /// Closes the current cash session, calculates totals, and records in ledger.
  /// The AUTHORITATIVE open `days` row (queried by `is_open = 1`, not "today's"
  /// row) is closed in the same transaction: if the day-close fails, the whole
  /// transaction — including the session close — rolls back.
  /// Settlement math below is unchanged.
  Future<void> closeSession({
    required int sessionId,
    required double actualCash,
    String? notes,
  }) async {
    return db.transaction(() async {
      // Fail loudly on legacy duplicate open sessions instead of hiding them.
      await db.cashSessionDao.assertSingleOpenSession();

      // 1. Fetch session and transactions
      final session = await (db.select(db.cashSessions)
            ..where((t) => t.id.equals(sessionId)))
          .getSingleOrNull();
      if (session == null) throw Exception('الجلسة غير موجودة');
      if (session.status != 'open') throw Exception('Session is already closed');

      final now = DateTime.now();

      // 2. Calculate Expected Balance
      // Cash figures come from the invoices/expenses tables (mirrors the
      // day-close settlement). The ledger double-books a cash sale as
      // sale-debit + payment-credit, which cancels to zero.
      final invoices = await db.invoiceDao.getInvoicesByDateRange(
        session.openedAt,
        now,
      );
      double income = 0;
      for (final invoice in invoices) {
        if (invoice.paymentMethod == 'cash') {
          income += invoice.totalAmount;
        } else {
          income += invoice.paidAmount;
        }
      }
      final expenseItems = await db.expenseDao.getExpensesByDateRange(
        session.openedAt,
        now,
      );
      double expenses = 0;
      for (final e in expenseItems) {
        expenses += e.amount;
      }

      double expectedBalance = session.openingBalance + income - expenses;
      double difference = actualCash - expectedBalance;

      // 3. Update Cash Session Record
      await (db.update(db.cashSessions)
            ..where((t) => t.id.equals(sessionId)))
          .write(
        CashSessionsCompanion(
          closedAt: Value(now),
          status: const Value('closed'),
          closingBalance: Value(expectedBalance),
          closingCash: Value(actualCash),
          difference: Value(difference),
          totalSales: Value(income),
          totalExpenses: Value(expenses),
          notes: Value(notes),
        ),
      );

      // 4. Close the AUTHORITATIVE open day row (is_open = 1, oldest first) —
      //    not "today's" row, so a stale open day is the one that closes.
      //    No try/catch: a day-close failure fails the whole transaction and
      //    the session must not close.
      final openDay = await db.dayDao.getOpenDay();
      if (openDay != null) {
        await db.dayDao.closeDay(
          dayId: openDay['id'] as int,
          closingBalance: actualCash,
          notes: notes,
          closedBy: session.openedBy,
        );
      }

      // 5. Record closing in Ledger
      await db.ledgerDao.insertTransaction(
        LedgerTransactionsCompanion.insert(
          id: '${DateTime.now().millisecondsSinceEpoch}_session_close_$sessionId',
          entityType: 'Cash',
          refId: 'session_$sessionId',
          date: now,
          description: 'إغلاق صندوق (جلسة #$sessionId) - عجز/زيادة: ${difference.toStringAsFixed(2)}',
          debit: const Value(0.0),
          credit: Value(actualCash),
          origin: 'closing',
          paymentMethod: const Value('cash'),
        ),
      );
    });
  }

  Future<CashSession?> getCurrentSession() => db.cashSessionDao.getCurrentSession();
  
  Future<bool> isSessionOpen() => db.cashSessionDao.isCashOpen();

  /// صافي الكاش المتوقع للجلسة المفتوحة حالياً (لسه ما اتقفلتش).
  /// نفس منطق الحساب الموجود في [closeSession] بالظبط: رصيد افتتاحي
  /// + كاش وارد − كاش صادر من بداية الجلسة حتى الآن، من غير origin = 'opening'.
  /// لو مفيش جلسة مفتوحة بترجع 0.
  Future<double> getExpectedCash() async {
    final session = await getCurrentSession();
    if (session == null || session.status != 'open') return 0.0;

    final now = DateTime.now();
    final invoices = await db.invoiceDao.getInvoicesByDateRange(
      session.openedAt,
      now,
    );
    double income = 0;
    for (final invoice in invoices) {
      if (invoice.paymentMethod == 'cash') {
        income += invoice.totalAmount;
      } else {
        income += invoice.paidAmount;
      }
    }
    final expenseItems = await db.expenseDao.getExpensesByDateRange(
      session.openedAt,
      now,
    );
    double expenses = 0;
    for (final e in expenseItems) {
      expenses += e.amount;
    }
    return session.openingBalance + income - expenses;
  }
}
