// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'bom_dao.dart';

// ignore_for_file: type=lint
mixin _$BomDaoMixin on DatabaseAccessor<AppDatabase> {
  $ProductsTable get products => attachedDatabase.products;
  $BillOfMaterialsTable get billOfMaterials => attachedDatabase.billOfMaterials;
  $BomItemsTable get bomItems => attachedDatabase.bomItems;
  BomDaoManager get managers => BomDaoManager(this);
}

class BomDaoManager {
  final _$BomDaoMixin _db;
  BomDaoManager(this._db);
  $$ProductsTableTableManager get products =>
      $$ProductsTableTableManager(_db.attachedDatabase, _db.products);
  $$BillOfMaterialsTableTableManager get billOfMaterials =>
      $$BillOfMaterialsTableTableManager(
        _db.attachedDatabase,
        _db.billOfMaterials,
      );
  $$BomItemsTableTableManager get bomItems =>
      $$BomItemsTableTableManager(_db.attachedDatabase, _db.bomItems);
}
