import 'package:drift/drift.dart';

import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_orders_table.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_scrap_table.dart';
import 'package:pos_offline_desktop/core/database/tables/product_table.dart';

part 'manufacturing_scrap_dao.g.dart';

@DriftAccessor(tables: [ManufacturingScraps, Products])
class ManufacturingScrapDao extends DatabaseAccessor<AppDatabase>
    with _$ManufacturingScrapDaoMixin {
  ManufacturingScrapDao(super.db);

  // ── Reads ──

  Future<List<ManufacturingScrap>> getAll() =>
      (select(manufacturingScraps)
            ..orderBy([(s) => OrderingTerm.desc(s.createdAt)]))
          .get();

  Stream<List<ManufacturingScrap>> watchAll() =>
      (select(manufacturingScraps)
            ..orderBy([(s) => OrderingTerm.desc(s.createdAt)]))
          .watch();

  Future<List<ManufacturingScrap>> getForOrder(int orderId) =>
      (select(manufacturingScraps)
            ..where((s) => s.manufacturingOrderId.equals(orderId))
            ..orderBy([(s) => OrderingTerm.asc(s.id)]))
          .get();

  Stream<List<ManufacturingScrap>> watchForOrder(int orderId) =>
      (select(manufacturingScraps)
            ..where((s) => s.manufacturingOrderId.equals(orderId))
            ..orderBy([(s) => OrderingTerm.asc(s.id)]))
          .watch();

  Future<ManufacturingScrap?> getById(int id) =>
      (select(manufacturingScraps)..where((s) => s.id.equals(id)))
          .getSingleOrNull();

  /// Total quantity already written off for one product on one order.
  Future<double> scrappedQuantityFor({
    required int orderId,
    required int productId,
  }) async {
    final rows = await (select(manufacturingScraps)
          ..where(
            (s) =>
                s.manufacturingOrderId.equals(orderId) &
                s.productId.equals(productId),
          ))
        .get();
    return rows.fold<double>(0, (sum, r) => sum + r.quantity);
  }

  // ── Write ──

  /// Records a scrap line and removes the stock, atomically.
  ///
  /// Every check runs BEFORE the first write, so a rejected scrap leaves stock,
  /// movements and the order exactly as they were — the same discipline
  /// `completeManufacturingOrder` uses for an insufficient-stock shortage.
  ///
  /// Stock is reduced and one `manufacturing_scrap` movement is written; the
  /// order's `producedQuantity` is never touched, because that records what was
  /// *made*, not what survived.
  Future<ManufacturingScrap> recordScrap({
    required int orderId,
    required int productId,
    required double quantity,
    required String reason,
    required String responsibleParty,
    int? bomItemId,
    String? dispositionNote,
    String? performedBy,
  }) {
    return transaction(() async {
      // ── 1. Validate. Nothing below this block writes anything. ──
      if (quantity <= 0) {
        throw ArgumentError.value(
          quantity,
          'quantity',
          'Scrap quantity must be greater than zero',
        );
      }
      if (reason.trim().isEmpty) {
        throw ArgumentError.value(
          reason,
          'reason',
          'A scrap line needs a reason — pick one of '
              'ManufacturingScrapReason',
        );
      }
      if (!ManufacturingScrapReason.isValid(reason)) {
        throw ArgumentError.value(
          reason,
          'reason',
          'Unknown scrap reason. Allowed: '
              '${ManufacturingScrapReason.all.join(', ')}',
        );
      }
      if (responsibleParty.trim().isEmpty) {
        throw ArgumentError.value(
          responsibleParty,
          'responsibleParty',
          'Somebody has to be accountable for scrap',
        );
      }

      final order = await (select(db.manufacturingOrders)
            ..where((o) => o.id.equals(orderId)))
          .getSingleOrNull();
      if (order == null) {
        throw ArgumentError('ManufacturingOrder #$orderId not found');
      }
      if (order.status != ManufacturingOrderStatus.completed) {
        throw StateError(
          'Scrap can only be recorded on a completed order '
          '(current: ${order.status})',
        );
      }

      final product =
          await (select(db.products)..where((p) => p.id.equals(productId)))
              .getSingleOrNull();
      if (product == null) {
        throw ArgumentError('Product #$productId not found');
      }

      final previous = product.quantity;
      final available = previous.toDouble();
      if (quantity > available) {
        throw StateError(
          'Cannot scrap $quantity ${product.unit ?? ''} of ${product.name}: '
          'only $available in stock',
        );
      }

      // Scrapping the finished good cannot exceed what the order produced.
      if (productId == order.finishedProductId) {
        final already = await scrappedQuantityFor(
          orderId: orderId,
          productId: productId,
        );
        final total = already + quantity;
        if (total > order.producedQuantity) {
          throw StateError(
            'Cannot scrap $total units of ${product.name}: the order produced '
            'only ${order.producedQuantity}',
          );
        }
      }

      // ── 2. Write. Past this point nothing can fail on validation. ──
      final now = DateTime.now();
      final next = previous - quantity.round();

      await (update(db.products)..where((p) => p.id.equals(productId))).write(
        ProductsCompanion(quantity: Value(next), updatedAt: Value(now)),
      );

      await into(db.inventoryMovements).insert(
        InventoryMovementsCompanion.insert(
          productId: productId,
          movementType: 'manufacturing_scrap',
          quantity: -quantity.round(),
          unitCost: product.costPrice ?? product.price,
          totalValue: quantity.round() * (product.costPrice ?? product.price),
          movementDate: now,
          reference: order.orderNumber,
          referenceType: 'manufacturing_scrap',
          previousQuantity: previous,
          newQuantity: next,
          performedBy: Value(performedBy),
          notes: Value(
            'Scrapped: ${ManufacturingScrapReason.label(reason)} - '
            '${product.name} · المسؤول: $responsibleParty',
          ),
          createdAt: now,
          updatedAt: now,
        ),
      );

      final id = await into(manufacturingScraps).insert(
        ManufacturingScrapsCompanion.insert(
          manufacturingOrderId: orderId,
          productId: productId,
          bomItemId: Value(bomItemId),
          quantity: quantity,
          reason: reason,
          responsibleParty: responsibleParty,
          dispositionNote: Value(dispositionNote),
          performedBy: Value(performedBy),
          createdAt: Value(now),
        ),
      );

      return (select(manufacturingScraps)..where((s) => s.id.equals(id)))
          .getSingle();
    });
  }

  Future<int> deleteScrap(int id) =>
      (delete(manufacturingScraps)..where((s) => s.id.equals(id))).go();
}
