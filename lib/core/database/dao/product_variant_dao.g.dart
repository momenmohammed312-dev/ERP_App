// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'product_variant_dao.dart';

// ignore_for_file: type=lint
mixin _$ProductVariantDaoMixin on DatabaseAccessor<AppDatabase> {
  $ProductsTable get products => attachedDatabase.products;
  $ProductVariantsTable get productVariants => attachedDatabase.productVariants;
  ProductVariantDaoManager get managers => ProductVariantDaoManager(this);
}

class ProductVariantDaoManager {
  final _$ProductVariantDaoMixin _db;
  ProductVariantDaoManager(this._db);
  $$ProductsTableTableManager get products =>
      $$ProductsTableTableManager(_db.attachedDatabase, _db.products);
  $$ProductVariantsTableTableManager get productVariants =>
      $$ProductVariantsTableTableManager(
        _db.attachedDatabase,
        _db.productVariants,
      );
}
