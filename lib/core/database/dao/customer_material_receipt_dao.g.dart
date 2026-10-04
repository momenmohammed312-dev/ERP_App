// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'customer_material_receipt_dao.dart';

// ignore_for_file: type=lint
mixin _$CustomerMaterialReceiptDaoMixin on DatabaseAccessor<AppDatabase> {
  $CustomersTable get customers => attachedDatabase.customers;
  $ProductsTable get products => attachedDatabase.products;
  $BillOfMaterialsTable get billOfMaterials => attachedDatabase.billOfMaterials;
  $SuppliersTable get suppliers => attachedDatabase.suppliers;
  $VegetableShipmentsTable get vegetableShipments =>
      attachedDatabase.vegetableShipments;
  $InvoicesTable get invoices => attachedDatabase.invoices;
  $ManufacturingOrdersTable get manufacturingOrders =>
      attachedDatabase.manufacturingOrders;
  $CustomerMaterialReceiptsTable get customerMaterialReceipts =>
      attachedDatabase.customerMaterialReceipts;
  $CustomerMaterialReceiptItemsTable get customerMaterialReceiptItems =>
      attachedDatabase.customerMaterialReceiptItems;
  $CustomerStockBalancesTable get customerStockBalances =>
      attachedDatabase.customerStockBalances;
  $CustomerStockMovementsTable get customerStockMovements =>
      attachedDatabase.customerStockMovements;
  CustomerMaterialReceiptDaoManager get managers =>
      CustomerMaterialReceiptDaoManager(this);
}

class CustomerMaterialReceiptDaoManager {
  final _$CustomerMaterialReceiptDaoMixin _db;
  CustomerMaterialReceiptDaoManager(this._db);
  $$CustomersTableTableManager get customers =>
      $$CustomersTableTableManager(_db.attachedDatabase, _db.customers);
  $$ProductsTableTableManager get products =>
      $$ProductsTableTableManager(_db.attachedDatabase, _db.products);
  $$BillOfMaterialsTableTableManager get billOfMaterials =>
      $$BillOfMaterialsTableTableManager(
        _db.attachedDatabase,
        _db.billOfMaterials,
      );
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
  $$CustomerMaterialReceiptsTableTableManager get customerMaterialReceipts =>
      $$CustomerMaterialReceiptsTableTableManager(
        _db.attachedDatabase,
        _db.customerMaterialReceipts,
      );
  $$CustomerMaterialReceiptItemsTableTableManager
  get customerMaterialReceiptItems =>
      $$CustomerMaterialReceiptItemsTableTableManager(
        _db.attachedDatabase,
        _db.customerMaterialReceiptItems,
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
}
