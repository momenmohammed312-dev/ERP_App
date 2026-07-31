// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sales_returns_dao.dart';

// ignore_for_file: type=lint
mixin _$SalesReturnsDaoMixin on DatabaseAccessor<AppDatabase> {
  $SuppliersTable get suppliers => attachedDatabase.suppliers;
  $VegetableShipmentsTable get vegetableShipments =>
      attachedDatabase.vegetableShipments;
  $InvoicesTable get invoices => attachedDatabase.invoices;
  $SalesReturnsTable get salesReturns => attachedDatabase.salesReturns;
  $ProductsTable get products => attachedDatabase.products;
  $SalesReturnItemsTable get salesReturnItems =>
      attachedDatabase.salesReturnItems;
  SalesReturnsDaoManager get managers => SalesReturnsDaoManager(this);
}

class SalesReturnsDaoManager {
  final _$SalesReturnsDaoMixin _db;
  SalesReturnsDaoManager(this._db);
  $$SuppliersTableTableManager get suppliers =>
      $$SuppliersTableTableManager(_db.attachedDatabase, _db.suppliers);
  $$VegetableShipmentsTableTableManager get vegetableShipments =>
      $$VegetableShipmentsTableTableManager(
        _db.attachedDatabase,
        _db.vegetableShipments,
      );
  $$InvoicesTableTableManager get invoices =>
      $$InvoicesTableTableManager(_db.attachedDatabase, _db.invoices);
  $$SalesReturnsTableTableManager get salesReturns =>
      $$SalesReturnsTableTableManager(_db.attachedDatabase, _db.salesReturns);
  $$ProductsTableTableManager get products =>
      $$ProductsTableTableManager(_db.attachedDatabase, _db.products);
  $$SalesReturnItemsTableTableManager get salesReturnItems =>
      $$SalesReturnItemsTableTableManager(
        _db.attachedDatabase,
        _db.salesReturnItems,
      );
}
