import '../../database/app_database.dart';

class EquityPartnerRow {
  final Partner partner;
  final double opening;
  final double contributions;
  final double profitAllocations;
  final double withdrawals;
  final double closing;

  EquityPartnerRow({
    required this.partner,
    required this.opening,
    required this.contributions,
    required this.profitAllocations,
    required this.withdrawals,
    required this.closing,
  });
}

class EquityStatementData {
  final DateTime from;
  final DateTime to;
  final List<EquityPartnerRow> partners;
  final double totalOpening;
  final double totalContributions;
  final double totalProfitAllocations;
  final double totalWithdrawals;
  final double totalClosing;

  EquityStatementData({
    required this.from,
    required this.to,
    required this.partners,
    required this.totalOpening,
    required this.totalContributions,
    required this.totalProfitAllocations,
    required this.totalWithdrawals,
    required this.totalClosing,
  });
}

class EquityStatementService {
  final AppDatabase _db;
  EquityStatementService(this._db);

  Future<EquityStatementData> getStatement({required DateTime from, required DateTime to}) async {
    final partners = await _db.equityDao.getAllPartners();
    final allTxs = await _db.equityDao.getAllEquityTransactions();

    final rows = <EquityPartnerRow>[];
    double tOpening = 0, tContrib = 0, tProfit = 0, tWithdraw = 0, tClosing = 0;

    for (final p in partners) {
      double opening = 0, contrib = 0, profit = 0, withdraw = 0;
      for (final tx in allTxs.where((t) => t.partnerId == p.id)) {
        if (tx.date.isBefore(from)) {
          // Opening includes everything before from
          switch (tx.type) {
            case 'opening_capital':
            case 'capital_contribution':
            case 'profit_allocation':
              opening += tx.amount;
              break;
            case 'withdrawal':
              opening -= tx.amount;
              break;
          }
        } else if (!tx.date.isAfter(to)) {
          switch (tx.type) {
            case 'capital_contribution':
              contrib += tx.amount;
              break;
            case 'profit_allocation':
              profit += tx.amount;
              break;
            case 'withdrawal':
              withdraw += tx.amount;
              break;
            case 'opening_capital':
              // If opening_capital falls inside range, treat as contribution
              contrib += tx.amount;
              break;
          }
        }
      }
      final closing = opening + contrib + profit - withdraw;
      tOpening += opening;
      tContrib += contrib;
      tProfit += profit;
      tWithdraw += withdraw;
      tClosing += closing;
      rows.add(EquityPartnerRow(
        partner: p,
        opening: opening,
        contributions: contrib,
        profitAllocations: profit,
        withdrawals: withdraw,
        closing: closing,
      ));
    }

    return EquityStatementData(
      from: from,
      to: to,
      partners: rows,
      totalOpening: tOpening,
      totalContributions: tContrib,
      totalProfitAllocations: tProfit,
      totalWithdrawals: tWithdraw,
      totalClosing: tClosing,
    );
  }
}
