import 'package:drift/drift.dart';

import '../tables/ledger_transactions_table.dart';
import '../app_database.dart';

part 'ledger_dao.g.dart';

@DriftAccessor(tables: [LedgerTransactions])
class LedgerDao extends DatabaseAccessor<AppDatabase> with _$LedgerDaoMixin {
  LedgerDao(super.db);

  Future<List<LedgerTransaction>> getAllTransactions() =>
      select(ledgerTransactions).get();

  Future<List<LedgerTransaction>> getRecentTransactions(int limit) =>
      (select(ledgerTransactions)
            ..orderBy([
              (t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc),
            ])
            ..limit(limit))
          .get();

  Future<List<LedgerTransaction>> getTransactionsByEntity(
    String entityType,
    String refId,
  ) =>
      (select(ledgerTransactions)
            ..where(
              (tbl) =>
                  tbl.entityType.equals(entityType) & tbl.refId.equals(refId),
            )
            ..orderBy([
              (t) => OrderingTerm(expression: t.date, mode: OrderingMode.asc),
            ]))
          .get();

  Future<List<LedgerTransaction>> getTransactionsByDateRange(
    String entityType,
    String refId,
    DateTime from,
    DateTime to,
  ) =>
      (select(ledgerTransactions)
            ..where(
              (tbl) =>
                  tbl.entityType.equals(entityType) &
                  tbl.refId.equals(refId) &
                  tbl.date.isBetweenValues(from, to),
            )
            ..orderBy([
              (t) => OrderingTerm(expression: t.date, mode: OrderingMode.asc),
            ]))
          .get();

  Future<List<LedgerTransaction>> getCustomerTransactionsByDateRange(
    String customerId,
    DateTime from,
    DateTime to,
  ) => getTransactionsByDateRange('Customer', customerId, from, to);

  Future<List<LedgerTransaction>> getAllTransactionsByDateRange(
    DateTime from,
    DateTime to,
  ) =>
      (select(ledgerTransactions)
            ..where((tbl) => tbl.date.isBetweenValues(from, to))
            ..orderBy([
              (t) => OrderingTerm(expression: t.date, mode: OrderingMode.asc),
            ]))
          .get();

  Future<LedgerTransaction> insertTransaction(
    LedgerTransactionsCompanion transaction,
  ) async {
    final id = transaction.id.present
        ? transaction.id.value
        : DateTime.now().millisecondsSinceEpoch.toString();
    final transactionWithId = transaction.copyWith(id: Value(id));
    await into(ledgerTransactions).insert(transactionWithId);
    return await getTransactionById(id) ??
        (throw Exception('Failed to insert transaction'));
  }

  Future<LedgerTransaction?> getTransactionById(String id) => (select(
    ledgerTransactions,
  )..where((tbl) => tbl.id.equals(id))).getSingleOrNull();

  Future<double> getRunningBalance(
    String entityType,
    String refId, {
    DateTime? upToDate,
  }) async {
    double openingBalance = 0.0;
    if (entityType == 'Customer') {
      final customer = await (db.select(
        db.customers,
      )..where((t) => t.id.equals(refId))).getSingleOrNull();
      openingBalance = customer?.openingBalance ?? 0.0;
    } else if (entityType == 'Supplier') {
      final supplier = await (db.select(
        db.suppliers,
      )..where((t) => t.id.equals(refId))).getSingleOrNull();
      openingBalance = supplier?.openingBalance ?? 0.0;
    }

    final query = selectOnly(ledgerTransactions)
      ..addColumns([ledgerTransactions.debit, ledgerTransactions.credit])
      ..where(
        ledgerTransactions.entityType.equals(entityType) &
            ledgerTransactions.refId.equals(refId),
      );

    if (upToDate != null) {
      query.where(ledgerTransactions.date.isSmallerOrEqualValue(upToDate));
    }

    final result = await query.get();
    double total = openingBalance;
    for (final row in result) {
      final debit = row.read(ledgerTransactions.debit) ?? 0.0;
      final credit = row.read(ledgerTransactions.credit) ?? 0.0;
      if (entityType == 'Supplier') {
        total += credit - debit;
      } else {
        total += debit - credit;
      }
    }
    return total;
  }

  Stream<double> watchCurrentBalance() {
    return (select(ledgerTransactions)).watch().map((transactions) {
      double total = 0.0;
      for (final transaction in transactions) {
        total += transaction.debit - transaction.credit;
      }
      return total;
    });
  }

  Stream<List<LedgerTransaction>> watchAllTransactions() {
    return (select(ledgerTransactions)..orderBy([
          (t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc),
        ]))
        .watch();
  }

