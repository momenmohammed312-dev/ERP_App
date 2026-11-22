// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'routing_dao.dart';

// ignore_for_file: type=lint
mixin _$RoutingDaoMixin on DatabaseAccessor<AppDatabase> {
  $ProductsTable get products => attachedDatabase.products;
  $RoutingTemplatesTable get routingTemplates =>
      attachedDatabase.routingTemplates;
  $RoutingTemplateNodesTable get routingTemplateNodes =>
      attachedDatabase.routingTemplateNodes;
  $BillOfMaterialsTable get billOfMaterials => attachedDatabase.billOfMaterials;
  $CustomersTable get customers => attachedDatabase.customers;
  $SuppliersTable get suppliers => attachedDatabase.suppliers;
  $VegetableShipmentsTable get vegetableShipments =>
      attachedDatabase.vegetableShipments;
  $InvoicesTable get invoices => attachedDatabase.invoices;
  $ManufacturingOrdersTable get manufacturingOrders =>
      attachedDatabase.manufacturingOrders;
  $ManufacturingStagesTable get manufacturingStages =>
      attachedDatabase.manufacturingStages;
  $ManufacturingReworkRecordsTable get manufacturingReworkRecords =>
      attachedDatabase.manufacturingReworkRecords;
  $ProductVariantsTable get productVariants => attachedDatabase.productVariants;
  $ManufacturingStageOutputsTable get manufacturingStageOutputs =>
      attachedDatabase.manufacturingStageOutputs;
  RoutingDaoManager get managers => RoutingDaoManager(this);
}

class RoutingDaoManager {
  final _$RoutingDaoMixin _db;
  RoutingDaoManager(this._db);
  $$ProductsTableTableManager get products =>
      $$ProductsTableTableManager(_db.attachedDatabase, _db.products);
  $$RoutingTemplatesTableTableManager get routingTemplates =>
      $$RoutingTemplatesTableTableManager(
        _db.attachedDatabase,
        _db.routingTemplates,
      );
  $$RoutingTemplateNodesTableTableManager get routingTemplateNodes =>
      $$RoutingTemplateNodesTableTableManager(
        _db.attachedDatabase,
        _db.routingTemplateNodes,
      );
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
  $$ManufacturingStagesTableTableManager get manufacturingStages =>
      $$ManufacturingStagesTableTableManager(
        _db.attachedDatabase,
        _db.manufacturingStages,
      );
  $$ManufacturingReworkRecordsTableTableManager
  get manufacturingReworkRecords =>
      $$ManufacturingReworkRecordsTableTableManager(
        _db.attachedDatabase,
        _db.manufacturingReworkRecords,
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
