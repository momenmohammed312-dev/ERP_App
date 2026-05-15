// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'purchase_budget_dao.dart';

// ignore_for_file: type=lint
mixin _$PurchaseBudgetDaoMixin on DatabaseAccessor<AppDatabase> {
  $PurchaseBudgetsTable get purchaseBudgets => attachedDatabase.purchaseBudgets;
  $BudgetCategoriesTable get budgetCategories =>
      attachedDatabase.budgetCategories;
  $BudgetTransactionsTable get budgetTransactions =>
      attachedDatabase.budgetTransactions;
  $BudgetAlertsTable get budgetAlerts => attachedDatabase.budgetAlerts;
  PurchaseBudgetDaoManager get managers => PurchaseBudgetDaoManager(this);
}

class PurchaseBudgetDaoManager {
  final _$PurchaseBudgetDaoMixin _db;
  PurchaseBudgetDaoManager(this._db);
  $$PurchaseBudgetsTableTableManager get purchaseBudgets =>
      $$PurchaseBudgetsTableTableManager(
        _db.attachedDatabase,
        _db.purchaseBudgets,
      );
  $$BudgetCategoriesTableTableManager get budgetCategories =>
      $$BudgetCategoriesTableTableManager(
        _db.attachedDatabase,
        _db.budgetCategories,
      );
  $$BudgetTransactionsTableTableManager get budgetTransactions =>
      $$BudgetTransactionsTableTableManager(
        _db.attachedDatabase,
        _db.budgetTransactions,
      );
  $$BudgetAlertsTableTableManager get budgetAlerts =>
      $$BudgetAlertsTableTableManager(_db.attachedDatabase, _db.budgetAlerts);
}
