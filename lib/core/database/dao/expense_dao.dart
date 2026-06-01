import 'package:drift/drift.dart';

import '../tables/expenses_table.dart';
import '../app_database.dart';

part 'expense_dao.g.dart';

@DriftAccessor(tables: [Expenses])
class ExpenseDao extends DatabaseAccessor<AppDatabase> with _$ExpenseDaoMixin {
  ExpenseDao(super.db);

  Future<List<Expense>> getAllExpenses() => select(expenses).get();

  Future<List<Expense>> getExpensesByDateRange(DateTime from, DateTime to) =>
      (select(expenses)
            ..where((tbl) => tbl.date.isBetweenValues(from, to))
            ..orderBy([
              (t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc),
            ]))
          .get();

  Future<List<Expense>> getExpensesByCategory(String category) =>
      (select(expenses)
            ..where((tbl) => tbl.category.equals(category))
            ..orderBy([
              (t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc),
            ]))
          .get();

  Future<Expense> insertExpense(ExpensesCompanion expense) async {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final expenseWithId = expense.copyWith(id: Value(id));
    await into(expenses).insert(expenseWithId);
    return await getExpenseById(id) ??
        (throw Exception('Failed to insert expense'));
  }

  Future<Expense?> getExpenseById(String id) =>
      (select(expenses)..where((tbl) => tbl.id.equals(id))).getSingleOrNull();

  Future<int> updateExpense(Expense expense) => (update(
    expenses,
  )..where((tbl) => tbl.id.equals(expense.id))).write(expense);

  Future<int> deleteExpense(String id) =>
      (delete(expenses)..where((tbl) => tbl.id.equals(id))).go();

  Future<double> getTotalExpenses({DateTime? from, DateTime? to}) async {
    final query = selectOnly(expenses)..addColumns([expenses.amount]);

    if (from != null) {
      query.where(expenses.date.isBiggerOrEqualValue(from));
    }
    if (to != null) {
      query.where(expenses.date.isSmallerOrEqualValue(to));
    }

    final result = await query.get();
    return result.fold<double>(0.0, (sum, row) {
      final amount = row.read(expenses.amount) ?? 0.0;
      return sum + amount;
    });
  }

  /// إجمالي المصروفات لتاريخ معين
  Future<double> getTotalExpensesForDate(DateTime date) async {
    final start = DateTime(date.year, date.month, date.day);
    final end = DateTime(date.year, date.month, date.day, 23, 59, 59);
    final items = await (select(expenses)
      ..where((e) => e.date.isBetweenValues(start, end))).get();
    double total = 0;
    for (final e in items) {
      total += e.amount;
    }
    return total;
  }

  // Stream methods for real-time updates
  Stream<List<Expense>> watchAllExpenses() {
    return (select(expenses)..orderBy([
          (t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc),
        ]))
        .watch();
  }

  Stream<double> watchTotalExpenses() {
    return customSelect(
      'SELECT COALESCE(SUM(amount), 0) as total FROM expenses',
      readsFrom: {expenses},
    ).map((row) => row.readNullable<double>('total') ?? 0.0).watchSingle();
  }
}
