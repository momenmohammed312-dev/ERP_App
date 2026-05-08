// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'expense_dao.dart';

// ignore_for_file: type=lint
mixin _$ExpenseDaoMixin on DatabaseAccessor<AppDatabase> {
  $ExpensesTable get expenses => attachedDatabase.expenses;
  ExpenseDaoManager get managers => ExpenseDaoManager(this);
}

class ExpenseDaoManager {
  final _$ExpenseDaoMixin _db;
  ExpenseDaoManager(this._db);
  $$ExpensesTableTableManager get expenses =>
      $$ExpensesTableTableManager(_db.attachedDatabase, _db.expenses);
}
