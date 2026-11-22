// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'manufacturing_costing_dao.dart';

// ignore_for_file: type=lint
mixin _$ManufacturingCostingDaoMixin on DatabaseAccessor<AppDatabase> {
  $ProductsTable get products => attachedDatabase.products;
  $BillOfMaterialsTable get billOfMaterials => attachedDatabase.billOfMaterials;
  $CustomersTable get customers => attachedDatabase.customers;
  $SuppliersTable get suppliers => attachedDatabase.suppliers;
  $VegetableShipmentsTable get vegetableShipments =>
      attachedDatabase.vegetableShipments;
  $InvoicesTable get invoices => attachedDatabase.invoices;
  $ManufacturingOrdersTable get manufacturingOrders =>
      attachedDatabase.manufacturingOrders;
  $ManufacturingCostSnapshotsTable get manufacturingCostSnapshots =>
      attachedDatabase.manufacturingCostSnapshots;
  $ExtraMaterialApprovalsTable get extraMaterialApprovals =>
      attachedDatabase.extraMaterialApprovals;
  $ManufacturingStagesTable get manufacturingStages =>
      attachedDatabase.manufacturingStages;
  $BomItemsTable get bomItems => attachedDatabase.bomItems;
  $InventoryMovementsTable get inventoryMovements =>
      attachedDatabase.inventoryMovements;
  $CustomerStockMovementsTable get customerStockMovements =>
      attachedDatabase.customerStockMovements;
  $ConsumptionRecordsTable get consumptionRecords =>
      attachedDatabase.consumptionRecords;
  $ExternalOperationRecordsTable get externalOperationRecords =>
      attachedDatabase.externalOperationRecords;
  $ManufacturingCostComponentsTable get manufacturingCostComponents =>
      attachedDatabase.manufacturingCostComponents;
  $ManufacturingDeliveriesTable get manufacturingDeliveries =>
      attachedDatabase.manufacturingDeliveries;
  $ManufacturingDeliveryItemsTable get manufacturingDeliveryItems =>
      attachedDatabase.manufacturingDeliveryItems;
  $ManufacturingScrapsTable get manufacturingScraps =>
      attachedDatabase.manufacturingScraps;
  ManufacturingCostingDaoManager get managers =>
      ManufacturingCostingDaoManager(this);
}

class ManufacturingCostingDaoManager {
  final _$ManufacturingCostingDaoMixin _db;
  ManufacturingCostingDaoManager(this._db);
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
  $$ManufacturingCostSnapshotsTableTableManager
  get manufacturingCostSnapshots =>
      $$ManufacturingCostSnapshotsTableTableManager(
        _db.attachedDatabase,
        _db.manufacturingCostSnapshots,
      );
  $$ExtraMaterialApprovalsTableTableManager get extraMaterialApprovals =>
      $$ExtraMaterialApprovalsTableTableManager(
        _db.attachedDatabase,
        _db.extraMaterialApprovals,
      );
  $$ManufacturingStagesTableTableManager get manufacturingStages =>
      $$ManufacturingStagesTableTableManager(
        _db.attachedDatabase,
        _db.manufacturingStages,
      );
  $$BomItemsTableTableManager get bomItems =>
      $$BomItemsTableTableManager(_db.attachedDatabase, _db.bomItems);
  $$InventoryMovementsTableTableManager get inventoryMovements =>
      $$InventoryMovementsTableTableManager(
        _db.attachedDatabase,
        _db.inventoryMovements,
      );
  $$CustomerStockMovementsTableTableManager get customerStockMovements =>
      $$CustomerStockMovementsTableTableManager(
        _db.attachedDatabase,
        _db.customerStockMovements,
      );
  $$ConsumptionRecordsTableTableManager get consumptionRecords =>
      $$ConsumptionRecordsTableTableManager(
        _db.attachedDatabase,
        _db.consumptionRecords,
      );
  $$ExternalOperationRecordsTableTableManager get externalOperationRecords =>
      $$ExternalOperationRecordsTableTableManager(
        _db.attachedDatabase,
        _db.externalOperationRecords,
      );
  $$ManufacturingCostComponentsTableTableManager
  get manufacturingCostComponents =>
      $$ManufacturingCostComponentsTableTableManager(
        _db.attachedDatabase,
        _db.manufacturingCostComponents,
      );
  $$ManufacturingDeliveriesTableTableManager get manufacturingDeliveries =>
      $$ManufacturingDeliveriesTableTableManager(
        _db.attachedDatabase,
        _db.manufacturingDeliveries,
      );
  $$ManufacturingDeliveryItemsTableTableManager
  get manufacturingDeliveryItems =>
      $$ManufacturingDeliveryItemsTableTableManager(
        _db.attachedDatabase,
        _db.manufacturingDeliveryItems,
      );
  $$ManufacturingScrapsTableTableManager get manufacturingScraps =>
      $$ManufacturingScrapsTableTableManager(
        _db.attachedDatabase,
        _db.manufacturingScraps,
      );
}
