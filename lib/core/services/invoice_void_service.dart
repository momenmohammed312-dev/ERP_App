import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../services/invoice_number_formatter.dart';
import 'return_refund_service.dart';

/// أسباب إلغاء الفاتورة — مقصورة عشان التقارير تتجمّع صح.
class VoidReasons {
  static const inputError = 'input_error'; // خطأ إدخال
  static const customerChangedMind = 'customer_changed_mind';
  static const duplicate = 'duplicate'; // فاتورة مكررة
  static const testInvoice = 'test_invoice'; // فاتورة تجريبية
  static const other = 'other';

  static const all = [
    inputError,
    customerChangedMind,
    duplicate,
    testInvoice,
    other,
  ];

  static String label(String code) {
    switch (code) {
      case inputError:
        return 'خطأ إدخال';
      case customerChangedMind:
        return 'العميل غيّر رأيه';
      case duplicate:
        return 'فاتورة مكررة';
      case testInvoice:
        return 'فاتورة تجريبية';
      default:
        return 'أخرى';
    }
  }
}

/// ملخص اللي هيتمعمله قبل التأكيد — الـdialog بيعرضه للمستخدم.
class VoidPreview {
  final int invoiceId;
  final String invoiceNumber;
  final String? customerName;
  final double totalAmount;
  final int itemCount;
  final int returnCount;
  final int refundCount;
  final double cashRefundAmount;
  final int paymentCount;
  final int ledgerRowCount;

  VoidPreview({
    required this.invoiceId,
    required this.invoiceNumber,
    required this.customerName,
    required this.totalAmount,
    required this.itemCount,
    required this.returnCount,
    required this.refundCount,
    required this.cashRefundAmount,
    required this.paymentCount,
    required this.ledgerRowCount,
  });
}

/// إلغاء الفاتورة كأنها مجتش.
///
/// **مش hard delete** — السجل بيفضل موجود (audit)، بس بيختفي من كل التقارير
/// والأرصدة.
///
/// كل حاجة عملتها الفاتورة بتتعمل بالعكس، بالترتيب ده:
/// 1. المرتجعات المرتبطة (لو فيه): عكس المخزون + حذف قيود RET/RREF + حذف
///    المرتجع واسترداداته — عشان الإلغاء يمشي **حتى لو الفاتورة عليها مرتجع**
/// 2. مخزون كل السطور يرجع
/// 3. عدّادات شحنة الخضار ترجع
/// 4. قيود الـledger بتاع `receiptNumber = 'INV<id>'` (بيع + سداد + عمولة) تتشال
/// 5. دفعات `invoice_payments` تتشال
/// 6. `status = 'voided'` + سبب + مين + إمتى + صافي = صفر
/// 7. سجل مراجعة + push للـsync
///
/// كله جوه **transaction واحدة** — يا كله يا ولا حاجة.
class InvoiceVoidService {
  final AppDatabase _db;
  InvoiceVoidService(this._db);

  /// يبني الملخص قبل ما المستخدم يؤكد — عشان يشوف الأثر الحقيقي.
  Future<VoidPreview> preview(int invoiceId) async {
    final invoice = await (_db.select(_db.invoices)
          ..where((t) => t.id.equals(invoiceId)))
        .getSingleOrNull();
    if (invoice == null) throw Exception('الفاتورة غير موجودة');

    final items = await _db.invoiceDao.getItemsByInvoiceId(invoiceId);
    final returns = await _db.salesReturnsDao.getReturnsForInvoice(invoiceId);
    final payments = await _db.invoicePaymentsDao.getPaymentsForInvoice(invoiceId);
    final ledger = await _db.ledgerDao
        .getTransactionsByReceiptNumber('INV$invoiceId');

    // ملخص الاستردادات المرتبطة — عشان المستخدم يشوف إن في فلوس اتستردت
    // فعلاً وهيتم عكسها كمان.
    int refundCount = 0;
    double cashRefundAmount = 0;
    for (final r in returns) {
      final refunds = await _db.returnRefundsDao.getRefundsForReturn(r.id);
      refundCount += refunds.length;
      for (final f in refunds) {
        if (f.method == RefundMethod.cash || f.method == RefundMethod.original) {
          cashRefundAmount += f.amount;
        }
      }
    }

    return VoidPreview(
      invoiceId: invoiceId,
      invoiceNumber:
          displayInvoiceNumber(invoice.invoiceNumber, invoice.id) ??
              invoice.invoiceNumber ??
              '${invoice.id}',
      customerName: invoice.customerName,
      totalAmount: invoice.totalAmount,
      itemCount: items.length,
      returnCount: returns.length,
      refundCount: refundCount,
      cashRefundAmount: cashRefundAmount,
      paymentCount: payments.length,
      ledgerRowCount: ledger.length,
    );
  }

