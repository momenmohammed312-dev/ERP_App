import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/dao/staff_management_dao.dart';
import 'package:pos_offline_desktop/core/models/user_model.dart';
import 'package:pos_offline_desktop/services/staff_management_service.dart';
import 'package:pos_offline_desktop/ui/staff/services/staff_payroll_statement_generator.dart';

/// اعتماد وصرف مستند فترة:
/// - اعتماد الكل، صرف المستحق بقيد إجمالي واحد، منع اليوم المغلق،
/// - تخطي المدفوع، استبعاد المنتهية خدمتهم، رقم مستند متسلسل
void main() {
  late AppDatabase db;
  late StaffManagementDao dao;
  late StaffManagementService svc;
  late User admin;

  Future<void> addStaff(String staffId, {String status = 'active'}) async {
    final now = DateTime.now();
    await dao.addStaff(
      StaffTableCompanion.insert(
        staffId: staffId,
        name: 'موظف $staffId',
        position: 'Cashier',
        employmentType: 'full_time',
        basicSalary: 9000,
        hireDate: now,
        status: status,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  Future<void> addPayroll(
    String staffId,
    double net, {
    String status = 'calculated',
  }) async {
    final now = DateTime.now();
    await db
        .into(db.payrollTable)
        .insert(
          PayrollTableCompanion.insert(
            staffId: staffId,
            payrollPeriod: '2026-09',
            periodStart: DateTime(2026, 9, 1),
            periodEnd: DateTime(2026, 9, 30),
            basicSalary: 9000,
            netSalary: net,
            status: status,
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    dao = StaffManagementDao(db);
    svc = StaffManagementService(dao, db);
    admin = User(
      username: 'admin',
      passwordHash: 'x',
      fullName: 'Admin',
      role: UserRole.admin,
      createdAt: DateTime.now(),
    );
    await addStaff('STAFF0001');
    await addStaff('STAFF0002');
    await addStaff('STAFF0003', status: 'terminated');
    await addPayroll('STAFF0001', 8000);
    await addPayroll('STAFF0002', 7000);
    await addPayroll('STAFF0003', 5000);
  });
  tearDown(() async => await db.close());

  test('التفصيل: مستحق/مدفوع/مستبعد', () async {
    final b = await svc.getDisbursementBreakdown('2026-09');
    expect(b.payableCount, 2);
    expect(b.payableTotal, 15000);
    expect(b.excludedCount, 1);
    expect(b.excludedTotal, 5000);
    expect(b.paidCount, 0);
    expect(b.voucherNo, 'PAY-2026-09-1');
  });

  test('اعتماد الكل يعتمد المستحق فقط (يستثني المنتهي)', () async {
    final n = await svc.approvePayrollsForPeriod(admin, '2026-09');
    expect(n, 2);
    final rows = await (db.select(
      db.payrollTable,
    )..where((t) => t.payrollPeriod.equals('2026-09'))).get();
    final terminated = rows.firstWhere((p) => p.staffId == 'STAFF0003');
    expect(terminated.status, 'calculated');
  });

  test('الصرف بقيد إجمالي واحد + ربط المرتبات + رقم مستند', () async {
    await db.dayDao.openDay(openingBalance: 100000);
    final result = await svc.payPayrollsForPeriod(admin, '2026-09', 'cash');
    expect(result.count, 2);
    expect(result.total, 15000);
    expect(result.voucherNo, 'PAY-2026-09-1');

    final rows = await (db.select(
      db.payrollTable,
    )..where((t) => t.payrollPeriod.equals('2026-09'))).get();
    final paid = rows.where((p) => p.status == 'paid').toList();
    expect(paid.length, 2);
    final refIds = paid.map((p) => p.expenseRefId).toSet();
    expect(refIds.length, 1, reason: 'قيد إجمالي واحد لكل المرتبات');

    final expenses = await db.select(db.expenses).get();
    expect(expenses.length, 1);
    expect(expenses.first.amount, 15000);
    expect(expenses.first.category, 'salaries');
    expect(expenses.first.description, contains('PAY-2026-09-1'));
    expect(paid.map((p) => p.expenseRefId).toSet(), {
      expenses.first.id,
    }, reason: 'ربط حقيقي بصف المصرف');
  });

  test('الصرف الثاني يأخذ الرقم التالي', () async {
    await db.dayDao.openDay(openingBalance: 100000);
    await svc.payPayrollsForPeriod(admin, '2026-09', 'cash');
    final again = await svc.payPayrollsForPeriod(admin, '2026-09', 'cash');
    expect(again.count, 0);
    expect(again.voucherNo, 'PAY-2026-09-2');
  });

  test('الصرف يعتمد المحسوب تلقائياً', () async {
    await db.dayDao.openDay(openingBalance: 100000);
    final result = await svc.payPayrollsForPeriod(admin, '2026-09', 'cash');
    expect(result.count, 2);
  });

  test('اليوم المغلق يمنع الصرف', () async {
    expect(
      () => svc.payPayrollsForPeriod(admin, '2026-09', 'cash'),
      throwsException,
    );
  });

  test('المدفوع مسبقاً يُتخطى ولا يُصرف مرتين', () async {
    await db.dayDao.openDay(openingBalance: 100000);
    await svc.payPayrollsForPeriod(admin, '2026-09', 'cash');
    final again = await svc.payPayrollsForPeriod(admin, '2026-09', 'cash');
    expect(again.count, 0);
    expect(again.total, 0.0);
    final expenses = await db.select(db.expenses).get();
    expect(expenses.length, 1, reason: 'لا قيد جديد للصرف الثاني');
  });

  test('التحديد بالشيك بوكس يقتصر عليه التفصيل والصرف', () async {
    await db.dayDao.openDay(openingBalance: 100000);
    final first = await (db.select(
      db.payrollTable,
    )..where((t) => t.staffId.equals('STAFF0001'))).getSingle();
    final b = await svc.getDisbursementBreakdown(
      '2026-09',
      onlyIds: {first.id},
    );
    expect(b.payableCount, 1);
    expect(b.payableTotal, 8000);

    final result = await svc.payPayrollsForPeriod(
      admin,
      '2026-09',
      'cash',
      onlyIds: {first.id},
    );
    expect(result.count, 1);
    expect(result.total, 8000);
    final rows = await (db.select(
      db.payrollTable,
    )..where((t) => t.payrollPeriod.equals('2026-09'))).get();
    expect(rows.firstWhere((p) => p.staffId == 'STAFF0001').status, 'paid');
    expect(
      rows.firstWhere((p) => p.staffId == 'STAFF0002').status,
      'calculated',
    );
  });

  test('مجاميع الوثيقة = مجموع المرتبات (أساسي/إضافات/خصومات/صافي)', () async {
    final now = DateTime.now();
    await db
        .into(db.payrollTable)
        .insert(
          PayrollTableCompanion.insert(
            staffId: 'STAFF0001',
            payrollPeriod: '2026-10',
            periodStart: DateTime(2026, 10, 1),
            periodEnd: DateTime(2026, 10, 31),
            basicSalary: 9000,
            overtimePay: const Value(500),
            bonus: const Value(200),
            allowances: const Value(300),
            deductions: const Value(1000),
            netSalary: 9000,
            status: 'calculated',
            createdAt: now,
            updatedAt: now,
          ),
        );
    final rows = await (db.select(
      db.payrollTable,
    )..where((t) => t.payrollPeriod.equals('2026-10'))).get();
    final t = StaffPayrollStatementGenerator.computeVoucherTotals(rows);
    expect(t.basic, 9000);
    expect(t.additions, 1000);
    expect(t.deductions, 1000);
    expect(t.net, 9000);
  });

  test('بعد الصرف: التفصيل يعرض الكل مدفوعاً', () async {
    await db.dayDao.openDay(openingBalance: 100000);
    await svc.payPayrollsForPeriod(admin, '2026-09', 'cash');
    final b = await svc.getDisbursementBreakdown('2026-09');
    expect(b.payableCount, 0);
    expect(b.paidCount, 2);
    expect(b.paidTotal, 15000);
    expect(b.excludedCount, 1);
  });
}
