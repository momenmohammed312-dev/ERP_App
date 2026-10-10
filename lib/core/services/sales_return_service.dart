import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../database/app_database.dart';
import '../services/invoice_number_formatter.dart';

/// سطر قابل للإرجاع — يحسب المتاح = الكمية الأصلية - ما سبق إرجاعه
class ReturnableLine {
  final InvoiceItem invoiceItem;
  final Product? product;
  final int alreadyReturned;
  final int available;

  ReturnableLine({
    required this.invoiceItem,
    required this.product,
    required this.alreadyReturned,
    required this.available,
  });
}

/// خدمة المرتجع الجزئي على مستوى الصنف (مبيعات + مشتريات unified pattern).
/// كل العمليات atomic داخل transaction واحدة.
class SalesReturnService {
  final AppDatabase _db;
  SalesReturnService(this._db);

  /// يرجع لكل سطر في الفاتورة الكمية المتاحة للإرجاع
  Future<List<ReturnableLine>> getReturnableLines(int invoiceId) async {
    final items = await _db.invoiceDao.getItemsByInvoiceId(invoiceId);
    final result = <ReturnableLine>[];
    for (final item in items) {
      final already = await _getReturnedQtyForItem(item.id);
      final product = await _db.productDao.getProductById(item.productId);
      result.add(ReturnableLine(
        invoiceItem: item,
        product: product,
        alreadyReturned: already,
        available: (item.quantity - already).clamp(0, 1 << 30),
      ));
    }
    return result;
  }

  Future<int> _getReturnedQtyForItem(int invoiceItemId) async {
    final row = await _db.customSelect(
      'SELECT COALESCE(SUM(quantity),0) as s FROM sales_return_items WHERE invoice_item_id = ?',
      variables: [Variable.withInt(invoiceItemId)],
      readsFrom: {_db.salesReturnItems},
    ).getSingle();
    return (row.data['s'] as num?)?.toInt() ?? 0;
  }

  /// إجمالي المرتجع السابق لفاتورة (لكل التقارير)
  Future<double> getTotalReturnedForInvoice(int invoiceId) async {
    final rows = await _db.customSelect(
      'SELECT COALESCE(SUM(sri.quantity * sri.unit_price - sri.discount),0) as total '
      'FROM sales_return_items sri '
      'JOIN sales_returns sr ON sr.id = sri.return_id '
      'WHERE sr.original_invoice_id = ?',
      variables: [Variable.withInt(invoiceId)],
      readsFrom: {_db.salesReturns, _db.salesReturnItems},
    ).getSingle();
    return (rows.data['total'] as num?)?.toDouble() ?? 0.0;
  }

  /// حالة الصنف المرتجع — تحدد هل يرجع للمخزون ولا لا.
  /// 'sellable' (رجع للمخزون) | 'damaged' (تالف — جدول التالف مش المخزون)
  /// | 'supplier' (هيتبعت للمورد).
  static const restockSellable = 'sellable';
  static const restockDamaged = 'damaged';
  static const restockSupplier = 'supplier';

