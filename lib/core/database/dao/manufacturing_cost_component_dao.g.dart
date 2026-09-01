// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'manufacturing_cost_component_dao.dart';

// ignore_for_file: type=lint
mixin _$ManufacturingCostComponentDaoMixin on DatabaseAccessor<AppDatabase> {
  $ProductsTable get products => attachedDatabase.products;
  $BillOfMaterialsTable get billOfMaterials => attachedDatabase.billOfMaterials;
  $ManufacturingOrdersTable get manufacturingOrders =>
      attachedDatabase.manufacturingOrders;
  $ManufacturingCostComponentsTable get manufacturingCostComponents =>
      attachedDatabase.manufacturingCostComponents;
  ManufacturingCostComponentDaoManager get managers =>
      ManufacturingCostComponentDaoManager(this);
}

class ManufacturingCostComponentDaoManager {
  final _$ManufacturingCostComponentDaoMixin _db;
  ManufacturingCostComponentDaoManager(this._db);
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
  $$ManufacturingCostComponentsTableTableManager
  get manufacturingCostComponents =>
      $$ManufacturingCostComponentsTableTableManager(
        _db.attachedDatabase,
        _db.manufacturingCostComponents,
      );
}
