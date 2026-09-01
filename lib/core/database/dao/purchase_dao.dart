import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../app_database.dart';
import '../tables/tables.dart';

part 'purchase_dao.g.dart';

@DriftAccessor(tables: [Purchases, PurchaseItems])
class PurchaseDao extends DatabaseAccessor<AppDatabase>
    with _$PurchaseDaoMixin {
  PurchaseDao(super.db);

  // Get all purchases
  Future<List<Purchase>> getAllPurchases() {
    return (select(purchases)
          ..where((p) => p.isDeleted.equals(false))
          ..orderBy([
            (p) => OrderingTerm(
              expression: p.purchaseDate,
              mode: OrderingMode.desc,
            ),
          ]))
        .get();
  }

  // Get purchase by ID
  Future<Purchase?> getPurchaseById(String id) =>
      (select(purchases)
            ..where((p) => p.id.equals(id) & p.isDeleted.equals(false)))
          .getSingleOrNull();

  // Get purchases by supplier
  Future<List<Purchase>> getPurchasesBySupplier(String supplierId) =>
      (select(purchases)..where(
            (p) => p.supplierId.equals(supplierId) & p.isDeleted.equals(false),
          ))
          .get();

  // Get purchases by date range
  Future<List<Purchase>> getPurchasesByDateRange(DateTime start, DateTime end) {
    return (select(purchases)
          ..where(
            (p) =>
                p.purchaseDate.isBetweenValues(start, end) &
                p.isDeleted.equals(false),
          )
          ..orderBy([
            (p) => OrderingTerm(
              expression: p.purchaseDate,
              mode: OrderingMode.desc,
            ),
          ]))
        .get();
  }

  // Get today's purchases
  Future<List<Purchase>> getTodayPurchases() {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59);

    return getPurchasesByDateRange(startOfDay, endOfDay);
  }

  // Get purchase items for a purchase
  Future<List<PurchaseItem>> getPurchaseItems(String purchaseId) => (select(
    purchaseItems,
  )..where((pi) => pi.purchaseId.equals(purchaseId))).get();

  Future<List<(PurchaseItem, Product?)>> getItemsWithProductsByPurchase(
    String purchaseId,
  ) {
    final query = select(purchaseItems).join([
      leftOuterJoin(
        db.products,
        db.products.id.cast<String>().equalsExp(purchaseItems.productId),
      ),
    ])..where(purchaseItems.purchaseId.equals(purchaseId));

    return query.map((row) {
      return (row.readTable(purchaseItems), row.readTableOrNull(db.products));
    }).get();
  }

  // Insert purchase with items
  Future<String> insertPurchaseWithItems({
    String? supplierId,
    required String invoiceNumber,
    required String description,
    required double totalAmount,
    required double paidAmount,
    required String paymentMethod,
    required String status,
    required DateTime purchaseDate,
    String? notes,
    required List<Map<String, dynamic>> items,
  }) async {
    return transaction(() async {
      // Insert purchase
      final purchaseId = const Uuid().v4();
      await into(purchases).insert(
        PurchasesCompanion(
          id: Value(purchaseId),
          supplierId: supplierId != null
              ? Value(supplierId)
              : const Value.absent(),
          invoiceNumber: Value(invoiceNumber),
          description: Value(description),
          totalAmount: Value(totalAmount),
          paidAmount: Value(paidAmount),
          paymentMethod: Value(paymentMethod),
          status: Value(status),
          purchaseDate: Value(purchaseDate),
          createdAt: Value(DateTime.now()),
          notes: notes != null ? Value(notes) : const Value.absent(),
        ),
      );

      // Insert purchase items and update product quantities
      for (final item in items) {
        final productId = item['productId'] as int;
        final quantity = item['quantity'] as int;
        final unitPrice = item['unitPrice'] as double;
        final unit = item['unit'] as String;
        final cartonQuantity = item['cartonQuantity'] as int?;
        final cartonPrice = item['cartonPrice'] as double?;
        final discount = item['discount'] as double? ?? 0.0;
        final tax = item['tax'] as double? ?? 0.0;

        // Get current product stock
        final product = await (select(
          db.products,
        )..where((p) => p.id.equals(productId))).getSingleOrNull();
        if (product == null) {
          throw Exception('Product not found: $productId');
        }

        final originalStock = product.quantity;
        final newStock = originalStock + quantity;

        // Update product quantity
        await update(db.products).replace(
          ProductsCompanion(
            id: Value(product.id),
            name: Value(product.name),
            quantity: Value(newStock),
            price: Value(product.price),
            unit: Value(product.unit),
            category: Value(product.category),
            barcode: Value(product.barcode),
            cartonQuantity: Value(product.cartonQuantity),
            cartonPrice: Value(product.cartonPrice),
            status: Value(product.status),
          ),
        );

        // Phase 6: Audit trail — log purchase movement in InventoryMovements (first real usage parity with manufacturing)
        // Purely additive, does not affect purchase totals or balances.
        try {
          final now = DateTime.now();
          await into(db.inventoryMovements).insert(
            InventoryMovementsCompanion.insert(
              productId: productId,
              movementType: 'purchase',
              quantity: quantity,
              unitCost: unitPrice,
              totalValue: quantity * unitPrice,
              movementDate: purchaseDate,
              reference: invoiceNumber,
              referenceType: 'purchase_invoice',
              previousQuantity: originalStock,
              newQuantity: newStock,
              performedBy: const Value.absent(),
              notes: Value('شراء فاتورة $invoiceNumber من مورد ${supplierId ?? ''}'),
              createdAt: now,
              updatedAt: now,
            ),
          );
        } catch (e) {
          // Non-fatal — purchase itself already succeeded inside the same transaction,
          // but a movement logging failure should not abort the whole purchase.
          // Drift will still roll back if we throw, so we catch and log.
          // For strict atomicity, rethrow if you want purchase to fail on movement failure.
          // ignore: avoid_print
          print('Purchase inventory movement logging failed for product $productId: $e');
        }

        // Insert purchase item
        await into(purchaseItems).insert(
          PurchaseItemsCompanion.insert(
            id: '$purchaseId$productId',
            purchaseId: purchaseId,
            productId: productId.toString(),
            quantity: quantity,
            unitPrice: unitPrice,
            totalPrice: (quantity * unitPrice) - discount + tax,
            unit: unit,
            cartonQuantity: cartonQuantity != null
                ? Value(cartonQuantity)
                : const Value.absent(),
            cartonPrice: cartonPrice != null
                ? Value(cartonPrice)
                : const Value.absent(),
            discount: Value(discount),
            tax: Value(tax),
            createdAt: DateTime.now(),
            originalStock: Value(originalStock),
            newStock: Value(newStock),
          ),
        );
      }

      return purchaseId;
    });
  }

  // Update purchase status
  Future<void> updatePurchaseStatus(String purchaseId, String status) {
    return (update(purchases)..where((p) => p.id.equals(purchaseId))).write(
      PurchasesCompanion(status: Value(status)),
    );
  }

  // Soft delete purchase
  Future<void> deletePurchase(String purchaseId) {
    return (update(purchases)..where((p) => p.id.equals(purchaseId))).write(
      PurchasesCompanion(isDeleted: Value(true)),
    );
  }

  // Get purchase statistics
  Future<Map<String, dynamic>> getPurchaseStats() async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59);
    final startOfMonth = DateTime(now.year, now.month, 1);
    final endOfMonth = DateTime(now.year, now.month + 1, 0, 23, 59, 59);

    final todayPurchases = await getPurchasesByDateRange(startOfDay, endOfDay);
    final monthPurchases = await getPurchasesByDateRange(
      startOfMonth,
      endOfMonth,
    );
    final allPurchases = await getAllPurchases();

    return {
      'todayTotal': todayPurchases.fold<double>(
        0,
        (sum, p) => sum + p.totalAmount,
      ),
      'todayCount': todayPurchases.length,
      'monthTotal': monthPurchases.fold<double>(
        0,
        (sum, p) => sum + p.totalAmount,
      ),
      'monthCount': monthPurchases.length,
      'allTimeTotal': allPurchases.fold<double>(
        0,
        (sum, p) => sum + p.totalAmount,
      ),
      'allTimeCount': allPurchases.length,
    };
  }
}
