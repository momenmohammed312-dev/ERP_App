// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sales_dao.dart';

// ignore_for_file: type=lint
mixin _$SalesDaoMixin on DatabaseAccessor<AppDatabase> {
  $InvoicesTable get invoices => attachedDatabase.invoices;
  $SalesTable get sales => attachedDatabase.sales;
  SalesDaoManager get managers => SalesDaoManager(this);
}

class SalesDaoManager {
  final _$SalesDaoMixin _db;
  SalesDaoManager(this._db);
  $$InvoicesTableTableManager get invoices =>
      $$InvoicesTableTableManager(_db.attachedDatabase, _db.invoices);
  $$SalesTableTableManager get sales =>
      $$SalesTableTableManager(_db.attachedDatabase, _db.sales);
}
