import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/sales_returns_table.dart';

part 'sales_returns_dao.g.dart';

/// DAO لإدارة مرتجعات المبيعات
@DriftAccessor(tables: [SalesReturns, SalesReturnItems])
class SalesReturnsDao extends DatabaseAccessor<AppDatabase>
    with _$SalesReturnsDaoMixin {
  SalesReturnsDao(super.db);

  /// إضافة سجل مرتجع رئيسي
  Future<int> insertReturn(SalesReturnsCompanion ret) =>
      into(salesReturns).insert(ret);

  /// إضافة صنف مرتجع
  Future<int> insertReturnItem(SalesReturnItemsCompanion item) =>
      into(salesReturnItems).insert(item);

  /// الحصول على كل المرتجعات
  Future<List<SalesReturn>> getAllReturns() =>
      (select(salesReturns)
            ..orderBy([(t) => OrderingTerm.desc(t.returnDate)]))
          .get();

  /// الحصول على مرتجعات في فترة زمنية
  Future<List<SalesReturn>> getReturnsByDateRange(
    DateTime start,
    DateTime end,
  ) =>
      (select(salesReturns)
            ..where((t) => t.returnDate.isBetweenValues(start, end))
            ..orderBy([(t) => OrderingTerm.desc(t.returnDate)]))
          .get();

  /// الحصول على مرتجعات عميل معين
  Future<List<SalesReturn>> getReturnsByCustomer(String customerId) =>
      (select(salesReturns)
            ..where((t) => t.customerId.equals(customerId))
            ..orderBy([(t) => OrderingTerm.desc(t.returnDate)]))
          .get();

  /// الحصول على مرتجعات فاتورة معينة
  Future<List<SalesReturn>> getReturnsForInvoice(int invoiceId) =>
      (select(salesReturns)
            ..where((t) => t.originalInvoiceId.equals(invoiceId)))
          .get();

  /// الحصول على أصناف مرتجع معين
  Future<List<SalesReturnItem>> getItemsForReturn(int returnId) =>
      (select(salesReturnItems)
            ..where((t) => t.returnId.equals(returnId)))
          .get();

  /// إجمالي قيمة المرتجعات في فترة زمنية
  Future<double> getTotalReturnsByDateRange(
    DateTime start,
    DateTime end,
  ) async {
    final returns = await getReturnsByDateRange(start, end);
    return returns.fold<double>(0.0, (sum, r) => sum + r.totalAmount);
  }

  /// إجمالي المرتجعات اليومية
  Future<double> getTotalReturnsForDate(DateTime date) async {
    final start = DateTime(date.year, date.month, date.day);
    final end = DateTime(date.year, date.month, date.day, 23, 59, 59);
    return getTotalReturnsByDateRange(start, end);
  }

  /// معالجة مرتجع كامل مع تحديث المخزون وقيود اليومية في معاملة واحدة
  Future<int> processReturn({
    required SalesReturnsCompanion returnCompanion,
    required List<SalesReturnItemsCompanion> items,
  }) async {
    int returnId = 0;
    await db.transaction(() async {
      returnId = await into(salesReturns).insert(returnCompanion);

      for (final item in items) {
        final itemWithReturnId = item.copyWith(returnId: Value(returnId));
        await into(salesReturnItems).insert(itemWithReturnId);

        final product = await db.productDao.getProductById(item.productId.value);
        if (product != null) {
          await db.productDao.updateProduct(
            product.copyWith(quantity: product.quantity + item.quantity.value),
          );
        }
      }

      // Create ledger reversal entry for customer invoices
      final invoiceId = returnCompanion.originalInvoiceId.value;
      final invoice = await (db.select(db.invoices)
        ..where((t) => t.id.equals(invoiceId))
      ).getSingleOrNull();
      if (invoice != null &&
          invoice.customerId != null &&
          invoice.customerId != 'cash' &&
          invoice.customerId!.isNotEmpty) {
        final now = DateTime.now();
        final returnAmount = returnCompanion.totalAmount.value;
        await db.ledgerDao.insertTransaction(
          LedgerTransactionsCompanion.insert(
            id: '${now.millisecondsSinceEpoch}_ret_$returnId',
            entityType: 'Customer',
            refId: invoice.customerId!,
            date: now,
            description: 'مرتجع فاتورة #${invoice.invoiceNumber ?? invoice.id}',
            debit: const Value(0.0),
            credit: Value(returnAmount),
            origin: 'reversal',
            paymentMethod: const Value.absent(),
            receiptNumber: Value('RET$returnId'),
          ),
        );
      }
    });
    return returnId;
  }

  /// مراقبة كل المرتجعات (Stream)
  Stream<List<SalesReturn>> watchAllReturns() =>
      (select(salesReturns)
            ..orderBy([(t) => OrderingTerm.desc(t.returnDate)]))
          .watch();
}
