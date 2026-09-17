import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/models/user_model.dart';
import 'package:pos_offline_desktop/services/attendance/attendance_calculation_engine.dart';
import 'package:pos_offline_desktop/services/staff_management_service.dart';

/// Bug 4:
/// (a) lateMinutes counts only minutes PAST the grace end (not from
///     schedule start).
/// (b) flat fine per late day from the `late_penalty_amount` setting flows
///     into payroll deductions; default 0 keeps old behavior identical.
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

  group('flat late fine in payroll', () {
    Future<AppDatabase> seedDb({String? penaltySetting}) async {
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
      for (final day in [2, 3]) {
        await db.staffManagementDao.addAttendance(
          AttendanceTableCompanion.insert(
            staffId: 'ST-1',
            date: DateTime(2026, 9, day),
            status: 'late',
            createdAt: DateTime(2026, 9, day),
            updatedAt: DateTime(2026, 9, day),
          ),
        );
      }
      if (penaltySetting != null) {
        await db.into(db.attendanceSettings).insert(
              AttendanceSettingsCompanion.insert(
                settingKey: 'late_penalty_amount',
                settingValue: penaltySetting,
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

    test('2 late days x 50 fine => 100 deduction', () async {
      final db = await seedDb(penaltySetting: '50');
      final p = await calculated(db);
      expect(p.lateDays, 2);
      expect(p.lateDeduction, 100.0);
      expect(p.deductions, 100.0);
      expect(p.netSalary, 8900.0);
    });

    test('no setting => zero fine, old behavior identical', () async {
      final db = await seedDb();
      final p = await calculated(db);
      expect(p.lateDays, 2);
      expect(p.lateDeduction, 0.0);
      expect(p.deductions, 0.0);
      expect(p.netSalary, 9000.0);
    });
  });
}
