import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';

/// Supplier purchase returns (استرجاع مشتريات).
///
/// Mirrors the customer sales-return semantics in the smallest safe form:
/// - per-line return quantity can never exceed the line's current quantity
///   (repeat returns are naturally capped — second full return is a no-op);
/// - stock is decremented (floored at 0, never negative);
/// - purchase totals shrink; status re-derives from remaining;
/// - ledger gets reversal rows (Supplier DEBIT = less owed), linked with a
///   `RET-<purchaseId>-<millis>` receipt (same convention as sales returns).
/// Everything runs in ONE transaction. No dedicated header table is used:
/// the existing `purchase_returns` tables are typed for the *enhanced*
/// (integer-id) purchase subsystem and cannot reference TEXT-id purchases.
class PurchaseReturnService {
  final AppDatabase _db;

  PurchaseReturnService(this._db);

  /// Returns the total returned value. Throws on any guard violation with
  /// zero side effects (validation happens before any write).
  Future<double> processReturn({
    required String purchaseId,
    required Map<String, int> itemReturns,
    String reason = '',
  }) async {
    final wanted = itemReturns.entries.where((e) => e.value > 0).toList();
    if (wanted.isEmpty) return 0.0;

    return _db.transaction(() async {
      final purchase = await (_db.select(_db.purchases)
            ..where((t) => t.id.equals(purchaseId)))
          .getSingleOrNull();
      if (purchase == null) throw Exception('فاتورة المشتريات غير موجودة');
      if (purchase.supplierId == null || purchase.supplierId!.isEmpty) {
        throw Exception('فاتورة بلا مورد — لا يمكن الاسترجاع');
      }

      final lines = await _db.purchaseDao.getPurchaseItems(
        purchase.invoiceNumber,
      );
      final byId = {for (final l in lines) l.id: l};

      // 1. Validate everything first (no partial application).
      double returnValue = 0.0;
      for (final e in wanted) {
        final line = byId[e.key];
        if (line == null) {
          throw Exception('بند غير موجود في الفاتورة');
        }
        if (e.value > line.quantity) {
          throw Exception(
            'الكمية المرتجعة (${e.value}) تتجاوز كمية البند (${line.quantity})',
          );
        }
        returnValue += e.value * line.unitPrice;
      }
      if (returnValue <= 0) return 0.0;

      // 2. Apply line + stock changes.
      for (final e in wanted) {
        final line = byId[e.key]!;
        final newQty = line.quantity - e.value;
        final product = await _db.productDao.getProductById(
          int.tryParse(line.productId) ?? -1,
        );
        // Full-object replace: a partial ProductsCompanion here would wipe
        // absent columns (replace semantics). Never pass partial companions
        // to updateProduct.
        if (product != null) {
          final newStock = product.quantity - e.value;
          await _db.productDao.updateProduct(
            product.copyWith(
              quantity: newStock < 0 ? 0 : newStock,
              updatedAt: Value(DateTime.now()),
            ),
          );
        }
        if (newQty <= 0) {
          await (_db.delete(_db.purchaseItems)
                ..where((t) => t.id.equals(line.id)))
              .go();
        } else {
          await (_db.update(_db.purchaseItems)
                ..where((t) => t.id.equals(line.id)))
              .write(
            PurchaseItemsCompanion(
              quantity: Value(newQty),
              totalPrice: Value(newQty * line.unitPrice),
            ),
          );
        }
      }

      // 3. Shrink the purchase header, re-derive status. Paid stays as-is
      // (a return that exceeds it leaves a supplier credit, honestly shown
      // as negative remaining / negative balance).
      final newTotal = purchase.totalAmount - returnValue;
      final remaining = newTotal - purchase.paidAmount;
      final newStatus = remaining <= 0.01
          ? 'paid'
          : (purchase.paidAmount > 0 ? 'partial' : 'pending');
      await (_db.update(_db.purchases)
            ..where((t) => t.id.equals(purchaseId)))
          .write(
        PurchasesCompanion(
          totalAmount: Value(newTotal < 0 ? 0 : newTotal),
          status: Value(newStatus),
        ),
      );

      // 4. Ledger reversal rows (reduce what we owe).
      final now = DateTime.now();
      final receipt = 'RET-$purchaseId-${now.millisecondsSinceEpoch}';
      await _db.ledgerDao.insertTransaction(
        LedgerTransactionsCompanion.insert(
          id: '${const Uuid().v4()}_ret',
          entityType: 'Supplier',
          refId: purchase.supplierId!,
          date: now,
          description:
              'مرتجع مشتريات: فاتورة ${purchase.invoiceNumber}${
                reason.isNotEmpty ? ' ($reason)' : ''}',
          debit: Value(returnValue),
          credit: const Value(0.0),
          origin: 'reversal',
          receiptNumber: Value(receipt),
        ),
      );

      return returnValue;
    });
  }
}
