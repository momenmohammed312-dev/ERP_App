import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/dao/staff_management_dao.dart';
import 'package:pos_offline_desktop/services/attendance/attendance_calculation_engine.dart';
import 'package:pos_offline_desktop/services/staff_management_service.dart';

/// C1 — ONE authoritative lateness path.
///
/// Locks the grace rule (late only strictly after scheduleStart + grace;
/// minutes counted FROM schedule start, grace-inclusive) and proves that
/// card == attendance-summary == payroll-input by construction (same
/// function), on timed rows, excused rows, untimed permission rows and
/// stored-only (B1) rows.
void main() {
  const startMin = 9 * 60; // 09:00
  const grace = 15;

  int late(int h, int m) => computeLateness(
        checkInTime: DateTime(2026, 9, 2, h, m),
        scheduleStartMinutes: startMin,
        graceMinutes: grace,
      );

  group('computeLateness grace boundary', () {
    test('grace-1 (09:14) → 0', () => expect(late(9, 14), 0));
    test('grace exactly (09:15) → 0 (on time)', () => expect(late(9, 15), 0));
    test('grace+1 (09:16) → 16 (counted from schedule start)', () {
      expect(late(9, 16), 16);
    });
    test('10:30 → 90 (golden STAFFL1 rule)', () => expect(late(10, 30), 90));
    test('null check-in → 0', () {
      expect(
        computeLateness(
          checkInTime: null,
          scheduleStartMinutes: startMin,
          graceMinutes: grace,
        ),
        0,
      );
    });
  });

  group('engine calculateAttendance routes through computeLateness', () {
    const sched = ScheduleConfig(
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

    test('09:16 → late, 16 min', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(() async => await db.close());
      final engine = AttendanceCalculationEngine(
        db,
        db.attendanceDeviceDao,
        db.staffManagementDao,
      );
      final r = engine.calculateAttendance(
        checkInTime: DateTime(2026, 9, 2, 9, 16),
        schedule: sched,
      );
      expect(r.status, 'late');
      expect(r.lateMinutes, 16);
    });

    test('09:10 (within grace) → present, 0 min', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(() async => await db.close());
      final engine = AttendanceCalculationEngine(
        db,
        db.attendanceDeviceDao,
        db.staffManagementDao,
      );
      final r = engine.calculateAttendance(
        checkInTime: DateTime(2026, 9, 2, 9, 10),
        schedule: sched,
      );
      expect(r.status, 'present');
      expect(r.lateMinutes, 0);
    });
  });

  group('isEffectiveLateDay predicate (matches frozen payroll counting)', () {
    bool pred({
      required String status,
      DateTime? checkIn,
      bool excused = false,
      double excusedHours = 0,
    }) =>
        isEffectiveLateDay(
          status: status,
          checkInTime: checkIn,
          scheduleStartMinutes: startMin,
          graceMinutes: grace,
          excused: excused,
          excusedHours: excusedHours,
        );

    test('untimed late-status row → false (no lateness evidence)', () {
      expect(pred(status: 'late'), isFalse);
    });
    test('fully excused timed late → false (waived)', () {
      expect(
        pred(
          status: 'late',
          checkIn: DateTime(2026, 9, 2, 10, 0),
          excused: true,
        ),
        isFalse,
      );
    });
    test('partially excused timed late → true', () {
      expect(
        pred(
          status: 'late',
          checkIn: DateTime(2026, 9, 2, 10, 0),
          excused: true,
          excusedHours: 1.0,
        ),
        isTrue,
      );
    });
    test('present past grace → true; within grace → false', () {
      expect(
        pred(status: 'present', checkIn: DateTime(2026, 9, 2, 9, 20)),
        isTrue,
      );
      expect(
        pred(status: 'present', checkIn: DateTime(2026, 9, 2, 9, 10)),
        isFalse,
      );
    });
    test('early_leave / absent / leave are never late days', () {
      final ci = DateTime(2026, 9, 2, 9, 0);
      expect(pred(status: 'early_leave', checkIn: ci), isFalse);
      expect(pred(status: 'absent'), isFalse);
      expect(pred(status: 'leave'), isFalse);
    });
  });

  group('card == attendance == payroll-input on fixture month', () {
    late AppDatabase db;
    late StaffManagementDao dao;
    late StaffManagementService svc;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      dao = StaffManagementDao(db);
      svc = StaffManagementService(dao, db);
      await _insertSettings(db);
      await dao.addStaff(
        StaffTableCompanion.insert(
          staffId: 'STAFFC1',
          name: 'C1 Staff',
          position: 'Cashier',
          employmentType: 'full_time',
          basicSalary: 9000,
          hireDate: DateTime(2026, 1, 1),
          status: 'active',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
      Future<void> row(
        int day,
        String status, {
        DateTime? ci,
        DateTime? co,
        int lateMin = 0,
        bool excused = false,
        double excusedHours = 0,
      }) =>
          dao.addAttendance(
            AttendanceTableCompanion.insert(
              staffId: 'STAFFC1',
              date: DateTime(2026, 9, day),
              status: status,
              checkInTime: ci == null ? const Value.absent() : Value(ci),
              checkOutTime: co == null ? const Value.absent() : Value(co),
              workingHours: const Value(7.0),
              overtimeHours: const Value(0),
              lateMinutes: Value(lateMin),
              excused: Value(excused),
              excusedHours: Value(excusedHours),
              source: const Value('device'),
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          );

      await row(1, 'present',
          ci: DateTime(2026, 9, 1, 9, 0), co: DateTime(2026, 9, 1, 17, 0));
      await row(2, 'late',
          ci: DateTime(2026, 9, 2, 10, 30), co: DateTime(2026, 9, 2, 17, 0));
      await row(3, 'present',
          ci: DateTime(2026, 9, 3, 9, 20), co: DateTime(2026, 9, 3, 17, 0));
      // stored-late quirk row: status late but within grace → day counts, 0 min
      await row(6, 'late',
          ci: DateTime(2026, 9, 6, 9, 10), co: DateTime(2026, 9, 6, 17, 0));
      // fully excused late → waived from late input entirely
      await row(7, 'late',
          ci: DateTime(2026, 9, 7, 10, 0),
          co: DateTime(2026, 9, 7, 17, 0),
          excused: true);
      // untimed permission-late → no late day, 1h via permission path only
      await row(8, 'late', excused: true, excusedHours: 1.0);
      // B1 stored-only row (imported, no punch times) → minutes but no day
      await row(9, 'present', lateMin: 45);
      // early checkout characterization (C4 early byte-identical proof)
      await row(10, 'present',
          ci: DateTime(2026, 9, 10, 9, 0), co: DateTime(2026, 9, 10, 16, 0));
    });

    tearDown(() async => await db.close());

    test('payroll-input late minutes == single-function fold', () async {
      final s = await svc.getAttendanceSummary(
        'STAFFC1',
        DateTime(2026, 9, 1),
        DateTime(2026, 10, 1),
      );
      // Hand-computed: 90 (Sep 2) + 20 (Sep 3, past grace) + 0 + 0.
      expect(s.totalLateMinutes, 110);

      // Same function, row by row — equality by construction.
      final rows = await dao.getAttendanceByStaff(
        'STAFFC1',
        startDate: DateTime(2026, 9, 1),
        endDate: DateTime(2026, 10, 1),
      );
      var expected = 0;
      for (final r in rows) {
        if (isEffectiveLateDay(
          status: r.status,
          checkInTime: r.checkInTime,
          scheduleStartMinutes: startMin,
          graceMinutes: grace,
          excused: r.excused,
          excusedHours: r.excusedHours,
        )) {
          expected += computeLateness(
            checkInTime: r.checkInTime,
            scheduleStartMinutes: startMin,
            graceMinutes: grace,
          );
        }
      }
      expect(s.totalLateMinutes, expected);
      expect(s.lateDays, 3); // Sep 2, Sep 3, Sep 6 (timed late-status)
      expect(s.totalLateHours, closeTo(110 / 60 + 45 / 60, 1e-9),
          reason: 'live minutes + B1 stored-only 45min');
      expect(s.totalPermissionHours, 1.0);
    });

    test('early checkout minutes flow untouched (60min for 16:00)', () async {
      final s = await svc.getAttendanceSummary(
        'STAFFC1',
        DateTime(2026, 9, 1),
        DateTime(2026, 10, 1),
      );
      expect(s.totalEarlyMinutes, 60);
    });
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
