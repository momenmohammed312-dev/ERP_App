// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'purchase_orders_dao.dart';

// ignore_for_file: type=lint
mixin _$PurchaseOrdersDaoMixin on DatabaseAccessor<AppDatabase> {
  $PurchaseOrdersTable get purchaseOrders => attachedDatabase.purchaseOrders;
  $PurchaseOrderItemsTable get purchaseOrderItems =>
      attachedDatabase.purchaseOrderItems;
  $PurchaseOrderStatusesTable get purchaseOrderStatuses =>
      attachedDatabase.purchaseOrderStatuses;
  PurchaseOrdersDaoManager get managers => PurchaseOrdersDaoManager(this);
}

class PurchaseOrdersDaoManager {
  final _$PurchaseOrdersDaoMixin _db;
  PurchaseOrdersDaoManager(this._db);
  $$PurchaseOrdersTableTableManager get purchaseOrders =>
      $$PurchaseOrdersTableTableManager(
        _db.attachedDatabase,
        _db.purchaseOrders,
      );
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
