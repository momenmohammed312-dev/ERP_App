import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../app_database.dart';
import '../tables/inventory_movements_table.dart';

part 'inventory_movement_dao.g.dart';

/// DAO for Inventory Movements operations
/// عمليات حركة المخزون
@DriftAccessor(tables: [InventoryMovements])
class InventoryMovementDao extends DatabaseAccessor<AppDatabase>
    with _$InventoryMovementDaoMixin {
  InventoryMovementDao(super.db);

  /// Get all inventory movements
  /// الحصول على كل حركات المخزون
  Future<List<InventoryMovement>> getAllMovements() =>
      select(inventoryMovements).get();

  /// Get movements by product
  /// الحصول على حركات منتج معين
  Future<List<InventoryMovement>> getMovementsByProduct(int productId) =>
      (select(
        inventoryMovements,
      )..where((tbl) => tbl.productId.equals(productId))).get();

  /// Get movements by date range
  /// الحصول على حركات في فترة زمنية
  Future<List<InventoryMovement>> getMovementsByDateRange(
    DateTime startDate,
    DateTime endDate,
  ) =>
      (select(inventoryMovements)
            ..where(
              (tbl) => tbl.movementDate.isBetweenValues(startDate, endDate),
            )
            ..orderBy([
              (t) => OrderingTerm(
                expression: t.movementDate,
                mode: OrderingMode.desc,
              ),
            ]))
          .get();

  /// Get movements by type
  /// الحصول على حركات حسب النوع
  Future<List<InventoryMovement>> getMovementsByType(String movementType) =>
      (select(
        inventoryMovements,
      )..where((tbl) => tbl.movementType.equals(movementType))).get();

  /// Get movements by reference
  /// الحصول على حركات حسب المرجع
  Future<List<InventoryMovement>> getMovementsByReference(String reference) =>
      (select(
        inventoryMovements,
      )..where((tbl) => tbl.reference.equals(reference))).get();

  /// Create inventory movement
  /// إنشاء حركة مخزون
  Future<int> createMovement(InventoryMovementsCompanion movement) async {
    final movementId = await into(inventoryMovements).insert(movement);
    await _enqueueStockMovement(movement, movementId);
    return movementId;
  }

/// Enqueues a signed stock delta for sync. The payload matches the
   /// `apply_stock_delta` Postgres RPC arguments (snake_case) and never includes
   /// local snapshots like previous/new quantity. `location_id` is intentionally
   /// NOT set here: `SyncService.syncNow()` reads the device location id once
   /// and adds `location_id` to every payload centrally (both upserts and the
   /// `apply_stock_delta` RPC). Do not add it here or it will be set twice.
   /// Failures are swallowed so the local movement write always succeeds.
  Future<void> _enqueueStockMovement(
    InventoryMovementsCompanion movement,
    int movementId,
  ) async {
    try {
      final productLocalId = movement.productId.value;
      String? productSyncId;
      final product = await (select(db.products)
            ..where((p) => p.id.equals(productLocalId)))
          .getSingleOrNull();
      productSyncId = product?.syncId;
      if (productSyncId == null) return;

      // Guards against absent companion values so a partial companion never
      // crashes the enqueue (and silently drops a stock delta from sync).
      final quantityDelta =
          movement.quantity.present ? movement.quantity.value : null;
      final movementType =
          movement.movementType.present ? movement.movementType.value : null;
      final reference =
          movement.reference.present ? movement.reference.value : null;
      final movementDate = movement.movementDate.present
          ? movement.movementDate.value
          : null;
      if (quantityDelta == null || movementType == null || movementDate == null) {
        return;
      }

      await db.syncQueueDao.enqueue(
        tableName: 'stock_movements',
        recordSyncId: const Uuid().v4(),
        operation: 'stock_delta',
        payload: {
          'product_sync_id': productSyncId,
          'quantity_delta': quantityDelta,
          'movement_type': movementType,
          'reference': reference,
          'movement_date': movementDate.toIso8601String(),
        },
      );
    } catch (e) {
      print('Enqueue stock movement (id=$movementId) failed: $e');
    }
  }

  /// Create movement with automatic timestamps
  /// إنشاء حركة مع طوابع زمنية تلقائية
  Future<int> createMovementWithTimestamp({
    required int productId,
    required String movementType,
    required int quantity,
    required double unitCost,
    required double totalValue,
    required DateTime movementDate,
    required String reference,
    required String referenceType,
    required int previousQuantity,
    required int newQuantity,
    String? performedBy,
    String? notes,
  }) {
    final now = DateTime.now();
    return createMovement(
      InventoryMovementsCompanion.insert(
        productId: productId,
        movementType: movementType,
        quantity: quantity,
        unitCost: unitCost,
        totalValue: totalValue,
        movementDate: movementDate,
        reference: reference,
        referenceType: referenceType,
        previousQuantity: previousQuantity,
        newQuantity: newQuantity,
        performedBy: Value(performedBy),
        notes: Value(notes),
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  /// Get product movement summary
  /// الحصول على ملخص حركات المنتج
  Future<Map<String, dynamic>> getProductMovementSummary(int productId) async {
    final movements = await getMovementsByProduct(productId);

    int totalIn = 0;
    int totalOut = 0;
    double totalValue = 0.0;

    for (final movement in movements) {
      if (movement.quantity > 0) {
        totalIn += movement.quantity;
      } else {
        totalOut += movement.quantity.abs();
      }
      totalValue += movement.totalValue;
    }

    return {
      'totalIn': totalIn,
      'totalOut': totalOut,
      'netChange': totalIn - totalOut,
      'totalValue': totalValue,
      'movementCount': movements.length,
    };
  }

  /// Get low stock movements (recent movements for low stock items)
  /// الحصول على حركات المخزون المنخفض
  Future<List<InventoryMovement>> getLowStockMovements(int threshold) async {
    // Get products with low stock
    final lowStockProducts = await (select(
      db.products,
    )..where((tbl) => tbl.quantity.isSmallerThanValue(threshold))).get();

    if (lowStockProducts.isEmpty) return [];

    final productIds = lowStockProducts.map((p) => p.id).toList();

    return (select(inventoryMovements)
          ..where((tbl) => tbl.productId.isIn(productIds))
          ..orderBy([
            (t) => OrderingTerm(
              expression: t.movementDate,
              mode: OrderingMode.desc,
            ),
          ])
          ..limit(50))
        .get();
  }

  /// Get movement statistics
  /// الحصول على إحصائيات الحركات
  Future<Map<String, dynamic>> getMovementStatistics(
    DateTime startDate,
    DateTime endDate,
  ) async {
    final movements = await getMovementsByDateRange(startDate, endDate);

    int purchases = 0;
    int sales = 0;
    int adjustments = 0;
    double purchaseValue = 0.0;
    double salesValue = 0.0;

    for (final movement in movements) {
      switch (movement.movementType) {
        case 'purchase':
          purchases++;
          purchaseValue += movement.totalValue.abs();
          break;
        case 'sale':
          sales++;
          salesValue += movement.totalValue.abs();
          break;
        case 'adjustment':
          adjustments++;
          break;
      }
    }

    return {
      'totalMovements': movements.length,
      'purchases': purchases,
      'sales': sales,
      'adjustments': adjustments,
      'purchaseValue': purchaseValue,
      'salesValue': salesValue,
      'netValue': purchaseValue - salesValue,
    };
  }

  /// Delete old movements (cleanup)
  /// حذف الحركات القديمة (تنظيف)
  Future<int> deleteOldMovements(DateTime beforeDate) => (delete(
    inventoryMovements,
  )..where((tbl) => tbl.movementDate.isSmallerThanValue(beforeDate))).go();

  /// Update movement
  /// تحديث حركة
  Future<bool> updateMovement(InventoryMovement movement) =>
      update(inventoryMovements).replace(movement);

  /// Delete movement
  /// حذف حركة
  Future<int> deleteMovement(int id) =>
      (delete(inventoryMovements)..where((tbl) => tbl.id.equals(id))).go();
}
