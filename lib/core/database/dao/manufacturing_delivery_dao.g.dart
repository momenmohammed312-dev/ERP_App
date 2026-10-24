// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'manufacturing_delivery_dao.dart';

// ignore_for_file: type=lint
mixin _$ManufacturingDeliveryDaoMixin on DatabaseAccessor<AppDatabase> {
  $ProductsTable get products => attachedDatabase.products;
  $BillOfMaterialsTable get billOfMaterials => attachedDatabase.billOfMaterials;
  $CustomersTable get customers => attachedDatabase.customers;
  $SuppliersTable get suppliers => attachedDatabase.suppliers;
  $VegetableShipmentsTable get vegetableShipments =>
      attachedDatabase.vegetableShipments;
  $InvoicesTable get invoices => attachedDatabase.invoices;
  $ManufacturingOrdersTable get manufacturingOrders =>
      attachedDatabase.manufacturingOrders;
  $ManufacturingDeliveriesTable get manufacturingDeliveries =>
      attachedDatabase.manufacturingDeliveries;
  $ManufacturingDeliveryItemsTable get manufacturingDeliveryItems =>
      attachedDatabase.manufacturingDeliveryItems;
  $BomItemsTable get bomItems => attachedDatabase.bomItems;
  $ManufacturingScrapsTable get manufacturingScraps =>
      attachedDatabase.manufacturingScraps;
  $CustomerStockBalancesTable get customerStockBalances =>
      attachedDatabase.customerStockBalances;
  $CustomerStockMovementsTable get customerStockMovements =>
      attachedDatabase.customerStockMovements;
  $ProductVariantsTable get productVariants => attachedDatabase.productVariants;
  $InvoiceItemsTable get invoiceItems => attachedDatabase.invoiceItems;
  $LedgerTransactionsTable get ledgerTransactions =>
      attachedDatabase.ledgerTransactions;
  ManufacturingDeliveryDaoManager get managers =>
      ManufacturingDeliveryDaoManager(this);
}

class ManufacturingDeliveryDaoManager {
  final _$ManufacturingDeliveryDaoMixin _db;
  ManufacturingDeliveryDaoManager(this._db);
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
  $$BomItemsTableTableManager get bomItems =>
      $$BomItemsTableTableManager(_db.attachedDatabase, _db.bomItems);
  $$ManufacturingScrapsTableTableManager get manufacturingScraps =>
      $$ManufacturingScrapsTableTableManager(
        _db.attachedDatabase,
        _db.manufacturingScraps,
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
  $$ProductVariantsTableTableManager get productVariants =>
      $$ProductVariantsTableTableManager(
        _db.attachedDatabase,
        _db.productVariants,
      );
  $$InvoiceItemsTableTableManager get invoiceItems =>
      $$InvoiceItemsTableTableManager(_db.attachedDatabase, _db.invoiceItems);
  $$LedgerTransactionsTableTableManager get ledgerTransactions =>
      $$LedgerTransactionsTableTableManager(
        _db.attachedDatabase,
        _db.ledgerTransactions,
      );
}
