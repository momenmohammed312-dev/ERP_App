// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'customer_container_dao.dart';

// ignore_for_file: type=lint
mixin _$CustomerContainerDaoMixin on DatabaseAccessor<AppDatabase> {
  $ProductsTable get products => attachedDatabase.products;
  $CustomerContainersTable get customerContainers =>
      attachedDatabase.customerContainers;
  CustomerContainerDaoManager get managers => CustomerContainerDaoManager(this);
}

class CustomerContainerDaoManager {
  final _$CustomerContainerDaoMixin _db;
  CustomerContainerDaoManager(this._db);
  $$ProductsTableTableManager get products =>
      $$ProductsTableTableManager(_db.attachedDatabase, _db.products);
  $$CustomerContainersTableTableManager get customerContainers =>
      $$CustomerContainersTableTableManager(
        _db.attachedDatabase,
        _db.customerContainers,
      );
}
