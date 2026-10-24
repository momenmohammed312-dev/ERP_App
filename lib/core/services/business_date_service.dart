import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';

class BusinessDateService {
  final AppDatabase db;

  BusinessDateService(this.db);

  /// Opens a new cash session and records it in the ledger
  Future<void> openSession({
    required String openedBy,
    required double openingBalance,
  }) async {
    return db.transaction(() async {
      // 1. Create Cash Session record
      final session = await db.cashSessionDao.openCashSession(
        openedBy: openedBy,
        openingBalance: openingBalance,
      );

      // 2. Also open a day record in the days table (used by all other pages)
      try {
        await db.dayDao.openDay(
          openingBalance: openingBalance,
          openedBy: openedBy,
        );
      } catch (e) {
        debugPrint('BusinessDateService.openSession: dayDao.openDay failed: $e');
      }

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

  /// Closes the current cash session, calculates totals, and records in ledger
  Future<void> closeSession({
    required int sessionId,
    required double actualCash,
    String? notes,
  }) async {
    return db.transaction(() async {
      // 1. Fetch session and transactions
      final session = await (db.select(db.cashSessions)
            ..where((t) => t.id.equals(sessionId)))
          .getSingle();

      if (session.status != 'open') throw Exception('Session is already closed');

      final now = DateTime.now();

      // 2. Calculate Expected Balance
      // Cash figures come from the invoices/expenses tables (mirrors the
      // day-close settlement). The ledger double-books a cash sale as
      // sale-debit + payment-credit, which cancels to zero.
      final invoices = await db.invoiceDao.getInvoicesForCashSession(
        session.openedAt,
        now,
      );
      double income = 0;
      for (final invoice in invoices) {
        income += _calculateInvoiceCashIncome(invoice);
      }
      // المرتجعات اللي اتستردت نقداً بتخرج من الدرج — من غير السطر ده،
      // يوم الإغلاق بيقول الرصيد صح وانت ناقصك قيمة كل مرتجع نقدي.
      final cashRefunds = await db.returnRefundsDao.getCashRefundsForSessionBetween(
        session.openedAt,
        now,
      );
      income -= cashRefunds;
      final expenseItems = await db.expenseDao.getCashExpensesForSession(
        session.openedAt,
        now,
      );
      double expenses = 0;
      for (final e in expenseItems) {
        expenses += e.amount;
      }

      // [MONEY] حركات العُهد النقدية: الصرف يخرج نقد من الدرج، والتسوية أو الإلغاء ترد المتبقي.
      final custodyMovements = await _getCustodyCashMovementBetween(
        session.openedAt,
        now,
      );

      double expectedBalance =
          session.openingBalance + income - expenses - custodyMovements.netOutflow;
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

      // 4. Also close the day in the days table
      try {
        final todayDay = await db.dayDao.getTodayDay();
        if (todayDay != null) {
          await db.dayDao.closeDay(
            dayId: todayDay['id'] as int,
            closingBalance: actualCash,
            notes: notes,
            closedBy: session.openedBy,
          );
        }
      } catch (e) {
        debugPrint('BusinessDateService.closeSession: dayDao.closeDay failed: $e');
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
    final invoices = await db.invoiceDao.getInvoicesForCashSession(
      session.openedAt,
      now,
    );
    double income = 0;
    for (final invoice in invoices) {
      income += _calculateInvoiceCashIncome(invoice);
    }
    final expenseItems = await db.expenseDao.getCashExpensesForSession(
      session.openedAt,
      now,
    );
    double expenses = 0;
    for (final e in expenseItems) {
      expenses += e.amount;
    }
    // نفس منطق closeSession: المرتجع النقدي بخصم من المتوقع.
    income -= await db.returnRefundsDao.getCashRefundsForSessionBetween(
      session.openedAt,
      now,
    );
    // [MONEY] نفس منطق closeSession: صافي حركات العُهد النقدية (صرف - رد).
    final custodyMovements = await _getCustodyCashMovementBetween(
      session.openedAt,
      now,
    );
    return session.openingBalance +
        income -
        expenses -
        custodyMovements.netOutflow;
  }

  /// [MONEY] حساب دقيق للمتحصلات النقدية الفعلية من الفاتورة التي دخلت درج الكاش.
  /// يعالج بدقة طرق الدفع الإلكترونية والمختلطة وفواتير الآجل مع الدفعات المقدمة.
  double _calculateInvoiceCashIncome(Invoice invoice) {
    if (invoice.cashAmount > 0) {
      if (invoice.cashAmount > invoice.totalAmount &&
          invoice.paymentMethod == 'cash' &&
          invoice.totalAmount > 0) {
        return invoice.totalAmount;
      }
      return invoice.cashAmount;
    } else if (invoice.cardAmount > 0 && invoice.cashAmount == 0) {
      return 0.0;
    } else {
      final pm = invoice.paymentMethod?.toLowerCase().trim();
      if (pm == 'cash' || pm == 'نقدي' || pm == 'نقداً') {
        return invoice.totalAmount;
      } else if (pm == 'credit' || pm == null || pm.isEmpty) {
        return invoice.paidAmount;
      } else if ([
        'visa',
        'mastercard',
        'card',
        'bank',
        'transfer',
        'wallet',
        'instapay',
        'other',
        'split',
      ].contains(pm)) {
        return 0.0;
      } else {
        return 0.0;
      }
    }
  }

  /// [MONEY] صافي خروج النقدية للعهد بين تاريخين (صرف العهد − رد العهد).
  /// صرف العهدة يخرج نقداً من الدرج (debit)، والتسوية أو الإلغاء يرد المتبقي للدرج (credit).
  /// يعتمد على [createdAt] لضمان عدم اختفاء حركة العهدة عند تعديل [date] عبر DocumentDateService.
  Future<({double disbursed, double returned, double netOutflow})>
      _getCustodyCashMovementBetween(
    DateTime from,
    DateTime to,
  ) async {
    final rows = await (db.select(db.ledgerTransactions)
          ..where((t) =>
              t.origin.equals('custody') &
              t.paymentMethod.equals('cash') &
              ((t.createdAt.isNotNull() & t.createdAt.isBetweenValues(from, to)) |
                  (t.createdAt.isNull() & t.date.isBetweenValues(from, to)))))
        .get();

    double disbursed = 0.0;
    double returned = 0.0;
    for (final row in rows) {
      disbursed += row.debit;
      returned += row.credit;
    }
    return (
      disbursed: disbursed,
      returned: returned,
      netOutflow: disbursed - returned,
    );
  }
}