  /// معالجة مرتجع جزئي — [itemReturns] مفتاحها invoiceItemId والقيمة كمية الإرجاع
  ///
  /// [restockConditions] اختياري: نفس المفتاح، حالة الصنف لكل سطر. السطور
  /// اللي مش موجودة في الخريطة بتتعامل على إنها `sellable` (سلوك قديم).
  Future<int> processPartialReturn({
    required int invoiceId,
    required Map<int, int> itemReturns,
    String reason = 'customer_request',
    String? notes,
    String? processedBy,
    Map<int, String>? restockConditions,
  }) async {
    final wanted = itemReturns.entries.where((e) => e.value > 0).toList();
    if (wanted.isEmpty) throw Exception('لم يتم اختيار أي صنف للإرجاع');

    return _db.transaction(() async {
      final invoice = await (_db.select(_db.invoices)..where((t) => t.id.equals(invoiceId))).getSingleOrNull();
      if (invoice == null) throw Exception('الفاتورة غير موجودة');
      if (invoice.status == 'voided') throw Exception('لا يمكن إرجاع فاتورة ملغاة');
      if (invoice.status == 'draft') throw Exception('لا يمكن إرجاع مسودة');

      // جلب أسطر الفاتورة الأصلية
      final lines = await _db.invoiceDao.getItemsByInvoiceId(invoiceId);
      final byId = {for (final l in lines) l.id: l};

      // 1) تحقق كامل قبل أي كتابة
      double totalReturn = 0.0;
      final toProcess = <InvoiceItem, int>{};
      for (final e in wanted) {
        final line = byId[e.key];
        if (line == null) throw Exception('بند غير موجود في الفاتورة (id=${e.key})');
        final already = await _getReturnedQtyForItem(line.id);
        final available = line.quantity - already;
        if (available <= 0) throw Exception('الصنف "${line.productId}" تم إرجاعه بالكامل مسبقاً');
        if (e.value > available) {
          throw Exception('الكمية المطلوبة (${e.value}) تتجاوز المتاح للإرجاع ($available) للصنف');
        }
        toProcess[line] = e.value;
        // سعر السطر بعد الخصم موزع تناسبياً. quantity ممكن يكون 0 في سطر
        // تالف فبتقسم على 1 عشان ماينتجش Infinity/NaN.
        final qtyDivisor = line.quantity == 0 ? 1 : line.quantity;
        final netUnit = line.price - (line.discount / qtyDivisor);
        final lineValue = e.value * netUnit;
        if (lineValue.isNaN || lineValue.isInfinite) {
          throw Exception('صنف "${line.productId}" له سعر غير صالح — اتشيك على بيانات الفاتورة');
        }
        totalReturn += lineValue;
      }
      if (totalReturn <= 0) throw Exception('قيمة المرتجع صفر');

      // 2) إنشاء header
      final now = DateTime.now();
      final returnNumber = 'RET-${now.year}${now.month.toString().padLeft(2, '0')}'
          '${now.day.toString().padLeft(2, '0')}-'
          '${now.microsecondsSinceEpoch % 1000000}'
          '-${now.hashCode.abs() % 97}';
      final returnId = await _db.into(_db.salesReturns).insert(
        SalesReturnsCompanion.insert(
          returnNumber: returnNumber,
          originalInvoiceId: invoiceId,
          customerId: Value(invoice.customerId),
          customerName: invoice.customerName ?? 'عميل',
          returnDate: now,
          totalAmount: totalReturn,
          returnReason: reason,
          notes: Value(notes),
          status: const Value('completed'),
          processedBy: Value(processedBy),
          refundedAmount: const Value(0.0),
          settlementStatus: const Value('pending'),
          syncId: Value(const Uuid().v4()),
        ),
      );

      // 3) لكل سطر: insert sales_return_items + رجوع مخزون + شحنة + تتبع
      var restockedTotal = 0.0;
      for (final entry in toProcess.entries) {
        final line = entry.key;
        final qty = entry.value;
        final product = await _db.productDao.getProductById(line.productId);
        final qtyDivisor = line.quantity == 0 ? 1 : line.quantity;
        final netUnit = line.price - (line.discount / qtyDivisor);
        final lineTotal = qty * netUnit;
        final discountPortion = line.discount * qty / qtyDivisor;
        final commissionPortion = line.commission * qty / qtyDivisor;
        final condition = restockConditions?[line.id] ?? restockSellable;
        // التالف ومايُرسل للمورد مايرجعش للمخزون — بيروح جدول التالف بدل كده.
        final goesToStock = condition == restockSellable;

        await _db.into(_db.salesReturnItems).insert(
          SalesReturnItemsCompanion.insert(
            returnId: returnId,
            productId: line.productId,
            productName: product?.name ?? 'صنف ${line.productId}',
            quantity: qty,
            unitPrice: line.price,
            totalPrice: lineTotal,
            invoiceItemId: Value(line.id),
            discount: Value(discountPortion),
            commission: Value(commissionPortion),
            shipmentId: Value(line.shipmentId),
            returnReason: Value(reason),
            restockCondition: Value(condition),
            restockedQty: Value(goesToStock ? qty : 0),
            syncId: Value(const Uuid().v4()),
          ),
        );

        if (goesToStock) {
          restockedTotal += lineTotal;
          // مخزون
          if (product != null) {
            await _db.productDao.updateProduct(
              product.copyWith(quantity: product.quantity + qty),
            );
          }
          // شحنة خضار — عكس sold/remaining
          if (line.shipmentId != null) {
            final shipment =
                await _db.vegetableShipmentDao.getById(line.shipmentId!);
            if (shipment != null) {
              await _db.vegetableShipmentDao.updateShipment(
                shipment.copyWith(
                  barnikaSoldCount: (shipment.barnikaSoldCount - qty).clamp(0, 1 << 30),
                  barnikaRemainingCount: shipment.barnikaRemainingCount + qty,
                ),
              );
            }
          }
        }
      }

      await (_db.update(_db.salesReturns)..where((t) => t.id.equals(returnId)))
          .write(SalesReturnsCompanion(restockedAmount: Value(restockedTotal)));

      // صافي الفاتورة — الفاتورة نفسها ماتتغيرش، بس الأرقام دي بتتسجل
      // عشان التقارير ما تحتاجش تعمل join على sales_returns كل مرة.
      final newReturned = invoice.returnedAmount + totalReturn;
      await (_db.update(_db.invoices)..where((t) => t.id.equals(invoiceId))).write(
        InvoicesCompanion(
          returnedAmount: Value(newReturned),
          netAmount: Value((invoice.totalAmount - newReturned) < 0
              ? 0.0
              : invoice.totalAmount - newReturned),
        ),
      );

      // 4) قيد محاسبي عكسي للعميل الآجل
      if (invoice.customerId != null && invoice.customerId != 'cash' && invoice.customerId!.isNotEmpty) {
        await _db.ledgerDao.insertTransaction(
          LedgerTransactionsCompanion.insert(
            id: '${const Uuid().v4()}_ret_$returnId',
            entityType: 'Customer',
            refId: invoice.customerId!,
            date: now,
            description: 'مرتجع جزئي فاتورة ${displayInvoiceNumber(invoice.invoiceNumber, invoice.id) ?? invoice.id} ($returnNumber)',
            debit: const Value(0.0),
            credit: Value(totalReturn),
            origin: 'reversal',
            receiptNumber: Value('RET$returnId'),
          ),
        );
      }

      return returnId;
    });
  }
}
