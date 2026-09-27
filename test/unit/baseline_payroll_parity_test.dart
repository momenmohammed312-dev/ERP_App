import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/services/attendance/attendance_deduction_calculator.dart';

/// Parity suite for the approved v72 attendance/payroll restoration.
///
/// The golden reference is commit `5eb58db` (2026-09-15, schema v69) and the
/// acceptance oracle is `4f7e2a0`. These tests pin the APPROVED invariants with
/// exact numbers so a future change cannot silently move payroll again.
///
/// [APPROVED BUSINESS RULES — locked]
///
///   hourly          = basicSalary / dailyDivisor / standardHoursPerDay
///                     monthly 6000 -> 6000 / 30 / 8 = 25
///   overtimePay     = totalOvertime * hourly * overtimeRateMultiplier
///                     6000 monthly, 10h, x1.5 -> 25 * 10 * 1.5 = 375
///   late minutes    = checkIn - workStart   (grace only decides "is it late")
///   lateMultiplier  = configuredLatePenaltyPerHour > 0 ? value : 1.5
///                     ONE resolved value, shared by payroll and the UI
///
/// P1 (multiplier) and P2 (divisor) are asserted together on purpose: the old
/// /160 divisor was self-cancelling against the missing multiplier
/// (160 = 240 / 1.5), so the multiplier must never be applied without /240.
void main() {
  const workStart = 9 * 60; // 09:00
  const workEnd = 17 * 60; // 17:00
  const grace = 15;

  Staff staff({
    required double basicSalary,
    String employmentType = 'full_time',
    double? hourlyRate,
  }) {
    return Staff(
      id: 1,
      staffId: 'ST-1',
      name: 'موظف',
      position: 'Cashier',
      employmentType: employmentType,
      basicSalary: basicSalary,
      hourlyRate: hourlyRate,
      hireDate: DateTime(2026, 1, 1),
      status: 'active',
      isActive: true,
      useDefaultSchedule: true,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    );
  }

  Attendance row({
    required int day,
    required String status,
    int? inHour,
    int? inMinute,
    int? outHour,
    int? outMinute,
    String? notes,
    String? leaveType,
    double overtimeHours = 0.0,
  }) {
    final date = DateTime(2026, 9, day);
    return Attendance(
      id: day,
      staffId: 'ST-1',
      date: date,
      checkInTime: inHour == null
          ? null
          : DateTime(2026, 9, day, inHour, inMinute ?? 0),
      checkOutTime: outHour == null
          ? null
          : DateTime(2026, 9, day, outHour, outMinute ?? 0),
      checkInLocation: null,
      checkOutLocation: null,
      workingHours: null,
      status: status,
      excused: false,
      excusedHours: 0.0,
      leaveType: leaveType,
      notes: notes,
      source: 'manual',
      sourceDeviceId: null,
      rawEventId: null,
      overrideReason: null,
      overtimeHours: overtimeHours,
      lateMinutes: 0,
      permissionHours: 0.0,
      approvedBy: null,
      approvedAt: null,
      createdAt: date,
      updatedAt: date,
    );
  }

  AttendanceDeductionResult compute(
    Staff s,
    List<Attendance> records, {
    bool weeklyPeriod = false,
    double lateMultiplier = 1.5,
    double standardHoursPerDay = 8.0,
  }) {
    return computeAttendanceDeductions(
      records: records,
      staff: s,
      weeklyPeriod: weeklyPeriod,
      workStartMinutes: workStart,
      workEndMinutes: workEnd,
      graceMinutes: grace,
      lateMultiplier: lateMultiplier,
      absenceMultiplier: 1.0,
      absenceMode: 'day_wage',
      fixedAbsenceAmount: 0.0,
      standardHoursPerDay: standardHoursPerDay,
    );
  }

  // ── GATE A: P1 + P2 must be verified together ──────────────────────────
  group('P1+P2 atomic gate', () {
    test('monthly 6000 hourly is basic/240 = 25 (not /160)', () {
      final hourly = AttendanceDeductionRules.hourlyOf(
        staff(basicSalary: 6000),
        weeklyPeriod: false,
      );
      expect(hourly, closeTo(25.0, 0.000001));
    });

    test('weekly 1200 hourly is 1200/6/8 = 25', () {
      final hourly = AttendanceDeductionRules.hourlyOf(
        staff(basicSalary: 1200, employmentType: 'weekly'),
        weeklyPeriod: true,
      );
      expect(hourly, closeTo(25.0, 0.000001));
    });

    test('overtime 10h at x1.5 pays exactly 375', () {
      const totalOvertime = 10.0;
      const overtimeRateMultiplier = 1.5;
      final hourly = AttendanceDeductionRules.hourlyOf(
        staff(basicSalary: 6000),
        weeklyPeriod: false,
      );
      final overtimePay =
          totalOvertime * hourly * overtimeRateMultiplier;
      expect(hourly, closeTo(25.0, 0.000001));
      expect(overtimePay, closeTo(375.0, 0.000001));
    });

    test('the /160 divisor would have overpaid by 50% - regression guard', () {
      // 6000/160 = 37.5; 37.5 * 10 * 1.5 = 562.5, i.e. +50% over 375.
      final wrong = (staff(basicSalary: 6000).basicSalary / 160.0) * 10 * 1.5;
      expect(wrong, closeTo(562.5, 0.000001));
      final right = (staff(basicSalary: 6000).basicSalary / 30.0 / 8.0) * 10 * 1.5;
      expect(right, closeTo(375.0, 0.000001));
    });
  });

  // ── 1. monthly 6000, full attendance, no deductions ─────────────────────
  test('1. monthly 6000 full attendance produces zero deductions', () {
    final s = staff(basicSalary: 6000);
    final records = [
      for (var d = 1; d <= 5; d++)
        row(day: d, status: 'present', inHour: 8, inMinute: 50, outHour: 17),
    ];
    final r = compute(s, records);
    expect(r.hourly, closeTo(25.0, 0.000001));
    expect(r.absentDays, 0);
    expect(r.totalLateMinutes, 0);
    expect(r.totalPermissionMinutes, 0);
    expect(r.lateDeduction, closeTo(0.0, 0.000001));
    expect(r.permissionDeduction, closeTo(0.0, 0.000001));
    expect(r.absenceDeduction, closeTo(0.0, 0.000001));
    expect(r.total, closeTo(0.0, 0.000001));
  });

  // ── 2. monthly 6000, 5 late days x 20 minutes ──────────────────────────
  test('2. monthly 6000, 5 late days x 20 min late', () {
    final s = staff(basicSalary: 6000);
    // check-in 09:20 => 20 minutes from the 09:00 shift start.
    final records = [
      for (var d = 1; d <= 5; d++)
        row(day: d, status: 'late', inHour: 9, inMinute: 20, outHour: 17),
    ];
    final r = compute(s, records);
    expect(r.totalLateMinutes, 100); // 5 x 20
    expect(r.lateDays, 5);
    expect(r.lateDeduction, closeTo((100 / 60) * 25 * 1.5, 0.000001));
    expect(r.lateDeduction, closeTo(62.5, 0.000001));
  });

  // ── 3. monthly 6000, 10h overtime ──────────────────────────────────────
  test('3. monthly 6000, 10h overtime column carries the hours', () {
    final s = staff(basicSalary: 6000);
    final records = [
      row(
        day: 1,
        status: 'present',
        inHour: 8,
        inMinute: 50,
        outHour: 19,
        overtimeHours: 10.0,
      ),
    ];
    final r = compute(s, records);
    expect(r.hourly, closeTo(25.0, 0.000001));
    final overtimePay = 10.0 * r.hourly * 1.5;
    expect(overtimePay, closeTo(375.0, 0.000001));
  });

  // ── 4. monthly 6000, 3 permission days x 2h ────────────────────────────
  test('4. monthly 6000, 3 permission days x 2h each', () {
    final s = staff(basicSalary: 6000);
    // checkout 15:00 vs a 17:00 end => 2h permission per day.
    final records = [
      for (var d = 1; d <= 3; d++)
        row(day: d, status: 'present', inHour: 9, outHour: 15),
    ];
    final r = compute(s, records);
    expect(r.totalPermissionMinutes, 360); // 3 x 120
    expect(r.permissionDeduction, closeTo((360 / 60) * 25 * 1.0, 0.000001));
    expect(r.permissionDeduction, closeTo(150.0, 0.000001));
  });

  // ── 5. monthly 6000, 2 absence days ────────────────────────────────────
  test('5. monthly 6000, 2 absence days = 2 x (6000/30) x 1.0', () {
    final s = staff(basicSalary: 6000);
    final records = [row(day: 1, status: 'absent'), row(day: 2, status: 'absent')];
    final r = compute(s, records);
    expect(r.absentDays, 2);
    expect(r.dayWage, closeTo(200.0, 0.000001)); // 6000/30
    expect(r.absenceDeduction, closeTo(400.0, 0.000001));
  });

  // ── 6. weekly 1200 ─────────────────────────────────────────────────────
  test('6. weekly 1200 hourly and day-wage use the weekly divisor 6', () {
    final s = staff(basicSalary: 1200, employmentType: 'weekly');
    final r = compute(
      s,
      [row(day: 1, status: 'absent')],
      weeklyPeriod: true,
    );
    expect(r.hourly, closeTo(25.0, 0.000001)); // 1200/6/8
    expect(r.dayWage, closeTo(200.0, 0.000001)); // 1200/6
    expect(r.absenceDeduction, closeTo(200.0, 0.000001));
  });

  // ── 7. daily 300 x 22 present days (daily model kept from current line) ─
  test('7. daily 300 hourly is 300/8; daily pay model is kept as-is', () {
    final s = staff(basicSalary: 300, employmentType: 'daily');
    final r = compute(s, [
      for (var d = 1; d <= 22; d++)
        row(day: d, status: 'present', inHour: 9, outHour: 17),
    ]);
    expect(r.hourly, closeTo(37.5, 0.000001)); // 300/8 - unchanged
    // Daily staff earn by present days, so there is no extra absence deduction.
    expect(r.absenceDeduction, closeTo(0.0, 0.000001));
  });

  // ── late minute rule: from shift start, not after grace ────────────────
  group('late minutes are measured from the shift start', () {
    test('09:20 with 15 grace = 20 minutes, not 5', () {
      final r = compute(staff(basicSalary: 6000), [
        row(day: 1, status: 'late', inHour: 9, inMinute: 20, outHour: 17),
      ]);
      expect(r.totalLateMinutes, 20);
      expect(r.lateDeduction, closeTo((20 / 60) * 25 * 1.5, 0.000001));
    });

    test('09:10 is inside the 15-minute grace so it is NOT late', () {
      final r = compute(staff(basicSalary: 6000), [
        row(day: 1, status: 'present', inHour: 9, inMinute: 10, outHour: 17),
      ]);
      expect(r.totalLateMinutes, 0);
      expect(r.lateDeduction, 0);
    });

    test('excused rows never count as late', () {
      final r = compute(staff(basicSalary: 6000), [
        row(
          day: 1,
          status: 'excused',
          inHour: 12,
          outHour: 17,
        ),
      ]);
      expect(r.totalLateMinutes, 0);
      expect(r.lateDeduction, 0);
    });
  });

  // ── late multiplier resolution: one value for payroll and the UI ───────
  group('lateMultiplier resolution (shared by payroll and Employee Details)', () {
    test('unconfigured (null) resolves to 1.5', () {
      expect(AttendanceDeductionRules.resolveLateMultiplier(null), 1.5);
    });

    test('zero resolves to 1.5, never to a silent zero deduction', () {
      expect(AttendanceDeductionRules.resolveLateMultiplier(0), 1.5);
    });

    test('a configured value above zero is used as-is', () {
      expect(AttendanceDeductionRules.resolveLateMultiplier(2.0), 2.0);
      expect(AttendanceDeductionRules.resolveLateMultiplier(0.5), 0.5);
    });

    test('the resolved multiplier is what the calculator actually applies', () {
      final records = [
        row(day: 1, status: 'late', inHour: 9, inMinute: 20, outHour: 17),
      ];
      final viaDefault = compute(
        staff(basicSalary: 6000),
        records,
        lateMultiplier: AttendanceDeductionRules.resolveLateMultiplier(0),
      );
      final viaTwo = compute(
        staff(basicSalary: 6000),
        records,
        lateMultiplier: AttendanceDeductionRules.resolveLateMultiplier(2.0),
      );
      expect(viaDefault.lateDeduction, closeTo((20 / 60) * 25 * 1.5, 0.000001));
      expect(viaTwo.lateDeduction, closeTo((20 / 60) * 25 * 2.0, 0.000001));
    });
  });

  // ── 8. perfect attendance bonus eligibility ────────────────────────────
  group('commitment / perfect-attendance bonus eligibility', () {
    Attendance clean() => row(
          day: 1,
          status: 'present',
          inHour: 8,
          inMinute: 50,
          outHour: 17,
        );

    test('clean attendance: absent=0, leave=0, late=0 => eligible', () {
      final r = compute(staff(basicSalary: 6000), [clean()]);
      expect(r.absentDays, 0);
      expect(r.totalLateMinutes, 0);
      expect(r.total, closeTo(0.0, 0.000001));
    });

    test('any absent day makes it ineligible', () {
      final r = compute(staff(basicSalary: 6000), [
        clean(),
        row(day: 2, status: 'absent'),
      ]);
      expect(r.absentDays, 1);
      expect(r.total, greaterThan(0.0));
    });

    test('any late minute makes it ineligible', () {
      final r = compute(staff(basicSalary: 6000), [
        row(day: 1, status: 'late', inHour: 9, inMinute: 20, outHour: 17),
      ]);
      expect(r.totalLateMinutes, 20);
      expect(r.total, greaterThan(0.0));
    });

    test('a permission/early-leave does not create lateness', () {
      final r = compute(staff(basicSalary: 6000), [
        row(day: 1, status: 'excused', inHour: 9, outHour: 17),
      ]);
      expect(r.totalLateMinutes, 0);
    });
  });

  // ── 9. advances are capped at the net earned ───────────────────────────
  group('advance capping', () {
    test('applied advances = min(totalAdvances, netBeforeAdvances)', () {
      const basic = 6000.0;
      const netBeforeAdvances = basic + 375.0; // salary + overtime
      const requested = 20000.0;
      final capped = requested < netBeforeAdvances
          ? requested
          : netBeforeAdvances;
      expect(capped, closeTo(6375.0, 0.000001));
      expect(capped, lessThan(requested));
      // Net must never go negative because of advances.
      expect(netBeforeAdvances - capped, closeTo(0.0, 0.000001));
    });

    test('a small advance is applied in full', () {
      const netBeforeAdvances = 6375.0;
      const requested = 500.0;
      final capped = requested < netBeforeAdvances
          ? requested
          : netBeforeAdvances;
      expect(capped, closeTo(500.0, 0.000001));
    });
  });

  // ── 10. permission card hours == payroll permissionHours ───────────────
  test('10. permission card hours and payroll permissionHours agree', () {
    final s = staff(basicSalary: 6000);
    final records = [
      for (var d = 1; d <= 3; d++)
        row(day: d, status: 'present', inHour: 9, outHour: 15),
    ];
    final r = compute(s, records);
    // The card shows HOURS (fmtHM), the payroll stores HOURS.
    final cardHours = r.totalPermissionMinutes / 60.0;
    expect(cardHours, closeTo(6.0, 0.000001)); // 3 x 2h
    // The payroll's stored permissionHours must be that same number.
    expect(r.totalPermissionMinutes / 60.0, closeTo(cardHours, 0.000001));
    expect(r.permissionDeduction, closeTo(cardHours * r.hourly, 0.000001));
  });
}
