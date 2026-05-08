// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'enhanced_purchase_dao.dart';

// ignore_for_file: type=lint
mixin _$EnhancedPurchaseDaoMixin on DatabaseAccessor<AppDatabase> {
  $EnhancedSuppliersTable get enhancedSuppliers =>
      attachedDatabase.enhancedSuppliers;
  $EnhancedPurchasesTable get enhancedPurchases =>
      attachedDatabase.enhancedPurchases;
  $ProductsTable get products => attachedDatabase.products;
  $EnhancedPurchaseItemsTable get enhancedPurchaseItems =>
      attachedDatabase.enhancedPurchaseItems;
  $SupplierPaymentsTable get supplierPayments =>
      attachedDatabase.supplierPayments;
  EnhancedPurchaseDaoManager get managers => EnhancedPurchaseDaoManager(this);
}

class EnhancedPurchaseDaoManager {
  final _$EnhancedPurchaseDaoMixin _db;
  EnhancedPurchaseDaoManager(this._db);
  $$EnhancedSuppliersTableTableManager get enhancedSuppliers =>
      $$EnhancedSuppliersTableTableManager(
        _db.attachedDatabase,
        _db.enhancedSuppliers,
      );
  $$EnhancedPurchasesTableTableManager get enhancedPurchases =>
      $$EnhancedPurchasesTableTableManager(
        _db.attachedDatabase,
        _db.enhancedPurchases,
      );
  $$ProductsTableTableManager get products =>
      $$ProductsTableTableManager(_db.attachedDatabase, _db.products);
  $$EnhancedPurchaseItemsTableTableManager get enhancedPurchaseItems =>
      $$EnhancedPurchaseItemsTableTableManager(
        _db.attachedDatabase,
        _db.enhancedPurchaseItems,
      );
  $$SupplierPaymentsTableTableManager get supplierPayments =>
      $$SupplierPaymentsTableTableManager(
        _db.attachedDatabase,
        _db.supplierPayments,
      );
}