  Future<List<LedgerTransactionWithBalance>> getTransactionsWithRunningBalance(
    String entityType,
    String refId,
    DateTime from,
    DateTime to,
  ) async {
    final transactions = await getTransactionsByDateRange(
      entityType,
      refId,
      from,
      to,
    );

    final result = <LedgerTransactionWithBalance>[];
    double runningBalance = 0.0;

    // Get opening balance before the period
    if (from != DateTime(1970)) {
      runningBalance = await getRunningBalance(
        entityType,
        refId,
        upToDate: from.subtract(const Duration(days: 1)),
      );
    }

    for (final transaction in transactions) {
      if (entityType == 'Supplier') {
        runningBalance += (transaction.credit - transaction.debit);
      } else {
        runningBalance += (transaction.debit - transaction.credit);
      }
      result.add(
        LedgerTransactionWithBalance(
          transaction: transaction,
          runningBalance: runningBalance,
        ),
      );
    }

    return result;
  }

  Future<int> lockTransactionsForDay(DateTime date) {
    final lockBatch =
        '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
    return (update(ledgerTransactions)
          ..where((tbl) => tbl.date.equals(date) & tbl.lockBatch.isNull()))
        .write(LedgerTransactionsCompanion(lockBatch: Value(lockBatch)));
  }

  Future<bool> isDayLocked(DateTime date) {
    final lockBatch =
        '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
    return (selectOnly(ledgerTransactions)
          ..addColumns([ledgerTransactions.id])
          ..where(ledgerTransactions.lockBatch.equals(lockBatch)))
        .get()
        .then((result) => result.isNotEmpty);
  }

  Future<double> getCustomerBalance(String customerId) async {
    final customer = await (db.select(
      db.customers,
    )..where((t) => t.id.equals(customerId))).getSingleOrNull();
    final openingBalance = customer?.openingBalance ?? 0.0;

    final transactions =
        await (select(ledgerTransactions)..where(
              (tbl) =>
                  tbl.entityType.equals('Customer') &
                  tbl.refId.equals(customerId),
            ))
            .get();

    return transactions.fold<double>(openingBalance, (sum, transaction) {
      return sum + transaction.debit - transaction.credit;
    });
  }

  Future<double> getSupplierBalance(String supplierId) async {
    final supplier = await (db.select(
      db.suppliers,
    )..where((t) => t.id.equals(supplierId))).getSingleOrNull();
    final openingBalance = supplier?.openingBalance ?? 0.0;

    final transactions =
        await (select(ledgerTransactions)..where(
              (tbl) =>
                  tbl.entityType.equals('Supplier') &
                  tbl.refId.equals(supplierId),
            ))
            .get();

    return transactions.fold<double>(openingBalance, (sum, transaction) {
      return sum + transaction.credit - transaction.debit;
    });
  }

  Stream<double> watchTotalReceivables() {
    return customSelect(
      'SELECT SUM(balance) as total FROM ('
      '  SELECT c.opening_balance + SUM(COALESCE(l.debit, 0) - COALESCE(l.credit, 0)) as balance '
      '  FROM customers c '
      '  LEFT JOIN ledger_transactions l ON l.ref_id = c.id AND l.entity_type = \'Customer\' '
      '  GROUP BY c.id'
      ') WHERE balance > 0',
      readsFrom: {db.customers, db.ledgerTransactions},
    ).watchSingle().map((row) => row.readNullable<double>('total') ?? 0.0);
  }

  Future<List<Map<String, dynamic>>> getAllCustomerBalances() async {
    final rows = await customSelect(
      'SELECT c.id, c.name, c.phone, (c.opening_balance + SUM(COALESCE(l.debit, 0) - COALESCE(l.credit, 0))) as balance '
      'FROM customers c '
      'LEFT JOIN ledger_transactions l ON l.ref_id = c.id AND l.entity_type = \'Customer\' '
      'GROUP BY c.id '
      'ORDER BY balance DESC',
      readsFrom: {db.customers, db.ledgerTransactions},
    ).get();

    return rows.map((row) => row.data).toList();
  }

  Future<List<Map<String, dynamic>>> getAllSupplierBalances() async {
    final rows = await customSelect(
      'SELECT s.id, s.name, s.phone, (s.opening_balance + SUM(COALESCE(l.credit, 0) - COALESCE(l.debit, 0))) as balance '
      'FROM suppliers s '
      'LEFT JOIN ledger_transactions l ON l.ref_id = s.id AND l.entity_type = \'Supplier\' '
      'GROUP BY s.id '
      'ORDER BY balance DESC',
      readsFrom: {db.suppliers, db.ledgerTransactions},
    ).get();

    return rows.map((row) => row.data).toList();
  }
}

class LedgerTransactionWithBalance {
  final LedgerTransaction transaction;
  final double runningBalance;

  LedgerTransactionWithBalance({
    required this.transaction,
    required this.runningBalance,
  });
}
