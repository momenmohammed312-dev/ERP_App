import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/models/user_model.dart';
import 'package:pos_offline_desktop/services/attendance/attendance_deduction_calculator.dart';
import 'package:pos_offline_desktop/services/staff_management_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (MethodCall methodCall) async => '.',
      );

  User admin() => User(
        username: 'admin',
        passwordHash: 'x',
        fullName: 'Admin',
        role: UserRole.admin,
        createdAt: DateTime(2026, 1, 1),
      );

  group('Absence 1 day with multiplier 1.0 vs 1.5 vs 2.0', () {
    final monthlyStaff = Staff(
      id: 1,
      staffId: 'ST-01',
      name: 'أحمد علي',
      position: 'Cashier',
      employmentType: 'full_time',
      basicSalary: 6000.0,
      hireDate: DateTime(2026, 1, 1),
      status: 'active',
      isActive: true,
      useDefaultSchedule: true,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );

    Attendance absentRecord(int day) {
      final date = DateTime(2026, 9, day);
      return Attendance(
        id: day,
        staffId: 'ST-01',
        date: date,
        status: 'absent',
        excused: false,
        excusedHours: 0.0,
        source: 'manual',
        overtimeHours: 0.0,
        lateMinutes: 0,
        permissionHours: 0.0,
        createdAt: date,
        updatedAt: date,
      );
    }

    // Monthly basic = 6000 => day wage = 6000 / 30 = 200.0
    test('1 absent day with multiplier 1.0 deducts 1.0 day wage (200.0)', () {
      final res = computeAttendanceDeductions(
        records: [absentRecord(1)],
        staff: monthlyStaff,
        weeklyPeriod: false,
        workStartMinutes: 9 * 60,
        workEndMinutes: 17 * 60,
        graceMinutes: 15,
        absenceMultiplier: 1.0,
        absenceMode: 'day_wage',
      );

      expect(res.absentDays, 1);
      expect(res.dayWage, 200.0);
      expect(res.absenceMultiplier, 1.0);
      expect(res.absenceDeduction, closeTo(200.0, 0.001));
    });

    test('1 absent day with multiplier 1.5 deducts 1.5 day wages (300.0)', () {
      final res = computeAttendanceDeductions(
        records: [absentRecord(1)],
        staff: monthlyStaff,
        weeklyPeriod: false,
        workStartMinutes: 9 * 60,
        workEndMinutes: 17 * 60,
        graceMinutes: 15,
        absenceMultiplier: 1.5,
        absenceMode: 'day_wage',
      );

      expect(res.absentDays, 1);
      expect(res.dayWage, 200.0);
      expect(res.absenceMultiplier, 1.5);
      expect(res.absenceDeduction, closeTo(300.0, 0.001));
    });

    test('1 absent day with multiplier 2.0 deducts 2.0 day wages (400.0)', () {
      final res = computeAttendanceDeductions(
        records: [absentRecord(1)],
        staff: monthlyStaff,
        weeklyPeriod: false,
        workStartMinutes: 9 * 60,
        workEndMinutes: 17 * 60,
        graceMinutes: 15,
        absenceMultiplier: 2.0,
        absenceMode: 'day_wage',
      );

      expect(res.absentDays, 1);
      expect(res.dayWage, 200.0);
      expect(res.absenceMultiplier, 2.0);
      expect(res.absenceDeduction, closeTo(400.0, 0.001));
    });
  });

  group('Perfect attendance bonus settings and weekly logic in StaffManagementService', () {
    late AppDatabase db;
    late StaffManagementService service;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      service = StaffManagementService(db.staffManagementDao, db);

      // Default configured bonus = 250.0
      await db.into(db.attendanceSettings).insert(
            AttendanceSettingsCompanion.insert(
              settingKey: 'perfect_attendance_bonus',
              settingValue: '250',
              createdAt: DateTime(2026, 1, 1),
              updatedAt: DateTime(2026, 1, 1),
            ),
          );
    });

    tearDown(() => db.close());

    Future<void> setupSetting(String key, String value) async {
      final existing = await (db.select(db.attendanceSettings)
            ..where((s) => s.settingKey.equals(key)))
          .getSingleOrNull();
      if (existing != null) {
        await db.update(db.attendanceSettings).replace(
              existing.copyWith(settingValue: value, updatedAt: DateTime.now()),
            );
      } else {
        await db.into(db.attendanceSettings).insert(
              AttendanceSettingsCompanion.insert(
                settingKey: key,
                settingValue: value,
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              ),
            );
      }
    }

    test('bonus disabled => 0 even with perfect attendance', () async {
      await db.into(db.staffTable).insert(
            StaffTableCompanion.insert(
              staffId: 'ST-MONTHLY',
              name: 'موظف شهري',
              position: 'Cashier',
              employmentType: 'full_time',
              basicSalary: 5000,
              hireDate: DateTime(2026, 1, 1),
              status: 'active',
              createdAt: DateTime(2026, 1, 1),
              updatedAt: DateTime(2026, 1, 1),
            ),
          );

      // Add a present day
      await db.staffManagementDao.addAttendance(
        AttendanceTableCompanion.insert(
          staffId: 'ST-MONTHLY',
          date: DateTime(2026, 9, 1),
          status: 'present',
          checkInTime: Value(DateTime(2026, 9, 1, 9, 0)),
          checkOutTime: Value(DateTime(2026, 9, 1, 17, 0)),
          createdAt: DateTime(2026, 9, 1),
          updatedAt: DateTime(2026, 9, 1),
        ),
      );

      // Explicitly disable perfect attendance
      await setupSetting('perfect_attendance_enabled', 'false');

      await service.calculatePayroll(admin(), 'ST-MONTHLY', '2026-09');

      final slip = await (db.select(db.payrollTable)
            ..where((t) => t.staffId.equals('ST-MONTHLY') & t.payrollPeriod.equals('2026-09')))
          .getSingle();

      expect(slip.bonus, 0.0);
    });

    test('weekly employee + apply_weekly = false => 0 bonus', () async {
      await db.into(db.staffTable).insert(
            StaffTableCompanion.insert(
              staffId: 'ST-WEEKLY',
              name: 'موظف أسبوعي',
              position: 'Cashier',
              employmentType: 'weekly',
              basicSalary: 1000,
              hireDate: DateTime(2026, 1, 1),
              status: 'active',
              createdAt: DateTime(2026, 1, 1),
              updatedAt: DateTime(2026, 1, 1),
            ),
          );

      await db.staffManagementDao.addAttendance(
        AttendanceTableCompanion.insert(
          staffId: 'ST-WEEKLY',
          date: DateTime(2026, 9, 1),
          status: 'present',
          checkInTime: Value(DateTime(2026, 9, 1, 9, 0)),
          checkOutTime: Value(DateTime(2026, 9, 1, 17, 0)),
          createdAt: DateTime(2026, 9, 1),
          updatedAt: DateTime(2026, 9, 1),
        ),
      );

      await setupSetting('perfect_attendance_enabled', 'true');
      await setupSetting('perfect_attendance_apply_weekly', 'false');

      await service.calculatePayroll(admin(), 'ST-WEEKLY', '2026-09');

      final slip = await (db.select(db.payrollTable)
            ..where((t) => t.staffId.equals('ST-WEEKLY') & t.payrollPeriod.equals('2026-09')))
          .getSingle();

      expect(slip.bonus, 0.0);
    });

    test('weekly employee + apply_weekly = true => gets configured bonus', () async {
      await db.into(db.staffTable).insert(
            StaffTableCompanion.insert(
              staffId: 'ST-WEEKLY-BONUS',
              name: 'موظف أسبوعي يستحق بونص',
              position: 'Cashier',
              employmentType: 'weekly',
              basicSalary: 1000,
              hireDate: DateTime(2026, 1, 1),
              status: 'active',
              createdAt: DateTime(2026, 1, 1),
              updatedAt: DateTime(2026, 1, 1),
            ),
          );

      await db.staffManagementDao.addAttendance(
        AttendanceTableCompanion.insert(
          staffId: 'ST-WEEKLY-BONUS',
          date: DateTime(2026, 9, 1),
          status: 'present',
          checkInTime: Value(DateTime(2026, 9, 1, 9, 0)),
          checkOutTime: Value(DateTime(2026, 9, 1, 17, 0)),
          createdAt: DateTime(2026, 9, 1),
          updatedAt: DateTime(2026, 9, 1),
        ),
      );

      await setupSetting('perfect_attendance_enabled', 'true');
      await setupSetting('perfect_attendance_apply_weekly', 'true');

      await service.calculatePayroll(admin(), 'ST-WEEKLY-BONUS', '2026-09');

      final slip = await (db.select(db.payrollTable)
            ..where((t) => t.staffId.equals('ST-WEEKLY-BONUS') & t.payrollPeriod.equals('2026-09')))
          .getSingle();

      expect(slip.bonus, 250.0);
    });

    test('monthly employee => gets configured bonus when enabled', () async {
      await db.into(db.staffTable).insert(
            StaffTableCompanion.insert(
              staffId: 'ST-MONTHLY-BONUS',
              name: 'موظف شهري منتظم',
              position: 'Cashier',
              employmentType: 'full_time',
              basicSalary: 5000,
              hireDate: DateTime(2026, 1, 1),
              status: 'active',
              createdAt: DateTime(2026, 1, 1),
              updatedAt: DateTime(2026, 1, 1),
            ),
          );

      await db.staffManagementDao.addAttendance(
        AttendanceTableCompanion.insert(
          staffId: 'ST-MONTHLY-BONUS',
          date: DateTime(2026, 9, 1),
          status: 'present',
          checkInTime: Value(DateTime(2026, 9, 1, 9, 0)),
          checkOutTime: Value(DateTime(2026, 9, 1, 17, 0)),
          createdAt: DateTime(2026, 9, 1),
          updatedAt: DateTime(2026, 9, 1),
        ),
      );

      await setupSetting('perfect_attendance_enabled', 'true');
      // Even if apply_weekly is false, monthly still gets it
      await setupSetting('perfect_attendance_apply_weekly', 'false');

      await service.calculatePayroll(admin(), 'ST-MONTHLY-BONUS', '2026-09');

      final slip = await (db.select(db.payrollTable)
            ..where((t) => t.staffId.equals('ST-MONTHLY-BONUS') & t.payrollPeriod.equals('2026-09')))
          .getSingle();

      expect(slip.bonus, 250.0);
    });
  });

  group('Settings persistence for absence_penalty_days_multiplier', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() => db.close());

    test('save and load absence_penalty_days_multiplier in attendanceSettings', () async {
      // Initially not present -> defaults to 1.0 in UI/service
      final emptyRow = await (db.select(db.attendanceSettings)
            ..where((s) => s.settingKey.equals('absence_penalty_days_multiplier')))
          .getSingleOrNull();
      expect(emptyRow, isNull);

      // Save setting as 1.5
      await db.into(db.attendanceSettings).insert(
            AttendanceSettingsCompanion.insert(
              settingKey: 'absence_penalty_days_multiplier',
              settingValue: '1.5',
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          );

      final row1 = await (db.select(db.attendanceSettings)
            ..where((s) => s.settingKey.equals('absence_penalty_days_multiplier')))
          .getSingle();
      expect(row1.settingValue, '1.5');
      final val1 = double.tryParse(row1.settingValue) ?? 1.0;
      expect(val1, 1.5);

      // Update setting to 2.0
      await db.update(db.attendanceSettings).replace(
            row1.copyWith(
              settingValue: '2.0',
              updatedAt: DateTime.now(),
            ),
          );

      final row2 = await (db.select(db.attendanceSettings)
            ..where((s) => s.settingKey.equals('absence_penalty_days_multiplier')))
          .getSingle();
      expect(row2.settingValue, '2.0');
      final val2 = double.tryParse(row2.settingValue) ?? 1.0;
      expect(val2, 2.0);
    });
  });
}
