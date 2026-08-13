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

  Future<void> updateProductBarcode(int id, String barcode) async {
    await (update(products)..where((p) => p.id.equals(id))).write(
      ProductsCompanion(
        barcode: Value(barcode),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await _enqueueProduct(id, null, 'update');
  }

  /// Writes a product row pulled from Supabase without re-enqueueing it for
  /// push (the row already came from the remote, pushing it back is redundant).
  /// Looks up an existing local row by `syncId` first: if found, updates it
  /// only when the remote `updatedAt` is newer than the local one (last-write-
  /// wins); if not found, inserts a new local row with a fresh local
  /// autoincrement `id` but the same `syncId`.
  Future<void> upsertFromRemote(Map<String, dynamic> remoteRow) async {
    final syncId = remoteRow['sync_id'] as String?;
    if (syncId == null || syncId.isEmpty) return;
    final remoteUpdated =
        DateTime.tryParse(remoteRow['updated_at'] as String? ?? '');
    final existing = await (select(products)
          ..where((t) => t.syncId.equals(syncId)))
        .getSingleOrNull();

    if (existing != null &&
        existing.updatedAt != null &&
        remoteUpdated != null &&
        existing.updatedAt!.isAfter(remoteUpdated)) {
      // Local row is newer — last-write-wins: do not overwrite.
      return;
    }

    final companion = ProductsCompanion(
      syncId: Value(syncId),
      name: Value(remoteRow['name'] as String? ?? ''),
      quantity: Value((remoteRow['quantity'] as num?)?.toInt() ?? 0),
      price: Value((remoteRow['price'] as num?)?.toDouble() ?? 0),
      unit: Value(remoteRow['unit'] as String?),
      category: Value(remoteRow['category'] as String?),
      barcode: Value(remoteRow['barcode'] as String?),
      costPrice: Value((remoteRow['cost_price'] as num?)?.toDouble()),
      status: Value(remoteRow['status'] as String?),
      updatedAt: Value(remoteUpdated),
    );

    if (existing != null) {
      await (update(products)..where((t) => t.id.equals(existing.id)))
          .write(companion);
    } else {
      await into(products).insert(companion);
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
          'updated_at': (p.updatedAt ?? DateTime.now()).toUtc().toIso8601String(),
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

  /// Search products by name or barcode using LIKE.
  Future<List<Product>> searchProducts(String query) {
    final q = query.trim();
    if (q.isEmpty) return getAllProducts();

    return (select(products)
      ..where(
        (p) =>
            (p.status.equals('Deleted').not() | p.status.isNull()) &
            (p.name.like('%$q%') | p.barcode.like('%$q%')),
      ))
        .get();
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
      query = query..where(
        (p) => p.name.like('%$searchQuery%') | p.barcode.like('%$searchQuery%'),
      );
    }

    return query.get();
  }
}
