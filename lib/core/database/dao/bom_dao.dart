import 'package:drift/drift.dart';

import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_tables.dart';

part 'bom_dao.g.dart';

@DriftAccessor(tables: [BillOfMaterials, BomItems])
class BomDao extends DatabaseAccessor<AppDatabase> with _$BomDaoMixin {
  BomDao(super.db);

  // ── BillOfMaterials CRUD ──

  Future<List<BillOfMaterial>> getAllBoms() =>
      (select(billOfMaterials)
            ..where(
              (b) =>
                  b.type.isNull() | b.type.equals('system_placeholder').not(),
            )
            ..orderBy([(b) => OrderingTerm.desc(b.createdAt)]))
          .get();

  Stream<List<BillOfMaterial>> watchAllBoms() =>
      (select(billOfMaterials)
            ..where(
              (b) =>
                  b.type.isNull() | b.type.equals('system_placeholder').not(),
            )
            ..orderBy([(b) => OrderingTerm.desc(b.createdAt)]))
          .watch();

  Future<List<BillOfMaterial>> getActiveBoms() =>
      (select(billOfMaterials)
            ..where(
              (b) =>
                  b.status.equals('Active') &
                  (b.type.isNull() | b.type.equals('system_placeholder').not()),
            )
            ..orderBy([(b) => OrderingTerm.desc(b.createdAt)]))
          .get();

  Stream<List<BillOfMaterial>> watchActiveBoms() =>
      (select(billOfMaterials)..where(
            (b) =>
                b.status.equals('Active') &
                (b.type.isNull() | b.type.equals('system_placeholder').not()),
          ))
          .watch();

  Future<BillOfMaterial?> getBomById(int id) => (select(
    billOfMaterials,
  )..where((b) => b.id.equals(id))).getSingleOrNull();

  Future<List<BillOfMaterial>> getBomsForProduct(int productId) => (select(
    billOfMaterials,
  )..where((b) => b.finishedProductId.equals(productId))).get();

  Future<int> insertBom(BillOfMaterialsCompanion entry) =>
      into(billOfMaterials).insert(entry);

  Future<bool> updateBom(BillOfMaterial bom) =>
      update(billOfMaterials).replace(bom);

  Future<int> updateBomCompanion(BillOfMaterialsCompanion c) =>
      (update(billOfMaterials)..where((b) => b.id.equals(c.id.value))).write(c);

