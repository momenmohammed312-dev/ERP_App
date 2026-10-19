// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'equity_dao.dart';

// ignore_for_file: type=lint
mixin _$EquityDaoMixin on DatabaseAccessor<AppDatabase> {
  $PartnersTable get partners => attachedDatabase.partners;
  $EquityTransactionsTable get equityTransactions =>
      attachedDatabase.equityTransactions;
  EquityDaoManager get managers => EquityDaoManager(this);
}

class EquityDaoManager {
  final _$EquityDaoMixin _db;
  EquityDaoManager(this._db);
  $$PartnersTableTableManager get partners =>
      $$PartnersTableTableManager(_db.attachedDatabase, _db.partners);
  $$EquityTransactionsTableTableManager get equityTransactions =>
      $$EquityTransactionsTableTableManager(
        _db.attachedDatabase,
        _db.equityTransactions,
      );
}
