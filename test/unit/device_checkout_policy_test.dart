import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/dao/attendance_device_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/staff_management_dao.dart';
import 'package:pos_offline_desktop/services/attendance/attendance_calculation_engine.dart';
import 'package:pos_offline_desktop/services/attendance/attendance_sync_service.dart';

/// Locks the payroll-safe checkout policy (plan patch):
/// - 10min duplicate window (morning bursts never become checkout)
/// - checkout threshold = max(checkIn + 4h, scheduledEnd - 2h)
///   (default schedule 09:00-17:00 → threshold 15:00)
/// - checkout = latest event at/after threshold, else none (stays open)
void main() {
  late AppDatabase db;
  late StaffManagementDao staffDao;
  late AttendanceDeviceDao deviceDao;
  late AttendanceSyncService syncService;
  late AttendanceCalculationEngine engine;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    staffDao = db.staffManagementDao;
    deviceDao = db.attendanceDeviceDao;
    engine = AttendanceCalculationEngine(db, deviceDao, staffDao);
    await insertDefaultAttendanceSettings(db);
    syncService = AttendanceSyncService(deviceDao, staffDao, engine);
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> setupDevice(String staffId, String extId) async {
    await staffDao.addStaff(
      StaffTableCompanion.insert(
        staffId: staffId,
        name: 'Test Staff',
        position: 'Cashier',
        employmentType: 'Full',
        basicSalary: 3000,
        hireDate: DateTime.now(),
        status: 'active',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
    final deviceId = await deviceDao.addDevice(
      BiometricDevicesCompanion.insert(
        deviceCode: 'BIO-$staffId',
        name: 'Test Device',
        connectionType: 'tcp_ip',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
    await deviceDao.addMapping(
      StaffBiometricMappingsCompanion.insert(
        staffId: staffId,
        deviceId: deviceId,
        externalUserId: extId,
        enrollmentStatus: 'enrolled',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
    return deviceId;
  }

  Future<void> punch(
    int deviceId,
    String extId,
    DateTime time,
    String hash,
  ) async {
    await deviceDao.addRawEvent(
      AttendanceRawEventsCompanion.insert(
        deviceId: deviceId,
        externalUserId: extId,
        eventTime: time,
        dedupHash: hash,
        status: 'pending',
        createdAt: DateTime.now(),
      ),
    );
  }

  test('09:00 + 10:05 stays open — no false checkout', () async {
    final deviceId = await setupDevice('STAFF0001', 'U1');
    await punch(deviceId, 'U1', DateTime(2026, 1, 14, 9, 0), 'p1-a');
    await punch(deviceId, 'U1', DateTime(2026, 1, 14, 10, 5), 'p1-b');

    final res = await syncService.processPendingEvents(deviceId);
    expect(res.matched, 2);
    expect(res.unmatched, 0);

    final records = await staffDao.getAttendanceByStaff('STAFF0001');
    expect(records, hasLength(1));
    expect(records.first.checkInTime, DateTime(2026, 1, 14, 9, 0));
    expect(records.first.checkOutTime, isNull);
  });

  test('09:00 + 10:05 + 17:00 → checkout is 17:00 only', () async {
    final deviceId = await setupDevice('STAFF0002', 'U2');
    await punch(deviceId, 'U2', DateTime(2026, 1, 14, 9, 0), 'p2-a');
    await punch(deviceId, 'U2', DateTime(2026, 1, 14, 10, 5), 'p2-b');
    await punch(deviceId, 'U2', DateTime(2026, 1, 14, 17, 0), 'p2-c');

    await syncService.processPendingEvents(deviceId);

    final records = await staffDao.getAttendanceByStaff('STAFF0002');
    expect(records, hasLength(1));
    expect(records.first.checkInTime, DateTime(2026, 1, 14, 9, 0));
    expect(records.first.checkOutTime, DateTime(2026, 1, 14, 17, 0));
  });

  test('09:00 + 12:00 alone stays open (no assumed half-day checkout)',
      () async {
    final deviceId = await setupDevice('STAFF0003', 'U3');
    await punch(deviceId, 'U3', DateTime(2026, 1, 14, 9, 0), 'p3-a');
    await punch(deviceId, 'U3', DateTime(2026, 1, 14, 12, 0), 'p3-b');

    await syncService.processPendingEvents(deviceId);

    final records = await staffDao.getAttendanceByStaff('STAFF0003');
    expect(records, hasLength(1));
    expect(records.first.checkOutTime, isNull);
  });

  test('09:00 + 09:30 + 17:00 → checkout 17:00, middle superseded',
      () async {
    final deviceId = await setupDevice('STAFF0004', 'U4');
    await punch(deviceId, 'U4', DateTime(2026, 1, 14, 9, 0), 'p4-a');
    await punch(deviceId, 'U4', DateTime(2026, 1, 14, 9, 30), 'p4-b');
    await punch(deviceId, 'U4', DateTime(2026, 1, 14, 17, 0), 'p4-c');

    await syncService.processPendingEvents(deviceId);

    final records = await staffDao.getAttendanceByStaff('STAFF0004');
    expect(records, hasLength(1));
    expect(records.first.checkInTime, DateTime(2026, 1, 14, 9, 0));
    expect(records.first.checkOutTime, DateTime(2026, 1, 14, 17, 0));
  });

  test('morning burst → single check-in, no checkout, no duplicates',
      () async {
    final deviceId = await setupDevice('STAFF0005', 'U5');
    await punch(deviceId, 'U5', DateTime(2026, 1, 14, 8, 59, 50), 'p5-a');
    await punch(deviceId, 'U5', DateTime(2026, 1, 14, 8, 59, 51), 'p5-b');
    await punch(deviceId, 'U5', DateTime(2026, 1, 14, 8, 59, 53), 'p5-c');
    await punch(deviceId, 'U5', DateTime(2026, 1, 14, 9, 0, 1), 'p5-d');

    final res = await syncService.processPendingEvents(deviceId);
    expect(res.matched, 4);

    final records = await staffDao.getAttendanceByStaff('STAFF0005');
    expect(records, hasLength(1));
    expect(records.first.checkInTime, DateTime(2026, 1, 14, 8, 59, 50));
    expect(records.first.checkOutTime, isNull);
  });

  test('out-of-order 17:00, 09:00, 09:05 → 09:00 in, 17:00 out', () async {
    final deviceId = await setupDevice('STAFF0006', 'U6');
    await punch(deviceId, 'U6', DateTime(2026, 1, 14, 17, 0), 'p6-a');
    await punch(deviceId, 'U6', DateTime(2026, 1, 14, 9, 0), 'p6-b');
    await punch(deviceId, 'U6', DateTime(2026, 1, 14, 9, 5), 'p6-c');

    await syncService.processPendingEvents(deviceId);

    final records = await staffDao.getAttendanceByStaff('STAFF0006');
    expect(records, hasLength(1));
    expect(records.first.checkInTime, DateTime(2026, 1, 14, 9, 0));
    expect(records.first.checkOutTime, DateTime(2026, 1, 14, 17, 0));
  });

  test('reprocessing is idempotent — second run changes nothing', () async {
    final deviceId = await setupDevice('STAFF0007', 'U7');
    await punch(deviceId, 'U7', DateTime(2026, 1, 14, 9, 0), 'p7-a');
    await punch(deviceId, 'U7', DateTime(2026, 1, 14, 17, 0), 'p7-b');

    await syncService.processPendingEvents(deviceId);
    final second = await syncService.processPendingEvents(deviceId);
    expect(second.matched, 0);

    final records = await staffDao.getAttendanceByStaff('STAFF0007');
    expect(records, hasLength(1));
    expect(records.first.checkInTime, DateTime(2026, 1, 14, 9, 0));
    expect(records.first.checkOutTime, DateTime(2026, 1, 14, 17, 0));
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
    ('break_minutes', '60'), // ساعة بريك تُخصم من ساعات العمل الفعلية
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
