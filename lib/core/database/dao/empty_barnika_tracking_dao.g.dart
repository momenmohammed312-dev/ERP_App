// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'empty_barnika_tracking_dao.dart';

// ignore_for_file: type=lint
mixin _$EmptyBarnikaTrackingDaoMixin on DatabaseAccessor<AppDatabase> {
  $CustomersTable get customers => attachedDatabase.customers;
  $EmptyBarnikaTrackingTable get emptyBarnikaTracking =>
      attachedDatabase.emptyBarnikaTracking;
  EmptyBarnikaTrackingDaoManager get managers =>
      EmptyBarnikaTrackingDaoManager(this);
}

class EmptyBarnikaTrackingDaoManager {
  final _$EmptyBarnikaTrackingDaoMixin _db;
  EmptyBarnikaTrackingDaoManager(this._db);
  $$CustomersTableTableManager get customers =>
      $$CustomersTableTableManager(_db.attachedDatabase, _db.customers);
  $$EmptyBarnikaTrackingTableTableManager get emptyBarnikaTracking =>
      $$EmptyBarnikaTrackingTableTableManager(
        _db.attachedDatabase,
        _db.emptyBarnikaTracking,
      );
}
