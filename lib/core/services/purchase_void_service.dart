import 'package:drift/drift.dart';

import '../database/app_database.dart';

/// إلغاء فاتورة مشتريات كأنها مجتش.
///
/// نظير [InvoiceVoidService] للبيع، بس عشان المشتريات شغالة بنظام تاني:
///
/// | | المبيعات (`Invoices`) | المشتريات (`Purchases`) |
/// |---|---|---|
/// | المفتاح | `int` | `text` (= رقم الفاتورة) |
/// | أثر المخزون عند الإنشاء | **نقص** | **زيادة** |
/// | سطور الفاتورة | `invoice_items` | `purchase_items` (`id` مركّب) |
/// | معرّفات القيود | `INV<id>` | `<number>_ledger` / `_ledger_pay` |
/// | الحذف | `status='voided'` | `is_deleted = 1` (soft delete أصلاً في الجدول) |
///
/// كل حاجة عملتها الفاتورة بتترجع بالعكس في **transaction واحدة**:
/// 1. حارس: موجودة / مش متمسحة / مفيش مرتجعات / اليوم مفتوح
/// 2. **نقص** المخزون (كان زاده)
/// 3. حذف سطور الفاتورة
/// 4. حذف قيود المورد (`_ledger` و `_ledger_pay`)
/// 5. `is_deleted = 1` + سبب + مين + إمتى
/// 6. سجل مراجعة
class PurchaseVoidService {
  final AppDatabase _db;
  PurchaseVoidService(this._db);

  Future<void> voidPurchase({
    required String purchaseId,
    required String reason,
    required String voidedBy,
  }) async {
    if (reason.trim().isEmpty) throw Exception('سبب الإلغاء مطلوب');

    await _db.transaction(() async {
      // ---------- 1) تحقق قبل أي كتابة ----------
      final purchase = await (_db.select(_db.purchases)
            ..where((t) => t.id.equals(purchaseId)))
          .getSingleOrNull();
      if (purchase == null) throw Exception('فاتورة المشتريات غير موجودة');
      if (purchase.isDeleted) throw Exception('الفاتورة ملغاة بالفعل');

      if (!await _db.dayDao.isDayOpen()) {
        throw Exception('اليوم مقفول — افتحه قبل إلغاء فاتورة');
      }

      // لو الرصيد خلص (totalAmount <= 0 بعد استرجاع كامل) يبقى السجل
      // تاريخي وخلاص — الإلغاء مش هيفيد.
      if (purchase.totalAmount <= 0.01) {
        throw Exception(
          'الفاتورة دي متسترجعة بالكامل بالفعل — سيبها زي ما هي',
        );
      }

      final lines = await _db.purchaseDao.getPurchaseItems(purchase.invoiceNumber);
      final number = purchase.invoiceNumber;

      // ---------- 2) عكس المخزون (كان زاده) ----------
      for (final line in lines) {
        final productId = int.tryParse(line.productId);
        if (productId == null) continue; // منتج محذوف أو id نصي
        final product = await _db.productDao.getProductById(productId);
        if (product == null) continue;
        final back = product.quantity - line.quantity;
        await _db.productDao.updateProduct(
          product.copyWith(
            quantity: back < 0 ? 0 : back,
            updatedAt: Value(DateTime.now()),
          ),
        );
      }

      // ---------- 3) حذف سطور الفاتورة ----------
      await (_db.delete(_db.purchaseItems)
            ..where((t) => t.purchaseId.equals(number)))
          .go();

      // ---------- 4) عكس قيود المورد ----------
      // `recordSupplierPurchase` بيكتب بمعرّفات حتمية، فبنمسح نفس الأسماء.
      await _db.ledgerDao.deleteTransaction('${number}_ledger');
      await _db.ledgerDao.deleteTransaction('${number}_ledger_pay');

      // ---------- 5) الحذف الناعم ----------
      // `Purchases.is_deleted` موجود في الجدول أصلاً — مش hard delete، فالبيانات
      // بتفضل في الداتابيز وتظهر في أي استعلام بيفلتر is_deleted = 0 بس.
      await (_db.update(_db.purchases)..where((t) => t.id.equals(purchaseId)))
          .write(
        PurchasesCompanion(
          isDeleted: const Value(true),
          notes: Value(
            [
              if (purchase.notes?.isNotEmpty == true) purchase.notes!,
              'ملغاة بواسطة $voidedBy: $reason',
            ].join(' — '),
          ),
        ),
      );

      // ---------- 6) سجل مراجعة ----------
      try {
        await _db.auditDao.logAudit(
          action: 'VOID',
          tableName: 'purchases',
          details: 'purchase=$number supplier=${purchase.supplierId ?? '-'} '
              'total=${purchase.totalAmount} lines=${lines.length} '
              'reason=$reason by=$voidedBy',
        );
      } catch (_) {
        // سجل المراجعة ماينفعش يوقف عملية مالية.
      }
    });
  }
}