import '../../database/app_database.dart';

class GeneralLedgerLine {
  final JournalEntry entry;
  final JournalLine line;
  final double runningBalance;
  GeneralLedgerLine({required this.entry, required this.line, required this.runningBalance});
}

class GeneralLedgerData {
  final Account? account; // null = all accounts
  final DateTime from;
  final DateTime to;
  final double openingBalance;
  final List<GeneralLedgerLine> lines;
  final double closingBalance;

  GeneralLedgerData({
    required this.account,
    required this.from,
    required this.to,
    required this.openingBalance,
    required this.lines,
    required this.closingBalance,
  });
}

class GeneralLedgerService {
  final AppDatabase _db;
  GeneralLedgerService(this._db);

  Future<GeneralLedgerData> getLedger({String? accountId, required DateTime from, required DateTime to}) async {
    Account? account;
    if (accountId != null) {
      account = await _db.accountsDao.getById(accountId);
    }

    // Opening balance: sum of all lines for account before from
    double opening = 0;
    if (accountId != null) {
      opening = await _getBalanceUpTo(accountId, from.subtract(const Duration(milliseconds: 1)));
    } else if (account == null && accountId == null) {
      // For "all accounts" view, opening is 0 (not meaningful)
      opening = 0;
    }

    // Collect lines in range
    final allLines = await _db.select(_db.journalLines).get();
    final filtered = <GeneralLedgerLine>[];
    // Need to join with entries for date/status filtering
    final entriesMap = <String, JournalEntry>{};
    for (final line in allLines) {
      if (accountId != null && line.accountId != accountId) continue;
      var entry = entriesMap[line.journalEntryId];
      entry ??= await (_db.select(_db.journalEntries)..where((e) => e.id.equals(line.journalEntryId))).getSingleOrNull();
      if (entry == null) continue;
      entriesMap[line.journalEntryId] = entry;
      if (entry.date.isBefore(from) || entry.date.isAfter(to)) continue;
      if (entry.status == 'reversed') continue;
      filtered.add(GeneralLedgerLine(entry: entry, line: line, runningBalance: 0));
    }

    // Sort by entry date
    filtered.sort((a, b) => a.entry.date.compareTo(b.entry.date));

    double running = opening;
    final withRunning = <GeneralLedgerLine>[];
    for (final gl in filtered) {
      // For debit-normal accounts, running = debit - credit; for credit-normal, opposite
      // For generic "all" view, just use debit - credit
      double delta;
      if (account != null && account.normalBalance == 'credit') {
        delta = gl.line.credit - gl.line.debit;
        // But for running balance display, we want credit-normal to increase with credit
        // So delta = credit - debit
        // However for opening we already did debit-credit flipped, so keep consistent
        // For credit-normal, opening was - (debit-credit), so delta should be credit - debit
        running += gl.line.credit - gl.line.debit;
      } else {
        running += gl.line.debit - gl.line.credit;
      }
      withRunning.add(GeneralLedgerLine(entry: gl.entry, line: gl.line, runningBalance: running));
    }

    return GeneralLedgerData(
      account: account,
      from: from,
      to: to,
      openingBalance: opening,
      lines: withRunning,
      closingBalance: running,
    );
  }

  Future<double> _getBalanceUpTo(String accountId, DateTime asOf) async {
    final account = await _db.accountsDao.getById(accountId);
    if (account == null) return 0;
    final lines = await (_db.select(_db.journalLines)..where((l) => l.accountId.equals(accountId))).get();
    double bal = 0;
    for (final line in lines) {
      final entry = await (_db.select(_db.journalEntries)..where((e) => e.id.equals(line.journalEntryId))).getSingleOrNull();
      if (entry == null) continue;
      if (entry.date.isAfter(asOf)) continue;
      if (entry.status == 'reversed') continue;
      if (account.normalBalance == 'credit') {
        bal += line.credit - line.debit;
      } else {
        bal += line.debit - line.credit;
      }
    }
    return bal;
  }
}
