import 'package:drift/drift.dart';

import '../database/app_database.dart';

/// One editable purchase line (product must exist; orphan lines — product
/// deleted since — never reach here, the caller carries them forward
/// untouched and includes their frozen value in [total]).
class PurchaseEditLine {
  final int productId;
  final int quantity;
  final String unit;
  final double unitPrice;
  final double discount;
  final double tax;

  const PurchaseEditLine({
    required this.productId,
    required this.quantity,
    required this.unit,
    required this.unitPrice,
    this.discount = 0,
    this.tax = 0,
  });

  double get lineTotal => quantity * unitPrice - discount + tax;
}

/// Purchase-invoice edit application (single atomic unit).
///
/// The supplier and invoice number are preserved by contract (the UI locks
/// both). Steps inside ONE transaction: restore stock from replaced lines,
/// delete them, insert new lines + apply stock, rewrite the header totals,
/// delete the old ledger pair and post the new one. Orphan lines (product
/// gone) are detected here and left completely untouched.
class PurchaseEditService {
  final AppDatabase _db;

  PurchaseEditService(this._db);

  Future<void> applyEdit({
    required String purchaseId,
    required String invoiceNumber,
    required String supplierId,
    required double total,
    required double paid,
    required String paymentMethod,
    required List<PurchaseEditLine> lines,
  }) async {
    if (lines.isEmpty) throw Exception('يرجى إضافة منتج واحد على الأقل');
    for (final l in lines) {
      if (l.quantity <= 0) throw Exception('كمية غير صالحة لأحد الأصناف');
    }

    return _db.transaction(() async {
      final purchase = await (_db.select(_db.purchases)
            ..where((t) => t.id.equals(purchaseId)))
          .getSingleOrNull();
      if (purchase == null) throw Exception('فاتورة المشتريات غير موجودة');
      // Lines are keyed by invoice NUMBER (not row id) — resolve it here.
      final lineKey = purchase.invoiceNumber;
      final oldLines = await _db.purchaseDao.getPurchaseItems(lineKey);

      // Orphans: product row gone — keep the DB row and stock as-is.
      final orphanIds = <String>{};
      for (final old in oldLines) {
        final product = await _db.productDao.getProductById(
          int.tryParse(old.productId) ?? -1,
        );
        if (product == null) orphanIds.add(old.id);
      }

      // 1. Undo replaced lines: SUBTRACT their quantities back out of
      // stock (purchases increase stock), floored at zero, then delete
      // the rows. Orphans are skipped entirely.
      for (final old
          in oldLines.where((l) => !orphanIds.contains(l.id))) {
        final product = await _db.productDao.getProductById(
          int.tryParse(old.productId) ?? -1,
        );
        if (product != null) {
          final restored = product.quantity - old.quantity;
          await _db.productDao.updateProduct(
            product.copyWith(
              quantity: restored < 0 ? 0 : restored,
              updatedAt: Value(DateTime.now()),
            ),
          );
        }
        await (_db.delete(_db.purchaseItems)
              ..where((t) => t.id.equals(old.id)))
            .go();
      }

      // 2. Insert new lines + apply stock.
      for (final entry in lines) {
          await _db.into(_db.purchaseItems).insert(
              PurchaseItemsCompanion.insert(
                id: '${invoiceNumber}_${entry.productId}',
                purchaseId: invoiceNumber,
                productId: entry.productId.toString(),
                quantity: entry.quantity,
                unitPrice: entry.unitPrice,
                totalPrice: entry.lineTotal,
                unit: entry.unit,
                createdAt: DateTime.now(),
              ),
            );
        final current = await _db.productDao.getProductById(entry.productId);
        if (current == null) {
          throw Exception('المنتج غير موجود (ID: ${entry.productId})');
        }
        await _db.productDao.updateProduct(
          current.copyWith(
            quantity: current.quantity + entry.quantity,
            updatedAt: Value(DateTime.now()),
          ),
        );
      }

      // 3. Header totals + re-derived status.
      final remaining = total - paid;
      await (_db.update(_db.purchases)
            ..where((t) => t.id.equals(purchaseId)))
          .write(
        PurchasesCompanion(
          totalAmount: Value(total),
          paidAmount: Value(paid),
          paymentMethod: Value(paymentMethod),
          status: Value(
            remaining <= 0.01
                ? 'paid'
                : (paid > 0 ? 'partial' : 'pending'),
          ),
        ),
      );

      // 4. Rewrite the ledger pair (deterministic ids, old rows removed).
      await _db.ledgerDao.deleteTransaction('${invoiceNumber}_ledger');
      await _db.ledgerDao.deleteTransaction('${invoiceNumber}_ledger_pay');
      await _db.ledgerDao.recordSupplierPurchase(
        supplierId: supplierId,
        invoiceNumber: invoiceNumber,
        total: total,
        paid: paid,
        date: DateTime.now(),
      );
    });
  }
}
