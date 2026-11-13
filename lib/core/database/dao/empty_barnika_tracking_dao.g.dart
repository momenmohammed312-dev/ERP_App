// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'empty_barnika_tracking_dao.dart';

// ignore_for_file: type=lint
mixin _$EmptyBarnikaTrackingDaoMixin on DatabaseAccessor<AppDatabase> {
  $CustomersTable get customers => attachedDatabase.customers;
  $SuppliersTable get suppliers => attachedDatabase.suppliers;
  $VegetableShipmentsTable get vegetableShipments =>
      attachedDatabase.vegetableShipments;
  $InvoicesTable get invoices => attachedDatabase.invoices;
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
  $$SuppliersTableTableManager get suppliers =>
      $$SuppliersTableTableManager(_db.attachedDatabase, _db.suppliers);
  $$VegetableShipmentsTableTableManager get vegetableShipments =>
      $$VegetableShipmentsTableTableManager(
        _db.attachedDatabase,
        _db.vegetableShipments,
      );
  $$InvoicesTableTableManager get invoices =>
      $$InvoicesTableTableManager(_db.attachedDatabase, _db.invoices);
  $$EmptyBarnikaTrackingTableTableManager get emptyBarnikaTracking =>
      $$EmptyBarnikaTrackingTableTableManager(
        _db.attachedDatabase,
        _db.emptyBarnikaTracking,
      );
}
