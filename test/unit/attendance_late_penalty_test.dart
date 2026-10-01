import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/models/user_model.dart';
import 'package:pos_offline_desktop/services/attendance/attendance_calculation_engine.dart';
import 'package:pos_offline_desktop/services/staff_management_service.dart';

/// Late deduction, v72 approved rule:
///
///   hourly        = basicSalary / dailyDivisor / standardHoursPerDay  (/240)
///   late hours    = (checkIn - workStart) / 60
///   lateDeduction = late hours * hourly * lateMultiplier
///
/// `lateMultiplier` is resolved once through
/// AttendanceDeductionRules.resolveLateMultiplier() from the
/// `late_penalty_per_hour` setting, falling back to 1.5 when it is 0/unset, and
/// the payroll and the Employee Details display share that one value.
///
/// Grace decides only WHETHER a row counts as late: arriving inside the grace
/// window is on time. Once the row IS late the minutes are measured from the
/// shift start, so 09:20 with a 15-minute grace is 20 late minutes, not 5.
/// Excused rows never count.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (MethodCall methodCall) async => '.',
      );

  const schedule = ScheduleConfig(
    workStartHour: 9,
    workStartMinute: 0,
    workEndHour: 17,
    workEndMinute: 0,
    workDays: [0, 1, 2, 3, 4],
    weekendDay: 5,
    gracePeriodMinutes: 15,
    standardHoursPerDay: 8,
    overtimeRateMultiplier: 1.5,
  );

  AttendanceCalculationEngine engine(AppDatabase db) =>
      AttendanceCalculationEngine(
        db,
        db.attendanceDeviceDao,
        db.staffManagementDao,
      );

  User admin() => User(
        username: 'admin',
        passwordHash: 'x',
        fullName: 'Admin',
        role: UserRole.admin,
        createdAt: DateTime(2026, 1, 1),
      );

  group('grace math (display)', () {
    test('20 min over start with 15 grace => late, 5 minutes', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final r = engine(db).calculateAttendance(
        checkInTime: DateTime(2026, 9, 1, 9, 20),
        schedule: schedule,
      );
      expect(r.status, 'late');
      expect(r.lateMinutes, 5);
    });

    test('grace boundary: at grace exactly on time, +1 late by 1', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final onTime = engine(db).calculateAttendance(
        checkInTime: DateTime(2026, 9, 1, 9, 15),
        schedule: schedule,
      );
      expect(onTime.status, 'present');
      expect(onTime.lateMinutes, 0);
      final late = engine(db).calculateAttendance(
        checkInTime: DateTime(2026, 9, 1, 9, 16),
        schedule: schedule,
      );
      expect(late.status, 'late');
      expect(late.lateMinutes, 1);
    });
  });

  group('grace decides IF late, shift start decides HOW MUCH', () {
    Future<AppDatabase> seedDb({double? multiplier}) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db.into(db.staffTable).insert(
            StaffTableCompanion.insert(
              staffId: 'ST-1',
              name: 'موظف',
              position: 'Cashier',
              employmentType: 'full_time',
              basicSalary: 9000.0,
              hireDate: DateTime(2026, 1, 1),
              status: 'active',
              createdAt: DateTime(2026, 1, 1),
              updatedAt: DateTime(2026, 1, 1),
            ),
          );
      // 9:20 with a 15-minute grace. Inside the grace? No. So the row is late,
      // and the deducted minutes run from the 09:00 shift start => 20 each.
      for (final day in [2, 3]) {
        await db.staffManagementDao.addAttendance(
          AttendanceTableCompanion.insert(
            staffId: 'ST-1',
            date: DateTime(2026, 9, day),
            status: 'late',
            checkInTime: Value(DateTime(2026, 9, day, 9, 20)),
            createdAt: DateTime(2026, 9, day),
            updatedAt: DateTime(2026, 9, day),
          ),
        );
      }
      if (multiplier != null) {
        await db.into(db.attendanceSettings).insert(
              AttendanceSettingsCompanion.insert(
                settingKey: 'late_penalty_per_hour',
                settingValue: '$multiplier',
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              ),
            );
      }
      return db;
    }

    Future<Payroll> calculated(AppDatabase db) async {
      await StaffManagementService(db.staffManagementDao, db).calculatePayroll(
        admin(),
        'ST-1',
        '2026-09',
      );
      final rows = await (db.select(db.payrollTable)
            ..where((t) => t.staffId.equals('ST-1')))
          .get();
      expect(rows.length, 1);
      return rows.first;
    }

    test('9000 monthly => 37.5 hourly (9000/30/8, not /160)', () async {
      final db = await seedDb();
      final p = await calculated(db);
      expect(p.overtimeRate, closeTo(37.5, 0.001));
    });

    test('2 days x 20 shift-start minutes x 37.5 hourly x 1.5 => 37.5', () async {
      final db = await seedDb();
      final p = await calculated(db);
      expect(p.lateDays, 2);
      expect(p.lateHours, closeTo(40 / 60, 0.001));
      expect(p.lateDeduction, closeTo(37.5, 0.001));
      expect(p.deductions, closeTo(37.5, 0.001));
      expect(p.netSalary, closeTo(8962.5, 0.001));
    });

    test('late_penalty_per_hour = 2.0 applies', () async {
      final db = await seedDb(multiplier: 2.0);
      final p = await calculated(db);
      expect(p.lateDeduction, closeTo(50.0, 0.001));
      expect(p.netSalary, closeTo(8950.0, 0.001));
    });

    test('an unset setting falls back to 1.5, never to a silent zero', () async {
      final db = await seedDb();
      final p = await calculated(db);
      expect(p.lateDeduction, greaterThan(0.0));
    });

    test('excused rows never count as late', () async {
      final db = await seedDb();
      await db.staffManagementDao.addAttendance(
        AttendanceTableCompanion.insert(
          staffId: 'ST-1',
          date: DateTime(2026, 9, 4),
          status: 'excused',
          checkInTime: Value(DateTime(2026, 9, 4, 12, 0)),
          createdAt: DateTime(2026, 9, 4),
          updatedAt: DateTime(2026, 9, 4),
        ),
      );
      final p = await calculated(db);
      expect(p.lateDays, 2);
      expect(p.lateDeduction, closeTo(37.5, 0.001));
    });
  });
}
