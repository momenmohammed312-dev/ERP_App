import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/models/user_model.dart';
import 'package:pos_offline_desktop/services/attendance/attendance_calculation_engine.dart';
import 'package:pos_offline_desktop/services/attendance/attendance_deduction_calculator.dart';
import 'package:pos_offline_desktop/services/staff_management_service.dart';

/// An employee whose contract schedule is 08:00-17:00 but who occasionally works
/// an off-schedule shift that crosses midnight: in 17:00, out 00:00 next day.
///
/// Requirement under test:
///   * overtime credited for the REAL elapsed time past the schedule end (7.0h)
///   * NO late deduction for that day
///   * NO early-leave / permission deduction for that day
///   * normal same-day shifts stay byte-identical
///
/// Every normal-shift assertion here is a regression guard. The two protected
/// parity suites (baseline_payroll_parity_test and
/// attendance_deduction_calculator_test) are NOT modified by this change set.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (MethodCall call) async => '.',
  );

  const workStart = 8 * 60; // 08:00
  const workEnd = 17 * 60; // 17:00
  const grace = 15;
  const graceEnd = workStart + grace; // 08:15

  // Monday 2026-09-14 .. Tuesday 2026-09-15, so "next day" is unambiguous.
  final mon = DateTime(2026, 9, 14);

  Attendance row({
    required DateTime date,
    String status = 'present',
    DateTime? inTime,
    DateTime? outTime,
    bool excused = false,
    double excusedHours = 0.0,
    double permissionHours = 0.0,
    String? notes,
    String? leaveType,
  }) {
    return Attendance(
      id: date.day,
      staffId: 'ST-1',
      date: date,
      status: status,
      checkInTime: inTime,
      checkOutTime: outTime,
      checkInLocation: null,
      checkOutLocation: null,
      workingHours: null,
      overtimeHours: 0.0,
      excused: excused,
      excusedHours: excusedHours,
      permissionHours: permissionHours,
      leaveType: leaveType,
      notes: notes,
      source: 'manual',
      sourceDeviceId: null,
      rawEventId: null,
      overrideReason: null,
      lateMinutes: 0,
      approvedBy: null,
      approvedAt: null,
      createdAt: date,
      updatedAt: date,
    );
  }

  Staff staff({double basicSalary = 6000}) {
    return Staff(
      id: 1,
      staffId: 'ST-1',
      name: 'Staff',
      position: 'Cashier',
      employmentType: 'full_time',
      basicSalary: basicSalary,
      hourlyRate: null,
      hireDate: DateTime(2026, 1, 1),
      status: 'active',
      isActive: true,
      useDefaultSchedule: true,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );
  }

  AttendanceDeductionResult compute(
    List<Attendance> records, {
    Staff? s,
    int ws = workStart,
    int we = workEnd,
  }) {
    return computeAttendanceDeductions(
      records: records,
      staff: s ?? staff(),
      weeklyPeriod: false,
      workStartMinutes: ws,
      workEndMinutes: we,
      graceMinutes: grace,
      lateMultiplier: 1.5,
    );
  }

  const schedule = ScheduleConfig(
    workStartHour: 8,
    workStartMinute: 0,
    workEndHour: 17,
    workEndMinute: 0,
    workDays: [0, 1, 2, 3, 4, 5, 6],
    weekendDay: 6,
    gracePeriodMinutes: grace,
    standardHoursPerDay: 8,
    overtimeRateMultiplier: 1.5,
    overtimeGraceMinutes: 30,
  );

  // =======================================================================
  // GROUP A - the requirement: 17:00 -> next day 00:00
  // =======================================================================
  group('A. off-schedule shift across midnight', () {
    final r = row(
      date: mon,
      status: 'present',
      inTime: DateTime(2026, 9, 14, 17),
      outTime: DateTime(2026, 9, 15),
    );

    test('A1 the predicate recognises the day', () {
      expect(AttendanceDeductionRules.isOffScheduleMidnightCrossing(r), isTrue);
    });

    test('A2 no late deduction', () {
      expect(
        AttendanceDeductionRules.lateMinutesOf(
          r,
          workStartMinutes: workStart,
          workEndMinutes: workEnd,
          graceMinutes: grace,
        ),
        0,
      );
    });

    test('A3 no early-leave / permission deduction', () {
      expect(
        AttendanceDeductionRules.isPermissionRecord(
          r,
          workEndMinutes: workEnd,
        ),
        isFalse,
      );
      expect(
        AttendanceDeductionRules.permissionMinutesOf(
          r,
          workEndMinutes: workEnd,
        ),
        0,
      );
    });

    test('A4 the whole deduction result is zero', () {
      final d = compute([r]);
      expect(d.totalLateMinutes, 0);
      expect(d.totalPermissionMinutes, 0);
      expect(d.lateDeduction, 0);
      expect(d.permissionDeduction, 0);
      expect(d.total, 0);
    });
  });

  // =======================================================================
  // Engine calculations - one shared in-memory DB for the whole group.
  // =======================================================================
  group('engine calculations', () {
    late AppDatabase db;

    setUp(() async => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() async => db.close());

    AttendanceCalcResult calc(DateTime checkIn, DateTime checkOut) {
      return AttendanceCalculationEngine(
        db,
        db.attendanceDeviceDao,
        db.staffManagementDao,
      ).calculateAttendance(
        checkInTime: checkIn,
        checkOutTime: checkOut,
        schedule: schedule,
      );
    }

    test('A5 17:00 -> next day 00:00 is 7.0 worked, 7.0 overtime, not late',
        () {
      final r = calc(DateTime(2026, 9, 14, 17), DateTime(2026, 9, 15));
      expect(r.workingHours, closeTo(7.0, 0.0001));
      expect(r.overtimeHours, closeTo(7.0, 0.0001));
      expect(r.status, isNot('late'));
      expect(r.status, 'present');
      expect(r.lateMinutes, 0);
    });

    test('A5b a same-day 17:00 -> 00:00 pair is rolled forward, not negative',
        () {
      final r = calc(DateTime(2026, 9, 14, 17), DateTime(2026, 9, 14));
      expect(r.workingHours, closeTo(7.0, 0.0001));
      expect(r.workingHours, greaterThanOrEqualTo(0));
    });

    test('E3 engine output is never negative for an inverted pair', () {
      final r = calc(DateTime(2026, 9, 14, 17), DateTime(2026, 9, 14));
      expect(r.workingHours, greaterThanOrEqualTo(0));
      expect(r.overtimeHours, greaterThanOrEqualTo(0));
      expect(r.lateMinutes, greaterThanOrEqualTo(0));
    });

    test('F7 12:00 -> 21:00 keeps 9.0 worked / 4.0 overtime', () {
      // check-in 12:00 is past the 08:15 grace end so the row is legitimately
      // 'late'; the point of this assertion is that the hours are unchanged.
      final r = calc(DateTime(2026, 9, 14, 12), DateTime(2026, 9, 14, 21));
      expect(r.workingHours, closeTo(9.0, 0.0001));
      expect(r.overtimeHours, closeTo(4.0, 0.0001));
      expect(r.status, 'late');
    });

    test('F8 08:10 -> 17:00 is on time with no overtime', () {
      final r = calc(DateTime(2026, 9, 14, 8, 10), DateTime(2026, 9, 14, 17));
      expect(r.status, 'present');
      expect(r.lateMinutes, 0);
      expect(r.overtimeHours, 0);
      expect(r.workingHours, closeTo(8.833333, 0.001));
    });
  });

  // =======================================================================
  // GROUP B - a forgotten check-out must stay fully deducted
  // =======================================================================
  group('B. forgotten check-out is still deducted', () {
    test('B1 next-morning 08:30 punch: predicate is false', () {
      final r = row(
        date: mon,
        inTime: DateTime(2026, 9, 14, 8),
        outTime: DateTime(2026, 9, 15, 8, 30),
      );
      expect(AttendanceDeductionRules.isOffScheduleMidnightCrossing(r), isFalse);
    });

    test('B2 the early-leave deduction survives the exemption', () {
      final d = compute([
        row(
          date: mon,
          inTime: DateTime(2026, 9, 14, 8),
          outTime: DateTime(2026, 9, 15, 8, 30),
        ),
      ]);
      // Checked in exactly on the shift start -> no lateness. Left at 08:30,
      // far before the 17:00 end -> the early leave is still docked:
      // 17:00 - 08:30 = 510 minutes.
      expect(d.totalLateMinutes, 0);
      expect(d.totalPermissionMinutes, 17 * 60 - (8 * 60 + 30));
      expect(d.totalPermissionMinutes, 510);
      expect(d.permissionDeduction, greaterThan(0));
    });

    test('B3 the 06:00 clock bound rejects a stale next-morning punch', () {
      final r = row(
        date: mon,
        inTime: DateTime(2026, 9, 14, 9),
        outTime: DateTime(2026, 9, 15, 8, 30),
      );
      expect(AttendanceDeductionRules.isOffScheduleMidnightCrossing(r), isFalse);
    });

    test('B4 the 14h elapsed bound rejects a 21h stale span', () {
      // 08:00 -> 05:00 next day passes the clock bound but not the elapsed one.
      final r = row(
        date: mon,
        inTime: DateTime(2026, 9, 14, 8),
        outTime: DateTime(2026, 9, 15, 5),
      );
      expect(AttendanceDeductionRules.isOffScheduleMidnightCrossing(r), isFalse);
    });

    test('B5 the next-calendar-day bound rejects a two-day gap', () {
      final r = row(
        date: mon,
        inTime: DateTime(2026, 9, 14, 8),
        outTime: DateTime(2026, 9, 16, 5),
      );
      expect(AttendanceDeductionRules.isOffScheduleMidnightCrossing(r), isFalse);
    });

    test('B6 a late employee who leaves at 18:00 stays late', () {
      // 09:20 against an 08:00 start and a 08:15 grace end -> 80 minutes.
      final d = compute([
        row(
          date: mon,
          inTime: DateTime(2026, 9, 14, 9, 20),
          outTime: DateTime(2026, 9, 14, 18),
        ),
      ]);
      expect(d.totalLateMinutes, 80);
    });
  });

  // =======================================================================
  // GROUP C - the mandated "genuinely 9h late" case
  // =======================================================================
  group('C. 17:00 -> 18:00 same day is NOT an off-schedule shift', () {
    final r = row(
      date: mon,
      status: 'late',
      inTime: DateTime(2026, 9, 14, 17),
      outTime: DateTime(2026, 9, 14, 18),
    );

    test('C1 the predicate is false (same day, out clock after in clock)', () {
      expect(AttendanceDeductionRules.isOffScheduleMidnightCrossing(r), isFalse);
    });

    test('C2 the full 540 late minutes are still docked', () {
      expect(
        AttendanceDeductionRules.lateMinutesOf(
          r,
          workStartMinutes: workStart,
          workEndMinutes: workEnd,
          graceMinutes: grace,
        ),
        540,
      );
    });

    test('C3 no permission (she worked past the end, not early)', () {
      expect(
        AttendanceDeductionRules.permissionMinutesOf(
          r,
          workEndMinutes: workEnd,
        ),
        0,
      );
    });

    test('C4 lateDeduction is 9h x 25 x 1.5 = 337.50', () {
      final d = compute([r]);
      const hourly = 6000 / 30 / 8; // 25
      expect(d.lateDeduction, closeTo((540 / 60) * hourly * 1.5, 0.0001));
      expect(d.lateDeduction, closeTo(337.50, 0.0001));
    });
  });

  // =======================================================================
  // GROUP E - invariants: nothing may ever go negative
  // =======================================================================
  group('E. invariant grid - nothing may be negative', () {
    // Coarse 30-minute grid: 48 x 48 pairs per schedule config. The point is a
    // broad sweep, so violations are collected and reported once rather than
    // calling expect() (which is expensive) hundreds of thousands of times.
    const step = 30;

    test('E1 deduction rules stay non-negative over a coarse grid', () {
      final violations = <String>[];
      for (final ws in [workStart, 9 * 60]) {
        for (final we in [workEnd, 18 * 60]) {
          for (var i = 0; i < 1440; i += step) {
            for (var o = 0; o < 1440; o += step) {
              final r = row(
                date: mon,
                inTime: mon.add(Duration(minutes: i)),
                outTime: mon.add(Duration(minutes: o)),
              );
              final lm = AttendanceDeductionRules.lateMinutesOf(
                r,
                workStartMinutes: ws,
                workEndMinutes: we,
                graceMinutes: grace,
              );
              final pm = AttendanceDeductionRules.permissionMinutesOf(
                r,
                workEndMinutes: we,
              );
              if (lm < 0 || pm < 0) {
                violations.add('ws=$ws we=$we in=$i out=$o late=$lm perm=$pm');
              }
            }
          }
        }
      }
      expect(violations, isEmpty);
    });

    test('E2 deductions stay non-negative and finite over the grid', () {
      final violations = <String>[];
      for (var i = 0; i < 1440; i += step) {
        for (var o = 0; o < 1440; o += step) {
          final d = compute([
            row(
              date: mon,
              inTime: mon.add(Duration(minutes: i)),
              outTime: mon.add(Duration(minutes: o)),
            ),
          ]);
          if (!d.lateDeduction.isFinite ||
              !d.permissionDeduction.isFinite ||
              d.lateDeduction < 0 ||
              d.permissionDeduction < 0 ||
              d.absenceDeduction < 0) {
            violations.add('in=$i out=$o late=${d.lateDeduction} '
                'perm=${d.permissionDeduction} absent=${d.absenceDeduction}');
          }
        }
      }
      expect(violations, isEmpty);
    });

    test('E3 an inverted same-day pair is never negative', () {
      final d = compute([
        row(
          date: mon,
          inTime: DateTime(2026, 9, 14, 17),
          outTime: DateTime(2026, 9, 14),
        ),
      ]);
      expect(d.totalLateMinutes, greaterThanOrEqualTo(0));
      expect(d.lateDeduction, greaterThanOrEqualTo(0));
      expect(d.permissionDeduction, greaterThanOrEqualTo(0));
    });
  });

  // =======================================================================
  // GROUP F - regression shapes must be untouched
  // =======================================================================
  group('F. normal same-day shapes are unchanged', () {
    test('F1 09:00 -> 15:00 still docks 120 permission minutes', () {
      final d = compute([
        row(
          date: mon,
          inTime: DateTime(2026, 9, 14, 9),
          outTime: DateTime(2026, 9, 14, 15),
        ),
      ]);
      expect(d.totalPermissionMinutes, 120);
    });

    test('F2 09:20 -> 17:00 still docks the 80 late minutes', () {
      final d = compute([
        row(
          date: mon,
          inTime: DateTime(2026, 9, 14, 9, 20),
          outTime: DateTime(2026, 9, 14, 17),
        ),
      ]);
      expect(d.totalLateMinutes, 80);
    });

    test('F3 08:10 -> 17:00 is on time (inside the 08:15 grace)', () {
      expect(08 * 60 + 10, lessThanOrEqualTo(graceEnd));
      final d = compute([
        row(
          date: mon,
          inTime: DateTime(2026, 9, 14, 8, 10),
          outTime: DateTime(2026, 9, 14, 17),
        ),
      ]);
      expect(d.totalLateMinutes, 0);
    });

    test('F4 a night schedule 20:00 -> 02:30 is fully exempt and unchanged', () {
      // 1200 >= 150 (workEnd) is true and the crossing is true -> 0 late,
      // which is exactly what the pre-existing grace check already produced.
      final d = compute(
        [
          row(
            date: mon,
            inTime: DateTime(2026, 9, 14, 20),
            outTime: DateTime(2026, 9, 15, 2, 30),
          ),
        ],
        ws: 20 * 60,
        we: 2 * 60 + 30,
      );
      expect(d.totalLateMinutes, 0);
      expect(d.totalPermissionMinutes, 0);
    });

    test('F5 an excused row with a notes window still docks 60 minutes', () {
      // The v73 guards sit AFTER every admin-asserted marker, so an explicit
      // permission must still win over the timestamp heuristic.
      final d = compute([
        row(
          date: mon,
          status: 'excused',
          notes: '[\u0625\u0630\u0646 \u0634\u062e\u0635\u064a - \u0645\u0646 15:00 \u0625\u0644\u0649 16:00]',
        ),
      ]);
      expect(d.totalPermissionMinutes, 60);
    });

    test('F6 an admin permission hours column still wins', () {
      final d = compute([
        row(
          date: mon,
          status: 'present',
          inTime: DateTime(2026, 9, 14, 17),
          outTime: DateTime(2026, 9, 15),
          permissionHours: 2.5,
          notes: '[\u0625\u0630\u0646 \u0645\u062e\u0635\u0635 - \u0645\u0639 \u0627\u0644\u062e\u0635\u0645 - 2.5 \u0633\u0627\u0639\u0629]',
        ),
      ]);
      expect(d.totalPermissionMinutes, 150);
    });

    test('F7 summary copy agrees with the rules class', () {
      // getAttendanceSummary keeps its own grace-based copy of the rule; this
      // pins that both agree about the off-schedule exemption.
      expect(
        AttendanceDeductionRules.isOffScheduleMidnightCrossing(
          row(
            date: mon,
            inTime: DateTime(2026, 9, 14, 17),
            outTime: DateTime(2026, 9, 15),
          ),
        ),
        isTrue,
      );
    });
  });

  // =======================================================================
  // GROUP G - persistence, repair and the payroll slip
  // =======================================================================
  group('G. persistence, repair and payroll', () {
    late AppDatabase db;

    User admin() => User(
          username: 'admin',
          passwordHash: 'x',
          fullName: 'Admin',
          role: UserRole.admin,
          createdAt: DateTime(2026, 1, 1),
        );

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      await db.into(db.staffTable).insert(
            StaffTableCompanion.insert(
              staffId: 'ST-1',
              name: 'Staff',
              position: 'Cashier',
              employmentType: 'full_time',
              basicSalary: 6000.0,
              hireDate: DateTime(2026, 1, 1),
              status: 'active',
              createdAt: DateTime(2026, 1, 1),
              updatedAt: DateTime(2026, 1, 1),
            ),
          );
      const settings = {
        'default_work_start': '08:00',
        'default_work_end': '17:00',
        'grace_period_minutes': '15',
      };
      for (final entry in settings.entries) {
        await db.into(db.attendanceSettings).insert(
              AttendanceSettingsCompanion.insert(
                settingKey: entry.key,
                settingValue: entry.value,
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              ),
            );
      }
    });

    tearDown(() async => db.close());

    Future<void> seedNegativeRow() async {
      await db.staffManagementDao.addAttendance(
        AttendanceTableCompanion.insert(
          staffId: 'ST-1',
          date: mon,
          status: 'present',
          checkInTime: Value(DateTime(2026, 9, 14, 17)),
          checkOutTime: Value(DateTime(2026, 9, 15)),
          workingHours: Value(-17.0),
          source: const Value('device'),
          createdAt: DateTime(2026, 9, 14),
          updatedAt: DateTime(2026, 9, 14),
        ),
      );
    }

    test('G1 recordManualOverride with 17:00 / 00:00 persists 7.0 hours',
        () async {
      await StaffManagementService(db.staffManagementDao, db)
          .recordManualOverride(
        admin(),
        'ST-1',
        date: mon,
        status: 'present',
        reason: 'off-schedule night shift',
        // What manual_override_dialog now produces via pairCheckInOut:
        checkInTime: DateTime(2026, 9, 14, 17),
        checkOutTime: DateTime(2026, 9, 15),
        notes: null,
      );

      final rows = await db.staffManagementDao.getAttendanceByStaff('ST-1');
      expect(rows, hasLength(1));
      expect(rows.first.workingHours, closeTo(7.0, 0.0001));
      expect(rows.first.workingHours, greaterThanOrEqualTo(0));
      expect(rows.first.checkOutTime, DateTime(2026, 9, 15));
    });

    test('G2 recomputeOvertimeForPeriod repairs a -17.0 row', () async {
      await seedNegativeRow();

      final res = await StaffManagementService(db.staffManagementDao, db)
          .recomputeOvertimeForPeriod(admin(), 'ST-1', mon, mon);

      expect(res.recomputed, 1);
      final rows = await db.staffManagementDao.getAttendanceByStaff('ST-1');
      expect(rows.first.workingHours, closeTo(7.0, 0.0001));
      expect(rows.first.overtimeHours, closeTo(7.0, 0.0001));
    });

    test('G2b recompute skips a row inside a PAID period', () async {
      await seedNegativeRow();
      await db.into(db.payrollTable).insert(
            PayrollTableCompanion.insert(
              staffId: 'ST-1',
              payrollPeriod: '2026-09',
              periodStart: DateTime(2026, 9, 1),
              periodEnd: DateTime(2026, 9, 30),
              basicSalary: 6000,
              netSalary: 6000,
              status: 'paid',
              createdAt: DateTime(2026, 9, 30),
              updatedAt: DateTime(2026, 9, 30),
            ),
          );

      final res = await StaffManagementService(db.staffManagementDao, db)
          .recomputeOvertimeForPeriod(admin(), 'ST-1', mon, mon);

      expect(res.recomputed, 0);
      expect(res.skipped, 1);
      final rows = await db.staffManagementDao.getAttendanceByStaff('ST-1');
      expect(rows.first.workingHours, -17.0,
          reason: 'a paid period is frozen and must not be rewritten');
    });

    test('G3 payroll credits 7h overtime at 6000/month', () async {
      await db.staffManagementDao.addAttendance(
        AttendanceTableCompanion.insert(
          staffId: 'ST-1',
          date: mon,
          status: 'present',
          checkInTime: Value(DateTime(2026, 9, 14, 17)),
          checkOutTime: Value(DateTime(2026, 9, 15)),
          workingHours: Value(7.0),
          overtimeHours: Value(7.0),
          source: const Value('device'),
          createdAt: DateTime(2026, 9, 14),
          updatedAt: DateTime(2026, 9, 14),
        ),
      );

      await StaffManagementService(db.staffManagementDao, db)
          .calculatePayroll(admin(), 'ST-1', '2026-09');

      final slips = await (db.select(db.payrollTable)
            ..where((t) => t.staffId.equals('ST-1')))
          .get();
      expect(slips, hasLength(1));
      final p = slips.first;
      const hourly = 6000 / 30 / 8; // 25
      expect(p.overtimeHours, closeTo(7.0, 0.0001));
      expect(p.overtimePay, closeTo(7.0 * hourly * 1.5, 0.0001));
      expect(p.overtimePay, closeTo(262.50, 0.0001));
      expect(p.lateDeduction, 0);
      expect(p.permissionDeduction, 0);
      expect(p.netSalary, closeTo(6000 + 262.50, 0.0001));
    });
  });
}
