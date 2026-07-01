import 'package:drift/drift.dart';

/// Registry of physical biometric/attendance capture devices
@DataClassName('BiometricDevice')
class BiometricDevices extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get deviceCode => text().unique()(); // internal unique code, e.g. 'BIO-001'

  TextColumn get name => text()(); // friendly name, e.g. 'Main Entrance Terminal'

  TextColumn get vendor => text().nullable()(); // e.g. 'ZKTeco', 'Hikvision'

  TextColumn get model => text().nullable()();

  TextColumn get connectionType => text()(); // 'tcp_ip' | 'usb_import' | 'sdk' | 'file_import'

  TextColumn get ipAddress => text().nullable()();

  IntColumn get port => integer().nullable()();

  TextColumn get serialNumber => text().nullable()();

  TextColumn get location => text().nullable()(); // physical branch/location label

  TextColumn get authToken => text().nullable()(); // if device/SDK requires a key

  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  DateTimeColumn get lastSyncAt => dateTime().nullable()();

  TextColumn get lastSyncStatus => text().nullable()(); // 'success' | 'failed' | 'partial'

  TextColumn get lastSyncError => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();

  DateTimeColumn get updatedAt => dateTime()();
}

/// Links a staff member to their enrolled identity on a specific device
@DataClassName('StaffBiometricMapping')
class StaffBiometricMappings extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get staffId => text()(); // references StaffTable.staffId (TEXT business id)

  IntColumn get deviceId => integer()(); // references BiometricDevices.id

  TextColumn get externalUserId => text()(); // the user/employee ID as known BY THE DEVICE

  TextColumn get cardNumber => text().nullable()();

  IntColumn get fingerIndex => integer().nullable()(); // which finger was enrolled, if applicable

  TextColumn get templateRef => text().nullable()(); // opaque reference to biometric template, never raw biometric data

  TextColumn get enrollmentStatus => text()(); // 'pending' | 'enrolled' | 'failed' | 'revoked'

  BoolColumn get isPrimary => boolean().withDefault(const Constant(false))();

  DateTimeColumn get enrolledAt => dateTime().nullable()();

  DateTimeColumn get createdAt => dateTime()();

  DateTimeColumn get updatedAt => dateTime()();
}

/// Unprocessed events as received from a device, before normalization/matching
@DataClassName('AttendanceRawEvent')
class AttendanceRawEvents extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get deviceId => integer()(); // references BiometricDevices.id

  TextColumn get externalUserId => text()(); // raw ID as reported by the device

  DateTimeColumn get eventTime => dateTime()();

  TextColumn get eventType => text().nullable()(); // 'check_in' | 'check_out' | 'unknown' (device may not say)

  TextColumn get rawPayload => text().nullable()(); // original payload (JSON/text) for debugging/replay

  TextColumn get syncBatchId => text().nullable()(); // groups events from one sync run

  TextColumn get dedupHash => text().unique()(); // sha256(deviceId + externalUserId + eventTime) to prevent duplicate ingestion

  TextColumn get status => text()(); // 'pending' | 'matched' | 'unmatched' | 'processed' | 'ignored' | 'error'

  TextColumn get matchedStaffId => text().nullable()(); // set once matched

  IntColumn get resultingAttendanceId => integer().nullable()(); // FK to attendance_table.id once processed

  TextColumn get errorMessage => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();

  DateTimeColumn get processedAt => dateTime().nullable()();
}

/// Audit trail of every sync attempt against a device
@DataClassName('AttendanceSyncLog')
class AttendanceSyncLogs extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get deviceId => integer()();

  TextColumn get syncBatchId => text()();

  DateTimeColumn get startedAt => dateTime()();

  DateTimeColumn get finishedAt => dateTime().nullable()();

  TextColumn get status => text()(); // 'running' | 'success' | 'failed' | 'partial'

  IntColumn get eventsFetched => integer().withDefault(const Constant(0))();

  IntColumn get eventsMatched => integer().withDefault(const Constant(0))();

  IntColumn get eventsUnmatched => integer().withDefault(const Constant(0))();

  IntColumn get eventsDuplicate => integer().withDefault(const Constant(0))();

  TextColumn get errorMessage => text().nullable()();

  TextColumn get triggeredBy => text().nullable()(); // 'scheduler' | 'manual' | username
}
