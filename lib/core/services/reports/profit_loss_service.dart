import '../../database/app_database.dart';

class ProfitLossData {
  final DateTime from;
  final DateTime to;
  final double revenue;
  final double salesReturns;
  final double netRevenue;
  final double cogs;
  final double grossProfit;
  final double operatingExpenses;
  final double netProfit;
  final Map<String, double> expensesByCategory; // for future breakdown

  ProfitLossData({
    required this.from,
    required this.to,
    required this.revenue,
    required this.salesReturns,
    required this.netRevenue,
    required this.cogs,
    required this.grossProfit,
    required this.operatingExpenses,
    required this.netProfit,
    required this.expensesByCategory,
  });
}

class ProfitLossService {
  final AppDatabase _db;
  ProfitLossService(this._db);

  Future<ProfitLossData> getProfitLoss({required DateTime from, required DateTime to}) async {
    final accounts = await _db.accountsDao.getAllAccounts();
    Future<double> balInRange(String code) async {
      final acc = accounts.where((a) => a.code == code).firstOrNull;
      if (acc == null) return 0;
      return _getAccountBalanceInRange(acc.id, from, to);
    }

    final revenue = -await balInRange('4000'); // credit normal -> - (debit-credit)
    final returns = await balInRange('4100'); // debit normal -> positive
    final netRevenue = revenue - returns;
    final cogs = await balInRange('5000');
    final grossProfit = netRevenue - cogs;
    final operatingExpenses = await balInRange('5100');
    final netProfit = grossProfit - operatingExpenses;

    return ProfitLossData(
      from: from,
      to: to,
      revenue: revenue,
      salesReturns: returns,
      netRevenue: netRevenue,
      cogs: cogs,
      grossProfit: grossProfit,
      operatingExpenses: operatingExpenses,
      netProfit: netProfit,
      expensesByCategory: {'5100': operatingExpenses},
    );
  }

  Future<double> _getAccountBalanceInRange(String accountId, DateTime from, DateTime to) async {
    final lines = await (_db.select(_db.journalLines)..where((l) => l.accountId.equals(accountId))).get();
    double debit = 0, credit = 0;
    for (final line in lines) {
      final entry = await (_db.select(_db.journalEntries)..where((e) => e.id.equals(line.journalEntryId))).getSingleOrNull();
      if (entry == null) continue;
      if (entry.date.isBefore(from) || entry.date.isAfter(to)) continue;
      if (entry.status == 'reversed') continue;
      debit += line.debit;
      credit += line.credit;
    }
    return debit - credit;
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
