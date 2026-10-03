// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'manufacturing_order_dao.dart';

// ignore_for_file: type=lint
mixin _$ManufacturingOrderDaoMixin on DatabaseAccessor<AppDatabase> {
  $ProductsTable get products => attachedDatabase.products;
  $BillOfMaterialsTable get billOfMaterials => attachedDatabase.billOfMaterials;
  $ManufacturingOrdersTable get manufacturingOrders =>
      attachedDatabase.manufacturingOrders;
  $BomItemsTable get bomItems => attachedDatabase.bomItems;
  $ManufacturingCostComponentsTable get manufacturingCostComponents =>
      attachedDatabase.manufacturingCostComponents;
  $InventoryMovementsTable get inventoryMovements =>
      attachedDatabase.inventoryMovements;
  ManufacturingOrderDaoManager get managers =>
      ManufacturingOrderDaoManager(this);
}

class ManufacturingOrderDaoManager {
  final _$ManufacturingOrderDaoMixin _db;
  ManufacturingOrderDaoManager(this._db);
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
  $$ManufacturingCostComponentsTableTableManager
  get manufacturingCostComponents =>
      $$ManufacturingCostComponentsTableTableManager(
        _db.attachedDatabase,
        _db.manufacturingCostComponents,
      );
  $$InventoryMovementsTableTableManager get inventoryMovements =>
      $$InventoryMovementsTableTableManager(
        _db.attachedDatabase,
        _db.inventoryMovements,
      );
}
