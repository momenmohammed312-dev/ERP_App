// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'manufacturing_order_dao.dart';

// ignore_for_file: type=lint
mixin _$ManufacturingOrderDaoMixin on DatabaseAccessor<AppDatabase> {
  $ProductsTable get products => attachedDatabase.products;
  $BillOfMaterialsTable get billOfMaterials => attachedDatabase.billOfMaterials;
  $CustomersTable get customers => attachedDatabase.customers;
  $SuppliersTable get suppliers => attachedDatabase.suppliers;
  $VegetableShipmentsTable get vegetableShipments =>
      attachedDatabase.vegetableShipments;
  $InvoicesTable get invoices => attachedDatabase.invoices;
  $ManufacturingOrdersTable get manufacturingOrders =>
      attachedDatabase.manufacturingOrders;
  $BomItemsTable get bomItems => attachedDatabase.bomItems;
  $ManufacturingCostComponentsTable get manufacturingCostComponents =>
      attachedDatabase.manufacturingCostComponents;
  $InventoryMovementsTable get inventoryMovements =>
      attachedDatabase.inventoryMovements;
  $CustomerStockBalancesTable get customerStockBalances =>
      attachedDatabase.customerStockBalances;
  $CustomerStockMovementsTable get customerStockMovements =>
      attachedDatabase.customerStockMovements;
  $ManufacturingStagesTable get manufacturingStages =>
      attachedDatabase.manufacturingStages;
  $ProductVariantsTable get productVariants => attachedDatabase.productVariants;
  $ManufacturingStageOutputsTable get manufacturingStageOutputs =>
      attachedDatabase.manufacturingStageOutputs;
  $ManufacturingScrapsTable get manufacturingScraps =>
      attachedDatabase.manufacturingScraps;
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
  $$CustomerStockBalancesTableTableManager get customerStockBalances =>
      $$CustomerStockBalancesTableTableManager(
        _db.attachedDatabase,
        _db.customerStockBalances,
      );
  $$CustomerStockMovementsTableTableManager get customerStockMovements =>
      $$CustomerStockMovementsTableTableManager(
        _db.attachedDatabase,
        _db.customerStockMovements,
      );
  $$ManufacturingStagesTableTableManager get manufacturingStages =>
      $$ManufacturingStagesTableTableManager(
        _db.attachedDatabase,
        _db.manufacturingStages,
      );
  $$ProductVariantsTableTableManager get productVariants =>
      $$ProductVariantsTableTableManager(
        _db.attachedDatabase,
        _db.productVariants,
      );
  $$ManufacturingStageOutputsTableTableManager get manufacturingStageOutputs =>
      $$ManufacturingStageOutputsTableTableManager(
        _db.attachedDatabase,
        _db.manufacturingStageOutputs,
      );
  $$ManufacturingScrapsTableTableManager get manufacturingScraps =>
      $$ManufacturingScrapsTableTableManager(
        _db.attachedDatabase,
        _db.manufacturingScraps,
      );
}
