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

      // 2. Record opening balance in General Ledger
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
      // Fetch all cash transactions since openedAt
      final transactions = await db.ledgerDao.getAllTransactionsByDateRange(
        session.openedAt,
        now,
      );

      // Calculate Cash Income and Expenses
      // Note: We only care about CASH method here for drawer balancing
      final cashTxs = transactions.where((t) => t.paymentMethod == 'cash' || t.entityType == 'Cash');
      
      double income = 0;
      double expenses = 0;

      for (var tx in cashTxs) {
        if (tx.origin == 'opening') continue; // Don't double count opening
        income += tx.debit;
        expenses += tx.credit;
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

      // 4. Record closing in Ledger
      await db.ledgerDao.insertTransaction(
        LedgerTransactionsCompanion.insert(
          id: '${DateTime.now().millisecondsSinceEpoch}_session_close_$sessionId',
          entityType: 'Cash',
          refId: 'session_$sessionId',
          date: now,
          description: 'إغلاق صندوق (جلسة #$sessionId) - عجز/زيادة: ${difference.toStringAsFixed(2)}',
          debit: const Value(0.0),
          credit: Value(actualCash), // Moving cash out of "Active Drawer"
          origin: 'closing',
          paymentMethod: const Value('cash'),
        ),
      );
    });
  }

  Future<CashSession?> getCurrentSession() => db.cashSessionDao.getCurrentSession();
  
  Future<bool> isSessionOpen() => db.cashSessionDao.isCashOpen();
}
