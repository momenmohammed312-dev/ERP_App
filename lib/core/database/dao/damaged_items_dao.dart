import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/damaged_items_table.dart';

part 'damaged_items_dao.g.dart';

/// DAO لإدارة المنتجات الهالكة والتالفة
@DriftAccessor(tables: [DamagedItems])
class DamagedItemsDao extends DatabaseAccessor<AppDatabase>
    with _$DamagedItemsDaoMixin {
  DamagedItemsDao(super.db);

  /// إضافة سجل هالك جديد
  Future<int> insertDamagedItem(DamagedItemsCompanion item) =>
      into(damagedItems).insert(item);

  /// الحصول على كل سجلات الهالك (مرتبة من الأحدث)
  Future<List<DamagedItem>> getAllDamagedItems() =>
      (select(damagedItems)
            ..orderBy([(t) => OrderingTerm.desc(t.damageDate)]))
          .get();

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
  Stream<List<DamagedItem>> watchAllDamagedItems() =>
      (select(damagedItems)
            ..orderBy([(t) => OrderingTerm.desc(t.damageDate)]))
          .watch();
}
