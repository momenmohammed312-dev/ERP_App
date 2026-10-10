// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'return_refunds_dao.dart';

// ignore_for_file: type=lint
mixin _$ReturnRefundsDaoMixin on DatabaseAccessor<AppDatabase> {
  $SuppliersTable get suppliers => attachedDatabase.suppliers;
  $VegetableShipmentsTable get vegetableShipments =>
      attachedDatabase.vegetableShipments;
  $InvoicesTable get invoices => attachedDatabase.invoices;
  $SalesReturnsTable get salesReturns => attachedDatabase.salesReturns;
  $ReturnRefundsTable get returnRefunds => attachedDatabase.returnRefunds;
  ReturnRefundsDaoManager get managers => ReturnRefundsDaoManager(this);
}

class ReturnRefundsDaoManager {
  final _$ReturnRefundsDaoMixin _db;
  ReturnRefundsDaoManager(this._db);
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
  $$ReturnRefundsTableTableManager get returnRefunds =>
      $$ReturnRefundsTableTableManager(_db.attachedDatabase, _db.returnRefunds);
}
