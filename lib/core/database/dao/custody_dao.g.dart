// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'custody_dao.dart';

// ignore_for_file: type=lint
mixin _$CustodyDaoMixin on DatabaseAccessor<AppDatabase> {
  $CashCustodiesTable get cashCustodies => attachedDatabase.cashCustodies;
  $CustodyExpensesTable get custodyExpenses => attachedDatabase.custodyExpenses;
  CustodyDaoManager get managers => CustodyDaoManager(this);
}

class CustodyDaoManager {
  final _$CustodyDaoMixin _db;
  CustodyDaoManager(this._db);
  $$CashCustodiesTableTableManager get cashCustodies =>
      $$CashCustodiesTableTableManager(_db.attachedDatabase, _db.cashCustodies);
  $$CustodyExpensesTableTableManager get custodyExpenses =>
      $$CustodyExpensesTableTableManager(
        _db.attachedDatabase,
        _db.custodyExpenses,
      );
}
