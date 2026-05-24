// database/dao/product_dao.dart
import 'package:drift/drift.dart';

import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/tables/product_table.dart';

part 'product_dao.g.dart';

@DriftAccessor(tables: [Products])
class ProductDao extends DatabaseAccessor<AppDatabase> with _$ProductDaoMixin {
  ProductDao(super.db);

  Future<List<Product>> getAllProducts() => 
      (select(products)..where((p) => p.status.equals('Deleted').not() | p.status.isNull())).get();
      
  Stream<List<Product>> watchAllProducts() => 
      (select(products)..where((p) => p.status.equals('Deleted').not() | p.status.isNull())).watch();
      
  Future insertProduct(Insertable<Product> product) =>
      into(products).insert(product);
      
  Future updateProduct(Insertable<Product> product) =>
      update(products).replace(product);
      
  // Total products count
  Future<int> getTotalProductCount() async {
    final countExp = products.id.count();
    final query = selectOnly(products)
      ..addColumns([countExp])
      ..where(products.status.equals('Deleted').not() | products.status.isNull());

    final result = await query.getSingle();
    return result.read(countExp) ?? 0;
  }

  Future deleteProduct(Product product) async {
    try {
      // Try hard delete first
      await delete(products).delete(product);
    } catch (e) {
      // If it fails (likely due to foreign key constraints), do a soft delete
      await update(products).replace(product.copyWith(status: const Value('Deleted')));
    }
  }

  /// Search products by name or SKU/code using LIKE.
  Future<List<Product>> searchProducts(String query) {
    final q = query.trim();
    if (q.isEmpty) return getAllProducts();

    return (select(products)
      ..where((p) => (p.status.equals('Deleted').not() | p.status.isNull()) & p.name.like('%$q%'))
    ).get();
  }

  /// Get products by category
  Future<List<Product>> getProductsByCategory(String? category) {
    if (category == null || category == 'all') {
      return getAllProducts();
    }
    return (select(products)
      ..where((p) => (p.status.equals('Deleted').not() | p.status.isNull()) & p.category.equals(category))
    ).get();
  }

  /// Search products by barcode
  Future<Product?> getProductByBarcode(String barcode) {
    return (select(products)
      ..where((p) => (p.status.equals('Deleted').not() | p.status.isNull()) & p.barcode.equals(barcode))
    ).getSingleOrNull();
  }

  /// Get all unique categories (excluding deleted products)
  Future<List<String>> getUniqueCategories() {
    final query = selectOnly(products)
      ..addColumns([products.category])
      ..where(products.category.isNotNull() & (products.status.equals('Deleted').not() | products.status.isNull()))
      ..groupBy([products.category]);

    return query.map((row) => row.read(products.category)!).get();
  }

  /// Get product by ID (Even if deleted, useful for historical invoices)
  Future<Product?> getProductById(int id) {
    return (select(products)..where((p) => p.id.equals(id))).getSingleOrNull();
  }

  /// Filter products by category and unit
  Future<List<Product>> filterProducts({
    String? category,
    String? unit,
    String? searchQuery,
  }) {
    var query = select(products)..where((p) => p.status.equals('Deleted').not() | p.status.isNull());

    if (category != null && category != 'all') {
      query = query..where((p) => p.category.equals(category));
    }

    if (unit != null && unit != 'all') {
      query = query..where((p) => p.unit.equals(unit));
    }

    if (searchQuery != null && searchQuery.isNotEmpty) {
      query = query..where((p) => p.name.like('%$searchQuery%'));
    }

    return query.get();
  }
}
