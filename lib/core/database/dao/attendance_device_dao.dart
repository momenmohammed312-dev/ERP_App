import 'package:drift/drift.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/tables/attendance_device_tables.dart';

part 'attendance_device_dao.g.dart';

@DriftAccessor(
  tables: [
    BiometricDevices,
    StaffBiometricMappings,
    AttendanceRawEvents,
    AttendanceSyncLogs,
  ],
)
class AttendanceDeviceDao extends DatabaseAccessor<AppDatabase>
    with _$AttendanceDeviceDaoMixin {
  AttendanceDeviceDao(super.db);

  // --- Devices ---

  Future<List<BiometricDevice>> getAllDevices() =>
      select(biometricDevices).get();

  Future<BiometricDevice?> getDeviceById(int id) => (select(
    biometricDevices,
  )..where((d) => d.id.equals(id))).getSingleOrNull();

  Future<int> addDevice(BiometricDevicesCompanion entry) =>
      into(biometricDevices).insert(entry);

  Future<bool> updateDevice(BiometricDevice device) =>
      update(biometricDevices).replace(device);

  Future<int> updateDeviceSyncState(
    int id, {
    DateTime? lastSyncAt,
    required String status,
    String? error,
  }) =>
      (update(biometricDevices)..where((device) => device.id.equals(id))).write(
        BiometricDevicesCompanion(
          lastSyncAt: lastSyncAt == null
              ? const Value<DateTime?>.absent()
              : Value<DateTime?>(lastSyncAt),
          lastSyncStatus: Value<String?>(status),
          lastSyncError: Value<String?>(error),
        ),
      );

  /// تصفير كيرسور المزامنة لجهاز معين (سحب كامل من الأول).
  ///
  /// آمن: منع التكرار بالـdedup hash، فإعادة السحب لا تنشئ دوبلكيت.
  /// يُستخدم من زر «إعادة سحب كامل» ومن حارس الكيرسور المسموم ضمنياً
  /// (الحارس يتجاهل القيمة بدل مسحها — السجل الأصلي يبقى للمراجعة).
  Future<int> resetDeviceSyncCursor(int deviceId) =>
      (update(
        biometricDevices,
      )..where((device) => device.id.equals(deviceId))).write(
        const BiometricDevicesCompanion(
          lastSyncAt: Value<DateTime?>(null),
          lastSyncError: Value<String?>(null),
        ),
      );

  Future<int> deleteDevice(int id) =>
      (delete(biometricDevices)..where((d) => d.id.equals(id))).go();

  // --- Mappings ---

  Future<List<StaffBiometricMapping>> getMappingsForStaff(String staffId) =>
      (select(
        staffBiometricMappings,
      )..where((m) => m.staffId.equals(staffId))).get();

  Future<List<StaffBiometricMapping>> getMappingsForDevice(int deviceId) =>
      (select(
        staffBiometricMappings,
      )..where((m) => m.deviceId.equals(deviceId))).get();

  Future<StaffBiometricMapping?> getMappingByExternalId(
    int deviceId,
    String externalUserId,
  ) =>
      (select(staffBiometricMappings)..where(
            (m) =>
                m.deviceId.equals(deviceId) &
                m.externalUserId.equals(externalUserId) &
                m.enrollmentStatus.equals('enrolled'),
          ))
          .getSingleOrNull();

  Future<StaffBiometricMapping?> getMappingRecordByExternalId(
    int deviceId,
    String externalUserId,
  ) =>
      (select(staffBiometricMappings)..where(
            (m) =>
                m.deviceId.equals(deviceId) &
                m.externalUserId.equals(externalUserId),
          ))
          .getSingleOrNull();

  Future<int> addMapping(StaffBiometricMappingsCompanion entry) =>
      into(staffBiometricMappings).insert(entry);

  Future<bool> updateMapping(StaffBiometricMapping mapping) =>
      update(staffBiometricMappings).replace(mapping);

  Future<int> deleteMapping(int id) =>
      (delete(staffBiometricMappings)..where((m) => m.id.equals(id))).go();

  /// الموظف المربوط برقم بصمة معيّن على **أي** جهاز (وليس جهاز واحد).
  ///
  /// لازم الاستيراد من ملف الإكسل يربط سجلاته بنفس الموظف المسجَّل على أي
  /// جهاز، وإلا اتعمل موظف جديد بنفس الـID. الترتيب: الـprimary الأول، ثم
  /// الأحدث تسجيلاً/تحديثاً. مافيش فهرس فريد على `externalUserId` عبر
  /// الأجهزة فالاستعلام يجيب كل الربوطات ويرتّبها.
  Future<StaffBiometricMapping?> getEnrolledMappingByExternalIdAnyDevice(
    String externalUserId, {
    int? excludeDeviceId,
  }) async {
    final query = select(staffBiometricMappings)
      ..where(
        (m) =>
            m.externalUserId.equals(externalUserId) &
            m.enrollmentStatus.equals('enrolled'),
      );
    if (excludeDeviceId != null) {
      query.where((m) => m.deviceId.equals(excludeDeviceId).not());
    }
    final rows = await query.get();
    if (rows.isEmpty) return null;
    rows.sort((a, b) {
      final primary = (b.isPrimary ? 1 : 0).compareTo(a.isPrimary ? 1 : 0);
      if (primary != 0) return primary;
      final enrolled = _nullableCompare(b.enrolledAt, a.enrolledAt);
      if (enrolled != 0) return enrolled;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return rows.first;
  }

  int _nullableCompare(DateTime? right, DateTime? left) {
    if (right == null && left == null) return 0;
    if (right == null) return -1;
    if (left == null) return 1;
    return right.compareTo(left);
  }

  /// كل حالات الربط（非 enrolled） لرقم بصمة على أي جهاز — للتقرير والربط
  /// اليدوي (مثلاً binding مرفوض `revoked` في شاشة الحركات غير المطابقة).
  Future<List<StaffBiometricMapping>> getMappingsByExternalIdAnyDevice(
    String externalUserId,
  ) =>
      (select(
        staffBiometricMappings,
      )..where((m) => m.externalUserId.equals(externalUserId))).get();

  // --- Raw Events ---

  Future<int> addRawEvent(AttendanceRawEventsCompanion entry) =>
      into(attendanceRawEvents).insert(
        entry,
        mode: InsertMode.insertOrIgnore,
      ); // Ignores duplicate dedupHash

  /// كل بصمات dedupHash لجهاز معين — لاكتشاف المكرر قبل الإدخال
  /// (insertOrIgnore لا يرجع 0 عند التجاهل بل آخر rowid، فلا يعتمد عليه).
  Future<Set<String>> getDedupHashesForDevice(int deviceId) async {
    final rows = await (select(
      attendanceRawEvents,
    )..where((e) => e.deviceId.equals(deviceId))).get();
    return rows.map((e) => e.dedupHash).toSet();
  }

  Future<List<AttendanceRawEvent>> getUnprocessedEvents() => (select(
    attendanceRawEvents,
  )..where((e) => e.status.equals('pending'))).get();

  Future<List<AttendanceRawEvent>> getUnprocessedEventsForDevice(
    int deviceId,
  ) =>
      (select(attendanceRawEvents)..where(
            (e) => e.status.equals('pending') & e.deviceId.equals(deviceId),
          ))
          .get();

  Future<List<AttendanceRawEvent>> getRetryableEventsForDevice(int deviceId) =>
      (select(attendanceRawEvents)..where(
            (e) =>
                e.deviceId.equals(deviceId) &
                (e.status.equals('pending') | e.status.equals('error')),
          ))
          .get();

  Future<List<AttendanceRawEvent>> getMatchedEventsForStaff(
    String staffId,
    DateTime from,
    DateTime to,
  ) =>
      (select(attendanceRawEvents)..where(
            (e) =>
                e.matchedStaffId.equals(staffId) &
                e.eventTime.isBiggerOrEqualValue(from) &
                e.eventTime.isSmallerThanValue(to) &
                e.status.equals('matched'),
          ))
          .get();

  Future<List<AttendanceRawEvent>> getUnmatchedEvents() => (select(
    attendanceRawEvents,
  )..where((e) => e.status.equals('unmatched'))).get();

  Future<int> countRawEventsResultingInAttendance(int attendanceId) {
    final countExpression = attendanceRawEvents.id.count();
    final query = selectOnly(attendanceRawEvents)
      ..addColumns([countExpression])
      ..where(attendanceRawEvents.resultingAttendanceId.equals(attendanceId));
    return query.map((row) => row.read(countExpression) ?? 0).getSingle();
  }

  Future<int> requeueUnmatchedEventsForExternalId(
    int deviceId,
    String externalUserId,
  ) =>
      (update(attendanceRawEvents)..where(
            (e) =>
                e.deviceId.equals(deviceId) &
                e.externalUserId.equals(externalUserId) &
                e.status.equals('unmatched'),
          ))
          .write(
            AttendanceRawEventsCompanion(
              status: const Value('pending'),
              matchedStaffId: const Value<String?>(null),
              resultingAttendanceId: const Value<int?>(null),
              errorMessage: const Value<String?>(null),
              processedAt: const Value<DateTime?>(null),
            ),
          );

  Future<bool> updateRawEvent(AttendanceRawEvent event) =>
      update(attendanceRawEvents).replace(event);

  // --- Sync Logs ---

  Future<int> addSyncLog(AttendanceSyncLogsCompanion entry) =>
      into(attendanceSyncLogs).insert(entry);

  Future<bool> updateSyncLog(AttendanceSyncLog log) =>
      update(attendanceSyncLogs).replace(log);

  Future<AttendanceSyncLog?> getSyncLogById(int id) => (select(
    attendanceSyncLogs,
  )..where((l) => l.id.equals(id))).getSingleOrNull();

  Future<AttendanceSyncLog?> getRunningLogForDevice(
    int deviceId,
    DateTime since,
  ) =>
      (select(attendanceSyncLogs)
            ..where(
              (l) =>
                  l.deviceId.equals(deviceId) &
                  l.status.equals('running') &
                  l.startedAt.isBiggerThanValue(since),
            )
            ..orderBy([(l) => OrderingTerm.desc(l.startedAt)])
            ..limit(1))
          .getSingleOrNull();

  Future<int> markStaleRunningFailed(DateTime cutoff, String errorMessage) =>
      (update(attendanceSyncLogs)..where(
            (l) =>
                l.status.equals('running') &
                l.startedAt.isSmallerThanValue(cutoff),
          ))
          .write(
            AttendanceSyncLogsCompanion(
              status: const Value('failed'),
              finishedAt: Value(DateTime.now()),
              errorMessage: Value(errorMessage),
            ),
          );

  Future<List<AttendanceSyncLog>> getRecentSyncLogs(int limit) =>
      (select(attendanceSyncLogs)
            ..orderBy([
              (t) => OrderingTerm(
                expression: t.startedAt,
                mode: OrderingMode.desc,
              ),
            ])
            ..limit(limit))
          .get();
}
