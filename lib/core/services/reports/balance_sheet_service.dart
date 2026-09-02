import '../../database/app_database.dart';

class BalanceSheetAccountRow {
  final Account account;
  final double balance; // positive = debit balance for assets, credit balance for liabilities/equity
  BalanceSheetAccountRow({required this.account, required this.balance});
}

class BalanceSheetData {
  final DateTime asOf;
  final List<BalanceSheetAccountRow> assets;
  final List<BalanceSheetAccountRow> liabilities;
  final List<BalanceSheetAccountRow> equity;
  final double totalAssets;
  final double totalLiabilities;
  final double totalEquity;
  final double totalLiabilitiesEquity;
  final double delta; // totalAssets - totalLiabilitiesEquity (should be ~0)

  BalanceSheetData({
    required this.asOf,
    required this.assets,
    required this.liabilities,
    required this.equity,
    required this.totalAssets,
    required this.totalLiabilities,
    required this.totalEquity,
    required this.totalLiabilitiesEquity,
    required this.delta,
  });

  bool get isBalanced => delta.abs() <= 0.01;
}

class BalanceSheetService {
  final AppDatabase _db;
  BalanceSheetService(this._db);

  Future<BalanceSheetData> getBalanceSheet({required DateTime asOf}) async {
    final accounts = await _db.accountsDao.getAllAccounts();
    final assets = <BalanceSheetAccountRow>[];
    final liabilities = <BalanceSheetAccountRow>[];
    final equity = <BalanceSheetAccountRow>[];

    double totalAssets = 0, totalLiab = 0, totalEquity = 0;

    for (final acc in accounts) {
      if (!acc.isActive) continue;
      final raw = await _getAccountBalanceUpTo(acc.id, asOf);
      // Normalize to positive balance per normalBalance
      double bal;
      if (acc.normalBalance == 'debit') {
        bal = raw; // debit - credit
      } else {
        bal = -raw; // credit - debit => flip
      }
      // For balance sheet display, we want positive numbers for each section
      // raw is debit - credit; for credit-normal accounts, positive means credit balance
      // So we use bal as defined.

      final row = BalanceSheetAccountRow(account: acc, balance: bal);
      switch (acc.type) {
        case 'asset':
          assets.add(row);
          totalAssets += bal;
          break;
        case 'liability':
          liabilities.add(row);
          totalLiab += bal;
          break;
        case 'equity':
          equity.add(row);
          totalEquity += bal;
          break;
        default:
          // revenue/expense not on balance sheet
          break;
      }
    }

    // Include current period net profit in equity (retained earnings)
    // Compute P&L up to asOf and add to equity
    final netProfit = await _getNetProfitUpTo(asOf);
    // Net profit increases equity (credit) — add to totalEquity
    totalEquity += netProfit;
    // Also add a synthetic row for current profit if non-zero
    if (netProfit.abs() > 0.01) {
      // Find retained earnings account 3200 to attach, or create synthetic
      final re = accounts.where((a) => a.code == '3200').firstOrNull;
      if (re != null) {
        equity.add(BalanceSheetAccountRow(account: re, balance: netProfit));
      }
    }

    final totalLiabEquity = totalLiab + totalEquity;
    final delta = totalAssets - totalLiabEquity;

    return BalanceSheetData(
      asOf: asOf,
      assets: assets,
      liabilities: liabilities,
      equity: equity,
      totalAssets: totalAssets,
      totalLiabilities: totalLiab,
      totalEquity: totalEquity,
      totalLiabilitiesEquity: totalLiabEquity,
      delta: delta,
    );
  }

  Future<double> _getAccountBalanceUpTo(String accountId, DateTime asOf) async {
    final lines = await (_db.select(_db.journalLines)
          ..where((l) => l.accountId.equals(accountId)))
        .get();
    // Need to filter by journal entry date <= asOf
    // Join via journalEntries
    double debit = 0, credit = 0;
    for (final line in lines) {
      final entry = await (_db.select(_db.journalEntries)..where((e) => e.id.equals(line.journalEntryId))).getSingleOrNull();
      if (entry == null) continue;
      if (entry.date.isAfter(asOf)) continue;
      if (entry.status == 'reversed') continue;
      debit += line.debit;
      credit += line.credit;
    }
    return debit - credit;
  }

  Future<double> _getNetProfitUpTo(DateTime asOf) async {
    final accounts = await _db.accountsDao.getAllAccounts();
    double revenue = 0, cogs = 0, expenses = 0, returns = 0;
    for (final acc in accounts) {
      if (!acc.isActive) continue;
      final bal = await _getAccountBalanceUpTo(acc.id, asOf);
      // For revenue (credit normal), profit = -bal (since bal = debit - credit, credit balance is negative)
      // For expense (debit normal), bal is positive debit
      if (acc.type == 'revenue') {
        if (acc.code == '4100') {
          returns += -bal; // sales returns is debit normal, but type revenue with debit normal? Actually 4100 is debit normal revenue contra
          // For 4100, normalBalance debit, bal = debit - credit, positive means returns
          returns += bal; // adjust
        } else {
          revenue += -bal;
        }
      } else if (acc.type == 'expense') {
        // expense normal debit, bal positive = expense
        if (acc.code == '5000') {
          cogs += bal;
        } else {
          expenses += bal;
        }
      }
    }
    // Simplified: net = revenue - returns - cogs - expenses
    // But our returns handling double counts; for Phase 7 minimal, just revenue - cogs - expenses
    // We'll compute correctly: revenue (4000) is credit, so -bal is positive.
    // Returns (4100) is debit, bal positive is returns amount, should subtract from revenue.
    // So net = (revenue - returns) - cogs - expenses
    // To avoid confusion, recompute directly:
    double rev = 0, ret = 0, c = 0, exp = 0;
    for (final acc in accounts) {
      final bal = await _getAccountBalanceUpTo(acc.id, asOf);
      if (acc.code == '4000') rev = -bal;
      if (acc.code == '4100') ret = bal;
      if (acc.code == '5000') c = bal;
      if (acc.code == '5100') exp = bal;
    }
    return rev - ret - c - exp;
  }

  /// Reconciliation check vs subledger (§20.4)
  Future<double> getArReconciliationDelta() async {
    final arAccount = await _db.accountsDao.getByCode('1100');
    if (arAccount == null) return 0;
    final journalAr = await _getAccountBalanceUpTo(arAccount.id, DateTime.now());
    // journalAr is debit - credit; for AR (debit normal) positive = AR balance
    // Subledger AR is sum per LedgerDao.getTotalReceivables() which is credit? For customer, balance = debit - credit + opening
    // For AR, subledger is same as journal AR: should match
    final subledgerAr = await _db.ledgerDao.getTotalReceivables();
    // journalAr positive is AR, subledgerAr positive is AR
    return journalAr - subledgerAr;
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
