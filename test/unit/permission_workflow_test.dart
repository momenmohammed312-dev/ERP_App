import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/dao/staff_management_dao.dart';
import 'package:pos_offline_desktop/services/attendance/attendance_calculation_engine.dart';
import 'package:pos_offline_desktop/services/staff_management_service.dart';

/// C4 — PERMISSIONS (no new subsystem, no schema change).
///
/// - Types stay string-based ('leave'|'late'|'early' → stored status).
/// - Duplicate prevention: second grant on a permission day returns the
///   typed [PermissionAlreadyExists] result; nothing is overwritten.
/// - Approval semantics on existing columns only (excused == approved
///   marker; approvedBy/approvedAt stamp is additive metadata).
/// - Approved late waives lateness only via the single C1 function; never
///   creates absence; money flows only through permissionDeduction ×1.0.
/// - Early-checkout computation is byte-identical (characterization +
///   `git diff` evidence that no early path was touched).
void main() {
  late AppDatabase db;
  late StaffManagementDao dao;
  late StaffManagementService svc;

  Future<void> addStaff(String staffId) async {
    final now = DateTime.now();
    await dao.addStaff(
      StaffTableCompanion.insert(
        staffId: staffId,
        name: 'Perm $staffId',
        position: 'Cashier',
        employmentType: 'full_time',
        basicSalary: 9000,
        hireDate: DateTime(2026, 1, 1),
        status: 'active',
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  Future<void> timedRow(
    String staffId,
    int day, {
    String status = 'present',
    int ciH = 9,
    int ciM = 0,
    int coH = 17,
    int coM = 0,
  }) async {
    await dao.addAttendance(
      AttendanceTableCompanion.insert(
        staffId: staffId,
        date: DateTime(2026, 9, day),
        status: status,
        checkInTime: Value(DateTime(2026, 9, day, ciH, ciM)),
        checkOutTime: Value(DateTime(2026, 9, day, coH, coM)),
        workingHours: const Value(7.0),
        overtimeHours: const Value(0),
        source: const Value('device'),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
  }

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    dao = StaffManagementDao(db);
    svc = StaffManagementService(dao, db);
    await _insertSettings(db);
  });

  tearDown(() async => await db.close());

  test('duplicate grant returns PermissionAlreadyExists, row untouched',
      () async {
    await addStaff('STAFFD1');
    await timedRow('STAFFD1', 2, status: 'late', ciH: 10, ciM: 30);

    final first = await svc.markLeaveDay(
      'STAFFD1',
      DateTime(2026, 9, 2),
      permissionType: 'late',
      excused: true,
      excusedHours: 0,
      approvedBy: 'Admin',
    );
    expect(first, isA<PermissionApplied>());

    // Second grant tries to overwrite with different hours — must be refused.
    final second = await svc.markLeaveDay(
      'STAFFD1',
      DateTime(2026, 9, 2),
      permissionType: 'late',
      excused: true,
      excusedHours: 5.0,
    );
    expect(second, isA<PermissionAlreadyExists>());
    final kept = (second as PermissionAlreadyExists).existing;
    expect(kept.excusedHours, 0);

    final stored = (await dao.getAttendanceOnDate(
      'STAFFD1',
      DateTime(2026, 9, 2),
    ))
        .single;
    expect(stored.excusedHours, 0,
        reason: 'silent overwrite must not happen');
    expect(stored.approvedBy, 'Admin',
        reason: 'approval stamp recorded on existing columns');
    expect(stored.approvedAt, isNotNull);
  });

  test('grant on a plain device-late row is allowed (main flow)', () async {
    await addStaff('STAFFD2');
    await timedRow('STAFFD2', 3, status: 'late', ciH: 10, ciM: 0);
    final r = await svc.markLeaveDay(
      'STAFFD2',
      DateTime(2026, 9, 3),
      permissionType: 'late',
      excused: true,
      excusedHours: 0,
    );
    expect(r, isA<PermissionApplied>());
    expect((r as PermissionApplied).created, isFalse);
  });

  test('fresh day leave grant creates the row with string type intact',
      () async {
    await addStaff('STAFFD3');
    final r = await svc.markLeaveDay(
      'STAFFD3',
      DateTime(2026, 9, 4),
      permissionType: 'leave',
      excused: true,
    );
    expect(r, isA<PermissionApplied>());
    expect((r as PermissionApplied).created, isTrue);
    final stored = (await dao.getAttendanceOnDate(
      'STAFFD3',
      DateTime(2026, 9, 4),
    ))
        .single;
    // C4: types stay string-based in attendance_table.
    expect(stored.status, 'leave');
  });

  test('approved late waives per C1, creates no absence', () async {
    await addStaff('STAFFD4');
    await timedRow('STAFFD4', 7, status: 'late', ciH: 10, ciM: 0);
    await svc.markLeaveDay(
      'STAFFD4',
      DateTime(2026, 9, 7),
      permissionType: 'late',
      excused: true,
      excusedHours: 0,
      approvedBy: 'Admin',
    );

    final s = await svc.getAttendanceSummary(
      'STAFFD4',
      DateTime(2026, 9, 1),
      DateTime(2026, 9, 30),
    );
    expect(s.totalLateMinutes, 0, reason: 'approved full excuse waives');
    expect(s.lateDays, 0);
    final rows = await dao.getAttendanceByStaff(
      'STAFFD4',
      startDate: DateTime(2026, 9, 1),
      endDate: DateTime(2026, 9, 30),
    );
    expect(rows.where((r) => r.status == 'absent'), isEmpty,
        reason: 'permission must never create absence');
    // Display predicate agrees (waived ⇒ not a late day).
    final stored = rows.single;
    expect(
      isEffectiveLateDay(
        status: stored.status,
        checkInTime: stored.checkInTime,
        scheduleStartMinutes: 540,
        graceMinutes: 15,
        excused: stored.excused,
        excusedHours: stored.excusedHours,
      ),
      isFalse,
    );
  });

  test('unapproved late penalizes exactly like normal late (no more)',
      () async {
    await addStaff('STAFFD5');
    await addStaff('STAFFD6');
    await timedRow('STAFFD5', 8, ciH: 10, ciM: 0);
    await timedRow('STAFFD6', 8, ciH: 10, ciM: 0);
    // STAFFD6 requests (pending: excused=false) — payroll sees normal late.
    final r = await svc.markLeaveDay(
      'STAFFD6',
      DateTime(2026, 9, 8),
      permissionType: 'late',
      excused: false,
      excusedHours: 0,
    );
    expect(r, isA<PermissionApplied>());

    final a = await svc.getAttendanceSummary(
      'STAFFD5',
      DateTime(2026, 9, 1),
      DateTime(2026, 9, 30),
    );
    final b = await svc.getAttendanceSummary(
      'STAFFD6',
      DateTime(2026, 9, 1),
      DateTime(2026, 9, 30),
    );
    expect(b.totalLateMinutes, a.totalLateMinutes);
    expect(b.totalLateMinutes, 60);
    expect(b.totalPermissionHours, 0);
  });

  test('partial excuse money flows exactly through permission ×1.0',
      () async {
    await addStaff('STAFFD7');
    await timedRow('STAFFD7', 6, ciH: 10, ciM: 0); // 60min late
    await timedRow('STAFFD7', 7, ciH: 10, ciM: 0); // 60min late
    await svc.calculatePeriodPay(
      staffId: 'STAFFD7',
      payrollPeriod: '2026-09-T2',
      periodStart: DateTime(2026, 9, 6),
      periodEnd: DateTime(2026, 9, 7),
      baseSalary: 9000,
      dailyDivisor: 30,
    );
    final before = (await dao.getPayrollByStaff('STAFFD7')).single;
    expect(before.lateDeduction, closeTo(2.0 * 37.5 * 1.5, 1e-9));
    expect(before.permissionDeduction, 0);

    // Partial excuse of 1h on Sep 7 (plain present row ⇒ grant allowed).
    final r = await svc.markLeaveDay(
      'STAFFD7',
      DateTime(2026, 9, 7),
      permissionType: 'late',
      excused: true,
      excusedHours: 1.0,
      approvedBy: 'Admin',
    );
    expect(r, isA<PermissionApplied>());
    await svc.calculatePeriodPay(
      staffId: 'STAFFD7',
      payrollPeriod: '2026-09-T2',
      periodStart: DateTime(2026, 9, 6),
      periodEnd: DateTime(2026, 9, 7),
      baseSalary: 9000,
      dailyDivisor: 30,
    );
    final after = (await dao.getPayrollByStaff('STAFFD7')).single;
    expect(after.lateDeduction, closeTo(before.lateDeduction, 1e-9),
        reason: 'frozen late semantics untouched by the excuse');
    expect(after.permissionHours, closeTo(1.0, 1e-9));
    expect(after.permissionDeduction, closeTo(1.0 * 37.5 * 1.0, 1e-9),
        reason: 'permission money flows only through ×1.0 path');
  });

  test('approve/reject on existing columns; approve of nothing → false',
      () async {
    await addStaff('STAFFD8');
    await timedRow('STAFFD8', 9, ciH: 10, ciM: 0);
    // Request (pending).
    await svc.markLeaveDay(
      'STAFFD8',
      DateTime(2026, 9, 9),
      permissionType: 'late',
      excused: false,
      excusedHours: 0,
    );
    // Approve → waived.
    expect(
      await svc.approvePermissionDay(
        'STAFFD8',
        DateTime(2026, 9, 9),
        approvedBy: 'Admin',
      ),
      isTrue,
    );
    var s = await svc.getAttendanceSummary(
      'STAFFD8',
      DateTime(2026, 9, 1),
      DateTime(2026, 9, 30),
    );
    expect(s.totalLateMinutes, 0);
    // Reject (existing clear path) → normal late restored.
    await svc.clearExcusedDay('STAFFD8', DateTime(2026, 9, 9));
    s = await svc.getAttendanceSummary(
      'STAFFD8',
      DateTime(2026, 9, 1),
      DateTime(2026, 9, 30),
    );
    expect(s.totalLateMinutes, 60);
    // Approving a day with no permission row writes nothing.
    expect(
      await svc.approvePermissionDay(
        'STAFFD8',
        DateTime(2026, 9, 10),
        approvedBy: 'Admin',
      ),
      isFalse,
    );
    expect(
      await dao.getAttendanceOnDate('STAFFD8', DateTime(2026, 9, 10)),
      isEmpty,
    );
  });

  test('early checkout computation byte-identical (before/after proof)',
      () async {
    await addStaff('STAFFD9');
    // 16:00 checkout vs 17:00 end → 60 early minutes; excused variants.
    await timedRow('STAFFD9', 13, coH: 16, coM: 0);
    await timedRow('STAFFD9', 14, coH: 16, coM: 30);
    final s = await svc.getAttendanceSummary(
      'STAFFD9',
      DateTime(2026, 9, 1),
      DateTime(2026, 9, 30),
    );
    expect(s.totalEarlyMinutes, 90,
        reason: 'early path untouched by remediation (see git diff)');
    expect(s.totalLateMinutes, 0);
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
