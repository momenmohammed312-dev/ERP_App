import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/dao/staff_management_dao.dart';
import 'package:pos_offline_desktop/core/models/user_model.dart';
import 'package:pos_offline_desktop/services/staff_management_service.dart';

/// Advance lifecycle (locked): an advance deducts at most its unpaid
/// remainder; fully-covered advances settle and stop forever; recalcs are
/// neutral (no double counting); weekly cap carries the remainder over.
void main() {
  late AppDatabase db;
  late StaffManagementDao staffDao;
  late StaffManagementService svc;
  late User admin;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    staffDao = db.staffManagementDao;
    svc = StaffManagementService(staffDao, db);
    admin = User(
      username: 'admin',
      passwordHash: 'x',
      fullName: 'Admin',
      role: UserRole.admin,
      createdAt: DateTime.now(),
    );
    await insertDefaultAttendanceSettings(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> addWeeklyStaff(String staffId, {double salary = 3000}) async {
    await staffDao.addStaff(
      StaffTableCompanion.insert(
        staffId: staffId,
        name: 'Weekly Staff',
        position: 'Worker',
        employmentType: 'part_time',
        basicSalary: 0,
        hireDate: DateTime.now(),
        status: 'active',
        payFrequency: const Value('weekly'),
        weeklySalary: Value(salary),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<void> fillWeek(String staffId) async {
    for (var d = DateTime(2026, 8, 29);
        !d.isAfter(DateTime(2026, 9, 3));
        d = d.add(const Duration(days: 1))) {
      await staffDao.addAttendance(
        AttendanceTableCompanion.insert(
          staffId: staffId,
          date: DateTime(d.year, d.month, d.day),
          status: 'present',
          checkInTime: Value(DateTime(d.year, d.month, d.day, 9, 0)),
          checkOutTime: Value(DateTime(d.year, d.month, d.day, 17, 0)),
          workingHours: const Value(7.0),
          overtimeHours: const Value(0),
          source: const Value('device'),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
    }
  }

  Future<void> fillWeek2(String staffId) async {
    // W2 = Sat Sep 5 .. Thu Sep 10 (all filled → no date-dependent absences).
    for (var d = DateTime(2026, 9, 5);
        !d.isAfter(DateTime(2026, 9, 10));
        d = d.add(const Duration(days: 1))) {
      await staffDao.addAttendance(
        AttendanceTableCompanion.insert(
          staffId: staffId,
          date: DateTime(d.year, d.month, d.day),
          status: 'present',
          checkInTime: Value(DateTime(d.year, d.month, d.day, 9, 0)),
          checkOutTime: Value(DateTime(d.year, d.month, d.day, 17, 0)),
          workingHours: const Value(7.0),
          overtimeHours: const Value(0),
          source: const Value('device'),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
    }
  }
  Future<int> addAdvance(
    String staffId,
    double amount, {
    int? installments,
    String? deductOnPeriod,
  }) async {
    return db.into(db.staffAdvances).insert(
          StaffAdvancesCompanion.insert(
            staffId: staffId,
            amount: amount,
            requestDate: DateTime.now(),
            status: 'approved',
            installmentMonths: installments == null
                ? const Value.absent()
                : Value(installments),
            monthlyDeduction: installments == null
                ? const Value.absent()
                : Value(amount / installments),
            deductOnPeriod: deductOnPeriod == null
                ? const Value.absent()
                : Value(deductOnPeriod),
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );
  }

  Future<StaffAdvance> advanceOf(String staffId) async {
    final rows = await staffDao.getAdvancesByStaff(staffId);
    expect(rows, hasLength(1));
    return rows.first;
  }

  test('single advance settles after one full deduction', () async {
    await addWeeklyStaff('STFA1');
    await fillWeek('STFA1');
    await addAdvance('STFA1', 2000);

    await svc.calculateWeeklyPay(admin, 'STFA1', 2026, 9, 1);
    var p = (await staffDao.getPayrollByStaff('STFA1')).first;
    expect(p.advances, 2000);
    expect(p.netSalary, 1000);
    var adv = await advanceOf('STFA1');
    expect(adv.paidAmount, 2000);
    expect(adv.status, 'settled');

    // Next week: nothing deducted anymore.
    await fillWeek2('STFA1');
    await svc.calculateWeeklyPay(admin, 'STFA1', 2026, 9, 2);
    final rows = await staffDao.getPayrollByStaff('STFA1');
    expect(rows, hasLength(2));
    final w2 = rows.firstWhere((r) => r.payrollPeriod == '2026-09-W2');
    expect(w2.advances, 0);
    expect(w2.netSalary, 3000);
  });

  test('installments deduct slice per period until covered', () async {
    await addWeeklyStaff('STFA2');
    await fillWeek('STFA2');
    await addAdvance('STFA2', 4000, installments: 4);

    await svc.calculateWeeklyPay(admin, 'STFA2', 2026, 9, 1);
    expect((await advanceOf('STFA2')).paidAmount, 1000);

    await fillWeek2('STFA2');
    await svc.calculateWeeklyPay(admin, 'STFA2', 2026, 9, 2);
    final adv = await advanceOf('STFA2');
    expect(adv.paidAmount, 2000);
    expect(adv.status, 'approved', reason: 'not yet fully covered');
  });

  test('recalc of the same period is neutral (no double count)', () async {
    await addWeeklyStaff('STFA3');
    await fillWeek('STFA3');
    await addAdvance('STFA3', 4000, installments: 4);

    await svc.calculateWeeklyPay(admin, 'STFA3', 2026, 9, 1);
    await svc.calculateWeeklyPay(admin, 'STFA3', 2026, 9, 1);

    expect((await advanceOf('STFA3')).paidAmount, 1000);
    final rows = await staffDao.getPayrollByStaff('STFA3');
    expect(rows, hasLength(1));
    expect(rows.first.advances, 1000);
  });

  test('capped share carries remainder to next week', () async {
    await addWeeklyStaff('STFA4');
    await fillWeek('STFA4');
    await addAdvance('STFA4', 5000);

    await svc.calculateWeeklyPay(admin, 'STFA4', 2026, 9, 1);
    var p = (await staffDao.getPayrollByStaff('STFA4')).first;
    expect(p.advances, 3000);
    expect(p.netSalary, 0);
    expect((await advanceOf('STFA4')).status, 'approved');

    await fillWeek2('STFA4');
    await svc.calculateWeeklyPay(admin, 'STFA4', 2026, 9, 2);
    final rows = await staffDao.getPayrollByStaff('STFA4');
    final w2 = rows.firstWhere((r) => r.payrollPeriod == '2026-09-W2');
    expect(w2.advances, 2000);
    expect(w2.netSalary, 1000);
    expect((await advanceOf('STFA4')).status, 'settled');
  });

  test('monthly single advance deducts once then settles', () async {    await staffDao.addStaff(
      StaffTableCompanion.insert(
        staffId: 'STFA5',
        name: 'Monthly',
        position: 'Cashier',
        employmentType: 'full_time',
        basicSalary: 9000,
        hireDate: DateTime.now(),
        status: 'active',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
    await staffDao.addAttendance(
      AttendanceTableCompanion.insert(
        staffId: 'STFA5',
        date: DateTime(2026, 9, 3),
        status: 'present',
        checkInTime: Value(DateTime(2026, 9, 3, 9, 0)),
        checkOutTime: Value(DateTime(2026, 9, 3, 17, 0)),
        workingHours: const Value(7.0),
        overtimeHours: const Value(0),
        source: const Value('device'),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
    await addAdvance('STFA5', 1500);

    await svc.calculatePayroll(admin, 'STFA5', '2026-09');
    expect((await advanceOf('STFA5')).status, 'settled');

    await svc.calculatePayroll(admin, 'STFA5', '2026-10');
    final oct =
        (await staffDao.getPayrollByStaff('STFA5')).firstWhere(
      (r) => r.payrollPeriod == '2026-10',
    );
    expect(oct.advances, 0);
  });

  test('advance assigned to W2 skips W1, deducts W2', () async {
    await addWeeklyStaff('STFA6');
    await fillWeek('STFA6');
    await fillWeek2('STFA6');
    await addAdvance('STFA6', 1200, deductOnPeriod: '2026-09-W2');

    await svc.calculateWeeklyPay(admin, 'STFA6', 2026, 9, 1);
    var w1 = (await staffDao.getPayrollByStaff('STFA6')).first;
    expect(w1.advances, 0);
    expect(w1.netSalary, 3000);

    await svc.calculateWeeklyPay(admin, 'STFA6', 2026, 9, 2);
    final rows = await staffDao.getPayrollByStaff('STFA6');
    final w2 = rows.firstWhere((r) => r.payrollPeriod == '2026-09-W2');
    expect(w2.advances, 1200);
    expect(w2.netSalary, 1800);
    expect((await advanceOf('STFA6')).status, 'settled');
  });
}

Future<void> insertDefaultAttendanceSettings(AppDatabase appDb) async {
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
  ];
  for (final entry in settings) {
    await appDb.into(appDb.attendanceSettings).insert(
          AttendanceSettingsCompanion.insert(
            settingKey: entry.$1,
            settingValue: entry.$2,
            createdAt: now,
            updatedAt: now,
          ),
        );
  }
}
