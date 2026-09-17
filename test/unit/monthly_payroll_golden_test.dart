import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/dao/staff_management_dao.dart';
import 'package:pos_offline_desktop/core/models/user_model.dart';
import 'package:pos_offline_desktop/services/staff_management_service.dart';

/// Monthly golden regression: locks the pre-weekly monthly behavior
/// (daily = basic ÷ 30, no bonus without setting, absence = ÷30).
/// Any future change that alters these numbers must fail loudly here.
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

  Future<void> addMonthlyStaff(String staffId) async {
    await staffDao.addStaff(
      StaffTableCompanion.insert(
        staffId: staffId,
        name: 'Monthly Staff',
        position: 'Cashier',
        employmentType: 'full_time',
        basicSalary: 9000,
        hireDate: DateTime.now(),
        status: 'active',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
  }

  /// All Sun–Thu workdays of Aug 2026 present 09:00→17:00, except [skipDays].
  Future<void> fillAugust(String staffId, {Set<int> skipDays = const {}}) async {
    for (var day = 1; day <= 31; day++) {
      final d = DateTime(2026, 8, day);
      // Sun..Thu only (Fri/Sat off-schedule).
      if (d.weekday == DateTime.friday || d.weekday == DateTime.saturday) {
        continue;
      }
      if (skipDays.contains(day)) continue;
      await staffDao.addAttendance(
        AttendanceTableCompanion.insert(
          staffId: staffId,
          date: DateTime(2026, 8, day),
          status: 'present',
          checkInTime: Value(DateTime(2026, 8, day, 9, 0)),
          checkOutTime: Value(DateTime(2026, 8, day, 17, 0)),
          workingHours: const Value(7.0),
          overtimeHours: const Value(0),
          source: const Value('device'),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
    }
  }

  test('full August 2026 → net = basic, no bonus', () async {
    await addMonthlyStaff('STAFFG1');
    await fillAugust('STAFFG1');

    await svc.calculatePayroll(admin, 'STAFFG1', '2026-08');

    final p = (await staffDao.getPayrollByStaff('STAFFG1')).first;
    expect(p.payrollPeriod, '2026-08');
    expect(p.basicSalary, 9000);
    expect(p.bonus, 0);
    expect(p.absentDays, 0);
    expect(p.netSalary, 9000);
    expect(p.status, 'calculated');
  });

  test('one absence → deduct basic ÷ 30', () async {
    await addMonthlyStaff('STAFFG2');
    await fillAugust('STAFFG2', skipDays: {5}); // Wed Aug 5

    await svc.calculatePayroll(admin, 'STAFFG2', '2026-08');

    final p = (await staffDao.getPayrollByStaff('STAFFG2')).first;
    expect(p.absentDays, 1);
    expect(p.netSalary, 8700, reason: '9000 - 9000/30');
  });

  test('paid monthly cannot be recalculated', () async {
    await addMonthlyStaff('STAFFG3');
    await fillAugust('STAFFG3');

    await svc.calculatePayroll(admin, 'STAFFG3', '2026-08');
    final p = (await staffDao.getPayrollByStaff('STAFFG3')).first;
    await staffDao.markPayrollPaid(
      p.id,
      paymentDate: DateTime.now(),
      paymentMethod: 'cash',
    );

    expect(() => svc.calculatePayroll(admin, 'STAFFG3', '2026-08'),
        throwsException);
  });

  test('late 90min counts from work start including grace = 1.5h', () async {
    // القاعدة المتفق عليها: التأخير من بداية الدوام (09:00) شاملاً السماح،
    // أي بصمة 10:30 = 90 دقيقة = 1.5 ساعة (وليست 75 دقيقة).
    await addMonthlyStaff('STAFFL1');
    await staffDao.addAttendance(
      AttendanceTableCompanion.insert(
        staffId: 'STAFFL1',
        date: DateTime(2026, 9, 2),
        status: 'late',
        checkInTime: Value(DateTime(2026, 9, 2, 10, 30)),
        checkOutTime: Value(DateTime(2026, 9, 2, 17, 0)),
        workingHours: const Value(5.5),
        overtimeHours: const Value(0),
        source: const Value('manual'),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    await svc.calculatePayroll(admin, 'STAFFL1', '2026-09');

    final p = (await staffDao.getPayrollByStaff('STAFFL1')).first;
    expect(p.lateHours, 1.5);
    // hourly = 9000/30/8 = 37.5 → 1.5 × 37.5 × 1.5 = 84.375
    expect(p.lateDeduction, closeTo(84.375, 0.001));
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
