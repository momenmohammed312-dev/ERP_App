import 'package:drift/drift.dart';
import '../../../services/license_entitlement.dart';
import '../app_database.dart';
import '../tables/damaged_items_table.dart';

part 'damaged_items_dao.g.dart';

/// DAO لإدارة المنتجات الهالكة والتالفة
@DriftAccessor(tables: [DamagedItems])
class DamagedItemsDao extends DatabaseAccessor<AppDatabase>
    with _$DamagedItemsDaoMixin {
  DamagedItemsDao(super.db);

  /// BUG-018 — entitlement guard.
  ///
  /// The home screen greys out the launcher, but that is a widget around a
  /// button. This DAO is reachable from the route, from a test, and from any
  /// future call site, so the write itself has to ask. Denied BEFORE the
  /// statement runs, so nothing is partially persisted.
  ///
  /// Deliberately not inside a transaction: `grants()` is a synchronous
  /// in-memory read, so there is no disk I/O to hold a transaction open for.
  static void _requireLicense(String operation) => LicenseEntitlement.instance
      .require('damaged_goods', operation: operation);

  /// ????? ??? ???? ????
  Future<int> insertDamagedItem(DamagedItemsCompanion item) {
    _requireLicense('تسجيل تالف');
    return into(damagedItems).insert(item);
  }

  /// ????? ??? ???? ?????
  Future<void> updateDamagedItem(DamagedItemsCompanion item) {
    _requireLicense('تعديل تالف');
    return (update(
      damagedItems,
    )..where((t) => t.id.equals(item.id.value))).write(item);
  }

  /// ??? ??? ????
  Future<void> deleteDamagedItem(int id) {
    _requireLicense('حذف تالف');
    return (delete(damagedItems)..where((t) => t.id.equals(id))).go();
  }

  /// إجمالي الكميات التالفة لمنتج معين
  Future<int> getTotalQuantityByProduct(int productId) async {
    final items = await getDamagedItemsByProduct(productId);
    return items.fold<int>(0, (sum, i) => sum + i.quantity);
  }

  /// الحصول على كل سجلات الهالك (مرتبة من الأحدث)
  Future<List<DamagedItem>> getAllDamagedItems() => (select(
    damagedItems,
  )..orderBy([(t) => OrderingTerm.desc(t.damageDate)])).get();

  /// الحصول على سجلات الهالك في فترة زمنية
  Future<List<DamagedItem>> getDamagedItemsByDateRange(
    DateTime start,
    DateTime end,
  ) =>
      (select(damagedItems)
            ..where((t) => t.damageDate.isBetweenValues(start, end))
            ..orderBy([(t) => OrderingTerm.desc(t.damageDate)]))
          .get();

  /// الحصول على سجلات هالك منتج معين
  Future<List<DamagedItem>> getDamagedItemsByProduct(int productId) =>
      (select(damagedItems)
            ..where((t) => t.productId.equals(productId))
            ..orderBy([(t) => OrderingTerm.desc(t.damageDate)]))
          .get();

  /// إجمالي الخسائر في فترة زمنية
  Future<double> getTotalLossByDateRange(DateTime start, DateTime end) async {
    final items = await getDamagedItemsByDateRange(start, end);
    return items.fold<double>(0.0, (sum, i) => sum + i.totalLoss);
  }

  /// إجمالي الخسائر اليومية
  Future<double> getTotalLossForDate(DateTime date) async {
    final start = DateTime(date.year, date.month, date.day);
    final end = DateTime(date.year, date.month, date.day, 23, 59, 59);
    return getTotalLossByDateRange(start, end);
  }

  /// مراقبة كل سجلات الهالك (Stream)
  Stream<List<DamagedItem>> watchAllDamagedItems() => (select(
    damagedItems,
  )..orderBy([(t) => OrderingTerm.desc(t.damageDate)])).watch();

  /// JOIN query — returns damaged items with product name (eliminates nested FutureBuilder)
  Future<List<DamagedItemWithProduct>> getAllDamagedItemsWithProducts() async {
    final query = select(damagedItems).join([
      innerJoin(db.products, db.products.id.equalsExp(damagedItems.productId)),
    ])..orderBy([OrderingTerm.desc(damagedItems.damageDate)]);

    return query
        .map(
          (row) => DamagedItemWithProduct(
            item: row.readTable(damagedItems),
            productName: row.readTable(db.products).name,
          ),
        )
        .get();
  }

  Stream<List<DamagedItemWithProduct>> watchAllDamagedItemsWithProducts() {
    final query = select(damagedItems).join([
      innerJoin(db.products, db.products.id.equalsExp(damagedItems.productId)),
    ])..orderBy([OrderingTerm.desc(damagedItems.damageDate)]);

    return query
        .map(
          (row) => DamagedItemWithProduct(
            item: row.readTable(damagedItems),
            productName: row.readTable(db.products).name,
          ),
        )
        .watch();
  }
}

class DamagedItemWithProduct {
  final DamagedItem item;
  final String productName;
  const DamagedItemWithProduct({required this.item, required this.productName});
}
