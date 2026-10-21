import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/return_refunds_table.dart';

part 'return_refunds_dao.g.dart';

/// DAO لاسترداد أموال المرتجعات (الفلوس اللي بتخرج بعد رجوع البضاعة).
@DriftAccessor(tables: [ReturnRefunds])
class ReturnRefundsDao extends DatabaseAccessor<AppDatabase>
    with _$ReturnRefundsDaoMixin {
  ReturnRefundsDao(super.db);

  Future<int> insertRefund(ReturnRefundsCompanion refund) =>
      into(returnRefunds).insert(refund);

  /// كل الاستردادات السارية (غير الملغاة) لمرتجع معيّن، الأقدم أولاً.
  Future<List<ReturnRefund>> getRefundsForReturn(int returnId) =>
      (select(returnRefunds)
            ..where((t) => t.returnId.equals(returnId) & t.isVoided.equals(false))
            ..orderBy([(t) => OrderingTerm.asc(t.refundDate)]))
          .get();

  /// إجمالي المسترد فعلياً لمرتجع — المصدر الوحيد للحقيقة في كل الشاشات.
  Future<double> getRefundedAmountForReturn(int returnId) async {
    final row = await (selectOnly(returnRefunds)
          ..addColumns([returnRefunds.amount.sum()])
          ..where(returnRefunds.returnId.equals(returnId) &
              returnRefunds.isVoided.equals(false)))
        .map((r) => r.read(returnRefunds.amount.sum()))
        .getSingle();
    return (row ?? 0.0).toDouble();
  }

  /// المتبقي من المرتجع — الكاشير بيشوفه ويقدر يسترد لحد ما يوصل صفر.
  Future<double> getOutstandingForReturn(int returnId) async {
    final ret = await (db.select(db.salesReturns)
          ..where((t) => t.id.equals(returnId)))
        .getSingleOrNull();
    if (ret == null) return 0.0;
    final refunded = await getRefundedAmountForReturn(returnId);
    final outstanding = ret.totalAmount - refunded;
    return outstanding < 0 ? 0.0 : outstanding;
  }

  /// استردادات نقدية في فترة — دي اللي بتخصم من رصيد اليوم المتوقع.
  /// مينفعش نستخدمها غير لـcash: رصيد العميل مالوش علاقة بالصندوق.
  Future<double> getCashRefundsBetween(DateTime from, DateTime to) async {
    final row = await (selectOnly(returnRefunds)
          ..addColumns([returnRefunds.amount.sum()])
          ..where(returnRefunds.refundDate.isBetweenValues(from, to) &
              returnRefunds.method.equals('cash') &
              returnRefunds.isVoided.equals(false)))
        .map((r) => r.read(returnRefunds.amount.sum()))
        .getSingle();
    return (row ?? 0.0).toDouble();
  }

  /// استردادات نقدية تمت فعلياً داخل جلسة نقدية بناءً على تاريخ الإنشاء [createdAt].
  /// تخصم من رصيد الدرج الفعلي حتى لو تغير [refundDate] عبر DocumentDateService.
  Future<double> getCashRefundsForSessionBetween(DateTime from, DateTime to) async {
    final row = await (selectOnly(returnRefunds)
          ..addColumns([returnRefunds.amount.sum()])
          ..where(((returnRefunds.createdAt.isNotNull() &
                      returnRefunds.createdAt.isBetweenValues(from, to)) |
                  (returnRefunds.createdAt.isNull() &
                      returnRefunds.refundDate.isBetweenValues(from, to))) &
              returnRefunds.method.equals('cash') &
              returnRefunds.isVoided.equals(false)))
        .map((r) => r.read(returnRefunds.amount.sum()))
        .getSingle();
    return (row ?? 0.0).toDouble();
  }

  /// كل الاستردادات النقدية من بداية اليوم (للصندوق الحيّ).
  Future<double> getCashRefundsSince(DateTime from) async {
    final row = await (selectOnly(returnRefunds)
          ..addColumns([returnRefunds.amount.sum()])
          ..where(returnRefunds.refundDate.isBiggerOrEqualValue(from) &
              returnRefunds.method.equals('cash') &
              returnRefunds.isVoided.equals(false)))
        .map((r) => r.read(returnRefunds.amount.sum()))
        .getSingle();
    return (row ?? 0.0).toDouble();
  }

  /// استردادات في فترة (أي طريقة) — للتقارير.
  Future<List<ReturnRefund>> getRefundsByDateRange(DateTime from, DateTime to) =>
      (select(returnRefunds)
            ..where((t) => t.refundDate.isBetweenValues(from, to) &
                t.isVoided.equals(false))
            ..orderBy([(t) => OrderingTerm.desc(t.refundDate)]))
          .get();

  Future<ReturnRefund?> getRefundById(int id) =>
      (select(returnRefunds)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<ReturnRefund?> getActiveRefundByReference(String reference) =>
      (select(returnRefunds)
            ..where((t) => t.referenceNumber.equals(reference) &
                t.isVoided.equals(false)))
          .getSingleOrNull();

  /// إلغاء الاسترداد — soft delete بس مع تسجيل السبب (audit).
  Future<void> voidRefund(int refundId, String reason, String voidedBy) =>
      (update(returnRefunds)..where((t) => t.id.equals(refundId))).write(
        ReturnRefundsCompanion(
          isVoided: const Value(true),
          voidedAt: Value(DateTime.now()),
          voidedBy: Value(voidedBy),
          voidReason: Value(reason),
          updatedAt: Value(DateTime.now()),
        ),
      );

  Stream<List<ReturnRefund>> watchRefundsForReturn(int returnId) =>
      (select(returnRefunds)
            ..where((t) => t.returnId.equals(returnId) & t.isVoided.equals(false))
            ..orderBy([(t) => OrderingTerm.desc(t.refundDate)]))
          .watch();
}