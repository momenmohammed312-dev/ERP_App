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

  /// مفتاح عدم التكرار للمرتجع: نفس رقم المرتجع = نفس المحاولة (D7).
  Future<SalesReturn?> getByReturnNumber(String returnNumber) =>
      (select(
        salesReturns,
      )..where((t) => t.returnNumber.equals(returnNumber))).getSingleOrNull();

  /// إجمالي الكميات المرتجعة سابقًا لفاتورة (مفتاح "productId|variantId").
  Future<Map<String, int>> getReturnedQtyByKey(int invoiceId) async {
    final out = <String, int>{};
    for (final r in await getReturnsForInvoice(invoiceId)) {
      for (final ri in await getItemsForReturn(r.id)) {
        final k = '${ri.productId}|${ri.variantId ?? 0}';
        out[k] = (out[k] ?? 0) + ri.quantity;
      }
    }
    return out;
  }

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

  /// معالجة مرتجع مع تحديث المخزون والشحنة والعمولة واليومية في معاملة واحدة (D7).
  ///
  /// - عدم التكرار: نفس `returnNumber` يرجع الصف الموجود (صفر آثار جديدة).
  /// - حارس الكمية المتبقية: مجموع المرتجع التراكمي لكل صنف لا يتجاوز المباع
  ///   أبدًا؛ أي تجاوز = استثناء قبل أي كتابة (صفر آثار — الـtransaction تُلفظ).
  /// - يحدّث ترويسة الفاتورة (total −= المرتجع + إعادة اشتقاق الحالة، والمدفوع
  ///   يبقى)، ويعكس عدّادات الشحنة FIFO وحصة العمولة والبرنيكة.
  Future<int> processReturn({
    required SalesReturnsCompanion returnCompanion,
    required List<SalesReturnItemsCompanion> items,
  }) async {
    int returnId = 0;
    await db.transaction(() async {
      // Idempotency key: retry with the same number returns the first row.
      final existing = await getByReturnNumber(
        returnCompanion.returnNumber.value,
      );
      if (existing != null) {
        returnId = existing.id;
        return;
      }

      if (items.isEmpty) throw Exception('لا أصناف في المرتجع');
      final invoiceId = returnCompanion.originalInvoiceId.value;
      final invoice = await (db.select(db.invoices)
        ..where((t) => t.id.equals(invoiceId))
      ).getSingleOrNull();
      if (invoice == null) throw Exception('الفاتورة الأصلية غير موجودة');
      if (invoice.status == 'voided') {
        throw Exception('لا يمكن إرجاع فاتورة ملغاة');
      }
      final invoiceItems = await db.invoiceDao.getItemsByInvoiceId(invoiceId);
      if (invoiceItems.isEmpty) throw Exception('الفاتورة بلا أصناف');

      String keyOf(int pid, int? vid) => '$pid|${vid ?? 0}';
      final sold = <String, int>{};
      for (final it in invoiceItems) {
        final k = keyOf(it.productId, it.variantId);
        sold[k] = (sold[k] ?? 0) + it.quantity;
      }
      final returned = await getReturnedQtyByKey(invoiceId);

      final headerTotal = returnCompanion.totalAmount.value;
      if (headerTotal <= 0) throw Exception('إجمالي المرتجع يجب أن يكون أكبر من صفر');
      for (final item in items) {
        final qty = item.quantity.value;
        if (qty <= 0) throw Exception('كمية المرتجع يجب أن تكون أكبر من صفر');
        final k = keyOf(item.productId.value, item.variantId.value);
        final allowed = (sold[k] ?? 0) - (returned[k] ?? 0);
        if (qty > allowed) {
          if (allowed <= 0) {
            throw Exception(
              'تم إرجاع كامل الكمية المباعة من هذا الصنف مسبقًا — صفر آثار جديدة',
            );
          }
          throw Exception(
            'كمية المرتجع ($qty) تتجاوز المتبقي القابل للإرجاع ($allowed) — صفر آثار جديدة',
          );
        }
      }

      returnId = await into(salesReturns).insert(returnCompanion);

      var totalReturnQty = 0;
      for (final item in items) {
        final itemWithReturnId = item.copyWith(returnId: Value(returnId));
        await into(salesReturnItems).insert(itemWithReturnId);
        totalReturnQty += item.quantity.value;

        final prevProduct = await db.productDao.getProductById(
          item.productId.value,
        );
        // مرتجع صنف (لون/فئة): الاسترجاع للصنف + إعادة حساب مجموع الأب.
        final returnVariantId = item.variantId.value;
        if (returnVariantId != null) {
          final variant = await db.productVariantDao.getVariantById(
            returnVariantId,
          );
          if (variant != null) {
            await db.productVariantDao.updateVariantQuantity(
              variant.id,
              variant.quantity + item.quantity.value,
            );
            final total = await db.productVariantDao
                .getTotalQuantityByProduct(item.productId.value);
            final parent = await db.productDao.getProductById(
              item.productId.value,
            );
            if (parent != null) {
              await db.productDao.updateProduct(
                parent.copyWith(quantity: total),
              );
            }
          } else {
            // الصنف اتحذف نهائيًا — نكمل للاسترجاع المباشر للأب تحت.
            final product = await db.productDao.getProductById(
              item.productId.value,
            );
            if (product != null) {
              await db.productDao.updateProduct(
                product.copyWith(
                  quantity: product.quantity + item.quantity.value,
                ),
              );
            }
          }
        } else {
          final product = await db.productDao.getProductById(item.productId.value);
          if (product != null) {
            await db.productDao.updateProduct(
              product.copyWith(quantity: product.quantity + item.quantity.value),
            );
          }
        }

        // D9: حركة إرجاع حقيقية (موجبة) مرتبطة بالفاتورة الأصلية.
        final afterProduct = await db.productDao.getProductById(
          item.productId.value,
        );
        await db.inventoryMovementDao.createMovementWithTimestamp(
          productId: item.productId.value,
          movementType: 'return',
          quantity: item.quantity.value,
          unitCost: item.unitPrice.value,
          totalValue: item.unitPrice.value * item.quantity.value,
          movementDate: DateTime.now(),
          reference: invoice.invoiceNumber ?? 'INV$invoiceId',
          referenceType: 'sale_invoice',
          previousQuantity: prevProduct?.quantity ?? 0,
          newQuantity:
              afterProduct?.quantity ??
              ((prevProduct?.quantity ?? 0) + item.quantity.value),
          notes: item.variantId.value != null
              ? 'return variant:${item.variantId.value}'
              : 'return',
        );
      }

      // عكس عدّادات الشحنة FIFO مع إزاحة المرتجعات السابقة (لا ازدواج).
      for (final item in items) {
        final k = keyOf(item.productId.value, item.variantId.value);
        var toSkip = returned[k] ?? 0;
        var need = item.quantity.value;
        for (final inv in invoiceItems) {
          if (need <= 0) break;
          if (inv.productId != item.productId.value ||
              inv.variantId != item.variantId.value ||
              inv.shipmentId == null) {
            continue;
          }
          var lineQty = inv.quantity;
          if (toSkip >= lineQty) {
            toSkip -= lineQty;
            continue;
          }
          lineQty -= toSkip;
          toSkip = 0;
          final take = need <= lineQty ? need : lineQty;
          final shipment = await db.vegetableShipmentDao.getById(
            inv.shipmentId!,
          );
          if (shipment != null) {
            await db.vegetableShipmentDao.updateShipment(
              shipment.copyWith(
                barnikaSoldCount:
                    (shipment.barnikaSoldCount - take).clamp(0, 1 << 62),
                barnikaRemainingCount: shipment.barnikaRemainingCount + take,
              ),
            );
          }
          need -= take;
        }
      }

      // عكس حصة العمولة لكل مورد (D8: مدين للحصة — تُنقص الـpayable الدائن).
      if (invoice.totalAmount > 0) {
        final sellBySupplier = <String, double>{};
        final commBase = <String, double>{};
        for (final inv in invoiceItems) {
          if (inv.shipmentId == null || inv.commission <= 0) continue;
          final sh = await db.vegetableShipmentDao.getById(inv.shipmentId!);
          if (sh == null) continue;
          // سعر السطر مخزّن unit (canonical) — الإجمالي = price × quantity.
          sellBySupplier[sh.supplierId] =
              (sellBySupplier[sh.supplierId] ?? 0) +
              (inv.price * inv.quantity);
          commBase[sh.supplierId] =
              (commBase[sh.supplierId] ?? 0) + inv.commission;
        }
        final ratio = headerTotal / invoice.totalAmount;
        for (final sid in sellBySupplier.keys) {
          final supplierDue =
              (sellBySupplier[sid] ?? 0) - (commBase[sid] ?? 0);
          final share = supplierDue * ratio;
          if (share <= 0.001) continue;
          await db.ledgerDao.insertTransaction(
            LedgerTransactionsCompanion.insert(
              id: '${const Uuid().v4()}_ret',
              entityType: 'Supplier',
              refId: sid,
              date: DateTime.now(),
              description:
                  'عكس عمولة مرتجع فاتورة #${invoice.invoiceNumber ?? invoiceId}',
              debit: Value(share),
              credit: const Value(0.0),
              origin: 'reversal',
              receiptNumber: Value('RET$returnId'),
            ),
          );
        }
      }

      // ترويسة الفاتورة: total −= المرتجع، والمدفوع يبقى، والحالة تُشتق.
      final newTotal = (invoice.totalAmount - headerTotal).clamp(0.0, 1 << 62).toDouble();
      final newStatus = invoice.paidAmount >= newTotal - 0.01
          ? 'paid'
          : (invoice.paidAmount > 0 ? 'partial' : 'pending');
      await db.invoiceDao.updateInvoice(
        InvoicesCompanion(
          id: Value(invoiceId),
          totalAmount: Value(newTotal),
          status: Value(newStatus),
        ),
      );

      // برنيكة: إرجاع جزئي للصف المطابق (status-machine يمنع التجاوز).
      final custId = invoice.customerId;
      if (custId != null &&
          custId != 'cash' &&
          custId.isNotEmpty &&
          totalReturnQty > 0) {
        final totalSoldQty = invoiceItems.fold<int>(0, (s, e) => s + e.quantity);
        final outstanding = await db.emptyBarnikaTrackingDao
            .getOutstandingByCustomer(custId);
        final matches = outstanding.where((r) {
          if (r.quantityOut != totalSoldQty) return false;
          return r.dateOut.difference(invoice.date).abs() <=
              const Duration(hours: 24);
        }).toList();
        if (matches.length == 1) {
          final missing =
              matches.first.quantityOut - matches.first.quantityReturned;
          final take = totalReturnQty <= missing ? totalReturnQty : missing;
          if (take > 0) {
            await db.emptyBarnikaTrackingDao.recordReturn(
              id: matches.first.id,
              quantityReturned: take,
            );
          }
        }
      }

      // Create ledger reversal entry for customer invoices (credit only, as before)
      final now = DateTime.now();
      final returnAmount = returnCompanion.totalAmount.value;
      if (invoice.customerId != null &&
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
        // متسامح مع تكرار أكواد الحسابات (بلا UNIQUE) — أول صف بدل no-op/single.
        Future<String> accId(String code) async {
          final rows = await (db.select(
            db.accounts,
          )..where((a) => a.code.equals(code))..limit(1)).get();
          if (rows.isEmpty) throw Exception('Account $code not found');
          return rows.first.id;
        }

        final salesReturnsId = await accId('4100');
        final arId = await accId('1100');
        final cashId = await accId('1000');
        final inventoryId = await accId('1200');
        final cogsId = await accId('5000');

        final isCashReturn = invoice.customerId == null ||
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
