// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'manufacturing_cost_component_dao.dart';

// ignore_for_file: type=lint
mixin _$ManufacturingCostComponentDaoMixin on DatabaseAccessor<AppDatabase> {
  $ProductsTable get products => attachedDatabase.products;
  $BillOfMaterialsTable get billOfMaterials => attachedDatabase.billOfMaterials;
  $CustomersTable get customers => attachedDatabase.customers;
  $SuppliersTable get suppliers => attachedDatabase.suppliers;
  $VegetableShipmentsTable get vegetableShipments =>
      attachedDatabase.vegetableShipments;
  $InvoicesTable get invoices => attachedDatabase.invoices;
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
  $$ManufacturingCostComponentsTableTableManager
  get manufacturingCostComponents =>
      $$ManufacturingCostComponentsTableTableManager(
        _db.attachedDatabase,
        _db.manufacturingCostComponents,
      );
}
