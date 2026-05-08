// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'customer_dao.dart';

// ignore_for_file: type=lint
mixin _$CustomerDaoMixin on DatabaseAccessor<AppDatabase> {
  $CustomersTable get customers => attachedDatabase.customers;
  CustomerDaoManager get managers => CustomerDaoManager(this);
}

class CustomerDaoManager {
  final _$CustomerDaoMixin _db;
  CustomerDaoManager(this._db);
  $$CustomersTableTableManager get customers =>
      $$CustomersTableTableManager(_db.attachedDatabase, _db.customers);
}
