import 'package:drift/drift.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/tables/credit_payments_table.dart';

part 'credit_payments_dao.g.dart';

@DriftAccessor(tables: [CreditPayments])
class CreditPaymentsDao extends DatabaseAccessor<AppDatabase>
    with _$CreditPaymentsDaoMixin {
  CreditPaymentsDao(super.db);

  Future<List<CreditPayment>> getCreditPaymentsBySaleId(int saleId) {
    return (select(
      creditPayments,
    )..where((t) => t.saleId.equals(saleId))).get();
  }

  Stream<double> watchTotalCreditPayments() {
    return customSelect(
      'SELECT SUM(amount) as total FROM credit_payments',
    ).map((row) => row.readNullable<double>('total') ?? 0.0).watchSingle();
  }

  Future<double> getTotalCreditPayments() async {
    final result = await customSelect(
      'SELECT SUM(amount) as total FROM credit_payments',
    ).getSingle();
    return result.read<double>('total');
  }

  Future<void> addCreditPayment(CreditPaymentsCompanion payment) {
    return into(creditPayments).insert(payment);
  }

  Future<void> updateCreditPayment(CreditPayment payment) {
    return update(creditPayments).replace(payment);
  }

  Future<void> deleteCreditPayment(int id) {
    return (delete(creditPayments)..where((t) => t.id.equals(id))).go();
  }

  Future<List<CreditPayment>> getAllCreditPayments() {
    return (select(creditPayments)..orderBy([
          (t) =>
              OrderingTerm(expression: t.paymentDate, mode: OrderingMode.desc),
        ]))
        .get();
  }

  Stream<List<CreditPayment>> watchAllCreditPayments() {
    return (select(creditPayments)..orderBy([
          (t) =>
              OrderingTerm(expression: t.paymentDate, mode: OrderingMode.desc),
        ]))
        .watch();
  }
}
