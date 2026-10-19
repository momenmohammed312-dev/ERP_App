import 'package:drift/drift.dart';
import '../../../services/license_entitlement.dart';
import '../app_database.dart';
import '../tables/cash_custody_tables.dart';

part 'custody_dao.g.dart';

@DriftAccessor(tables: [CashCustodies, CustodyExpenses])
class CustodyDao extends DatabaseAccessor<AppDatabase> with _$CustodyDaoMixin {
  CustodyDao(super.db);

  /// جلب جميع العهد مرتبة من الأحدث إلى الأقدم
  Future<List<CashCustody>> getAllCustodies() {
    return (select(
      cashCustodies,
    )..orderBy([(t) => OrderingTerm.desc(t.date)])).get();
  }

  /// بث مباشر لجميع العهد
  Stream<List<CashCustody>> watchAllCustodies() {
    return (select(
      cashCustodies,
    )..orderBy([(t) => OrderingTerm.desc(t.date)])).watch();
  }

  /// جلب عهدة بواسطة المعرف
  Future<CashCustody?> getCustodyById(int id) {
    return (select(
      cashCustodies,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  /// جلب العهد المفتوحة فقط
  Future<List<CashCustody>> getOpenCustodies() {
    return (select(cashCustodies)
          ..where((t) => t.status.equals('open'))
          ..orderBy([(t) => OrderingTerm.desc(t.date)]))
        .get();
  }

  /// BUG-017 — entitlement guard. Denied before the statement runs, so a
  /// refusal never leaves a half-written row behind. `grants()` is an
  /// in-memory read, so nothing holds a transaction open here.
  static void _requireLicense(String operation) =>
      LicenseEntitlement.instance.require('custody', operation: operation);

  /// إدخال عهدة جديدة
  Future<int> insertCustody(CashCustodiesCompanion custody) {
    _requireLicense('فتح عهدة');
    return into(cashCustodies).insert(custody);
  }

  /// تحديث بيانات العهدة
  Future<int> updateCustody(int id, CashCustodiesCompanion custody) {
    _requireLicense('تعديل عهدة');
    return (update(
      cashCustodies,
    )..where((t) => t.id.equals(id))).write(custody);
  }

  /// جلب مصروفات عهدة محددة
  Future<List<CustodyExpense>> getExpensesByCustody(int custodyId) {
    return (select(custodyExpenses)
          ..where((t) => t.custodyId.equals(custodyId))
          ..orderBy([(t) => OrderingTerm.desc(t.date)]))
        .get();
  }

  /// بث مباشر لمصروفات عهدة معينة
  Stream<List<CustodyExpense>> watchExpensesByCustody(int custodyId) {
    return (select(custodyExpenses)
          ..where((t) => t.custodyId.equals(custodyId))
          ..orderBy([(t) => OrderingTerm.desc(t.date)]))
        .watch();
  }

  /// إضافة مصروف على عهدة
  Future<int> insertExpense(CustodyExpensesCompanion expense) {
    _requireLicense('تسجيل مصروف عهدة');
    return into(custodyExpenses).insert(expense);
  }

  /// حذف مصروف من عهدة
  Future<int> deleteExpense(int expenseId) {
    _requireLicense('حذف مصروف عهدة');
    return (delete(custodyExpenses)..where((t) => t.id.equals(expenseId))).go();
  }

  /// جلب مصروف محدد
  Future<CustodyExpense?> getExpenseById(int expenseId) {
    return (select(
      custodyExpenses,
    )..where((t) => t.id.equals(expenseId))).getSingleOrNull();
  }

  /// حساب إجمالي المصروفات لعهدة معينة
  Future<double> calculateTotalExpenses(int custodyId) async {
    final query = selectOnly(custodyExpenses)
      ..addColumns([custodyExpenses.amount.sum()])
      ..where(custodyExpenses.custodyId.equals(custodyId));
    final result = await query.getSingle();
    return result.read(custodyExpenses.amount.sum()) ?? 0.0;
  }

  /// معرف العهدة التالي لتكوين رقم العهدة
  Future<int> getNextCustodyId() async {
    final query = selectOnly(cashCustodies)
      ..addColumns([cashCustodies.id.max()]);
    final result = await query.getSingle();
    final maxId = result.read(cashCustodies.id.max());
    return (maxId ?? 0) + 1;
  }
}
