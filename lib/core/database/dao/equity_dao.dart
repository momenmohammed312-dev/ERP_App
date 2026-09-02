import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/partners_table.dart';
import '../tables/equity_transactions_table.dart';

part 'equity_dao.g.dart';

@DriftAccessor(tables: [Partners, EquityTransactions])
class EquityDao extends DatabaseAccessor<AppDatabase> with _$EquityDaoMixin {
  EquityDao(super.db);

  // ── Partners ──

  Future<List<Partner>> getAllPartners() => select(partners).get();

  Future<List<Partner>> getActivePartners() =>
      (select(partners)..where((p) => p.isActive.equals(true))).get();

  Future<Partner?> getPartnerById(String id) =>
      (select(partners)..where((p) => p.id.equals(id))).getSingleOrNull();

  Stream<List<Partner>> watchAllPartners() => select(partners).watch();

  Future<int> insertPartner(PartnersCompanion entry) => into(partners).insert(entry);

  Future<bool> updatePartner(Partner partner) => update(partners).replace(partner);

  Future<int> updatePartnerCompanion(PartnersCompanion c) =>
      (update(partners)..where((p) => p.id.equals(c.id.value))).write(c);

  Future<int> deletePartner(String id) => (delete(partners)..where((p) => p.id.equals(id))).go();

  // ── EquityTransactions ──

  Future<List<EquityTransaction>> getAllEquityTransactions() =>
      (select(equityTransactions)..orderBy([(e) => OrderingTerm.desc(e.date)])).get();

  Future<List<EquityTransaction>> getTransactionsForPartner(String partnerId) =>
      (select(equityTransactions)
            ..where((e) => e.partnerId.equals(partnerId))
            ..orderBy([(e) => OrderingTerm.desc(e.date)]))
          .get();

  Stream<List<EquityTransaction>> watchAllEquityTransactions() =>
      (select(equityTransactions)..orderBy([(e) => OrderingTerm.desc(e.date)])).watch();

  Stream<List<EquityTransaction>> watchForPartner(String partnerId) =>
      (select(equityTransactions)..where((e) => e.partnerId.equals(partnerId))).watch();

  Future<EquityTransaction?> getEquityTransactionById(String id) =>
      (select(equityTransactions)..where((e) => e.id.equals(id))).getSingleOrNull();

  Future<int> insertEquityTransaction(EquityTransactionsCompanion entry) =>
      into(equityTransactions).insert(entry);

  Future<bool> updateEquityTransaction(EquityTransaction tx) => update(equityTransactions).replace(tx);

  Future<int> deleteEquityTransaction(String id) =>
      (delete(equityTransactions)..where((e) => e.id.equals(id))).go();

  // ── Aggregates ──

  Future<double> getPartnerBalance(String partnerId) async {
    final txs = await getTransactionsForPartner(partnerId);
    double bal = 0;
    for (final t in txs) {
      switch (t.type) {
        case 'opening_capital':
        case 'capital_contribution':
        case 'profit_allocation':
          bal += t.amount;
          break;
        case 'withdrawal':
          bal -= t.amount;
          break;
      }
    }
    return bal;
  }

  Future<double> getTotalEquity() async {
    final txs = await getAllEquityTransactions();
    double bal = 0;
    for (final t in txs) {
      switch (t.type) {
        case 'opening_capital':
        case 'capital_contribution':
        case 'profit_allocation':
          bal += t.amount;
          break;
        case 'withdrawal':
          bal -= t.amount;
          break;
      }
    }
    return bal;
  }
}
