// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'purchase_orders_dao.dart';

// ignore_for_file: type=lint
mixin _$PurchaseOrdersDaoMixin on DatabaseAccessor<AppDatabase> {
  $EnhancedSuppliersTable get enhancedSuppliers =>
      attachedDatabase.enhancedSuppliers;
  $PurchaseOrdersTable get purchaseOrders => attachedDatabase.purchaseOrders;
  $ProductsTable get products => attachedDatabase.products;
  $PurchaseOrderItemsTable get purchaseOrderItems =>
      attachedDatabase.purchaseOrderItems;
  $PurchaseOrderStatusesTable get purchaseOrderStatuses =>
      attachedDatabase.purchaseOrderStatuses;
  PurchaseOrdersDaoManager get managers => PurchaseOrdersDaoManager(this);
}

class PurchaseOrdersDaoManager {
  final _$PurchaseOrdersDaoMixin _db;
  PurchaseOrdersDaoManager(this._db);
  $$EnhancedSuppliersTableTableManager get enhancedSuppliers =>
      $$EnhancedSuppliersTableTableManager(
        _db.attachedDatabase,
        _db.enhancedSuppliers,
      );
  $$PurchaseOrdersTableTableManager get purchaseOrders =>
      $$PurchaseOrdersTableTableManager(
        _db.attachedDatabase,
        _db.purchaseOrders,
      );
  $$ProductsTableTableManager get products =>
      $$ProductsTableTableManager(_db.attachedDatabase, _db.products);
  $$PurchaseOrderItemsTableTableManager get purchaseOrderItems =>
      $$PurchaseOrderItemsTableTableManager(
        _db.attachedDatabase,
        _db.purchaseOrderItems,
      );
  $$PurchaseOrderStatusesTableTableManager get purchaseOrderStatuses =>
      $$PurchaseOrderStatusesTableTableManager(
        _db.attachedDatabase,
        _db.purchaseOrderStatuses,
      );
}
