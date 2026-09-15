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

  Future<List<StaffBiometricMapping>> getAllMappings() => select(staffBiometricMappings).get();

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

  /// Retryable raw events: 'pending' (never processed) + 'error'
  /// (per-event failure, safe to retry). 'matched'/'ignored' are terminal.
  Future<List<AttendanceRawEvent>> getRetryableEventsForDevice(
          int deviceId) =>
      (select(attendanceRawEvents)
            ..where((e) =>
                e.deviceId.equals(deviceId) &
                (e.status.equals('pending') | e.status.equals('error'))))
          .get();

  /// History of already-matched events for one staff in [from, to).
  /// Used by group recompute so late/out-of-order events re-derive the same
  /// attendance deterministically instead of appending blindly.
  Future<List<AttendanceRawEvent>> getMatchedEventsForStaff(
          int deviceId, String staffId, DateTime from, DateTime to) =>
      (select(attendanceRawEvents)
            ..where((e) =>
                e.deviceId.equals(deviceId) &
                e.matchedStaffId.equals(staffId) &
                e.eventTime.isBiggerOrEqualValue(from) &
                e.eventTime.isSmallerThanValue(to) &
                e.status.equals('matched')))
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

  /// Latest sync log for one device (for truthful UI messages:
  /// success vs success_no_new_records vs partial vs failed).
  Future<AttendanceSyncLog?> getLatestSyncLogForDevice(int deviceId) =>
      (select(attendanceSyncLogs)
            ..where((l) => l.deviceId.equals(deviceId))
            ..orderBy([
              (t) => OrderingTerm(expression: t.startedAt, mode: OrderingMode.desc)
            ])
            ..limit(1))
          .getSingleOrNull();

  /// Returns the still-open sync for [deviceId] started after [since], if any.
  /// Used as a DB-backed concurrency guard (manual vs auto overlap).
  Future<AttendanceSyncLog?> getRunningLogForDevice(
          int deviceId, DateTime since) =>
      (select(attendanceSyncLogs)
            ..where((l) =>
                l.deviceId.equals(deviceId) &
                l.status.equals('running') &
                l.startedAt.isBiggerThanValue(since)))
          .getSingleOrNull();

  /// Closes orphaned 'running' logs from crashed/interrupted syncs so they
  /// never block future runs. Returns the number of logs recovered.
  Future<int> markStaleRunningFailed(DateTime cutoff, String errorMessage) =>
      (update(attendanceSyncLogs)
            ..where((l) =>
                l.status.equals('running') &
                l.startedAt.isSmallerThanValue(cutoff)))
          .write(AttendanceSyncLogsCompanion(
        status: const Value('failed'),
        finishedAt: Value(DateTime.now()),
        errorMessage: Value(errorMessage),
      ));
}
