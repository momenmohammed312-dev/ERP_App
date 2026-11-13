import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/dao/attendance_device_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/staff_management_dao.dart';
import 'package:pos_offline_desktop/core/models/user_model.dart';
import 'package:pos_offline_desktop/services/attendance/attendance_calculation_engine.dart';
import 'package:pos_offline_desktop/services/attendance/attendance_deduction_calculator.dart';
import 'package:pos_offline_desktop/services/attendance/attendance_source.dart';
import 'package:pos_offline_desktop/services/attendance/attendance_sync_service.dart';
import 'package:pos_offline_desktop/services/staff_management_service.dart';

class FakeSource extends AttendanceSource {
  final List<RawAttendanceEvent> events;
  FakeSource({required this.events}) : super(deviceIdentifier: 'fake-test');

  @override
  AttendanceSourceStatus get status => AttendanceSourceStatus.connected;

  @override
  Future<bool> connect() async => true;

  @override
  Future<void> disconnect() async {}

  @override
  Future<List<RawAttendanceEvent>> fetchEvents({DateTime? since}) async {
    if (since == null) return List.of(events);
    return events.where((e) => e.eventTime.isAfter(since)).toList();
  }
}

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

  const scheduleWithRest = ScheduleConfig(
    workStartHour: 8,
    workStartMinute: 0,
    workEndHour: 17,
    workEndMinute: 0,
    workDays: [0, 1, 2, 3, 4, 5, 6],
    weekendDay: 5,
    gracePeriodMinutes: 15,
    standardHoursPerDay: 8,
    overtimeRateMultiplier: 1.5,
    overtimeGraceMinutes: 30,
    restBreakEnabled: true,
    restBreakStartHour: 13,
    restBreakStartMinute: 0,
    restBreakEndHour: 14,
    restBreakEndMinute: 0,
  );

  Staff makeStaff({String id = 'ST-1', double basicSalary = 6000.0}) => Staff(
        id: 1,
        staffId: id,
        name: 'أحمد علي',
        position: 'عامل تشغيل',
        employmentType: 'full_time',
        basicSalary: basicSalary,
        hireDate: DateTime(2026, 1, 1),
        status: 'active',
        isActive: true,
        useDefaultSchedule: true,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );

  Attendance makeRecord({
    required DateTime date,
    required DateTime checkIn,
    DateTime? checkOut,
    String status = 'present',
    String? notes,
    double workingHours = 0.0,
    double overtimeHours = 0.0,
    double permissionHours = 0.0,
    double excusedHours = 0.0,
    bool excused = false,
  }) =>
      Attendance(
        id: 1,
        staffId: 'ST-1',
        date: date,
        status: status,
        checkInTime: checkIn,
        checkOutTime: checkOut,
        workingHours: workingHours,
        overtimeHours: overtimeHours,
        notes: notes,
        excused: excused,
        excusedHours: excusedHours,
        permissionHours: permissionHours,
        lateMinutes: 0,
        source: 'manual',
        createdAt: date,
        updatedAt: date,
      );

  group('BUG-035: ScheduleConfig standard minutes with rest break', () {
    test('standardMinutesPerDay deducts rest break when enabled (540 - 60 = 480 = 8h)', () {
      expect(scheduleWithRest.standardMinutesPerDay, 480);
      expect(scheduleWithRest.restBreakMinutes, 60);
    });

    test('standardMinutesPerDay stays raw span when rest break disabled', () {
      const scheduleWithoutRest = ScheduleConfig(
        workStartHour: 8,
        workStartMinute: 0,
        workEndHour: 17,
        workEndMinute: 0,
        workDays: [0, 1, 2, 3, 4],
        weekendDay: 5,
        gracePeriodMinutes: 15,
        standardHoursPerDay: 8,
        overtimeRateMultiplier: 1.5,
        restBreakEnabled: false,
      );
      expect(scheduleWithoutRest.standardMinutesPerDay, 540);
      expect(scheduleWithoutRest.restBreakMinutes, 0);
    });
  });

  group('BUG-035: AttendanceCalculationEngine working hours & half-day status', () {
    late AppDatabase db;
    late AttendanceCalculationEngine engine;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      engine = AttendanceCalculationEngine(
        db,
        db.attendanceDeviceDao,
        db.staffManagementDao,
      );
    });

    tearDown(() => db.close());

    test('Full day 08:00 -> 17:00 yields net 8.0 working hours (9h elapsed - 1h rest)', () {
      final res = engine.calculateAttendance(
        checkInTime: DateTime(2026, 11, 11, 8, 0),
        checkOutTime: DateTime(2026, 11, 11, 17, 0),
        schedule: scheduleWithRest,
      );
      expect(res.status, 'present');
      expect(res.workingHours, closeTo(8.0, 0.001));
      expect(res.overtimeHours, 0.0);
      expect(res.lateMinutes, 0);
    });

    test('Leave at 12:00 (08:00 -> 12:00) yields 4.0h worked and status stays present (half day >= 4h)', () {
      final res = engine.calculateAttendance(
        checkInTime: DateTime(2026, 11, 11, 8, 0),
        checkOutTime: DateTime(2026, 11, 11, 12, 0),
        schedule: scheduleWithRest,
      );
      expect(res.workingHours, closeTo(4.0, 0.001));
      expect(res.status, 'present', reason: '4.0h worked equals 8h * 0.5 standard workday, must not be degraded to early_leave');
    });

    test('Leave at 11:30 (08:00 -> 11:30) yields 3.5h worked and status early_leave (< 4h)', () {
      final res = engine.calculateAttendance(
        checkInTime: DateTime(2026, 11, 11, 8, 0),
        checkOutTime: DateTime(2026, 11, 11, 11, 30),
        schedule: scheduleWithRest,
      );
      expect(res.workingHours, closeTo(3.5, 0.001));
      expect(res.status, 'early_leave');
    });

    test('Leave at 13:00 (08:00 -> 13:00) yields 5.0h worked and status present', () {
      final res = engine.calculateAttendance(
        checkInTime: DateTime(2026, 11, 11, 8, 0),
        checkOutTime: DateTime(2026, 11, 11, 13, 0),
        schedule: scheduleWithRest,
      );
      expect(res.workingHours, closeTo(5.0, 0.001));
      expect(res.status, 'present');
    });

    test('Leave at 13:30 (08:00 -> 13:30 during rest) yields 5.0h worked (5.5h - 0.5h rest)', () {
      final res = engine.calculateAttendance(
        checkInTime: DateTime(2026, 11, 11, 8, 0),
        checkOutTime: DateTime(2026, 11, 11, 13, 30),
        schedule: scheduleWithRest,
      );
      expect(res.workingHours, closeTo(5.0, 0.001));
      expect(res.status, 'present');
    });

    test('Leave at 15:00 (08:00 -> 15:00) yields 6.0h worked (7h elapsed - 1h rest)', () {
      final res = engine.calculateAttendance(
        checkInTime: DateTime(2026, 11, 11, 8, 0),
        checkOutTime: DateTime(2026, 11, 11, 15, 0),
        schedule: scheduleWithRest,
      );
      expect(res.workingHours, closeTo(6.0, 0.001));
      expect(res.status, 'present');
    });

    test('Overtime 08:00 -> 18:00 yields 9.0h worked and 1.0h overtime past 17:00', () {
      final res = engine.calculateAttendance(
        checkInTime: DateTime(2026, 11, 11, 8, 0),
        checkOutTime: DateTime(2026, 11, 11, 18, 0),
        schedule: scheduleWithRest,
      );
      expect(res.workingHours, closeTo(9.0, 0.001));
      expect(res.overtimeHours, closeTo(1.0, 0.001));
    });
  });

  group('BUG-035: AttendanceDeductionRules.permissionMinutesOf with rest break', () {
    const workEnd = 17 * 60; // 1020 min
    const restStart = 13 * 60; // 780 min
    const restEnd = 14 * 60; // 840 min

    test('Leaving at 12:00 docks 240 minutes (4.0 hours), NOT 300 minutes (5.0 hours)', () {
      final r = makeRecord(
        date: DateTime(2026, 11, 11),
        checkIn: DateTime(2026, 11, 11, 8, 0),
        checkOut: DateTime(2026, 11, 11, 12, 0),
        status: 'present',
      );

      final minutes = AttendanceDeductionRules.permissionMinutesOf(
        r,
        workEndMinutes: workEnd,
        restBreakEnabled: true,
        restBreakStartMinutes: restStart,
        restBreakEndMinutes: restEnd,
      );
      expect(minutes, 240, reason: '12:00 to 17:00 is 5h, minus 1h rest window overlap = 4h permission');
    });

    test('Leaving at 13:00 docks 180 minutes (3.0 hours), NOT 240 minutes (4.0 hours)', () {
      final r = makeRecord(
        date: DateTime(2026, 11, 11),
        checkIn: DateTime(2026, 11, 11, 8, 0),
        checkOut: DateTime(2026, 11, 11, 13, 0),
        status: 'present',
      );

      final minutes = AttendanceDeductionRules.permissionMinutesOf(
        r,
        workEndMinutes: workEnd,
        restBreakEnabled: true,
        restBreakStartMinutes: restStart,
        restBreakEndMinutes: restEnd,
      );
      expect(minutes, 180, reason: '13:00 to 17:00 is 4h, minus 1h rest window overlap = 3h permission');
    });

    test('Leaving at 13:30 (during rest) docks 180 minutes (3.0 hours)', () {
      final r = makeRecord(
        date: DateTime(2026, 11, 11),
        checkIn: DateTime(2026, 11, 11, 8, 0),
        checkOut: DateTime(2026, 11, 11, 13, 30),
        status: 'present',
      );

      final minutes = AttendanceDeductionRules.permissionMinutesOf(
        r,
        workEndMinutes: workEnd,
        restBreakEnabled: true,
        restBreakStartMinutes: restStart,
        restBreakEndMinutes: restEnd,
      );
      expect(minutes, 180, reason: '13:30 to 17:00 is 3.5h, minus 30m remaining rest = 3h permission');
    });

    test('Leaving at 15:00 docks 120 minutes (2.0 hours) - no rest overlap', () {
      final r = makeRecord(
        date: DateTime(2026, 11, 11),
        checkIn: DateTime(2026, 11, 11, 8, 0),
        checkOut: DateTime(2026, 11, 11, 15, 0),
        status: 'present',
      );

      final minutes = AttendanceDeductionRules.permissionMinutesOf(
        r,
        workEndMinutes: workEnd,
        restBreakEnabled: true,
        restBreakStartMinutes: restStart,
        restBreakEndMinutes: restEnd,
      );
      expect(minutes, 120);
    });

    test('Leaving at 16:00 docks 60 minutes (1.0 hour)', () {
      final r = makeRecord(
        date: DateTime(2026, 11, 11),
        checkIn: DateTime(2026, 11, 11, 8, 0),
        checkOut: DateTime(2026, 11, 11, 16, 0),
        status: 'present',
      );

      final minutes = AttendanceDeductionRules.permissionMinutesOf(
        r,
        workEndMinutes: workEnd,
        restBreakEnabled: true,
        restBreakStartMinutes: restStart,
        restBreakEndMinutes: restEnd,
      );
      expect(minutes, 60);
    });

    test('early_leave status record is recognized as permission record', () {
      final r = makeRecord(
        date: DateTime(2026, 11, 11),
        checkIn: DateTime(2026, 11, 11, 8, 0),
        checkOut: DateTime(2026, 11, 11, 11, 0),
        status: 'early_leave',
      );
      expect(AttendanceDeductionRules.isPermissionRecord(r, workEndMinutes: workEnd), isTrue);
      final minutes = AttendanceDeductionRules.permissionMinutesOf(
        r,
        workEndMinutes: workEnd,
        restBreakEnabled: true,
        restBreakStartMinutes: restStart,
        restBreakEndMinutes: restEnd,
      );
      // 11:00 to 17:00 is 6h minus 1h rest = 5h = 300 minutes
      expect(minutes, 300);
    });
  });

  group('BUG-035: Hourly permission in notes with Arabic 12h/24h format and rest overlap', () {
    const workEnd = 17 * 60;
    const restStart = 13 * 60;
    const restEnd = 14 * 60;

    test('Permission "من 11:00 ص إلى 02:00 م" crosses rest -> 2h deducted (3h gross - 1h rest)', () {
      final r = makeRecord(
        date: DateTime(2026, 11, 11),
        checkIn: DateTime(2026, 11, 11, 8, 0),
        notes: 'إذن ساعي: من 11:00 ص إلى 02:00 م',
        status: 'excused',
      );

      final minutes = AttendanceDeductionRules.permissionMinutesOf(
        r,
        workEndMinutes: workEnd,
        restBreakEnabled: true,
        restBreakStartMinutes: restStart,
        restBreakEndMinutes: restEnd,
      );
      expect(minutes, 120);
    });

    test('Permission "من 01:00 م إلى 02:00 م" during rest hour -> 0 deduction', () {
      final r = makeRecord(
        date: DateTime(2026, 11, 11),
        checkIn: DateTime(2026, 11, 11, 8, 0),
        notes: 'إذن ساعي: من 01:00 م إلى 02:00 م',
        status: 'excused',
      );

      final minutes = AttendanceDeductionRules.permissionMinutesOf(
        r,
        workEndMinutes: workEnd,
        restBreakEnabled: true,
        restBreakStartMinutes: restStart,
        restBreakEndMinutes: restEnd,
      );
      expect(minutes, 0);
    });

    test('Permission "من 09:00 إلى 12:00" before rest -> 180 min (3h) unchanged', () {
      final r = makeRecord(
        date: DateTime(2026, 11, 11),
        checkIn: DateTime(2026, 11, 11, 8, 0),
        notes: 'من 09:00 إلى 12:00',
        status: 'excused',
      );

      final minutes = AttendanceDeductionRules.permissionMinutesOf(
        r,
        workEndMinutes: workEnd,
        restBreakEnabled: true,
        restBreakStartMinutes: restStart,
        restBreakEndMinutes: restEnd,
      );
      expect(minutes, 180);
    });

    test('Midday permission "من 11:00 ص إلى 02:00 م" is deducted even when employee checked out at 17:00', () {
      final r = makeRecord(
        date: DateTime(2026, 11, 11),
        checkIn: DateTime(2026, 11, 11, 8, 0),
        checkOut: DateTime(2026, 11, 11, 17, 0),
        notes: 'إذن ساعي: من 11:00 ص إلى 02:00 م',
        status: 'excused',
      );

      final minutes = AttendanceDeductionRules.permissionMinutesOf(
        r,
        workEndMinutes: workEnd,
        restBreakEnabled: true,
        restBreakStartMinutes: restStart,
        restBreakEndMinutes: restEnd,
      );
      expect(minutes, 120, reason: 'Midday permission must not be zeroed out just because employee stayed until 17:00');
    });

    test('Arabic-Indic numerals in permission notes "من ٠١:٠٠ م إلى ٠٣:٠٠ م" are parsed and overlap deducted', () {
      final r = makeRecord(
        date: DateTime(2026, 11, 11),
        checkIn: DateTime(2026, 11, 11, 8, 0),
        notes: 'إذن: من ٠١:٠٠ م إلى ٠٣:٠٠ م',
        status: 'excused',
      );

      final minutes = AttendanceDeductionRules.permissionMinutesOf(
        r,
        workEndMinutes: workEnd,
        restBreakEnabled: true,
        restBreakStartMinutes: restStart,
        restBreakEndMinutes: restEnd,
      );
      // 13:00 to 15:00 is 120 min, minus 13:00-14:00 rest (60 min) = 60 min net
      expect(minutes, 60);
    });

    test('Alif without hamza "الى" in permission notes "من 11:00 الى 02:00 م" is parsed', () {
      final r = makeRecord(
        date: DateTime(2026, 11, 11),
        checkIn: DateTime(2026, 11, 11, 8, 0),
        notes: 'إذن خاص: من 11:00 الى 02:00 م',
        status: 'excused',
      );

      final minutes = AttendanceDeductionRules.permissionMinutesOf(
        r,
        workEndMinutes: workEnd,
        restBreakEnabled: true,
        restBreakStartMinutes: restStart,
        restBreakEndMinutes: restEnd,
      );
      expect(minutes, 120);
    });

    test('Asymmetric PM marker "من 1:00 إلى 3:00 م" parses as afternoon 13:00 to 15:00', () {
      final r = makeRecord(
        date: DateTime(2026, 11, 11),
        checkIn: DateTime(2026, 11, 11, 8, 0),
        notes: 'إذن: من 1:00 إلى 3:00 م',
        status: 'excused',
      );

      final minutes = AttendanceDeductionRules.permissionMinutesOf(
        r,
        workEndMinutes: workEnd,
        restBreakEnabled: true,
        restBreakStartMinutes: restStart,
        restBreakEndMinutes: restEnd,
      );
      // 13:00 to 15:00 minus 13:00-14:00 rest = 60 min
      expect(minutes, 60);
    });

    test('Midday permission (11:00-14:00) plus early departure at 16:00 accumulates correctly', () {
      final r = makeRecord(
        date: DateTime(2026, 11, 11),
        checkIn: DateTime(2026, 11, 11, 8, 0),
        checkOut: DateTime(2026, 11, 11, 16, 0),
        notes: 'إذن ساعي: من 11:00 ص إلى 02:00 م',
        status: 'excused',
      );

      final minutes = AttendanceDeductionRules.permissionMinutesOf(
        r,
        workEndMinutes: workEnd,
        restBreakEnabled: true,
        restBreakStartMinutes: restStart,
        restBreakEndMinutes: restEnd,
      );
      // Midday: 120 min net + Early leave 16:00 to 17:00: 60 min net = 180 min total
      expect(minutes, 180);
    });
  });

  group('BUG-035: Payroll and deduction consistency with rest break', () {
    test('computeAttendanceDeductions calculates correct deduction amount for 12:00 leave', () {
      final staff = makeStaff(basicSalary: 6000.0); // 6000 / 30 / 8 = 25 EGP/hr
      final r = makeRecord(
        date: DateTime(2026, 11, 11),
        checkIn: DateTime(2026, 11, 11, 8, 0),
        checkOut: DateTime(2026, 11, 11, 12, 0),
        status: 'present',
      );

      final d = computeAttendanceDeductions(
        records: [r],
        staff: staff,
        weeklyPeriod: false,
        workStartMinutes: 8 * 60,
        workEndMinutes: 17 * 60,
        graceMinutes: 15,
        restBreakEnabled: true,
        restBreakStartMinutes: 13 * 60,
        restBreakEndMinutes: 14 * 60,
      );

      expect(d.totalPermissionMinutes, 240);
      expect(d.permissionDays, 1);
      // 4 hours * 25 EGP/hr = 100 EGP
      expect(d.permissionDeduction, closeTo(100.0, 0.001));
    });
  });

  group('BUG-035: Biometric sync early checkout acceptance', () {
    late AppDatabase db;
    late AttendanceDeviceDao deviceDao;
    late StaffManagementDao staffDao;
    late AttendanceSyncService syncService;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      deviceDao = AttendanceDeviceDao(db);
      staffDao = StaffManagementDao(db);
      final engine = AttendanceCalculationEngine(db, deviceDao, staffDao);
      syncService = AttendanceSyncService(
        deviceDao,
        staffDao,
        engine,
        sourceFactory: (_) => FakeSource(
          events: [
            RawAttendanceEvent(
              externalUserId: '10',
              eventTime: DateTime(2026, 11, 11, 8, 0),
              eventType: 'check_in',
            ),
            RawAttendanceEvent(
              externalUserId: '10',
              eventTime: DateTime(2026, 11, 11, 12, 0),
              eventType: 'check_out',
            ),
          ],
        ),
      );
    });

    tearDown(() => db.close());

    test('Biometric sync accepts 12:00 punch as early checkout after 08:00 checkin', () async {
      final now = DateTime.now();
      // Seed employee
      await staffDao.addStaff(
        StaffTableCompanion.insert(
          staffId: 'ST-10',
          name: 'محمد مصطفى',
          position: 'فني',
          employmentType: 'full_time',
          basicSalary: 5000.0,
          hireDate: DateTime(2026, 1, 1),
          status: 'active',
          isActive: const Value(true),
          createdAt: now,
          updatedAt: now,
        ),
      );

      // Seed device
      final deviceId = await deviceDao.addDevice(
        BiometricDevicesCompanion.insert(
          deviceCode: 'ZK-TEST',
          name: 'جهاز البصمة الرئيسي',
          connectionType: 'tcp_ip',
          ipAddress: const Value('192.168.1.201'),
          port: const Value(4370),
          createdAt: now,
          updatedAt: now,
        ),
      );

      // Seed mapping
      await deviceDao.addMapping(
        StaffBiometricMappingsCompanion.insert(
          staffId: 'ST-10',
          deviceId: deviceId,
          externalUserId: '10',
          enrollmentStatus: 'enrolled',
          createdAt: now,
          updatedAt: now,
        ),
      );

      final device = (await deviceDao.getDeviceById(deviceId))!;
      final res = await syncService.syncDevice(device);

      expect(res.error, isNull);

      final attendance = await staffDao.getAttendanceByStaff('ST-10');
      expect(attendance.length, 1);
      final rec = attendance.first;
      expect(rec.checkInTime, DateTime(2026, 11, 11, 8, 0));
      expect(rec.checkOutTime, DateTime(2026, 11, 11, 12, 0), reason: '12:00 early checkout punch must be accepted and paired');
      expect(rec.status, 'present');
      expect(rec.workingHours, closeTo(4.0, 0.001));
    });
  });

  group('BUG-035: Period repair repairs unclosed records and recomputes rest hours', () {
    late AppDatabase db;
    late StaffManagementService service;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      service = StaffManagementService(db.staffManagementDao, db);

      // Seed rest break in settings
      final now = DateTime.now();
      for (final s in [
        ('default_work_start', '08:00'),
        ('default_work_end', '17:00'),
        ('rest_break_enabled', 'true'),
        ('rest_break_start', '13:00'),
        ('rest_break_end', '14:00'),
      ]) {
        await db.into(db.attendanceSettings).insert(
              AttendanceSettingsCompanion.insert(
                settingKey: s.$1,
                settingValue: s.$2,
                createdAt: now,
                updatedAt: now,
              ),
              mode: InsertMode.insertOrReplace,
            );
      }

      await db.into(db.staffTable).insert(
            StaffTableCompanion.insert(
              staffId: 'ST-20',
              name: 'سعيد كمال',
              position: 'عامل',
              employmentType: 'full_time',
              basicSalary: 6000.0,
              hireDate: DateTime(2026, 1, 1),
              status: 'active',
              isActive: const Value(true),
              createdAt: DateTime(2026, 1, 1),
              updatedAt: DateTime(2026, 1, 1),
            ),
          );
    });

    tearDown(() => db.close());

    test('repairPeriodRecords pairs raw 12:00 punch to unclosed record and recalculates worked hours', () async {
      final workDay = DateTime(2026, 11, 10);
      final tIn = DateTime(2026, 11, 10, 8, 0);
      final tOut = DateTime(2026, 11, 10, 12, 0);

      // Unclosed record with null checkOutTime
      await db.into(db.attendanceTable).insert(
            AttendanceTableCompanion.insert(
              staffId: 'ST-20',
              date: workDay,
              status: 'present',
              checkInTime: Value(tIn),
              checkOutTime: const Value(null),
              workingHours: const Value(0.0),
              createdAt: workDay,
              updatedAt: workDay,
            ),
          );

      // Raw matched punch event in database
      await db.into(db.attendanceRawEvents).insert(
            AttendanceRawEventsCompanion.insert(
              deviceId: 1,
              externalUserId: '20',
              eventTime: tOut,
              dedupHash: 'repair-hash-1',
              status: 'matched',
              matchedStaffId: const Value('ST-20'),
              createdAt: tOut,
            ),
          );

      final result = await service.repairPeriodRecords(
        admin(),
        'ST-20',
        DateTime(2026, 11, 1),
        DateTime(2026, 11, 30),
      );

      expect(result.recomputed, 1);

      final recs = await db.staffManagementDao.getAttendanceByStaff('ST-20');
      expect(recs.length, 1);
      final repaired = recs.first;
      expect(repaired.checkOutTime, tOut);
      expect(repaired.workingHours, closeTo(4.0, 0.001));
    });

    test('repairPeriodRecords updates old early_leave (4h worked) to present under rest rules', () async {
      final workDay = DateTime(2026, 11, 11);
      final tIn = DateTime(2026, 11, 11, 8, 0);
      final tOut = DateTime(2026, 11, 11, 12, 0);

      // Previously saved as early_leave under old 9h schedule
      await db.into(db.attendanceTable).insert(
            AttendanceTableCompanion.insert(
              staffId: 'ST-20',
              date: workDay,
              status: 'early_leave',
              checkInTime: Value(tIn),
              checkOutTime: Value(tOut),
              workingHours: const Value(4.0),
              createdAt: workDay,
              updatedAt: workDay,
            ),
          );

      final result = await service.repairPeriodRecords(
        admin(),
        'ST-20',
        DateTime(2026, 11, 1),
        DateTime(2026, 11, 30),
      );

      expect(result.recomputed, 1);

      final recs = await db.staffManagementDao.getAttendanceByStaff('ST-20');
      final repaired = recs.firstWhere((r) => r.date == workDay);
      expect(repaired.status, 'present', reason: '4.0h worked equals 8h net standard day * 0.5, must be present');
    });
  });

  group('BUG-035: Overnight shifts and rest window crossing midnight', () {
    test('calculateWindowOverlap with overnight shift (22:00 -> 06:00) and rest (02:00 -> 03:00)', () {
      final overlap = AttendanceDeductionRules.calculateWindowOverlap(
        windowAStart: 22 * 60, // 1320
        windowAEnd: 6 * 60 + 1440, // 1800
        windowBStart: 2 * 60, // 120
        windowBEnd: 3 * 60, // 180
      );
      expect(overlap, 60);
    });

    test('calculateWindowOverlap with rest break crossing midnight (23:30 -> 00:30)', () {
      final overlap = AttendanceDeductionRules.calculateWindowOverlap(
        windowAStart: 20 * 60, // 1200
        windowAEnd: 4 * 60 + 1440, // 1680
        windowBStart: 23 * 60 + 30, // 1410
        windowBEnd: 30, // 00:30
      );
      expect(overlap, 60);
    });

    test('AttendanceCalculationEngine calculates overnight 22:00 -> 06:00 net 7.0h worked with 1h rest', () {
      final db = AppDatabase(NativeDatabase.memory());
      final engine = AttendanceCalculationEngine(
        db,
        db.attendanceDeviceDao,
        db.staffManagementDao,
      );

      const overnightSched = ScheduleConfig(
        workStartHour: 22,
        workStartMinute: 0,
        workEndHour: 6,
        workEndMinute: 0,
        workDays: [0, 1, 2, 3, 4, 5, 6],
        weekendDay: 5,
        gracePeriodMinutes: 15,
        standardHoursPerDay: 7,
        overtimeRateMultiplier: 1.5,
        restBreakEnabled: true,
        restBreakStartHour: 2,
        restBreakStartMinute: 0,
        restBreakEndHour: 3,
        restBreakEndMinute: 0,
      );

      final res = engine.calculateAttendance(
        checkInTime: DateTime(2026, 11, 11, 22, 0),
        checkOutTime: DateTime(2026, 11, 12, 6, 0),
        schedule: overnightSched,
      );
      expect(res.workingHours, closeTo(7.0, 0.001));
      db.close();
    });
  });

  group('BUG-035: StaffManagementDao.checkOut rest overlap consistency', () {
    test('DAO checkOut deducts rest overlap when workingHours not explicitly passed', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final now = DateTime.now();

      await (db.update(db.attendanceSettings)
            ..where((s) => s.settingKey.equals('rest_break_enabled')))
          .write(
        const AttendanceSettingsCompanion(settingValue: Value('true')),
      );
      await (db.update(db.attendanceSettings)
            ..where((s) => s.settingKey.equals('rest_break_start')))
          .write(
        const AttendanceSettingsCompanion(settingValue: Value('13:00')),
      );
      await (db.update(db.attendanceSettings)
            ..where((s) => s.settingKey.equals('rest_break_end')))
          .write(
        const AttendanceSettingsCompanion(settingValue: Value('14:00')),
      );

      await db.into(db.staffTable).insert(
            StaffTableCompanion.insert(
              staffId: 'ST-DAO-1',
              name: 'محمد علي',
              position: 'فني',
              employmentType: 'full_time',
              basicSalary: 6000.0,
              hireDate: DateTime(2026, 1, 1),
              status: 'active',
              isActive: const Value(true),
              createdAt: DateTime(2026, 1, 1),
              updatedAt: DateTime(2026, 1, 1),
            ),
          );

      final today = DateTime(now.year, now.month, now.day);
      // Checkin at 08:00 today
      final checkInTime = DateTime(now.year, now.month, now.day, 8, 0);

      await db.into(db.attendanceTable).insert(
            AttendanceTableCompanion.insert(
              staffId: 'ST-DAO-1',
              date: today,
              status: 'present',
              checkInTime: Value(checkInTime),
              createdAt: today,
              updatedAt: today,
            ),
          );

      // Perform checkout directly via DAO without workingHours
      final success = await db.staffManagementDao.checkOut('ST-DAO-1');
      expect(success, isTrue);

      final recs = await db.staffManagementDao.getAttendanceByStaff('ST-DAO-1');
      expect(recs.length, 1);
      final r = recs.first;
      expect(r.checkOutTime, isNotNull);
      // If checked out after 14:00, rest overlap (60m) must be deducted
      final rawMinutes = r.checkOutTime!.difference(checkInTime).inMinutes;
      if (r.checkOutTime!.hour >= 14) {
        expect(r.workingHours, closeTo((rawMinutes - 60) / 60.0, 0.05));
      }

      await db.close();
    });
  });
}
