// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sales_returns_dao.dart';

// ignore_for_file: type=lint
mixin _$SalesReturnsDaoMixin on DatabaseAccessor<AppDatabase> {
  $SalesReturnsTable get salesReturns => attachedDatabase.salesReturns;
  $SalesReturnItemsTable get salesReturnItems =>
      attachedDatabase.salesReturnItems;
  SalesReturnsDaoManager get managers => SalesReturnsDaoManager(this);
}

class SalesReturnsDaoManager {
  final _$SalesReturnsDaoMixin _db;
  SalesReturnsDaoManager(this._db);
  $$SalesReturnsTableTableManager get salesReturns =>
      $$SalesReturnsTableTableManager(_db.attachedDatabase, _db.salesReturns);
  $$SalesReturnItemsTableTableManager get salesReturnItems =>
      $$SalesReturnItemsTableTableManager(
        _db.attachedDatabase,
        _db.salesReturnItems,
      );
}