  Future<void> voidInvoice({
    required int invoiceId,
    required String reason,
    String? notes,
    required String voidedBy,
  }) async {
    if (reason.trim().isEmpty) throw Exception('سبب الإلغاء مطلوب');

    await _db.transaction(() async {
      // ---------- 1) تحقق كامل قبل أي كتابة ----------
      final invoice = await (_db.select(_db.invoices)
            ..where((t) => t.id.equals(invoiceId)))
          .getSingleOrNull();
      if (invoice == null) throw Exception('الفاتورة غير موجودة');

      // idempotent
      if (invoice.status == 'voided') {
        throw Exception('الفاتورة ملغاة بالفعل');
      }

      // نفس الحارس المستخدم في كل عملية مالية تانية بالبرنامج.
      if (!await _db.dayDao.isDayOpen()) {
        throw Exception('اليوم مقفول — افتحه قبل إلغاء فاتورة');
      }

final items = await _db.invoiceDao.getItemsByInvoiceId(invoiceId);
      // بيتحسب قبل الحذف عشان سجل المراجعة يبقى رقم حقيقي.
      final paymentCount =
          (await _db.invoicePaymentsDao.getPaymentsForInvoice(invoiceId)).length;

      // ---------- 1.5) عكس المرتجعات المرتبطة (لو الفاتورة عليها مرتجع) ----------
      // الفاتورة ممكن يكون عليها مرتجع جزئي أو كامل. المرتجع وقت إنشائه:
      //   • رجّع جزء من المخزون (restockedQty للأسطر sellable)
      //   • عكس عدّاد الشحنة
      //   • كتب قيد عميل عكسي receiptNumber='RET<id>'
      //   • ممكن يكون اتسترد منه فلوس (return_refunds + قيد Cash 'RREF<id>')
      // كل ده لازم يتم عكسه الأول، وإلا المخزون هيبقى أضعف/أقوى مرتين.
      final returns = await _db.salesReturnsDao.getReturnsForInvoice(invoiceId);
      int reversedReturns = 0;
      int reversedRefunds = 0;
      double reversedCashRefund = 0;
      for (final ret in returns) {
        // (أ) عكس الاستردادات: قيد الكاش بيتشال، والسجل بيتحذف مع المرتجع.
        final refunds = await _db.returnRefundsDao.getRefundsForReturn(ret.id);
        for (final rf in refunds) {
          reversedRefunds++;
          if (rf.method == RefundMethod.cash ||
              rf.method == RefundMethod.original) {
            reversedCashRefund += rf.amount;
          }
          await _db.ledgerDao.deleteTransactionsByReceiptNumber('RREF${rf.id}');
        }

        // (ب) عكس المخزون اللي المرتجع ضخّه. التالف ماكانش دخل المخزون
        // أصلاً (restockedQty=0) فمفيش حاجة نعكسها.
        final ritems = await _db.salesReturnsDao.getItemsForReturn(ret.id);
        for (final ri in ritems) {
          final restored = ri.restockedQty;
          if (restored <= 0) continue;
          final product = await _db.productDao.getProductById(ri.productId);
          if (product != null) {
            await _db.productDao.updateProduct(
              product.copyWith(
                quantity: (product.quantity - restored).clamp(0, 1 << 30),
              ),
            );
          }
          if (ri.shipmentId != null) {
            final shipment =
                await _db.vegetableShipmentDao.getById(ri.shipmentId!);
            if (shipment != null) {
              await _db.vegetableShipmentDao.updateShipment(
                shipment.copyWith(
                  barnikaSoldCount:
                      (shipment.barnikaSoldCount + restored).clamp(0, 1 << 30),
                  barnikaRemainingCount:
                      (shipment.barnikaRemainingCount - restored)
                          .clamp(0, 1 << 30),
                ),
              );
            }
          }
        }

        // (ج) قيد العميل العكسي بتاع المرتجع يتشال، والمرتجع نفسه يتشال.
        await _db.ledgerDao.deleteTransactionsByReceiptNumber('RET${ret.id}');
        await _db.salesReturnsDao.deleteReturnCascade(ret.id);
        reversedReturns++;
      }

      // ---------- 2) رجوع المخزون ----------
      for (final item in items) {
        final product =
            await _db.productDao.getProductById(item.productId);
        if (product != null) {
          await _db.productDao.updateProduct(
            product.copyWith(quantity: product.quantity + item.quantity),
          );
        }
      }

      // ---------- 3) عكس عدّادات شحنة الخضار ----------
      for (final item in items) {
        if (item.shipmentId == null) continue;
        final shipment =
            await _db.vegetableShipmentDao.getById(item.shipmentId!);
        if (shipment == null) continue;
        await _db.vegetableShipmentDao.updateShipment(
          shipment.copyWith(
            barnikaSoldCount:
                (shipment.barnikaSoldCount - item.quantity).clamp(0, 1 << 30),
            barnikaRemainingCount: shipment.barnikaRemainingCount + item.quantity,
          ),
        );
      }

      // ---------- 4) عكس قيود الـledger ----------
      // كل صف بيع/سداد/عمولة ليه receiptNumber = 'INV<id>'. بنمسحهم كلهم
      // عشان الرصيد يبقى 0 بالظبط من غير تعديل على أي تقرير موجود.
      final ledgerRows =
          await _db.ledgerDao.getTransactionsByReceiptNumber('INV$invoiceId');
      await _db.ledgerDao.deleteTransactionsByReceiptNumber('INV$invoiceId');

      // ---------- 5) دفعات الفاتورة ----------
      await _db.invoicePaymentsDao.deletePaymentsForInvoice(invoiceId);

      // ---------- 6) حالة الفاتورة ----------
      await (_db.update(_db.invoices)..where((t) => t.id.equals(invoiceId)))
          .write(
        InvoicesCompanion(
          status: const Value('voided'),
          voidedAt: Value(DateTime.now()),
          voidReason: Value(reason),
          voidedBy: Value(voidedBy),
          returnedAmount: const Value(0.0),
          netAmount: const Value(0.0),
          refundedAmount: const Value(0.0),
          updatedAt: Value(DateTime.now()),
        ),
      );

      // ---------- 7) سجل مراجعة ----------
      // السطر ده هو الأثر الوحيد اللي بيفضل — الباقي اتشال فعلاً.
      await _audit(
        invoiceId: invoiceId,
        invoiceNumber: invoice.invoiceNumber,
        customerId: invoice.customerId,
        customerName: invoice.customerName,
        reason: reason,
        notes: notes,
        voidedBy: voidedBy,
        totalAmount: invoice.totalAmount,
        itemCount: items.length,
        reversedLedger: ledgerRows.length,
        reversedPayments: paymentCount,
        reversedReturns: reversedReturns,
        reversedRefunds: reversedRefunds,
        reversedCashRefund: reversedCashRefund,
      );

      // ---------- 8) مزامنة مع باقي الأجهزة ----------
      // بدون السطر ده، السيرفر بيفضل شايف الفاتورة مدفوعة.
      await _db.invoiceDao.voidInvoiceSync(invoiceId);
    });
  }

  Future<void> _audit({
    required int invoiceId,
    required String? invoiceNumber,
    required String? customerId,
    required String? customerName,
    required String reason,
    required String? notes,
    required String voidedBy,
    required double totalAmount,
    required int itemCount,
    required int reversedLedger,
    required int reversedPayments,
    required int reversedReturns,
    required int reversedRefunds,
    required double reversedCashRefund,
  }) async {
    try {
      await _db.auditDao.logAudit(
        action: 'VOID',
        tableName: 'invoices',
        recordId: invoiceId,
        details: 'invoice=$invoiceNumber customer=${customerName ?? customerId ?? '-'} '
            'total=$totalAmount items=$itemCount ledger=$reversedLedger '
            'payments=$reversedPayments returns=$reversedReturns '
            'refunds=$reversedRefunds cashRefund=$reversedCashRefund '
            'reason=$reason notes=${notes ?? '-'} by=$voidedBy',
      );
    } catch (_) {
      // سجل المراجعة ماينفعش يوقف عملية مالية — الفاتورة اتلغت فعلاً.
    }
  }
}