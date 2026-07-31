// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'credit_payments_dao.dart';

// ignore_for_file: type=lint
mixin _$CreditPaymentsDaoMixin on DatabaseAccessor<AppDatabase> {
  $SuppliersTable get suppliers => attachedDatabase.suppliers;
  $VegetableShipmentsTable get vegetableShipments =>
      attachedDatabase.vegetableShipments;
  $InvoicesTable get invoices => attachedDatabase.invoices;
  $CreditPaymentsTable get creditPayments => attachedDatabase.creditPayments;
  CreditPaymentsDaoManager get managers => CreditPaymentsDaoManager(this);
}

class CreditPaymentsDaoManager {
  final _$CreditPaymentsDaoMixin _db;
  CreditPaymentsDaoManager(this._db);
  $$SuppliersTableTableManager get suppliers =>
      $$SuppliersTableTableManager(_db.attachedDatabase, _db.suppliers);
  $$VegetableShipmentsTableTableManager get vegetableShipments =>
      $$VegetableShipmentsTableTableManager(
        _db.attachedDatabase,
        _db.vegetableShipments,
      );
  $$InvoicesTableTableManager get invoices =>
      $$InvoicesTableTableManager(_db.attachedDatabase, _db.invoices);
  $$CreditPaymentsTableTableManager get creditPayments =>
      $$CreditPaymentsTableTableManager(
        _db.attachedDatabase,
        _db.creditPayments,
      );
}
