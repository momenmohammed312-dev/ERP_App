import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/ui/staff/services/staff_payroll_statement_generator.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  test('مجاميع الوثيقة = مجموع المرتبات (أساسي/إضافات/خصومات/صافي)', () async {
    final now = DateTime.now();
    await db.into(db.payrollTable).insert(
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

    final rows = await (db.select(db.payrollTable)
          ..where((t) => t.payrollPeriod.equals('2026-10')))
        .get();

    final t = StaffPayrollStatementGenerator.computeVoucherTotals(rows);
    expect(t.basic, 9000);
    expect(t.additions, 1000); // 500 + 200 + 300
    expect(t.deductions, 1000);
    expect(t.net, 9000);
  });

  test('تجاوز 22 اسماً يحدد الحد الأقصى voucherMaxRows لضمان صفحة واحدة', () {
    expect(StaffPayrollStatementGenerator.voucherMaxRows, 22);
  });
}
