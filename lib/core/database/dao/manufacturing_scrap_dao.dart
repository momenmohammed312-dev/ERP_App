import 'package:drift/drift.dart';

import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/tables/customer_material_receipts_table.dart';
import 'package:pos_offline_desktop/core/database/tables/inventory_movements_table.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_orders_table.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_scrap_table.dart';
import 'package:pos_offline_desktop/core/database/tables/product_table.dart';

part 'manufacturing_scrap_dao.g.dart';

@DriftAccessor(tables: [
  ManufacturingScraps,
  Products,
  ManufacturingOrders,
  InventoryMovements,
  CustomerStockBalances,
  CustomerStockMovements,
])
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

  /// Scraps recorded within a specific date range (for reports).
  Future<List<ManufacturingScrap>> getScrapsInRange({
    required DateTime start,
    required DateTime end,
  }) {
    return (select(manufacturingScraps)
          ..where((s) =>
              s.createdAt.isBiggerOrEqualValue(start) &
              s.createdAt.isSmallerOrEqualValue(end))
          ..orderBy([(s) => OrderingTerm.desc(s.createdAt)]))
        .get();
  }

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
      if (order.status != ManufacturingOrderStatus.completed &&
          order.status != ManufacturingOrderStatus.inProgress) {
        throw StateError(
          'Scrap can only be recorded on an in-progress or completed order '
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
        if (order.producedQuantity <= 0) {
          throw StateError(
            'Cannot scrap finished product ${product.name}: the order has not produced any units yet',
          );
        }
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

  // ── Phase B1: Manufacturing For Others Scrap With Policy ──

  /// Records order scrap for manufacturing-for-others with policy execution.
  ///
  /// Policies:
  /// - 'customer_bears': no compensation, financial action = 'none'.
  /// - 'factory_pays_piece_value': fault must be factory; compensation = quantity * piece_unit_value; action = 'deducted_from_invoice'.
  /// - 'factory_bears_labour_only': labour fee is waived; action = 'labour_waived'.
  /// - 'factory_replaces_piece': factory provides replacement from its inventory;
  ///   REQUIRES factory product stock >= quantity. If insufficient, throws [StateError]
  ///   with clear message and leaves zero writes. Action = 'replaced'.
  ///
  /// Enforces:
  /// - faultParty must be 'factory' or 'customer'.
  /// - All validations run before any write.
  Future<ManufacturingScrap> recordOrderScrapWithPolicy({
    required int orderId,
    required int productId,
    required double quantity,
    required String reason,
    required String responsibleParty,
    required String faultParty,
    int? replacementProductId,
    int? bomItemId,
    String? dispositionNote,
    String? performedBy,
  }) {
    return transaction(() async {
      // 1. Basic validation
      if (quantity <= 0) {
        throw ArgumentError.value(quantity, 'quantity', 'Scrap quantity must be greater than zero');
      }
      if (reason.trim().isEmpty) {
        throw ArgumentError.value(reason, 'reason', 'A scrap line needs a reason');
      }
      if (!ManufacturingScrapReason.isValid(reason)) {
        throw ArgumentError.value(reason, 'reason', 'Unknown scrap reason');
      }
      if (responsibleParty.trim().isEmpty) {
        throw ArgumentError.value(responsibleParty, 'responsibleParty', 'responsibleParty is required');
      }
      if (faultParty != 'factory' && faultParty != 'customer') {
        throw ArgumentError.value(faultParty, 'faultParty', 'faultParty must be either "factory" or "customer"');
      }

      final order = await (select(manufacturingOrders)..where((o) => o.id.equals(orderId))).getSingleOrNull();
      if (order == null) {
        throw ArgumentError('ManufacturingOrder #$orderId not found');
      }
      if (order.status != ManufacturingOrderStatus.completed &&
          order.status != ManufacturingOrderStatus.inProgress) {
        throw StateError(
          'Scrap can only be recorded on an in-progress or completed order (current: ${order.status})',
        );
      }

      final product = await (select(products)..where((p) => p.id.equals(productId))).getSingleOrNull();
      if (product == null) {
        throw ArgumentError('Product #$productId not found');
      }
      if (productId == order.finishedProductId && order.producedQuantity <= 0) {
        throw StateError(
          'Cannot scrap finished product ${product.name}: the order has not produced any units yet',
        );
      }

      final policy = order.scrapPolicy ?? 'customer_bears';
      String compensationAction;
      double compensationAmount = 0.0;

      // 2. Policy-specific validation and stock checks
      Product? replacementProduct;
      if (policy == 'factory_replaces_piece') {
        final replaceId = replacementProductId ?? productId;
        replacementProduct = await (select(products)..where((p) => p.id.equals(replaceId))).getSingleOrNull();
        if (replacementProduct == null) {
          throw ArgumentError('Replacement product #$replaceId not found');
        }
        final availableFactoryStock = replacementProduct.quantity;
        final requiredInt = quantity.round();
        if (availableFactoryStock < requiredInt) {
          throw StateError(
            'Cannot replace customer scrap with factory stock: required $requiredInt ${replacementProduct.unit ?? ''} of ${replacementProduct.name}, but factory has only $availableFactoryStock on hand',
          );
        }
        compensationAction = 'replaced';
      } else if (policy == 'factory_pays_piece_value') {
        if (faultParty == 'factory') {
          final pieceValue = order.pieceUnitValue ?? 0.0;
          compensationAmount = double.parse((quantity * pieceValue).toStringAsFixed(2));
          compensationAction = 'deducted_from_invoice';
        } else {
          compensationAmount = 0.0;
          compensationAction = 'none';
        }
      } else if (policy == 'factory_bears_labour_only') {
        compensationAction = 'labour_waived';
        compensationAmount = 0.0;
      } else {
        // customer_bears
        compensationAction = 'none';
        compensationAmount = 0.0;
      }

      // 3. Stock deduction for replaced policy
      final now = DateTime.now();
      if (policy == 'factory_replaces_piece' && replacementProduct != null) {
        final prev = replacementProduct.quantity;
        final requiredInt = quantity.round();
        final next = prev - requiredInt;
        await (update(products)..where((p) => p.id.equals(replacementProduct!.id))).write(
          ProductsCompanion(quantity: Value(next), updatedAt: Value(now)),
        );

        await into(inventoryMovements).insert(
          InventoryMovementsCompanion.insert(
            productId: replacementProduct.id,
            movementType: 'manufacturing_consumption',
            quantity: -requiredInt,
            unitCost: replacementProduct.costPrice ?? replacementProduct.price,
            totalValue: requiredInt * (replacementProduct.costPrice ?? replacementProduct.price),
            movementDate: now,
            reference: order.orderNumber,
            referenceType: 'manufacturing_order',
            previousQuantity: prev,
            newQuantity: next,
            performedBy: Value(performedBy),
            notes: Value('صرف قطعة بديلة لهالك العميل بأمر ${order.orderNumber}'),
            createdAt: now,
            updatedAt: now,
          ),
        );
      }

      // 4. Insert scrap record with policy results
      final id = await into(manufacturingScraps).insert(
        ManufacturingScrapsCompanion.insert(
          manufacturingOrderId: orderId,
          productId: productId,
          bomItemId: Value(bomItemId),
          quantity: quantity,
          reason: reason,
          responsibleParty: responsibleParty,
          dispositionNote: Value(dispositionNote),
          faultParty: Value(faultParty),
          compensationAction: Value(compensationAction),
          compensationAmount: Value(compensationAmount),
          performedBy: Value(performedBy),
          createdAt: Value(now),
        ),
      );

      return (select(manufacturingScraps)..where((s) => s.id.equals(id))).getSingle();
    });
  }
}
