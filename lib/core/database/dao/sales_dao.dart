import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/tables.dart';

part 'sales_dao.g.dart';

@DriftAccessor(tables: [Sales, Invoices])
class SalesDao extends DatabaseAccessor<AppDatabase> with _$SalesDaoMixin {
  SalesDao(super.db);

  Future<List<Sale>> getAllSales() => select(sales).get();

  Stream<List<Sale>> watchTodaySales() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = DateTime(now.year, now.month, now.day, 23, 59, 59);
    return (select(
      sales,
    )..where((t) => t.date.isBetweenValues(start, end))).watch();
  }

  Future<int> insertSale(SalesCompanion sale) async {
    return into(sales).insert(sale);
  }

  Future<double> getTodayTotalSales() async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = DateTime(now.year, now.month, now.day, 23, 59, 59);
    final expr = sales.total.sum();
    final result =
        await (selectOnly(sales)
              ..addColumns([expr])
              ..where(sales.date.isBetweenValues(start, end)))
            .getSingle();
    return result.read(expr) ?? 0.0;
  }
}
