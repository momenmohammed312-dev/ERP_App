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

  /// Every session with status = 'open' (oldest first). More than one is a
  /// legacy anomaly: [getCurrentSession] keeps its latest-wins read for
  /// display, but open/close flows must go through [assertSingleOpenSession]
  /// so multiples can never hide.
  Future<List<CashSession>> getOpenSessions() =>
      (select(cashSessions)
            ..where((tbl) => tbl.status.equals('open'))
            ..orderBy([(tbl) => OrderingTerm.asc(tbl.openedAt)]))
          .get();

  /// Returns the unique open session, or null when none is open.
  /// Throws when several sessions are open at once — the caller must surface
  /// this for manual repair instead of silently acting on the latest row.
  Future<CashSession?> assertSingleOpenSession() async {
    final open = await getOpenSessions();
    if (open.length > 1) {
      throw Exception(
        'توجد ${open.length} جلسات صندوق مفتوحة في نفس الوقت — يلزم مراجعة يدوية قبل المتابعة',
      );
    }
    return open.isEmpty ? null : open.first;
  }

  Future<CashSession> openCashSession({
    required String openedBy,
    double openingBalance = 0.0,
  }) async {
    // Forbid a second open session: only one cash session may be open.
    final alreadyOpen = await getOpenSessions();
    if (alreadyOpen.isNotEmpty) {
      throw Exception('توجد جلسة صندوق مفتوحة بالفعل — أغلقها أولاً');
    }
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
