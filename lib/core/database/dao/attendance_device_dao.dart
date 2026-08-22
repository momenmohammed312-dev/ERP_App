import 'package:drift/drift.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/tables/attendance_device_tables.dart';

part 'attendance_device_dao.g.dart';

@DriftAccessor(tables: [
  BiometricDevices,
  StaffBiometricMappings,
  AttendanceRawEvents,
  AttendanceSyncLogs,
])
class AttendanceDeviceDao extends DatabaseAccessor<AppDatabase>
    with _$AttendanceDeviceDaoMixin {
  AttendanceDeviceDao(super.db);

  // --- Devices ---

  Future<List<BiometricDevice>> getAllDevices() => select(biometricDevices).get();

  Future<BiometricDevice?> getDeviceById(int id) =>
      (select(biometricDevices)..where((d) => d.id.equals(id))).getSingleOrNull();

  Future<int> addDevice(BiometricDevicesCompanion entry) =>
      into(biometricDevices).insert(entry);

  Future<bool> updateDevice(BiometricDevice device) =>
      update(biometricDevices).replace(device);

  Future<int> deleteDevice(int id) =>
      (delete(biometricDevices)..where((d) => d.id.equals(id))).go();

  // --- Mappings ---

  Future<List<StaffBiometricMapping>> getMappingsForStaff(String staffId) =>
      (select(staffBiometricMappings)..where((m) => m.staffId.equals(staffId))).get();

  Future<List<StaffBiometricMapping>> getMappingsForDevice(int deviceId) =>
      (select(staffBiometricMappings)..where((m) => m.deviceId.equals(deviceId))).get();

  Future<StaffBiometricMapping?> getMappingByExternalId(
          int deviceId, String externalUserId) =>
      (select(staffBiometricMappings)
            ..where((m) =>
                m.deviceId.equals(deviceId) &
                m.externalUserId.equals(externalUserId) &
                m.enrollmentStatus.equals('enrolled')))
          .getSingleOrNull();

  Future<int> addMapping(StaffBiometricMappingsCompanion entry) =>
      into(staffBiometricMappings).insert(entry);

  Future<bool> updateMapping(StaffBiometricMapping mapping) =>
      update(staffBiometricMappings).replace(mapping);

  Future<int> deleteMapping(int id) =>
      (delete(staffBiometricMappings)..where((m) => m.id.equals(id))).go();

  // --- Raw Events ---

  Future<int> addRawEvent(AttendanceRawEventsCompanion entry) =>
      into(attendanceRawEvents).insert(entry, mode: InsertMode.insertOrIgnore); // Ignores duplicate dedupHash

  Future<List<AttendanceRawEvent>> getUnprocessedEvents() =>
      (select(attendanceRawEvents)..where((e) => e.status.equals('pending')))
          .get();

  Future<List<AttendanceRawEvent>> getUnprocessedEventsForDevice(int deviceId) =>
      (select(attendanceRawEvents)
            ..where((e) => e.status.equals('pending') & e.deviceId.equals(deviceId)))
          .get();

  Future<List<AttendanceRawEvent>> getUnmatchedEvents() =>
      (select(attendanceRawEvents)..where((e) => e.status.equals('unmatched')))
          .get();

  Future<bool> updateRawEvent(AttendanceRawEvent event) =>
      update(attendanceRawEvents).replace(event);

  // --- Sync Logs ---

  Future<int> addSyncLog(AttendanceSyncLogsCompanion entry) =>
      into(attendanceSyncLogs).insert(entry);

  Future<bool> updateSyncLog(AttendanceSyncLog log) =>
      update(attendanceSyncLogs).replace(log);

  Future<AttendanceSyncLog?> getSyncLogById(int id) =>
      (select(attendanceSyncLogs)..where((l) => l.id.equals(id)))
          .getSingleOrNull();

  Future<List<AttendanceSyncLog>> getRecentSyncLogs(int limit) =>
      (select(attendanceSyncLogs)
            ..orderBy([(t) => OrderingTerm(expression: t.startedAt, mode: OrderingMode.desc)])
            ..limit(limit))
          .get();
}
