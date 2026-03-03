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

  Future<bool> closeCashSession(int sessionId) async {
    final result =
        await (update(
          cashSessions,
        )..where((tbl) => tbl.id.equals(sessionId))).write(
          CashSessionsCompanion(
            closedAt: Value(DateTime.now()),
            status: const Value('closed'),
          ),
        );
    return result > 0;
  }

  Future<bool> isCashOpen() async {
    final session = await getCurrentSession();
    return session != null && session.status == 'open';
  }
}
