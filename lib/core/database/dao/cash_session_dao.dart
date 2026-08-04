import 'package:drift/drift.dart';

import '../tables/cash_session_table.dart';
import '../app_database.dart';

part 'cash_session_dao.g.dart';

@DriftAccessor(tables: [CashSessions])
class CashSessionDao extends DatabaseAccessor<AppDatabase>
    with _$CashSessionDaoMixin {
  CashSessionDao(super.db);

  Future<List<CashSession>> getAllSessions() => select(cashSessions).get();

  Future<CashSession?> getCurrentSession() =>
      (select(cashSessions)
            ..orderBy([(tbl) => OrderingTerm.desc(tbl.openedAt)])
            ..limit(1))
          .getSingleOrNull();

  Future<CashSession> openCashSession({
    required String openedBy,
    double openingBalance = 0.0,
  }) async {
    final companion = CashSessionsCompanion.insert(
      openedBy: Value(openedBy),
      openedAt: DateTime.now(),
      status: Value('open'),
      openingBalance: Value(openingBalance),
    );

    final id = await into(cashSessions).insert(companion);
    return await (select(
      cashSessions,
    )..where((tbl) => tbl.id.equals(id))).getSingle();
  }

  /// Closes a cash session. The extra settlement values (expected/actual cash,
  /// difference, notes, optional settlement amount) persist in existing
  /// columns on [CashSessions] — all parameters are optional so existing
  /// callers are unaffected.
  Future<bool> closeCashSession(
    int sessionId, {
    double? expectedBalance,
    double? actualCash,
    double? difference,
    String? notes,
    double? settlementAmount,
  }) async {
    final result =
        await (update(
          cashSessions,
        )..where((tbl) => tbl.id.equals(sessionId))).write(
          CashSessionsCompanion(
            closedAt: Value(DateTime.now()),
            status: const Value('closed'),
            closingBalance: expectedBalance != null
                ? Value(expectedBalance)
                : const Value.absent(),
            closingCash: actualCash != null ? Value(actualCash) : const Value.absent(),
            difference: difference != null ? Value(difference) : const Value.absent(),
            notes: notes != null ? Value(notes) : const Value.absent(),
            settlementAmount: settlementAmount != null
                ? Value(settlementAmount)
                : const Value.absent(),
          ),
        );
    return result > 0;
  }

  Future<bool> isCashOpen() async {
    final session = await getCurrentSession();
    return session != null && session.status == 'open';
  }
}
