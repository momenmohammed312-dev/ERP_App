// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'attendance_device_dao.dart';

// ignore_for_file: type=lint
mixin _$AttendanceDeviceDaoMixin on DatabaseAccessor<AppDatabase> {
  $BiometricDevicesTable get biometricDevices =>
      attachedDatabase.biometricDevices;
  $StaffBiometricMappingsTable get staffBiometricMappings =>
      attachedDatabase.staffBiometricMappings;
  $AttendanceRawEventsTable get attendanceRawEvents =>
      attachedDatabase.attendanceRawEvents;
  $AttendanceSyncLogsTable get attendanceSyncLogs =>
      attachedDatabase.attendanceSyncLogs;
  AttendanceDeviceDaoManager get managers => AttendanceDeviceDaoManager(this);
}

class AttendanceDeviceDaoManager {
  final _$AttendanceDeviceDaoMixin _db;
  AttendanceDeviceDaoManager(this._db);
  $$BiometricDevicesTableTableManager get biometricDevices =>
      $$BiometricDevicesTableTableManager(
        _db.attachedDatabase,
        _db.biometricDevices,
      );
  $$StaffBiometricMappingsTableTableManager get staffBiometricMappings =>
      $$StaffBiometricMappingsTableTableManager(
        _db.attachedDatabase,
        _db.staffBiometricMappings,
      );
  $$AttendanceRawEventsTableTableManager get attendanceRawEvents =>
      $$AttendanceRawEventsTableTableManager(
        _db.attachedDatabase,
        _db.attendanceRawEvents,
      );
  $$AttendanceSyncLogsTableTableManager get attendanceSyncLogs =>
      $$AttendanceSyncLogsTableTableManager(
        _db.attachedDatabase,
        _db.attendanceSyncLogs,
      );
}