  /// Soft-toggle: Active <-> Inactive
  Future<void> toggleBomStatus(int id) async {
    final bom = await getBomById(id);
    if (bom == null) return;
    final newStatus = bom.status == 'Active' ? 'Inactive' : 'Active';
    await (update(billOfMaterials)..where((b) => b.id.equals(id))).write(
      BillOfMaterialsCompanion(
        status: Value(newStatus),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> deleteBom(int id) async {
    // Cascade will delete BomItems via FK onDelete cascade, but a recipe with
    // manufacturing orders against it must survive so those orders keep their
    // meaning. See _assertBomIsEditable.
    await _assertBomIsEditable(id);
    await (delete(billOfMaterials)..where((b) => b.id.equals(id))).go();
  }

  // ── BomItems CRUD ──

  Future<List<BomItem>> getItemsForBom(int bomId) =>
      (select(bomItems)
            ..where((i) => i.bomId.equals(bomId))
            ..orderBy([
              (i) => OrderingTerm.asc(i.sortOrder),
              (i) => OrderingTerm.asc(i.id),
            ]))
          .get();

  Stream<List<BomItem>> watchItemsForBom(int bomId) =>
      (select(bomItems)
            ..where((i) => i.bomId.equals(bomId))
            ..orderBy([
              (i) => OrderingTerm.asc(i.sortOrder),
              (i) => OrderingTerm.asc(i.id),
            ]))
          .watch();

  Future<int> insertBomItem(BomItemsCompanion entry) =>
      into(bomItems).insert(entry);

  Future<bool> updateBomItem(BomItem item) => update(bomItems).replace(item);

  Future<void> deleteBomItem(int id) =>
      (delete(bomItems)..where((i) => i.id.equals(id))).go();

  Future<void> deleteAllItemsForBom(int bomId) =>
      (delete(bomItems)..where((i) => i.bomId.equals(bomId))).go();

  // ── Transactional helpers ──

  /// Creates a BOM header + all its line items in a single transaction.
  ///
  /// Thin wrapper over [insertBomWithItemsChecked] that discards the warnings,
  /// so the original int-returning surface from 4f7e2a0 is unchanged and every
  /// caller goes through the same validation.
  Future<int> insertBomWithItems({
    required BillOfMaterialsCompanion bom,
    required List<BomItemsCompanion> items,
  }) async {
    final result = await insertBomWithItemsChecked(bom: bom, items: items);
    return result.bomId;
  }

  /// Creates a BOM header + its line items, validating `product_type` at both
  /// ends and returning any non-blocking warnings.
  ///
  /// [Products.productType] is nullable and NULL means "standard/retail", so a
  /// product that predates the column cannot be distinguished from a wrongly
  /// configured one. The rule is therefore asymmetric:
  ///
  ///  * NULL            -> warning. The insert goes through. Blocking here would
  ///                       make every pre-v73 product unusable in a recipe.
  ///  * correct type    -> silent.
  ///  * explicitly wrong -> throw, before any write.
  ///
  /// OQ6. A BOM produces a `finished_product` and consumes `raw_material`s;
  /// feeding either end a type that is explicitly the wrong role is a mistake
  /// worth stopping on.
  Future<({int bomId, List<String> warnings})> insertBomWithItemsChecked({
    required BillOfMaterialsCompanion bom,
    required List<BomItemsCompanion> items,
  }) {
    return transaction(() async {
      final warnings = <String>[];

      final finishedId = bom.finishedProductId.value;
      final finished = await (select(
        db.products,
      )..where((p) => p.id.equals(finishedId))).getSingleOrNull();
      if (finished == null) {
        throw ArgumentError('Product #$finishedId not found');
      }
      switch (finished.productType) {
        case null:
          warnings.add(
            'المنتج "${finished.name}" لسه مالوش نوع محدد — اتأكد إنه '
            'منتج نهائي مش خام',
          );
        case 'finished_product':
          break;
        case 'raw_material':
          // FEAT-007: custody flows produce the SAME product the
          // customer lends us (fabric in -> printed fabric out). Accept
          // the type with a warning instead of blocking.
          warnings.add(
            'المنتج "${finished.name}" خام لكنه ناتج الوصفة — '
            'مقبول لتصنيع للغير، اتأكد من النوع',
          );
        default:
          throw ArgumentError(
            'المنتج "${finished.name}" نوعه '
            '"${finished.productType}" — الوصفة لازم تنتج '
            'finished_product',
          );
      }

      for (final item in items) {
        final rawId = item.rawMaterialProductId.value;
        final raw = await (select(
          db.products,
        )..where((p) => p.id.equals(rawId))).getSingleOrNull();
        if (raw == null) {
          throw ArgumentError('Product #$rawId not found');
        }
        switch (raw.productType) {
          case null:
            warnings.add(
              'الخامة "${raw.name}" مالها نوع محدد — اتأكد إنها خام مش '
              'منتج نهائي',
            );
          case 'raw_material':
            break;
          case 'finished_product':
            throw ArgumentError(
              'الخامة "${raw.name}" منتج نهائي — الوصفة consume خام، مش '
              'منتج تاني',
            );
          default:
            warnings.add(
              'الخامة "${raw.name}" نوعها "${raw.productType}" — المفروض '
              'خام',
            );
        }
      }

      final bomId = await into(billOfMaterials).insert(bom);
      for (var i = 0; i < items.length; i++) {
        final c = items[i].copyWith(bomId: Value(bomId), sortOrder: Value(i));
        await into(bomItems).insert(c);
      }
      return (bomId: bomId, warnings: warnings);
    });
  }

  /// Refuses to touch a recipe that a manufacturing order already points at.
  ///
  /// BomDao.replaceBomItems deletes every line and re-inserts, so editing a
  /// referenced BOM would silently reinterpret that order's historical cost —
  /// the recorded unit cost would still be there, but its meaning would not.
  /// That is unrecoverable once real production has run.
  Future<void> _assertBomIsEditable(int bomId) async {
    final bom = await getBomById(bomId);
    if (bom != null && bom.type == 'system_placeholder') {
      throw StateError('لا يمكن تعديل وصفة النظام الأساسية (أو حذفها).');
    }

    final orders = await (select(
      db.manufacturingOrders,
    )..where((o) => o.bomId.equals(bomId))).get();
    if (orders.isEmpty) return;
    throw StateError(
      'This recipe has ${orders.length} manufacturing order(s) against it and '
      'cannot be edited or deleted. Create a new recipe instead so the '
      'existing orders keep their meaning. '
      'الوصفة دي عليها ${orders.length} أمر تصنيع — اعمل وصفة جديدة.',
    );
  }

  /// Replaces all line items for an existing BOM in a single transaction.
  /// Header can optionally be updated via [bomUpdate].
  ///
  /// Refuses when any order references the BOM — see [_assertBomIsEditable].
  Future<void> replaceBomItems({
    required int bomId,
    required List<BomItemsCompanion> items,
    BillOfMaterialsCompanion? bomUpdate,
  }) {
    return transaction(() async {
      await _assertBomIsEditable(bomId);
      if (bomUpdate != null) {
        await (update(
          billOfMaterials,
        )..where((b) => b.id.equals(bomId))).write(bomUpdate);
      }
      await (delete(bomItems)..where((i) => i.bomId.equals(bomId))).go();
      for (var i = 0; i < items.length; i++) {
        final c = items[i].copyWith(bomId: Value(bomId), sortOrder: Value(i));
        await into(bomItems).insert(c);
      }
    });
  }

  /// Joins BOM items with their raw-material Product rows for display.
  Future<List<(BomItem, Product)>> getItemsWithProducts(int bomId) async {
    final query =
        select(bomItems).join([
            innerJoin(
              db.products,
              db.products.id.equalsExp(bomItems.rawMaterialProductId),
            ),
          ])
          ..where(bomItems.bomId.equals(bomId))
          ..orderBy([
            OrderingTerm.asc(bomItems.sortOrder),
            OrderingTerm.asc(bomItems.id),
          ]);

    final rows = await query.get();
    return rows
        .map((row) => (row.readTable(bomItems), row.readTable(db.products)))
        .toList();
  }

  /// Simple cost simulation: sum( quantityRequired * current costPrice ) per item.
  /// Uses Products.costPrice fallback to price, same as D.7 logic.
  Future<double> simulateMaterialCost(int bomId) async {
    final items = await getItemsWithProducts(bomId);
    double total = 0;
    for (final (item, product) in items) {
      final unitCost = product.costPrice ?? product.price;
      final waste =
          item.wastePercentageOverride ??
          0; // header waste not applied here, caller may combine
      final effective = item.quantityRequired * (1 + waste / 100);
      total += effective * unitCost;
    }
    return total;
  }

  Future<int> createSystemPlaceholderBom(int productId) async {
    return insertBom(
      BillOfMaterialsCompanion.insert(
        name: 'System Placeholder',
        finishedProductId: productId,
        type: const Value('system_placeholder'),
      ),
    );
  }

  Future<void> updateBomGuarded(BillOfMaterialsCompanion c) async {
    await _assertBomIsEditable(c.id.value);
    await updateBomCompanion(c);
  }

  Future<void> deleteBomGuarded(int id) async {
    await deleteBom(id);
  }
}
