import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/dao/staff_management_dao.dart';
import 'package:pos_offline_desktop/core/models/user_model.dart';
import 'package:pos_offline_desktop/services/staff_management_service.dart';

/// STEP 3 verification for Weekly Payroll (locked rules):
/// - week Sat→Thu, belongs to Thursday's month (Sep 2026: W1 = Aug29..Sep3)
/// - daily = weekly ÷ 6, no 200 bonus, advances capped with carry-over.
void main() {
  late AppDatabase db;
  late StaffManagementDao staffDao;
  late StaffManagementService svc;
  late User admin;

  User adminUser() => User(
        username: 'admin',
        passwordHash: 'x',
        fullName: 'Admin',
        role: UserRole.admin,
        createdAt: DateTime.now(),
      );

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    staffDao = db.staffManagementDao;
    svc = StaffManagementService(staffDao, db);
    admin = adminUser();
    await insertDefaultAttendanceSettings(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> addWeeklyStaff(
    String staffId, {
    double salary = 3000,
    String employmentType = 'part_time',
  }) async {
    await staffDao.addStaff(
      StaffTableCompanion.insert(
        staffId: staffId,
        name: 'Weekly Staff',
        position: 'Worker',
        employmentType: employmentType,
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

  Future<void> addPresentDay(
    String staffId,
    DateTime day, {
    int inHour = 9,
    int inMin = 0,
  }) async {
    await staffDao.addAttendance(
      AttendanceTableCompanion.insert(
        staffId: staffId,
        date: DateTime(day.year, day.month, day.day),
        status: 'present',
        checkInTime: Value(DateTime(day.year, day.month, day.day, inHour, inMin)),
        checkOutTime:
            Value(DateTime(day.year, day.month, day.day, 17, 0)),
        workingHours: const Value(7.0),
        overtimeHours: const Value(0),
        source: const Value('device'),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
  }

  test('weekBounds: Sep 2026 W1 = Sat Aug29 .. Thu Sep3', () {
    final b = svc.weekBounds(2026, 9, 1);
    expect(b.$1, DateTime(2026, 8, 29));
    expect(b.$2, DateTime(2026, 9, 3, 23, 59, 59));
  });

  test('weekBounds: Sep 2026 has no W5 (only 4 Thursdays)', () {
    expect(() => svc.weekBounds(2026, 9, 5), throwsException);
  });

  test('eligibility: monthly staff and missing salary throw', () async {
    await staffDao.addStaff(
      StaffTableCompanion.insert(
        staffId: 'STAFFM',
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
    expect(() => svc.calculateWeeklyPay(admin, 'STAFFM', 2026, 9, 1),
        throwsException);

    await staffDao.addStaff(
      StaffTableCompanion.insert(
        staffId: 'STAFFN',
        name: 'NoSalary',
        position: 'Worker',
        employmentType: 'part_time',
        basicSalary: 0,
        hireDate: DateTime.now(),
        status: 'active',
        payFrequency: const Value('weekly'),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
    expect(() => svc.calculateWeeklyPay(admin, 'STAFFN', 2026, 9, 1),
        throwsException);
  });

  test('full 6-day week → net = weekly salary, no 200 bonus', () async {
    await addWeeklyStaff('STAFFW1');
    for (var d = DateTime(2026, 8, 29);
        !d.isAfter(DateTime(2026, 9, 3));
        d = d.add(const Duration(days: 1))) {
      await addPresentDay('STAFFW1', d);
    }

    await svc.calculateWeeklyPay(admin, 'STAFFW1', 2026, 9, 1);

    final rows = await staffDao.getPayrollByStaff('STAFFW1');
    expect(rows, hasLength(1));
    final p = rows.first;
    expect(p.payrollPeriod, '2026-09-W1');
    expect(p.basicSalary, 3000);
    expect(p.bonus, 0, reason: '200 bonus must NOT apply weekly');
    expect(p.netSalary, 3000);
    expect(p.status, 'calculated');
  });

  test('one absence → deduct one daily (weekly ÷ 6)', () async {
    await addWeeklyStaff('STAFFW2');
    // Skip Wed Sep 2 (a workday) → auto-absence; Sat is off-schedule anyway.
    for (var d = DateTime(2026, 8, 29);
        !d.isAfter(DateTime(2026, 9, 3));
        d = d.add(const Duration(days: 1))) {
      if (d.day == 2) continue;
      await addPresentDay('STAFFW2', d);
    }

    await svc.calculateWeeklyPay(admin, 'STAFFW2', 2026, 9, 1);

    final p = (await staffDao.getPayrollByStaff('STAFFW2')).first;
    expect(p.absentDays, 1);
    expect(p.netSalary, 2500, reason: '3000 - 3000/6');
  });

  test('40min late from work start → lateHours × hourly × 1.5', () async {
    await addWeeklyStaff('STAFFW3');
    for (var d = DateTime(2026, 8, 29);
        !d.isAfter(DateTime(2026, 9, 3));
        d = d.add(const Duration(days: 1))) {
      if (d.day == 31) {
        await addPresentDay('STAFFW3', d, inHour: 9, inMin: 40);
      } else {
        await addPresentDay('STAFFW3', d);
      }
    }

    await svc.calculateWeeklyPay(admin, 'STAFFW3', 2026, 9, 1);

    final p = (await staffDao.getPayrollByStaff('STAFFW3')).first;
    // Locked rule: from work start including grace → 09:40 − 09:00 = 40min.
    // (40/60) × (3000/6/8) × 1.5 = 62.5
    expect(p.lateDeduction, closeTo(62.5, 0.001));
    expect(p.netSalary, closeTo(3000 - 62.5, 0.001));
  });

  test('advance bigger than net is capped, net never negative', () async {
    await addWeeklyStaff('STAFFW4');
    for (var d = DateTime(2026, 8, 29);
        !d.isAfter(DateTime(2026, 9, 3));
        d = d.add(const Duration(days: 1))) {
      await addPresentDay('STAFFW4', d);
    }
    await staffDao.addAdvance(
      StaffAdvancesCompanion.insert(
        staffId: 'STAFFW4',
        amount: 5000,
        requestDate: DateTime.now(),
        status: 'approved',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    await svc.calculateWeeklyPay(admin, 'STAFFW4', 2026, 9, 1);

    final p = (await staffDao.getPayrollByStaff('STAFFW4')).first;
    expect(p.advances, 3000);
    expect(p.netSalary, 0);
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
