// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reconciliation_dao.dart';

// ignore_for_file: type=lint
mixin _$ReconciliationDaoMixin on DatabaseAccessor<AppDatabase> {
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
  $ManufacturingStagesTable get manufacturingStages =>
      attachedDatabase.manufacturingStages;
  $InventoryMovementsTable get inventoryMovements =>
      attachedDatabase.inventoryMovements;
  $CustomerStockMovementsTable get customerStockMovements =>
      attachedDatabase.customerStockMovements;
  $ConsumptionRecordsTable get consumptionRecords =>
      attachedDatabase.consumptionRecords;
  $StageYieldRecordsTable get stageYieldRecords =>
      attachedDatabase.stageYieldRecords;
  $ExternalOperationRecordsTable get externalOperationRecords =>
      attachedDatabase.externalOperationRecords;
  $ManufacturingScrapsTable get manufacturingScraps =>
      attachedDatabase.manufacturingScraps;
  $ProductVariantsTable get productVariants => attachedDatabase.productVariants;
  $ManufacturingStageOutputsTable get manufacturingStageOutputs =>
      attachedDatabase.manufacturingStageOutputs;
  ReconciliationDaoManager get managers => ReconciliationDaoManager(this);
}

class ReconciliationDaoManager {
  final _$ReconciliationDaoMixin _db;
  ReconciliationDaoManager(this._db);
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
  $$ManufacturingStagesTableTableManager get manufacturingStages =>
      $$ManufacturingStagesTableTableManager(
        _db.attachedDatabase,
        _db.manufacturingStages,
      );
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
  $$StageYieldRecordsTableTableManager get stageYieldRecords =>
      $$StageYieldRecordsTableTableManager(
        _db.attachedDatabase,
        _db.stageYieldRecords,
      );
  $$ExternalOperationRecordsTableTableManager get externalOperationRecords =>
      $$ExternalOperationRecordsTableTableManager(
        _db.attachedDatabase,
        _db.externalOperationRecords,
      );
  $$ManufacturingScrapsTableTableManager get manufacturingScraps =>
      $$ManufacturingScrapsTableTableManager(
        _db.attachedDatabase,
        _db.manufacturingScraps,
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
}
