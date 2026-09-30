import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/models/user_model.dart';
import 'package:pos_offline_desktop/services/staff_management_service.dart';

/// Reproduces the real user case (employee 2, Sep 16):
/// present row, 10:00 → 19:00, notes '[إذن - مع الخصم]', overtime 0,
/// saved via admin override. Repair must yield overtime 2.0 (19:00 past
/// 17:00 + 30 grace, measured from scheduled end) and coerce the row to
/// excused so the permission card counts it.
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

  Future<AppDatabase> seedDb() async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.into(db.staffTable).insert(
          StaffTableCompanion.insert(
            staffId: 'ST-2',
            name: 'موظف 2',
            position: 'موظف',
            employmentType: 'full_time',
            basicSalary: 1000.0,
            hireDate: DateTime(2026, 1, 1),
            status: 'active',
            createdAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 1),
          ),
        );
    final now = DateTime.now();
    for (final entry in [
      ('default_work_start', '08:00'),
      ('default_work_end', '17:00'),
      ('grace_period_minutes', '10'),
    ]) {
      await db.into(db.attendanceSettings).insert(
            AttendanceSettingsCompanion.insert(
              settingKey: entry.$1,
              settingValue: entry.$2,
              createdAt: now,
              updatedAt: now,
            ),
          );
    }
    // Stale row exactly like the user's: override source, zero overtime,
    // present status with an excuse written only in the notes.
    await db.staffManagementDao.addAttendance(
      AttendanceTableCompanion.insert(
        staffId: 'ST-2',
        date: DateTime(2026, 9, 16),
        status: 'present',
        checkInTime: Value(DateTime(2026, 9, 16, 10, 0)),
        checkOutTime: Value(DateTime(2026, 9, 16, 19, 0)),
        workingHours: const Value(9.0),
        notes: const Value('[إذن - مع الخصم]'),
        source: const Value('admin_override'),
        createdAt: DateTime(2026, 9, 16),
        updatedAt: DateTime(2026, 9, 16),
      ),
    );
    return db;
  }

  test('repair fixes overtime + coerces excuse on stale override row',
      () async {
    final db = await seedDb();
    final svc = StaffManagementService(db.staffManagementDao, db);

    final result = await svc.repairPeriodRecords(
      admin(),
      'ST-2',
      DateTime(2026, 9, 1),
      DateTime(2026, 9, 30),
    );
    expect(result.recomputed, 1);
    expect(result.excusesFixed, 1);
    expect(result.skipped, 0);

    final rows = await db.staffManagementDao.getAttendanceByStaff('ST-2');
    expect(rows.length, 1);
    final r = rows.first;
    expect(r.status, 'excused');
    expect(r.leaveType, 'other');
    expect(r.overtimeHours, closeTo(2.0, 0.001));
    expect(r.workingHours, closeTo(9.0, 0.001));

    final summary = await svc.getAttendanceSummary(
      'ST-2',
      DateTime(2026, 9, 1),
      DateTime(2026, 10, 1),
    );
    expect(summary.presentDays, 1);
    expect(summary.lateDays, 0);
    expect(summary.totalOvertime, closeTo(2.0, 0.001));
  });

  test('weekly period runs from Saturday through Thursday', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final service = StaffManagementService(db.staffManagementDao, db);

    final period = service.weekPeriodForDate(DateTime(2026, 9, 24));
    expect(period.year, 2026);
    expect(period.month, 9);
    expect(period.week, 4);

    final bounds = service.weekBoundsForDate(DateTime(2026, 9, 24));
    expect(bounds.$1, DateTime(2026, 9, 19));
    expect(bounds.$2, DateTime(2026, 9, 24, 23, 59, 59));
  });

  test('weekend days map to the correct Saturday-to-Thursday period', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final service = StaffManagementService(db.staffManagementDao, db);

    expect(
      service.weekPeriodForDate(DateTime(2026, 9, 19)),
      (year: 2026, month: 9, week: 4),
    );
    expect(
      service.weekPeriodForDate(DateTime(2026, 9, 25)),
      (year: 2026, month: 9, week: 4),
    );
    expect(
      service.weekPeriodForDate(DateTime(2026, 9, 26)),
      (year: 2026, month: 10, week: 1),
    );
  });
}
