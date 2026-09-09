import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/dao/attendance_device_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/staff_management_dao.dart';
import 'package:pos_offline_desktop/services/attendance/attendance_calculation_engine.dart';
import 'package:pos_offline_desktop/services/attendance/attendance_sync_service.dart';

/// يتحقق أن مسار الحضور من جهاز البصمة يستخدم نفس محرك الحساب (AttendanceCalculationEngine)
/// المستخدم في المسار اليدوي: بصمة الساعة 12 تبقى 'late'، والخروج بعد 9 ساعات يعطي overtime.
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

  test(
    'fingerprint at 12:00 is late, not present (default schedule 9:00 + 15 min grace)',
    () async {
      final staffId = await addStaff(staffDao, 'STAFF0001');
      final deviceId = await addDevice(deviceDao);
      await addMapping(deviceDao, deviceId, staffId, 'UID-001');

      final checkInTime = DateTime(2026, 1, 14, 12, 0);
      await addRawEvent(
        deviceDao,
        deviceId,
        'UID-001',
        checkInTime,
        'hash-checkin-1',
      );

      final result = await syncService.processPendingEvents(deviceId);
      expect(result.matched, 1);

      final records = await staffDao.getAttendanceByStaff(staffId);
      expect(records, hasLength(1));
      expect(records.first.status, 'late');
      expect(records.first.checkInTime, checkInTime);
      expect(records.first.source, 'device');
      expect(records.first.sourceDeviceId, deviceId);
      expect(records.first.rawEventId, isNotNull);
    },
  );

  test(
    'check-out after 9 hours writes overtimeHours > 0 in the device record, same as engine',
    () async {
      final staffId = await addStaff(staffDao, 'STAFF0002');
      final deviceId = await addDevice(deviceDao);
      await addMapping(deviceDao, deviceId, staffId, 'UID-002');

      final checkInTime = DateTime(2026, 1, 14, 12, 0);
      final checkOutTime = DateTime(2026, 1, 14, 21, 0); // 9 hours later
      await addRawEvent(
        deviceDao,
        deviceId,
        'UID-002',
        checkInTime,
        'hash-checkin-2',
      );
      await addRawEvent(
        deviceDao,
        deviceId,
        'UID-002',
        checkOutTime,
        'hash-checkout-2',
      );

      final expected = await engine.processCheckOut(
        staffId,
        checkInTime: checkInTime,
        checkOutTime: checkOutTime,
      );

      await syncService.processPendingEvents(deviceId);

      final records = await staffDao.getAttendanceByStaff(staffId);
      expect(records, hasLength(1));
      final record = records.first;
      expect(record.status, expected.status);
      expect(record.workingHours, expected.workingHours);
      expect(record.overtimeHours, expected.overtimeHours);
      // دوام 12:00→21:00 = 9 ساعات إجمالي − ساعة بريك = 8.0 ساعات فعلية، ووقت إضافي بعد نهاية الدوام 17:00 + 30 دقيقة مهلة = 3.5
      expect(record.workingHours, 8.0);
      expect(record.overtimeHours, greaterThan(0));
      expect(record.overtimeHours, 3.5);
      expect(record.checkOutTime, checkOutTime);
      expect(record.source, 'device');
      expect(record.sourceDeviceId, deviceId);
      expect(record.rawEventId, isNotNull);
    },
  );

  test(
    'device path and manual path produce identical status and working hours for the same times',
    () async {
      // Fixed times (deterministic): the device checkout policy is
      // schedule-aware, so wall-clock "now" punches would make this test
      // time-of-day dependent. Both sides use the same engine + fixed pair.
      final date = DateTime(2026, 1, 14);
      final checkInTime = DateTime(2026, 1, 14, 9, 0);
      final checkOutTime = DateTime(2026, 1, 14, 17, 0);

      final manualStaff = await addStaff(staffDao, 'STAFF0003');
      final deviceStaff = await addStaff(staffDao, 'STAFF0004');
      final deviceId = await addDevice(deviceDao);
      await addMapping(deviceDao, deviceId, deviceStaff, 'UID-003');

      // Manual path: same engine calculation, stored via DAO.
      final expected = await engine.processCheckOut(
        manualStaff,
        checkInTime: checkInTime,
        checkOutTime: checkOutTime,
      );
      await staffDao.addAttendance(
        AttendanceTableCompanion.insert(
          staffId: manualStaff,
          date: date,
          status: expected.status,
          checkInTime: Value(checkInTime),
          checkOutTime: Value(checkOutTime),
          workingHours: Value(expected.workingHours),
          overtimeHours: Value(expected.overtimeHours),
          source: const Value('manual'),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
      final manualRecord = (await staffDao.getAttendanceByStaff(
        manualStaff,
      )).first;
      expect(manualRecord.checkInTime, isNotNull);
      expect(manualRecord.checkOutTime, isNotNull);

      // Device path: feed the exact same check-in/check-out times via raw events
      await addRawEvent(
        deviceDao,
        deviceId,
        'UID-003',
        checkInTime,
        'hash-manual-dev-1',
      );
      await addRawEvent(
        deviceDao,
        deviceId,
        'UID-003',
        checkOutTime,
        'hash-manual-dev-2',
      );
      await syncService.processPendingEvents(deviceId);

      final deviceRecords = await staffDao.getAttendanceByStaff(deviceStaff);
      expect(deviceRecords, hasLength(1));
      final deviceRecord = deviceRecords.first;

      expect(
        deviceRecord.status,
        manualRecord.status,
        reason:
            'device and manual paths must compute the same status for the same times',
      );
      expect(
        deviceRecord.workingHours,
        manualRecord.workingHours,
        reason:
            'device and manual paths must compute the same working hours for the same times',
      );
      expect(
        deviceRecord.overtimeHours,
        manualRecord.overtimeHours,
        reason:
            'device and manual paths must compute the same overtime for the same times',
      );
      expect(deviceRecord.source, 'device');
      expect(deviceRecord.sourceDeviceId, deviceId);
      expect(deviceRecord.rawEventId, isNotNull);
    },
  );
}

Future<String> addStaff(StaffManagementDao staffDao, String staffId) async {
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
  return staffId;
}

Future<int> addDevice(AttendanceDeviceDao deviceDao) async {
  return deviceDao.addDevice(
    BiometricDevicesCompanion.insert(
      deviceCode: 'BIO-001',
      name: 'Test Device',
      connectionType: 'tcp_ip',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ),
  );
}

Future<void> addMapping(
  AttendanceDeviceDao deviceDao,
  int deviceId,
  String staffId,
  String externalUserId,
) async {
  await deviceDao.addMapping(
    StaffBiometricMappingsCompanion.insert(
      staffId: staffId,
      deviceId: deviceId,
      externalUserId: externalUserId,
      enrollmentStatus: 'enrolled',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ),
  );
}

Future<void> addRawEvent(
  AttendanceDeviceDao deviceDao,
  int deviceId,
  String externalUserId,
  DateTime eventTime,
  String hash,
) async {
  await deviceDao.addRawEvent(
    AttendanceRawEventsCompanion.insert(
      deviceId: deviceId,
      externalUserId: externalUserId,
      eventTime: eventTime,
      dedupHash: hash,
      status: 'pending',
      createdAt: DateTime.now(),
    ),
  );
}

Future<void> insertDefaultAttendanceSettings(AppDatabase appDb) async {
  // نفس القيم الافتراضية المدخلة في migration v48
  final now = DateTime.now();
  final settings = [
    ('default_work_start', '09:00'),
    ('default_work_end', '17:00'),
    ('default_work_days', 'sun,mon,tue,wed,thu'),
    ('default_weekend', 'fri'),
    ('grace_period_minutes', '15'),
    ('overtime_threshold_hours', '8'),
    ('overtime_rate_multiplier', '1.5'),
    ('overtime_grace_minutes', '30'), // مهلة بدء الإضافي (v67)
    ('break_minutes', '60'), // ساعة بريك تُخصم من ساعات العمل الفعلية
  ];
  for (final entry in settings) {
    await appDb
        .into(appDb.attendanceSettings)
        .insert(
          AttendanceSettingsCompanion.insert(
            settingKey: entry.$1,
            settingValue: entry.$2,
            createdAt: now,
            updatedAt: now,
          ),
        );
  }
}
