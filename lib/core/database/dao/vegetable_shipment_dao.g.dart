// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'vegetable_shipment_dao.dart';

// ignore_for_file: type=lint
mixin _$VegetableShipmentDaoMixin on DatabaseAccessor<AppDatabase> {
  $SuppliersTable get suppliers => attachedDatabase.suppliers;
  $VegetableShipmentsTable get vegetableShipments =>
      attachedDatabase.vegetableShipments;
  VegetableShipmentDaoManager get managers => VegetableShipmentDaoManager(this);
}

class VegetableShipmentDaoManager {
  final _$VegetableShipmentDaoMixin _db;
  VegetableShipmentDaoManager(this._db);
  $$SuppliersTableTableManager get suppliers =>
      $$SuppliersTableTableManager(_db.attachedDatabase, _db.suppliers);
  $$VegetableShipmentsTableTableManager get vegetableShipments =>
      $$VegetableShipmentsTableTableManager(
        _db.attachedDatabase,
        _db.vegetableShipments,
      );
}
