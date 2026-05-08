// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'inventory_movement_dao.dart';

// ignore_for_file: type=lint
mixin _$InventoryMovementDaoMixin on DatabaseAccessor<AppDatabase> {
  $ProductsTable get products => attachedDatabase.products;
  $InventoryMovementsTable get inventoryMovements =>
      attachedDatabase.inventoryMovements;
  InventoryMovementDaoManager get managers => InventoryMovementDaoManager(this);
}

class InventoryMovementDaoManager {
  final _$InventoryMovementDaoMixin _db;
  InventoryMovementDaoManager(this._db);
  $$ProductsTableTableManager get products =>
      $$ProductsTableTableManager(_db.attachedDatabase, _db.products);
  $$InventoryMovementsTableTableManager get inventoryMovements =>
      $$InventoryMovementsTableTableManager(
        _db.attachedDatabase,
        _db.inventoryMovements,
      );
}
