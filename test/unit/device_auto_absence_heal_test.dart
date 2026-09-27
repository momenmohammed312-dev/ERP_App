import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/dao/attendance_device_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/staff_management_dao.dart';
import 'package:pos_offline_desktop/services/attendance/attendance_calculation_engine.dart';
import 'package:pos_offline_desktop/services/attendance/attendance_sync_service.dart';

/// An auto-generated 'absent' row (no check-in) must never swallow a real
/// fingerprint: the first real event heals it into a check-in, and a
/// previously swallowed check-in sitting in the checkout field is shifted
/// back. Manual absents are respected and left untouched.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (MethodCall methodCall) async => '.',
      );

  late AppDatabase db;
  late StaffManagementDao staffDao;
  late AttendanceDeviceDao deviceDao;
  late AttendanceSyncService syncService;
  late int deviceId;
  const staffId = 'STAFF0001';
  const externalId = 'UID-001';

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    staffDao = db.staffManagementDao;
    deviceDao = db.attendanceDeviceDao;
    final engine = AttendanceCalculationEngine(db, deviceDao, staffDao);
    syncService = AttendanceSyncService(deviceDao, staffDao, engine);

    await staffDao.addStaff(
      StaffTableCompanion.insert(
        staffId: staffId,
        name: 'Test Staff',
        position: 'Cashier',
        employmentType: 'full_time',
        basicSalary: 3000,
        hireDate: DateTime(2026, 1, 10),
        status: 'active',
        createdAt: DateTime(2026, 1, 10),
        updatedAt: DateTime(2026, 1, 10),
      ),
    );
    deviceId = await deviceDao.addDevice(
      BiometricDevicesCompanion.insert(
        deviceCode: 'BIO-001',
        name: 'Test Device',
        connectionType: 'tcp_ip',
        createdAt: DateTime(2026, 1, 10),
        updatedAt: DateTime(2026, 1, 10),
      ),
    );
    await deviceDao.addMapping(
      StaffBiometricMappingsCompanion.insert(
        staffId: staffId,
        deviceId: deviceId,
        externalUserId: externalId,
        enrollmentStatus: 'enrolled',
        createdAt: DateTime(2026, 1, 10),
        updatedAt: DateTime(2026, 1, 10),
      ),
    );
  });

  Future<void> addRawEvent(DateTime time, String hash) async {
    await deviceDao.addRawEvent(
      AttendanceRawEventsCompanion.insert(
        deviceId: deviceId,
        externalUserId: externalId,
        eventTime: time,
        dedupHash: hash,
        status: 'pending',
        createdAt: time,
      ),
    );
  }

  Future<void> addAutoAbsent(
    DateTime day, {
    DateTime? swallowedCheckout,
  }) async {
    await staffDao.addAttendance(
      AttendanceTableCompanion.insert(
        staffId: staffId,
        date: DateTime(day.year, day.month, day.day),
        status: 'absent',
        checkOutTime: Value(swallowedCheckout),
        source: const Value('auto_generated'),
        createdAt: day,
        updatedAt: day,
      ),
    );
  }

  Future<void> useOvernightSchedule() async {
    final staff = await staffDao.getStaffById(staffId);
    await staffDao.updateStaff(
      staff!.copyWith(
        useDefaultSchedule: false,
        workScheduleStart: const Value('20:00'),
        workScheduleEnd: const Value('02:30'),
      ),
    );
  }

  Future<Attendance> singleRecord() async {
    final rows = await staffDao.getAttendanceByStaff(staffId);
    expect(rows, hasLength(1));
    return rows.first;
  }

  test('check-in heals a fresh auto-absent into present', () async {
    final day = DateTime(2026, 1, 14);
    await addAutoAbsent(day);
    await addRawEvent(DateTime(2026, 1, 14, 8, 0), 'hash-in-1');

    final result = await syncService.processPendingEvents(deviceId);

    expect(result.matched, 1);
    final r = await singleRecord();
    expect(r.status, 'present');
    expect(r.checkInTime, DateTime(2026, 1, 14, 8, 0));
    expect(r.checkOutTime, isNull);
    expect(r.source, 'device');
  });

  test('swallowed check-in shifts back when real checkout arrives', () async {
    final day = DateTime(2026, 1, 14);
    // Corrupted state from the old code: check-in 08:00 was written as checkout
    await addAutoAbsent(day, swallowedCheckout: DateTime(2026, 1, 14, 8, 0));
    await addRawEvent(DateTime(2026, 1, 14, 18, 0), 'hash-out-1');

    final result = await syncService.processPendingEvents(deviceId);

    expect(result.matched, 1);
    final r = await singleRecord();
    expect(r.status, 'present');
    expect(r.checkInTime, DateTime(2026, 1, 14, 8, 0));
    expect(r.checkOutTime, DateTime(2026, 1, 14, 18, 0));
    expect(r.workingHours, closeTo(10.0, 0.001));
    expect(r.overtimeHours, closeTo(1.0, 0.001));
  });

  test('manual absent rows are never healed', () async {
    final day = DateTime(2026, 1, 14);
    await staffDao.addAttendance(
      AttendanceTableCompanion.insert(
        staffId: staffId,
        date: DateTime(day.year, day.month, day.day),
        status: 'absent',
        source: const Value('manual'),
        createdAt: day,
        updatedAt: day,
      ),
    );
    await addRawEvent(DateTime(2026, 1, 14, 8, 0), 'hash-in-2');

    await syncService.processPendingEvents(deviceId);

    final r = await singleRecord();
    expect(r.status, 'absent');
    expect(r.checkInTime, isNull);
  });

  test('02:30 fingerprint closes previous open day (night shift)', () async {
    await useOvernightSchedule();
    // Previous day: checked in at 20:00, still open (no checkout).
    await staffDao.addAttendance(
      AttendanceTableCompanion.insert(
        staffId: staffId,
        date: DateTime(2026, 1, 13),
        status: 'present',
        checkInTime: Value(DateTime(2026, 1, 13, 20, 0)),
        source: const Value('device'),
        createdAt: DateTime(2026, 1, 13, 20, 0),
        updatedAt: DateTime(2026, 1, 13, 20, 0),
      ),
    );
    await addRawEvent(DateTime(2026, 1, 14, 2, 30), 'hash-night-1');

    final result = await syncService.processPendingEvents(deviceId);

    expect(result.matched, 1);
    final rows = await staffDao.getAttendanceByStaff(staffId);
    // No bogus check-in created for the new day — yesterday got its checkout.
    expect(rows, hasLength(1));
    final r = rows.first;
    expect(r.date, DateTime(2026, 1, 13));
    expect(r.checkInTime, DateTime(2026, 1, 13, 20, 0));
    expect(r.checkOutTime, DateTime(2026, 1, 14, 2, 30));
  });

  test(
    'first night-shift import keeps both punches on the previous day',
    () async {
      await useOvernightSchedule();
      await addRawEvent(DateTime(2026, 1, 13, 20), 'hash-night-first-in');
      await addRawEvent(DateTime(2026, 1, 14, 2, 30), 'hash-night-first-out');

      final result = await syncService.processPendingEvents(deviceId);

      expect(result.matched, 2);
      final rows = await staffDao.getAttendanceByStaff(staffId);
      expect(rows, hasLength(1));
      expect(rows.single.date, DateTime(2026, 1, 13));
      expect(rows.single.checkInTime, DateTime(2026, 1, 13, 20));
      expect(rows.single.checkOutTime, DateTime(2026, 1, 14, 2, 30));
    },
  );

  test(
    'first import of consecutive night shifts creates two work dates',
    () async {
      await useOvernightSchedule();
      await addRawEvent(DateTime(2026, 1, 13, 20), 'hash-night-chain-in-1');
      await addRawEvent(DateTime(2026, 1, 14, 2, 30), 'hash-night-chain-out-1');
      await addRawEvent(DateTime(2026, 1, 14, 20), 'hash-night-chain-in-2');
      await addRawEvent(DateTime(2026, 1, 15, 2, 30), 'hash-night-chain-out-2');

      final result = await syncService.processPendingEvents(deviceId);

      expect(result.matched, 4);
      expect(await staffDao.getAttendanceByStaff(staffId), hasLength(2));
      final first = await staffDao.getAttendanceOnDate(
        staffId,
        DateTime(2026, 1, 13),
      );
      expect(first, hasLength(1));
      expect(first.single.checkInTime, DateTime(2026, 1, 13, 20));
      expect(first.single.checkOutTime, DateTime(2026, 1, 14, 2, 30));
      final second = await staffDao.getAttendanceOnDate(
        staffId,
        DateTime(2026, 1, 14),
      );
      expect(second, hasLength(1));
      expect(second.single.checkInTime, DateTime(2026, 1, 14, 20));
      expect(second.single.checkOutTime, DateTime(2026, 1, 15, 2, 30));
    },
  );

  test(
    'later preceding 20:00 event converges the overnight work-date row',
    () async {
      await useOvernightSchedule();
      await addRawEvent(DateTime(2026, 1, 14, 2, 30), 'hash-night-late-first');
      final firstResult = await syncService.processPendingEvents(deviceId);
      expect(firstResult.matched, 1);
      final provisional = await singleRecord();
      expect(provisional.date, DateTime(2026, 1, 13));
      expect(provisional.checkInTime, DateTime(2026, 1, 14, 2, 30));
      expect(provisional.checkOutTime, isNull);

      await addRawEvent(DateTime(2026, 1, 13, 20), 'hash-night-late-second');
      final secondResult = await syncService.processPendingEvents(deviceId);

      expect(secondResult.matched, 1);
      final rows = await staffDao.getAttendanceByStaff(staffId);
      expect(rows, hasLength(1));
      expect(rows.single.id, provisional.id);
      expect(rows.single.date, DateTime(2026, 1, 13));
      expect(rows.single.checkInTime, DateTime(2026, 1, 13, 20));
      expect(rows.single.checkOutTime, DateTime(2026, 1, 14, 2, 30));
    },
  );

  test('historical cross-date overnight event is reparented, not deleted', () async {
    // ───────────────────────────────────────────────────────────────────────
    // v72: the stale-attendance DELETE is intentionally removed.
    //
    // The sync used to hard-delete any attendance row a re-matched raw event
    // had previously produced. That destroyed real data in two ways: a
    // re-punch on a day an admin had marked with a permission erased that
    // permission, and a row that had already fed a payslip vanished with no
    // trace. Baseline 5eb58db has no such deletion either.
    //
    // What must still work, and is what this test pins: the raw event is
    // reparented onto the correct attendance row, the times on that row are
    // corrected, and the superseded row is LEFT ALONCE instead of being
    // silently removed. A duplicate day a human can see is better than a punch
    // that vanishes.
    // ───────────────────────────────────────────────────────────────────────
    await useOvernightSchedule();
    final wrongAttendanceId = await staffDao.addAttendanceReturningId(
      AttendanceTableCompanion.insert(
        staffId: staffId,
        date: DateTime(2026, 1, 14),
        status: 'present',
        checkInTime: Value(DateTime(2026, 1, 14, 2, 30)),
        source: const Value('device'),
        sourceDeviceId: Value(deviceId),
        createdAt: DateTime(2026, 1, 14, 2, 30),
        updatedAt: DateTime(2026, 1, 14, 2, 30),
      ),
    );
    await addRawEvent(DateTime(2026, 1, 14, 2, 30), 'hash-night-reparent');
    final historicalEvent = (await deviceDao.getUnprocessedEventsForDevice(
      deviceId,
    )).single;
    await deviceDao.updateRawEvent(
      historicalEvent.copyWith(
        status: 'matched',
        matchedStaffId: const Value(staffId),
        resultingAttendanceId: Value(wrongAttendanceId),
        processedAt: Value(DateTime(2026, 1, 14, 2, 30)),
      ),
    );

    await addRawEvent(DateTime(2026, 1, 13, 20), 'hash-night-reparent-in');
    final result = await syncService.processPendingEvents(deviceId);

    expect(result.matched, 1);
    final rows = await staffDao.getAttendanceByStaff(staffId);

    // The superseded row is NOT deleted any more, so the day now has both.
    expect(rows, hasLength(2));

    // The reparented row is correct...
    final reparentedRow = rows.firstWhere((r) => r.date == DateTime(2026, 1, 13));
    expect(reparentedRow.checkInTime, DateTime(2026, 1, 13, 20));
    expect(reparentedRow.checkOutTime, DateTime(2026, 1, 14, 2, 30));

    // ...and the superseded row survives untouched, still reconcilable by hand.
    expect(
      rows.any((r) => r.id == wrongAttendanceId),
      isTrue,
      reason: 'stale attendance rows must not be auto-deleted (v72)',
    );

    final reparented = await deviceDao.getUnprocessedEventsForDevice(deviceId);
    expect(reparented, isEmpty);
  });

  test(
    'historical admin event is never reparented by overnight repair',
    () async {
      await useOvernightSchedule();
      final adminAttendanceId = await staffDao.addAttendanceReturningId(
        AttendanceTableCompanion.insert(
          staffId: staffId,
          date: DateTime(2026, 1, 14),
          status: 'present',
          checkInTime: Value(DateTime(2026, 1, 14, 2, 30)),
          checkOutTime: Value(DateTime(2026, 1, 14, 3)),
          source: const Value('admin_override'),
          createdAt: DateTime(2026, 1, 14, 3),
          updatedAt: DateTime(2026, 1, 14, 3),
        ),
      );
      await addRawEvent(DateTime(2026, 1, 14, 2, 30), 'hash-night-admin');
      final historicalEvent = (await deviceDao.getUnprocessedEventsForDevice(
        deviceId,
      )).single;
      await deviceDao.updateRawEvent(
        historicalEvent.copyWith(
          status: 'matched',
          matchedStaffId: const Value(staffId),
          resultingAttendanceId: Value(adminAttendanceId),
          processedAt: Value(DateTime(2026, 1, 14, 3)),
        ),
      );

      await addRawEvent(DateTime(2026, 1, 13, 20), 'hash-night-admin-in');
      final result = await syncService.processPendingEvents(deviceId);

      expect(result.matched, 1);
      final adminRow = await staffDao.getAttendanceById(adminAttendanceId);
      expect(adminRow, isNotNull);
      expect(adminRow!.source, 'admin_override');
      expect(adminRow.checkInTime, DateTime(2026, 1, 14, 2, 30));
      expect(adminRow.checkOutTime, DateTime(2026, 1, 14, 3));
    },
  );

  test('corrupted auto-absence rolls into the previous work day', () async {
    await useOvernightSchedule();
    await staffDao.addAttendance(
      AttendanceTableCompanion.insert(
        staffId: staffId,
        date: DateTime(2026, 1, 13),
        status: 'absent',
        checkOutTime: Value(DateTime(2026, 1, 13, 20)),
        source: const Value('auto_generated'),
        createdAt: DateTime(2026, 1, 13),
        updatedAt: DateTime(2026, 1, 13),
      ),
    );
    await addRawEvent(DateTime(2026, 1, 14, 2, 30), 'hash-night-repair-out');

    final result = await syncService.processPendingEvents(deviceId);

    expect(result.matched, 1);
    final rows = await staffDao.getAttendanceByStaff(staffId);
    expect(rows, hasLength(1));
    expect(rows.single.date, DateTime(2026, 1, 13));
    expect(rows.single.checkInTime, DateTime(2026, 1, 13, 20));
    expect(rows.single.checkOutTime, DateTime(2026, 1, 14, 2, 30));
  });
}
