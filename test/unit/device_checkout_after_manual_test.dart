import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart' hide isNotNull, isNull;
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/services/attendance/attendance_calculation_engine.dart';
import 'package:pos_offline_desktop/services/attendance/attendance_sync_service.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

void main() {
  late AppDatabase db;
  setUp(() async { db = AppDatabase(NativeDatabase.memory()); });
  tearDown(() async => await db.close());

  test('Manual 09:00 then device 17:00 keeps checkIn and sets checkOut', () async {
    final staffDao = db.staffManagementDao;
    final deviceDao = db.attendanceDeviceDao;
    final staffId = 'STAFF0001';
    await staffDao.addStaff(StaffTableCompanion.insert(
      staffId: staffId, name: 'Test', position: 'Cashier', employmentType: 'Full', basicSalary: 3000,
      hireDate: DateTime.now(), status: 'active', createdAt: DateTime.now(), updatedAt: DateTime.now(),
    ));
    final deviceId = await deviceDao.addDevice(BiometricDevicesCompanion.insert(
      deviceCode: 'DEV1', name: 'TestDevice', connectionType: 'tcp_ip', ipAddress: Value('192.168.1.201'), port: Value(4370), createdAt: DateTime.now(), updatedAt: DateTime.now(),
    ));
    await deviceDao.addMapping(StaffBiometricMappingsCompanion.insert(
      staffId: staffId, deviceId: deviceId, externalUserId: '1', enrollmentStatus: 'enrolled', createdAt: DateTime.now(), updatedAt: DateTime.now(),
    ));
    final today = DateTime.now();
    final dateOnly = DateTime(today.year, today.month, today.day);
    final checkInManual = DateTime(today.year, today.month, today.day, 9, 0);
    // Manual attendance via DAO directly (simulates svc.recordManualAttendance)
    await staffDao.addAttendance(AttendanceTableCompanion.insert(
      staffId: staffId, date: dateOnly, status: 'present', checkInTime: Value(checkInManual), createdAt: DateTime.now(), updatedAt: DateTime.now(),
    ));
    var rec1 = (await staffDao.getAttendanceOnDate(staffId, dateOnly)).first;
    print('after manual: in=${rec1.checkInTime} out=${rec1.checkOutTime}');
    expect(rec1.checkInTime!.hour, 9);
    expect(rec1.checkOutTime, isNull);

    final deviceTime = DateTime(today.year, today.month, today.day, 17, 0);
    final hash = sha256.convert(utf8.encode('${deviceId}_1_${deviceTime.toIso8601String()}')).toString();
    await deviceDao.addRawEvent(AttendanceRawEventsCompanion.insert(
      deviceId: deviceId, externalUserId: '1', eventTime: deviceTime, dedupHash: hash, status: 'pending', createdAt: DateTime.now(),
    ));
    final engine = AttendanceCalculationEngine(db, deviceDao, staffDao);
    final sync = AttendanceSyncService(deviceDao, staffDao, engine);
    final res = await sync.processPendingEvents(deviceId);
    print('sync result matched=${res.matched} unmatched=${res.unmatched}');
    var rec2 = (await staffDao.getAttendanceOnDate(staffId, dateOnly)).first;
    print('after device: in=${rec2.checkInTime} out=${rec2.checkOutTime} wh=${rec2.workingHours}');
    expect(rec2.checkInTime, isNotNull);
    expect(rec2.checkInTime!.hour, 9, reason: 'checkIn must stay 09:00');
    expect(rec2.checkOutTime, isNotNull);
    expect(rec2.checkOutTime!.hour, 17, reason: 'checkOut must be 17:00 not swapped');
    expect(rec2.checkInTime!.isBefore(rec2.checkOutTime!), isTrue);
  });
}
