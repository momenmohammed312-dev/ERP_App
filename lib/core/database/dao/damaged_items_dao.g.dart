// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'damaged_items_dao.dart';

// ignore_for_file: type=lint
mixin _$DamagedItemsDaoMixin on DatabaseAccessor<AppDatabase> {
  $ProductsTable get products => attachedDatabase.products;
  $DamagedItemsTable get damagedItems => attachedDatabase.damagedItems;
  DamagedItemsDaoManager get managers => DamagedItemsDaoManager(this);
}

class DamagedItemsDaoManager {
  final _$DamagedItemsDaoMixin _db;
  DamagedItemsDaoManager(this._db);
  $$ProductsTableTableManager get products =>
      $$ProductsTableTableManager(_db.attachedDatabase, _db.products);
  $$DamagedItemsTableTableManager get damagedItems =>
      $$DamagedItemsTableTableManager(_db.attachedDatabase, _db.damagedItems);
}
