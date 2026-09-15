import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/dao/attendance_device_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/staff_management_dao.dart';
import 'package:pos_offline_desktop/core/models/user_model.dart';
import 'package:pos_offline_desktop/services/attendance/attendance_calculation_engine.dart';
import 'package:pos_offline_desktop/services/staff_management_service.dart';

/// Lateness consistency (locked rule: from work start, grace is only a gate):
/// - engine boundary series (08:00 start, 10-min grace)
/// - partial population: timed rows (live) + timeless import rows (stored)
/// - weekly multi-day aggregation → exact deduction
/// - monthly-import override carries totalLateHours (B2)
void main() {
  late AppDatabase db;
  late StaffManagementDao staffDao;
  late AttendanceDeviceDao deviceDao;
  late StaffManagementService svc;
  late AttendanceCalculationEngine engine;
  late User admin;

  const customSchedule = ScheduleConfig(
    workStartHour: 8,
    workStartMinute: 0,
    workEndHour: 16,
    workEndMinute: 0,
    workDays: [0, 1, 2, 3, 4],
    weekendDay: 5,
    gracePeriodMinutes: 10,
    standardHoursPerDay: 8,
    overtimeRateMultiplier: 1.5,
    breakMinutes: 0,
  );

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    staffDao = db.staffManagementDao;
    deviceDao = db.attendanceDeviceDao;
    svc = StaffManagementService(staffDao, db);
    engine = AttendanceCalculationEngine(db, deviceDao, staffDao);
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

  group('engine boundary series (08:00 start, 10-min grace)', () {
    Future<int> lateAt(int h, int m) async {
      final r = engine.calculateAttendance(
        checkInTime: DateTime(2026, 9, 2, h, m),
        schedule: customSchedule,
      );
      return r.lateMinutes;
    }

    test('08:00 → 0 / present', () async {
      final r = engine.calculateAttendance(
        checkInTime: DateTime(2026, 9, 2, 8, 0),
        schedule: customSchedule,
      );
      expect(r.lateMinutes, 0);
      expect(r.status, 'present');
    });

    test('08:05 → 0 / present', () async {
      expect(await lateAt(8, 5), 0);
    });

    test('08:10 boundary → 0 / present', () async {
      final r = engine.calculateAttendance(
        checkInTime: DateTime(2026, 9, 2, 8, 10),
        schedule: customSchedule,
      );
      expect(r.lateMinutes, 0);
      expect(r.status, 'present');
    });

    test('08:11 → 11 / late', () async {
      final r = engine.calculateAttendance(
        checkInTime: DateTime(2026, 9, 2, 8, 11),
        schedule: customSchedule,
      );
      expect(r.lateMinutes, 11);
      expect(r.status, 'late');
    });

    test('08:15 → 15 / late', () async {
      expect(await lateAt(8, 15), 15);
    });

    test('08:30 → 30 / late (canonical case)', () async {
      expect(await lateAt(8, 30), 30);
    });

    test('09:00 → 60 / late', () async {
      expect(await lateAt(9, 0), 60);
    });
  });

  group('partial population (timed live + timeless stored)', () {
    test('mixed rows sum fully: 90 live + 45 stored = 2.25h', () async {
      await staffDao.addStaff(
        StaffTableCompanion.insert(
          staffId: 'STFM1',
          name: 'Mixed',
          position: 'Worker',
          employmentType: 'full_time',
          basicSalary: 9000,
          hireDate: DateTime.now(),
          status: 'active',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
      // Timed row, no stored value → live recompute (10:30 − 09:00 = 90).
      await staffDao.addAttendance(
        AttendanceTableCompanion.insert(
          staffId: 'STFM1',
          date: DateTime(2026, 9, 2),
          status: 'late',
          checkInTime: Value(DateTime(2026, 9, 2, 10, 30)),
          checkOutTime: Value(DateTime(2026, 9, 2, 17, 0)),
          workingHours: const Value(5.5),
          overtimeHours: const Value(0),
          source: const Value('device'),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
      // Timeless import row, stored 45min, no check-in → kept as-is.
      await staffDao.addAttendance(
        AttendanceTableCompanion.insert(
          staffId: 'STFM1',
          date: DateTime(2026, 9, 3),
          status: 'late',
          lateMinutes: const Value(45),
          source: const Value('import'),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      final s = await svc.getAttendanceSummary(
        'STFM1',
        DateTime(2026, 9, 1),
        DateTime(2026, 9, 30),
      );
      expect(s.totalLateMinutes, 90);
      expect(s.totalLateHours, closeTo(2.25, 0.0001));
    });
  });

  group('weekly multi-day late aggregation', () {
    test('30 + 60 min → deduction = 1.5h × hourly × 1.5 exactly', () async {
      await staffDao.addStaff(
        StaffTableCompanion.insert(
          staffId: 'STFW1',
          name: 'Weekly Late',
          position: 'Worker',
          employmentType: 'part_time',
          basicSalary: 0,
          hireDate: DateTime.now(),
          status: 'active',
          payFrequency: const Value('weekly'),
          weeklySalary: const Value(3000),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
      Future<void> day(int m, int d, int inH, int inM) =>
          staffDao.addAttendance(
            AttendanceTableCompanion.insert(
              staffId: 'STFW1',
              date: DateTime(2026, m, d),
              status: inH * 60 + inM > 915 ? 'late' : 'present',
              checkInTime: Value(DateTime(2026, m, d, inH, inM)),
              checkOutTime: Value(DateTime(2026, m, d, 17, 0)),
              workingHours: const Value(7.0),
              overtimeHours: const Value(0),
              source: const Value('device'),
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          );

      await day(8, 29, 9, 0);
      await day(8, 30, 9, 0);
      await day(8, 31, 9, 0);
      await day(9, 1, 9, 30); // +30
      await day(9, 2, 10, 0); // +60
      await day(9, 3, 9, 0);

      await svc.calculateWeeklyPay(admin, 'STFW1', 2026, 9, 1);

      final p = (await staffDao.getPayrollByStaff('STFW1')).first;
      expect(p.lateHours, closeTo(1.5, 0.0001));
      // hourly = 3000/6/8 = 62.5 → 1.5 × 62.5 × 1.5 = 140.625
      expect(p.lateDeduction, closeTo(140.625, 0.001));
    });
  });

  group('monthly-import override (B2)', () {
    test('imported lateHours flows into lateDeduction', () async {
      await staffDao.addStaff(
        StaffTableCompanion.insert(
          staffId: 'STFO1',
          name: 'Import Override',
          position: 'Cashier',
          employmentType: 'full_time',
          basicSalary: 9000,
          hireDate: DateTime.now(),
          status: 'active',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
      await db.into(db.monthlyAttendanceSummaryTable).insert(
            MonthlyAttendanceSummaryTableCompanion.insert(
              staffId: 'STFO1',
              period: '2026-09',
              lateHours: const Value(2.0),
              overtimeHours: const Value(0),
              excusedHours: const Value(0),
              absentDays: const Value(0),
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          );

      await svc.calculatePayroll(admin, 'STFO1', '2026-09');

      final p = (await staffDao.getPayrollByStaff('STFO1')).first;
      expect(p.lateHours, 2.0);
      // hourly = 9000/30/8 = 37.5 → 2.0 × 37.5 × 1.5 = 112.5
      expect(p.lateDeduction, closeTo(112.5, 0.001));
    });
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
