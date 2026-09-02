import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../app_database.dart';
import '../tables/sales_returns_table.dart';
import '../../services/accounting_service.dart';

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

  /// الحصول على مرتجع بواسطة المعرف
  Future<SalesReturn?> getReturnById(int id) =>
      (select(salesReturns)..where((t) => t.id.equals(id))).getSingleOrNull();

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

      // Create ledger reversal entry for customer invoices (credit only, as before)
      final invoiceId = returnCompanion.originalInvoiceId.value;
      final invoice = await (db.select(db.invoices)
        ..where((t) => t.id.equals(invoiceId))
      ).getSingleOrNull();
      final now = DateTime.now();
      final returnAmount = returnCompanion.totalAmount.value;
      if (invoice != null &&
          invoice.customerId != null &&
          invoice.customerId != 'cash' &&
          invoice.customerId!.isNotEmpty) {
        await db.ledgerDao.insertTransaction(
          LedgerTransactionsCompanion.insert(
            id: '${const Uuid().v4()}_ret_$returnId',
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

      // ── Headless Accounting: Journal for sales return (Phase 5) ──
      try {
        final accounting = AccountingService(db);
        Future<String> accId(String code) async {
          final a = await db.accountsDao.getByCode(code);
          if (a == null) throw Exception('Account $code not found');
          return a.id;
        }

        final salesReturnsId = await accId('4100');
        final arId = await accId('1100');
        final cashId = await accId('1000');
        final inventoryId = await accId('1200');
        final cogsId = await accId('5000');

        final isCashReturn = invoice == null ||
            invoice.customerId == null ||
            invoice.customerId == 'cash' ||
            invoice.customerId!.isEmpty;
        final creditAccountId = isCashReturn ? cashId : arId;

        await accounting.postSalesReturn(
          sourceId: returnId.toString(),
          date: now,
          amount: returnAmount,
          salesReturnsAccountId: salesReturnsId,
          debitAccountId: creditAccountId,
        );

        // Inventory reversal leg — compute cost of returned items
        double returnCost = 0;
        for (final item in items) {
          final product = await db.productDao.getProductById(item.productId.value);
          final unitCost = product?.costPrice ?? item.unitPrice.value;
          returnCost += unitCost * item.quantity.value;
        }
        if (returnCost > 0) {
          await db.journalDao.insertBalancedEntry(
            postingKey: 'sale_return_cogs:RET$returnId',
            date: now,
            description: 'عكس تكلفة مرتجع $returnId',
            sourceType: 'sale_return_cogs',
            sourceId: returnId.toString(),
            lines: [
              JournalLinesCompanion.insert(id: const Uuid().v4(), journalEntryId: '', accountId: inventoryId, debit: Value(returnCost), credit: const Value(0)),
              JournalLinesCompanion.insert(id: const Uuid().v4(), journalEntryId: '', accountId: cogsId, debit: const Value(0), credit: Value(returnCost)),
            ],
          );
        }
      } catch (e) {
        rethrow;
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
