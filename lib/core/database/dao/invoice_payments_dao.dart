import 'package:drift/drift.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/tables/invoice_payments_table.dart';

part 'invoice_payments_dao.g.dart';

/// DAO لإدارة مدفوعات الفواتير (يدعم Split Payment)
@DriftAccessor(tables: [InvoicePayments])
class InvoicePaymentsDao extends DatabaseAccessor<AppDatabase>
    with _$InvoicePaymentsDaoMixin {
  InvoicePaymentsDao(super.db);

  /// إضافة دفعة جديدة
  Future<int> insertPayment(InvoicePaymentsCompanion payment) =>
      into(invoicePayments).insert(payment);

  /// الحصول على كل دفعات فاتورة معينة
  Future<List<InvoicePayment>> getPaymentsForInvoice(int invoiceId) =>
      (select(invoicePayments)
            ..where((t) => t.invoiceId.equals(invoiceId))
            ..orderBy([(t) => OrderingTerm.asc(t.paidAt)]))
          .get();

  /// إجمالي المدفوع لفاتورة معينة
  Future<double> getTotalPaidForInvoice(int invoiceId) async {
    final payments = await getPaymentsForInvoice(invoiceId);
    return payments.fold<double>(0.0, (sum, p) => sum + p.amount);
  }

  /// حذف كل دفعات فاتورة (عند إلغاء الفاتورة)
  Future<int> deletePaymentsForInvoice(int invoiceId) =>
      (delete(invoicePayments)
            ..where((t) => t.invoiceId.equals(invoiceId)))
          .go();

  /// إجمالي الدفعات بطريقة دفع معينة في فترة زمنية
  Future<double> getTotalByMethodAndDateRange(
    String method,
    DateTime start,
    DateTime end,
  ) async {
    final payments = await (select(invoicePayments)
          ..where(
            (t) =>
                t.paymentMethod.equals(method) &
                t.paidAt.isBetweenValues(start, end),
          ))
        .get();
    return payments.fold<double>(0.0, (sum, p) => sum + p.amount);
  }

  /// مراقبة دفعات فاتورة (Stream)
  Stream<List<InvoicePayment>> watchPaymentsForInvoice(int invoiceId) =>
      (select(invoicePayments)
            ..where((t) => t.invoiceId.equals(invoiceId)))
          .watch();
}
