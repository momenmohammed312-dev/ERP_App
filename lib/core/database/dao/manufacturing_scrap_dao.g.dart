// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'manufacturing_scrap_dao.dart';

// ignore_for_file: type=lint
mixin _$ManufacturingScrapDaoMixin on DatabaseAccessor<AppDatabase> {
  $ProductsTable get products => attachedDatabase.products;
  $BillOfMaterialsTable get billOfMaterials => attachedDatabase.billOfMaterials;
  $ManufacturingOrdersTable get manufacturingOrders =>
      attachedDatabase.manufacturingOrders;
  $BomItemsTable get bomItems => attachedDatabase.bomItems;
  $ManufacturingScrapsTable get manufacturingScraps =>
      attachedDatabase.manufacturingScraps;
  ManufacturingScrapDaoManager get managers =>
      ManufacturingScrapDaoManager(this);
}

class ManufacturingScrapDaoManager {
  final _$ManufacturingScrapDaoMixin _db;
  ManufacturingScrapDaoManager(this._db);
  $$ProductsTableTableManager get products =>
      $$ProductsTableTableManager(_db.attachedDatabase, _db.products);
  $$BillOfMaterialsTableTableManager get billOfMaterials =>
      $$BillOfMaterialsTableTableManager(
        _db.attachedDatabase,
        _db.billOfMaterials,
      );
  $$ManufacturingOrdersTableTableManager get manufacturingOrders =>
      $$ManufacturingOrdersTableTableManager(
        _db.attachedDatabase,
        _db.manufacturingOrders,
      );
  $$BomItemsTableTableManager get bomItems =>
      $$BomItemsTableTableManager(_db.attachedDatabase, _db.bomItems);
  $$ManufacturingScrapsTableTableManager get manufacturingScraps =>
      $$ManufacturingScrapsTableTableManager(
        _db.attachedDatabase,
        _db.manufacturingScraps,
      );
}
