import 'package:drift/drift.dart';

import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/tables/manufacturing_tables.dart';

part 'bom_dao.g.dart';

@DriftAccessor(tables: [BillOfMaterials, BomItems])
class BomDao extends DatabaseAccessor<AppDatabase> with _$BomDaoMixin {
  BomDao(super.db);

  // ── BillOfMaterials CRUD ──

  Future<List<BillOfMaterial>> getAllBoms() =>
      (select(billOfMaterials)..orderBy([(b) => OrderingTerm.desc(b.createdAt)])).get();

  Stream<List<BillOfMaterial>> watchAllBoms() =>
      (select(billOfMaterials)..orderBy([(b) => OrderingTerm.desc(b.createdAt)])).watch();

  Future<List<BillOfMaterial>> getActiveBoms() =>
      (select(billOfMaterials)
            ..where((b) => b.status.equals('Active'))
            ..orderBy([(b) => OrderingTerm.desc(b.createdAt)]))
          .get();

  Stream<List<BillOfMaterial>> watchActiveBoms() =>
      (select(billOfMaterials)..where((b) => b.status.equals('Active'))).watch();

  Future<BillOfMaterial?> getBomById(int id) =>
      (select(billOfMaterials)..where((b) => b.id.equals(id))).getSingleOrNull();

  Future<List<BillOfMaterial>> getBomsForProduct(int productId) =>
      (select(billOfMaterials)..where((b) => b.finishedProductId.equals(productId))).get();

  Future<int> insertBom(BillOfMaterialsCompanion entry) => into(billOfMaterials).insert(entry);

  Future<bool> updateBom(BillOfMaterial bom) => update(billOfMaterials).replace(bom);

  Future<int> updateBomCompanion(BillOfMaterialsCompanion c) =>
      (update(billOfMaterials)..where((b) => b.id.equals(c.id.value))).write(c);

  /// Soft-toggle: Active <-> Inactive
  Future<void> toggleBomStatus(int id) async {
    final bom = await getBomById(id);
    if (bom == null) return;
    final newStatus = bom.status == 'Active' ? 'Inactive' : 'Active';
    await (update(billOfMaterials)..where((b) => b.id.equals(id))).write(
      BillOfMaterialsCompanion(status: Value(newStatus), updatedAt: Value(DateTime.now())),
    );
  }

  Future<void> deleteBom(int id) async {
    // Cascade will delete BomItems via FK onDelete cascade
    await (delete(billOfMaterials)..where((b) => b.id.equals(id))).go();
  }

  // ── BomItems CRUD ──

  Future<List<BomItem>> getItemsForBom(int bomId) => (select(bomItems)
        ..where((i) => i.bomId.equals(bomId))
        ..orderBy([(i) => OrderingTerm.asc(i.sortOrder), (i) => OrderingTerm.asc(i.id)]))
      .get();

  Stream<List<BomItem>> watchItemsForBom(int bomId) => (select(bomItems)
        ..where((i) => i.bomId.equals(bomId))
        ..orderBy([(i) => OrderingTerm.asc(i.sortOrder), (i) => OrderingTerm.asc(i.id)]))
      .watch();

  Future<int> insertBomItem(BomItemsCompanion entry) => into(bomItems).insert(entry);

  Future<bool> updateBomItem(BomItem item) => update(bomItems).replace(item);

  Future<void> deleteBomItem(int id) => (delete(bomItems)..where((i) => i.id.equals(id))).go();

  Future<void> deleteAllItemsForBom(int bomId) =>
      (delete(bomItems)..where((i) => i.bomId.equals(bomId))).go();

  // ── Transactional helpers ──

  /// Creates a BOM header + all its line items in a single transaction.
  Future<int> insertBomWithItems({
    required BillOfMaterialsCompanion bom,
    required List<BomItemsCompanion> items,
  }) {
    return transaction(() async {
      final bomId = await into(billOfMaterials).insert(bom);
      for (var i = 0; i < items.length; i++) {
        final c = items[i].copyWith(bomId: Value(bomId), sortOrder: Value(i));
        await into(bomItems).insert(c);
      }
      return bomId;
    });
  }

  /// Replaces all line items for an existing BOM in a single transaction.
  /// Header can optionally be updated via [bomUpdate].
  Future<void> replaceBomItems({
    required int bomId,
    required List<BomItemsCompanion> items,
    BillOfMaterialsCompanion? bomUpdate,
  }) {
    return transaction(() async {
      if (bomUpdate != null) {
        await (update(billOfMaterials)..where((b) => b.id.equals(bomId))).write(bomUpdate);
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
    final query = select(bomItems).join([
      innerJoin(db.products, db.products.id.equalsExp(bomItems.rawMaterialProductId)),
    ])
      ..where(bomItems.bomId.equals(bomId))
      ..orderBy([OrderingTerm.asc(bomItems.sortOrder), OrderingTerm.asc(bomItems.id)]);

    final rows = await query.get();
    return rows.map((row) => (row.readTable(bomItems), row.readTable(db.products))).toList();
  }

  /// Simple cost simulation: sum( quantityRequired * current costPrice ) per item.
  /// Uses Products.costPrice fallback to price, same as D.7 logic.
  Future<double> simulateMaterialCost(int bomId) async {
    final items = await getItemsWithProducts(bomId);
    double total = 0;
    for (final (item, product) in items) {
      final unitCost = product.costPrice ?? product.price;
      final waste = item.wastePercentageOverride ?? 0; // header waste not applied here, caller may combine
      final effective = item.quantityRequired * (1 + waste / 100);
      total += effective * unitCost;
    }
    return total;
  }
}
