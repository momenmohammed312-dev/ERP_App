import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/dao/staff_management_dao.dart';
import 'package:pos_offline_desktop/core/models/user_model.dart';
import 'package:pos_offline_desktop/services/payroll_display.dart';
import 'package:pos_offline_desktop/services/staff_management_service.dart';
import 'package:pos_offline_desktop/ui/staff/services/staff_payroll_statement_generator.dart';

/// C2 — PAYROLL FREEZE + PROOF, and C3 — BATCH PARITY.
///
/// Asserts CURRENT correct numbers on a fixture dataset (prove no mutation,
/// not new rules) and confirms the e786a8b-class guards still hold:
/// future-absence cap, excused split (late ×1.5 vs permission ×1.0),
/// paid-period immutability. No payroll formula is touched by the
/// remediation — these tests fail loudly if any number moves.
///
/// Fixture (monthly, basic 9000, divisor 30 → hourly 37.5):
/// - Sep 1,6,9,10 (2026): present 09:00→17:00, on time
/// - Sep 2: late 10:30 → 1.5h late
/// - Sep 3: checkout 19:00 → 2.0h overtime (from schedule end, past 30m grace)
/// - Sep 7: late 10:00 + partial excuse 1.0h → 1.0h late + 1.0h permission
/// - Sep 8: missing → auto-absence (1 day)
/// - advance 3000 approved (single share), penalty 200 active in window
///
/// Locked math:
/// overtimePay = 2 × 37.5 × 1.5 = 112.5
/// lateDeduction = 2.5 × 37.5 × 1.5 = 140.625
/// permissionDeduction = 1.0 × 37.5 × 1.0 = 37.5
/// absenceDeduction = 1 × 9000/30 × 1.0 = 300
/// deductions = 3000 + 200 + 140.625 + 37.5 + 300 = 3678.125
/// net = 9000 + 112.5 − 3678.125 = 5434.375
void main() {
  late AppDatabase db;
  late StaffManagementDao dao;
  late StaffManagementService svc;
  late User admin;

  Future<void> addStaff(String staffId) async {
    final now = DateTime.now();
    await dao.addStaff(
      StaffTableCompanion.insert(
        staffId: staffId,
        name: 'Lock-in $staffId',
        position: 'Cashier',
        employmentType: 'full_time',
        basicSalary: 9000,
        hireDate: DateTime(2026, 1, 1),
        status: 'active',
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  Future<void> row(
    String staffId,
    int day, {
    String status = 'present',
    DateTime? ci,
    DateTime? co,
    double ot = 0,
    bool excused = false,
    double excusedHours = 0,
  }) async {
    await dao.addAttendance(
      AttendanceTableCompanion.insert(
        staffId: staffId,
        date: DateTime(2026, 9, day),
        status: status,
        checkInTime: ci == null ? const Value.absent() : Value(ci),
        checkOutTime: co == null ? const Value.absent() : Value(co),
        workingHours: const Value(7.0),
        overtimeHours: Value(ot),
        excused: Value(excused),
        excusedHours: Value(excusedHours),
        source: const Value('device'),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<void> fillFixture(String staffId) async {
    for (final d in [1, 6, 9, 10]) {
      await row(staffId, d,
          ci: DateTime(2026, 9, d, 9, 0), co: DateTime(2026, 9, d, 17, 0));
    }
    await row(staffId, 2,
        status: 'late',
        ci: DateTime(2026, 9, 2, 10, 30),
        co: DateTime(2026, 9, 2, 17, 0));
    await row(staffId, 3,
        ci: DateTime(2026, 9, 3, 9, 0),
        co: DateTime(2026, 9, 3, 19, 0),
        ot: 2.0);
    await row(staffId, 7,
        status: 'late',
        ci: DateTime(2026, 9, 7, 10, 0),
        co: DateTime(2026, 9, 7, 17, 0),
        excused: true,
        excusedHours: 1.0);
    // Sep 8 left empty → auto-absence (future-cap allows it: Sep 2026 past).
  }

  Future<void> addAdvanceAndPenalty(String staffId) async {
    final now = DateTime.now();
    await dao.addAdvance(
      StaffAdvancesCompanion.insert(
        staffId: staffId,
        amount: 3000,
        requestDate: now,
        status: 'pending',
        createdAt: now,
        updatedAt: now,
      ),
    );
    final adv = (await dao.getAdvancesByStaff(staffId)).first;
    await svc.approveAdvance(admin, adv.id);
    // DAO approveAdvance flips pending→approved (payable, not yet paid out).
    await db.into(db.rewardsPenalties).insert(
          RewardsPenaltiesCompanion.insert(
            staffId: staffId,
            type: 'penalty',
            category: 'attendance',
            title: 'lock-in penalty',
            amount: const Value(200),
            incidentDate: DateTime(2026, 9, 4),
            issuedBy: 'Admin',
            status: 'active',
            effectiveDate: DateTime(2026, 9, 4),
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
    await _insertSettings(db);
  });

  tearDown(() async => await db.close());

  test('lock-in: full payroll numbers unchanged (C2 proof of no mutation)',
      () async {
    await addStaff('STAFFP1');
    await fillFixture('STAFFP1');
    await addAdvanceAndPenalty('STAFFP1');

    await svc.calculatePeriodPay(
      staffId: 'STAFFP1',
      payrollPeriod: '2026-09-T1',
      periodStart: DateTime(2026, 9, 1),
      periodEnd: DateTime(2026, 9, 10),
      baseSalary: 9000,
      dailyDivisor: 30,
    );

    final p = (await dao.getPayrollByStaff('STAFFP1')).single;
    expect(p.basicSalary, 9000);
    expect(p.overtimeHours, 2.0);
    expect(p.overtimePay, closeTo(112.5, 1e-9));
    expect(p.lateHours, closeTo(2.5, 1e-9));
    expect(p.lateDeduction, closeTo(140.625, 1e-9));
    expect(p.permissionHours, closeTo(1.0, 1e-9));
    expect(p.permissionDeduction, closeTo(37.5, 1e-9));
    expect(p.absentDays, 1);
    expect(p.advances, 3000);
    expect(p.penaltiesTotal, 200);
    expect(p.bonus, 0);
    expect(p.deductions, closeTo(3678.125, 1e-9));
    expect(p.netSalary, closeTo(5434.375, 1e-6));
    expect(p.status, 'calculated');
  });

  test('excused split guard: late ×1.5 vs permission ×1.0', () async {
    await addStaff('STAFFP2');
    await fillFixture('STAFFP2');
    await addAdvanceAndPenalty('STAFFP2');
    await svc.calculatePeriodPay(
      staffId: 'STAFFP2',
      payrollPeriod: '2026-09-T1',
      periodStart: DateTime(2026, 9, 1),
      periodEnd: DateTime(2026, 9, 10),
      baseSalary: 9000,
      dailyDivisor: 30,
    );
    final p = (await dao.getPayrollByStaff('STAFFP2')).single;
    const hourly = 9000 / 30 / 8; // 37.5
    expect(p.lateDeduction / p.lateHours / hourly, closeTo(1.5, 1e-9));
    expect(
      p.permissionDeduction / p.permissionHours / hourly,
      closeTo(1.0, 1e-9),
    );
  });

  test('paid-period immutability guard: paid rows cannot be recalculated',
      () async {
    await addStaff('STAFFP3');
    await fillFixture('STAFFP3');
    await svc.calculatePeriodPay(
      staffId: 'STAFFP3',
      payrollPeriod: '2026-09-T1',
      periodStart: DateTime(2026, 9, 1),
      periodEnd: DateTime(2026, 9, 10),
      baseSalary: 9000,
      dailyDivisor: 30,
    );
    final p = (await dao.getPayrollByStaff('STAFFP3')).single;
    await dao.markPayrollPaid(
      p.id,
      paymentDate: DateTime.now(),
      paymentMethod: 'cash',
    );
    expect(
      () => svc.calculatePeriodPay(
        staffId: 'STAFFP3',
        payrollPeriod: '2026-09-T1',
        periodStart: DateTime(2026, 9, 1),
        periodEnd: DateTime(2026, 9, 10),
        baseSalary: 9000,
        dailyDivisor: 30,
      ),
      throwsException,
    );
  });

  test('future-absence cap guard: no auto-absence beyond today', () async {
    await addStaff('STAFFP4');
    final now = DateTime.now();
    final period = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final start = DateTime(now.year, now.month, 1);
    final end = DateTime(now.year, now.month + 1, 0);
    await svc.calculatePeriodPay(
      staffId: 'STAFFP4',
      payrollPeriod: period,
      periodStart: start,
      periodEnd: end,
      baseSalary: 9000,
      dailyDivisor: 30,
    );
    final rows = await dao.getAttendanceByStaff(
      'STAFFP4',
      startDate: start,
      endDate: end.add(const Duration(days: 1)),
    );
    final today = DateTime(now.year, now.month, now.day);
    for (final r in rows) {
      final d = DateTime(r.date.year, r.date.month, r.date.day);
      expect(d.isAfter(today), isFalse,
          reason: 'future auto-absence leaked for $d');
    }
  });

  test('C3 parity: shared totals == single nets == service == batch txn',
      () async {
    await addStaff('STAFFB1');
    await addStaff('STAFFB2');
    await fillFixture('STAFFB1');
    await fillFixture('STAFFB2');
    await svc.calculatePeriodPay(
      staffId: 'STAFFB1',
      payrollPeriod: '2026-09-T1',
      periodStart: DateTime(2026, 9, 1),
      periodEnd: DateTime(2026, 9, 10),
      baseSalary: 9000,
      dailyDivisor: 30,
    );
    await svc.calculatePeriodPay(
      staffId: 'STAFFB2',
      payrollPeriod: '2026-09-T1',
      periodStart: DateTime(2026, 9, 1),
      periodEnd: DateTime(2026, 9, 10),
      baseSalary: 9000,
      dailyDivisor: 30,
    );
    final rows = await (db.select(
      db.payrollTable,
    )..where((t) => t.payrollPeriod.equals('2026-09-T1'))).get();
    expect(rows.length, 2);

    // Single: each stored net. Shared fold over the same rows.
    final singles = rows.map((p) => p.netSalary).toList();
    final shared = PayrollDisplay.totalsOf(rows);
    expect(shared.net, closeTo(singles[0] + singles[1], 1e-9));

    // Voucher path (kept API) delegates to the same fold.
    final voucher = StaffPayrollStatementGenerator.computeVoucherTotals(rows);
    expect(
      (voucher.basic, voucher.additions, voucher.deductions, voucher.net),
      (shared.basic, shared.additions, shared.deductions, shared.net),
    );

    // Service breakdown path uses the same fold.
    final breakdown = await svc.getDisbursementBreakdown('2026-09-T1');
    expect(breakdown.payableTotal, closeTo(shared.net, 1e-9));

    // Batch-pay transaction total obeys the same rules.
    await db.dayDao.openDay(openingBalance: 1000000);
    final paid = await svc.payPayrollsForPeriod(admin, '2026-09-T1', 'cash');
    expect(paid.total, closeTo(shared.net, 1e-9));
    expect(paid.count, 2);
  });
}

Future<void> _insertSettings(AppDatabase db) async {
  final now = DateTime.now();
  final settings = [
    ('default_work_start', '09:00'),
    ('default_work_end', '17:00'),
    ('default_work_days', 'sun,mon,tue,wed,thu'),
    ('default_weekend', 'fri'),
    ('grace_period_minutes', '15'),
    ('overtime_threshold_hours', '8'),
    ('overtime_rate_multiplier', '1.5'),
    ('break_minutes', '60'),
    ('overtime_grace_minutes', '30'),
  ];
  for (final e in settings) {
    await db.into(db.attendanceSettings).insert(
          AttendanceSettingsCompanion.insert(
            settingKey: e.$1,
            settingValue: e.$2,
            createdAt: now,
            updatedAt: now,
          ),
        );
  }
}
