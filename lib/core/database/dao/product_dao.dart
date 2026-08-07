// database/dao/product_dao.dart
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

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
      
  /// Inserts a product, stamps it with a fresh `syncId` + createdAt/updatedAt,
  /// and queues an 'insert' sync entry. The local write always succeeds even if
  /// enqueueing fails.
  Future<int> insertProduct(Insertable<Product> product) async {
    final syncId = const Uuid().v4();
    final now = DateTime.now();
    Insertable<Product> decorated = product;
    if (product is ProductsCompanion) {
      decorated = product.copyWith(
        syncId: Value(syncId),
        createdAt: Value(now),
        updatedAt: Value(now),
      );
    } else if (product is Product) {
      decorated = product.copyWith(
        syncId: Value(syncId),
        createdAt: Value(now),
        updatedAt: Value(now),
      );
    }
    final insertedId = await into(products).insert(decorated);
    await _enqueueProduct(insertedId, syncId, 'insert');
    return insertedId;
  }
      
  /// Updates a product, bumps `updatedAt`, and queues an 'update' sync.
  Future updateProduct(Insertable<Product> product) async {
    Insertable<Product> decorated = product;
    if (product is ProductsCompanion) {
      decorated = product.copyWith(updatedAt: Value(DateTime.now()));
    } else if (product is Product) {
      decorated = product.copyWith(updatedAt: Value(DateTime.now()));
    }
    await update(products).replace(decorated);
    final localId = product is ProductsCompanion
        ? product.id.value
        : product is Product
            ? product.id
            : null;
    if (localId != null) {
      await _enqueueProduct(localId, null, 'update');
    }
  }

  /// Enqueues a product for sync. Re-reads the row to build a payload that only
  /// references Supabase columns (snake_case), never the local int `id`.
  /// Any failure here is caught so it never breaks the local write.
  Future<void> _enqueueProduct(int id, String? syncIdOverride, String operation) async {
    try {
      final p = await getProductById(id);
      final syncId = syncIdOverride ?? p?.syncId;
      if (p == null || syncId == null) return;
      await db.syncQueueDao.enqueue(
        tableName: 'products',
        recordSyncId: syncId,
        operation: operation,
        payload: {
          'sync_id': syncId,
          'name': p.name,
          'quantity': p.quantity,
          'price': p.price,
          'unit': p.unit,
          'category': p.category,
          'barcode': p.barcode,
          'cost_price': p.costPrice,
          'status': p.status,
          'updated_at': (p.updatedAt ?? DateTime.now()).toIso8601String(),
        },
      );
    } catch (e) {
      print('Enqueue product ($operation) failed: $e');
    }
  }
      
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
