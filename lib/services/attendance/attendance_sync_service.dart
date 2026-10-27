import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/dao/attendance_device_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/staff_management_dao.dart';
import 'attendance_calculation_engine.dart';
import 'attendance_source.dart';
import 'zkteco/zkteco_client.dart';
import 'zkteco_tcp_attendance_source.dart';

class SyncResult {
  final int fetched;
  final int matched;
  final int unmatched;
  final int duplicate;
  final String? error;

  /// معلومة تشخيصية اختيارية (تُعرض مع النتيجة، لا تؤثر على الألوان).
  /// مثال: تصفير كيرسور مستقبلي، أو تأكيد عدم وجود جديد رغم الاتصال.
  final String? info;

  const SyncResult({
    required this.fetched,
    required this.matched,
    required this.unmatched,
    required this.duplicate,
    this.error,
    this.info,
  });
}

class _ResolvedEvent {
  final AttendanceRawEvent raw;
  final String staffId;
  final DateTime workDate;

  const _ResolvedEvent({
    required this.raw,
    required this.staffId,
    required this.workDate,
  });
}

class _ResolvedGroup {
  final String staffId;
  final DateTime workDate;
  final ScheduleConfig schedule;
  final List<_ResolvedEvent> events;

  _ResolvedGroup({
    required this.staffId,
    required this.workDate,
    required this.schedule,
  }) : events = <_ResolvedEvent>[];

  void add(_ResolvedEvent event) {
    events.add(event);
  }
}

class _AttendanceCandidate {
  final DateTime time;
  final AttendanceRawEvent? raw;
  final bool isExisting;
  final bool protectedExisting;

  const _AttendanceCandidate({
    required this.time,
    this.raw,
    this.isExisting = false,
    this.protectedExisting = false,
  });
}

class _ProtectedAttendanceException implements Exception {
  final String message;

  const _ProtectedAttendanceException(this.message);
}

class AttendanceSyncService {
  static const _duplicateWindow = Duration(minutes: 10);
  static const _minCheckoutAfterCheckIn = Duration(hours: 4);
  static const _checkoutThresholdBeforeEnd = Duration(hours: 2);

  /// كيرسور مخزن أبعد من الآن بهذا القدر يُعتبر مسموماً (قفزة ساعة سابقة)
  /// ويُتجاهل لصالح سحب كامل — وإلا حجب كل البصمات الحقيقية للأبد.
  static const _futureCursorTolerance = Duration(minutes: 2);

  final AttendanceDeviceDao _deviceDao;
  final StaffManagementDao _staffDao;
  final AttendanceCalculationEngine _engine;

  /// حقن مصدر بديل (للاختبارات): لو موجود يُستخدم بدل إنشاء مصدر TCP.
  final AttendanceSource Function(BiometricDevice device)? _sourceFactory;

  /// Prevents concurrent syncs for the same device
  static final Set<int> _syncingDevices = {};

  /// Auto-sync timer
  Timer? _autoSyncTimer;
  bool _isAutoSyncEnabled = false;

  AttendanceSyncService(this._deviceDao, this._staffDao, this._engine,
      {AttendanceSource Function(BiometricDevice device)? sourceFactory})
      : _sourceFactory = sourceFactory;

  /// Whether auto-sync is currently running
  bool get isAutoSyncEnabled => _isAutoSyncEnabled;

  /// محرك الحسابات (يُستخدم لمشاركة توليد الغياب مع مسار الاستيراد).
  AttendanceCalculationEngine get engine => _engine;

  /// Starts periodic auto-sync for all active devices
  void startAutoSync({Duration interval = const Duration(minutes: 5)}) {
    stopAutoSync();
    _isAutoSyncEnabled = true;
    _autoSyncTimer = Timer.periodic(interval, (_) async {
      try {
        await syncAllDevices(triggeredBy: 'auto_sync');
      } catch (e) {
        // Silently ignore auto-sync errors
      }
    });
  }

  /// Stops the auto-sync timer
  void stopAutoSync() {
    _autoSyncTimer?.cancel();
    _autoSyncTimer = null;
    _isAutoSyncEnabled = false;
  }

  /// رسالة عملية قصيرة لأخطاء الشبكة (تظهر كاملة في الواجهة بدل نص
  /// الـSocket الطويل): السبب الغالب أن الكمبيوتر ليس على نفس شبكة البصمة.
  static String _friendlySyncError(Object e, BiometricDevice device) {
    final text = e.toString();
    final lower = text.toLowerCase();
    final endpoint = device.ipAddress == null
        ? device.name
        : '${device.ipAddress}:${device.port ?? 4370}';
    if (lower.contains('10060') ||
        lower.contains('connection timed out') ||
        lower.contains('timed out')) {
      return 'تعذر الوصول لجهاز البصمة $endpoint (timeout) — تأكد أن الكمبيوتر على نفس شبكة الجهاز وأن الكابل والـIP سليمين';
    }
    if (lower.contains('connection refused') || lower.contains('errno = 10061')) {
      return 'جهاز البصمة $endpoint رفض الاتصال — تأكد من البورت ورقم الـIP';
    }
    if (lower.contains('unreachable') || lower.contains('errno = 10065')) {
      return 'جهاز البصمة $endpoint لا يمكن الوصول إليه — راجع الشبكة والراوتر';
    }
    return text;
  }

  static String _fmtShort(DateTime t) =>
      '${t.year}/${t.month}/${t.day} '
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  /// Triggers a sync for all active devices. Returns aggregate counts so
  /// the UI can show what actually happened instead of a blind "done".
  Future<SyncResult> syncAllDevices({String triggeredBy = 'manual'}) async {    await _deviceDao.markStaleRunningFailed(
      DateTime.now().subtract(const Duration(minutes: 10)),
      'stale lock recovered: sync did not finish within 10min',
    );
    final devices = await _deviceDao.getAllDevices();
    int fetched = 0, matched = 0, unmatched = 0, duplicate = 0;
    String? error;
    final infos = <String>[];
    // المزامنة الجماعية للأجهزة الحية TCP فقط — أجهزة الملف/USB لها زرها
    // الخاص، وتمريرها هنا كان يرمي 'Unsupported connection type' في النتيجة.
    for (final device
        in devices.where((d) => d.isActive && d.connectionType == 'tcp_ip')) {
      final r = await syncDevice(device, triggeredBy: triggeredBy);
      fetched += r.fetched;
      matched += r.matched;
      unmatched += r.unmatched;
      duplicate += r.duplicate;
      error ??= r.error;
      if (r.info != null && !infos.contains(r.info)) infos.add(r.info!);
    }
    return SyncResult(
      fetched: fetched,
      matched: matched,
      unmatched: unmatched,
      duplicate: duplicate,
      error: error,
      info: infos.isEmpty ? null : infos.join(' — '),
    );
  }

  /// Triggers a sync for a specific device. Returns what happened
  /// (fetched/matched/...) so a press with zero results is distinguishable
  /// from a press that actually imported attendance.
  Future<SyncResult> syncDevice(
    BiometricDevice device, {
    String triggeredBy = 'manual',
  }) async {
    // Prevent concurrent syncs for the same device
    if (_syncingDevices.contains(device.id)) {
      return const SyncResult(
        fetched: 0,
        matched: 0,
        unmatched: 0,
        duplicate: 0,
        error: 'المزامنة جارية بالفعل',
      );
    }
    _syncingDevices.add(device.id);

    try {
      final runningSince = DateTime.now().subtract(const Duration(minutes: 10));
      await _deviceDao.markStaleRunningFailed(
        runningSince,
        'stale lock recovered: sync did not finish within 10min',
      );
      final running = await _deviceDao.getRunningLogForDevice(
        device.id,
        runningSince,
      );
      if (running != null) {
        return const SyncResult(
          fetched: 0,
          matched: 0,
          unmatched: 0,
          duplicate: 0,
          error: 'المزامنة جارية بالفعل',
        );
      }
      final syncBatchId = const Uuid().v4();
      final logCompanion = AttendanceSyncLogsCompanion.insert(
        deviceId: device.id,
        syncBatchId: syncBatchId,
        startedAt: DateTime.now(),
        status: 'running',
        triggeredBy: Value(triggeredBy),
      );
      final logId = await _deviceDao.addSyncLog(logCompanion);

      AttendanceSource? source;
      int fetched = 0;
      int matched = 0;
      int unmatched = 0;
      int duplicate = 0;
      String? error;
      final notes = <String>[];

      try {
        // 1. Instantiate the correct source based on connection type
        // (or the injected factory in tests).
        if (_sourceFactory != null) {
          source = _sourceFactory(device);
        } else if (device.connectionType == 'tcp_ip') {
          if (device.ipAddress == null || device.port == null) {
            throw Exception(
              'IP Address and Port are required for TCP/IP devices',
            );
          }
          source = ZKTecoTcpAttendanceSource(
            ipAddress: device.ipAddress!,
            port: device.port!,
            authToken: device.authToken,
          );
        } else {
          throw Exception(
            'Unsupported connection type: ${device.connectionType}',
          );
        }

        // 2. Connect — مع تمرير السبب الحقيقي (packet loss / CommKey / timeout)
        final connected = await source.connect();
        if (!connected) {
          String detail =
              'فشل الاتصال بالجهاز ${device.ipAddress}:${device.port}';
          if (source is ZKTecoTcpAttendanceSource && source.lastError != null) {
            detail = source.lastError!;
          }
          throw Exception(detail);
        }

        // Restored: sync the terminal clock when it drifts more than 2
        // minutes — skew shifts every event timestamp, which then falls
        // outside the `since` filter and the import silently misses
        // check-ins/check-outs.
        bool clockAdjusted = false;
        DateTime? reportedDeviceTime;
        try {
          if (source is ZKTecoTcpAttendanceSource) {
            final tcpSource = source;
            final info = await tcpSource.getDeviceInfo();
            reportedDeviceTime = info.deviceTime;
            if (info.deviceTime != null) {
              final drift = DateTime.now().difference(info.deviceTime!).abs();
              if (drift > const Duration(minutes: 2)) {
                await tcpSource.setDeviceTime(DateTime.now());
                clockAdjusted = true;
              }
            }
          }
        } catch (_) {}

        final lastSyncAt = device.lastSyncAt;
        // حارس الكيرسور المسموم: قيمة مخزنة في المستقبل (قفزة ساعة سابقة)
        // كانت تحجب كل البصمات الحقيقية للأبد عبر فلتر isAfter — نمسحها
        // فوراً ونسحب سحباً كاملاً آمناً (منع التكرار بالـhash)، مع تسجيل تحذير.
        DateTime? effectiveSinceBase = lastSyncAt;
        if (lastSyncAt != null &&
            (clockAdjusted ||
                lastSyncAt.isAfter(
                    DateTime.now().add(_futureCursorTolerance)) ||
                (reportedDeviceTime != null &&
                    lastSyncAt.isAfter(
                        reportedDeviceTime.add(_futureCursorTolerance))))) {
          notes.add(
            'تم تصفير كيرسور مستقبلي مسموم '
            '(${_fmtShort(lastSyncAt)}) — سيُعاد السحب الكامل',
          );
          effectiveSinceBase = null;
          await _deviceDao.resetDeviceSyncCursor(device.id);
        }
        final overlapSince =
            effectiveSinceBase?.subtract(const Duration(minutes: 15));
        List<RawAttendanceEvent> events;
        try {
          events = await source.fetchEvents(since: overlapSince);
        } on ZkTransportException {
          await Future.delayed(const Duration(seconds: 2));
          try {
            await source.disconnect();
          } catch (_) {}
          if (!await source.connect()) {
            final detail = source is ZKTecoTcpAttendanceSource
                ? source.lastError
                : null;
            throw Exception(detail ?? 'فشلت إعادة الاتصال بجهاز الحضور');
          }
          events = await source.fetchEvents(since: overlapSince);
        }
        if (source is ZKTecoTcpAttendanceSource) {
          final report = source.lastFetchReport;
          if (report != null && report.droppedChunks > 0) {
            final sample = report.debugSample == null
                ? ''
                : ' (sample: ${report.debugSample})';
            throw Exception(
              'parser mismatch: dropped ${report.droppedChunks} chunks '
              'of ${report.rawBytes} bytes$sample',
            );
          }
        }
        fetched = events.length;

        // 4. Ingest raw events (dups counted by pre-check: insertOrIgnore
        // لا يميّز المكرر من قيمته الراجعة).
        final knownHashes =
            await _deviceDao.getDedupHashesForDevice(device.id);
        DateTime? maxEventTime;
        DateTime? minEventTime;
        await _deviceDao.attachedDatabase.transaction(() async {
          for (final event in events) {
            if (event.eventTime.isAfter(maxEventTime ?? DateTime.fromMillisecondsSinceEpoch(0))) {
              maxEventTime = event.eventTime;
            }
            if (minEventTime == null ||
                event.eventTime.isBefore(minEventTime!)) {
              minEventTime = event.eventTime;
            }
            // Generate Dedup Hash: sha256(deviceId + externalUserId + eventTime)
            final hashStr =
                '${device.id}_${event.externalUserId}_${event.eventTime.toIso8601String()}';
            final dedupHash = sha256.convert(utf8.encode(hashStr)).toString();
            if (knownHashes.contains(dedupHash)) {
              duplicate++;
              continue;
            }

            // Truncate rawPayload to prevent database bloat
            final rawPayload =
                event.rawPayload != null && event.rawPayload!.length > 10000
                ? event.rawPayload!.substring(0, 10000)
                : event.rawPayload;

            final rawCompanion = AttendanceRawEventsCompanion.insert(
              deviceId: device.id,
              externalUserId: event.externalUserId,
              eventTime: event.eventTime,
              eventType: Value(event.eventType),
              rawPayload: Value(rawPayload),
              syncBatchId: Value(syncBatchId),
              dedupHash: dedupHash,
              status: 'pending',
              createdAt: DateTime.now(),
            );

            await _deviceDao.addRawEvent(rawCompanion);
            knownHashes.add(dedupHash);
          }
        });

        // 5. Process pending events (Matching & Heuristics)
        final processResult = await processPendingEvents(device.id);
        matched = processResult.matched;
        unmatched = processResult.unmatched;

        // 5b. توليد الغياب للأيام المغلقة في نطاق البصمات الواردة:
        // أي موظف نشط بلا سجل في يوم عمل مغلق يُسجَّل غائباً.
        // (لا يفشل المزامنة لو تعثر — يُسجَّل ملاحظة فقط.)
        final minSeen = minEventTime;
        if (matched + unmatched > 0 && minSeen != null) {
          try {
            final absences =
                await _engine.generateAbsencesForRange(minSeen, DateTime.now());
            if (absences > 0) {
              notes.add('اتسجل غياب تلقائي: $absences');
            }
          } catch (_) {}
        }

        // الكيرسور = آخر حدث فعلياً مشاهد — لا يتقدم مع السحب الفارغ،
        // ولا يرجع للخلف أبداً (حماية من تداخل الـoverlap).
        // (لو كان مسموماً فقد مُسح أعلاه، فالأساس هنا سليم.)
        // نسخة محلية: maxEventTime يُكتب داخل closure فلا ترقية تلقائية له.
        final maxSeen = maxEventTime;
        DateTime? newSyncAt = effectiveSinceBase;
        if (maxSeen != null &&
            (newSyncAt == null || maxSeen.isAfter(newSyncAt))) {
          newSyncAt = maxSeen;
        }
        if (fetched == 0) {
          notes.add(
            effectiveSinceBase == null
                ? 'الجهاز متصل ولا يحمل سجلات — أول سحب'
                : 'الجهاز متصل ولا توجد بصمات جديدة منذ ${_fmtShort(effectiveSinceBase)}',
          );
        }

        final syncStatus = unmatched == 0 ? 'success' : 'partial';
        await _deviceDao.updateDeviceSyncState(
          device.id,
          lastSyncAt: newSyncAt,
          status: syncStatus,
        );
      } catch (e) {
        error = _friendlySyncError(e, device);
        await _deviceDao.updateDeviceSyncState(
          device.id,
          status: 'failed',
          error: error,
        );
      } finally {
        // Always disconnect the source
        try {
          await source?.disconnect();
        } catch (_) {}

        // Update sync log
        final currentLog = await _deviceDao.getSyncLogById(logId);
        if (currentLog != null) {
          final logStatus = error == null
              ? (unmatched == 0 ? 'success' : 'partial')
              : 'failed';
          await _deviceDao.updateSyncLog(
            currentLog.copyWith(
              finishedAt: Value(DateTime.now()),
              status: logStatus,
              eventsFetched: fetched,
              eventsMatched: matched,
              eventsUnmatched: unmatched,
              eventsDuplicate: duplicate,
              errorMessage: Value(error),
            ),
          );
        }
      }

      return SyncResult(
        fetched: fetched,
        matched: matched,
        unmatched: unmatched,
        duplicate: duplicate,
        error: error,
        info: notes.isEmpty ? null : notes.join(' — '),
      );
    } finally {
      _syncingDevices.remove(device.id);
    }
  }

  bool _isAutoCreatedPlaceholder(Staff? staff, String externalUserId) {
    if (staff == null) return false;
    final cleanName = staff.name.trim();
    return staff.basicSalary == 0 &&
        (cleanName == 'موظف $externalUserId' ||
            cleanName == 'موظف ${externalUserId.trim()}' ||
            (staff.notes != null &&
                staff.notes!.contains('أُنشئ تلقائياً من جهاز البصمة')));
  }

  Future<void> _mergeStaffAttendanceRecords({
    required String fromStaffId,
    required String toStaffId,
  }) async {
    final db = _deviceDao.attachedDatabase;
    final oldRows = await _staffDao.getAttendanceByStaff(fromStaffId);
    for (final oldRow in oldRows) {
      final targetRows =
          await _staffDao.getAttendanceOnDate(toStaffId, oldRow.date);
      if (targetRows.isEmpty) {
        await (db.update(db.attendanceTable)
              ..where((t) => t.id.equals(oldRow.id)))
            .write(
          AttendanceTableCompanion(
            staffId: Value(toStaffId),
            updatedAt: Value(DateTime.now()),
          ),
        );
      } else {
        final target = targetRows.first;
        DateTime? mergedCheckIn;
        if (target.checkInTime == null) {
          mergedCheckIn = oldRow.checkInTime;
        } else if (oldRow.checkInTime == null) {
          mergedCheckIn = target.checkInTime;
        } else {
          mergedCheckIn = target.checkInTime!.isBefore(oldRow.checkInTime!)
              ? target.checkInTime
              : oldRow.checkInTime;
        }

        DateTime? mergedCheckOut;
        if (target.checkOutTime == null) {
          mergedCheckOut = oldRow.checkOutTime;
        } else if (oldRow.checkOutTime == null) {
          mergedCheckOut = target.checkOutTime;
        } else {
          mergedCheckOut = target.checkOutTime!.isAfter(oldRow.checkOutTime!)
              ? target.checkOutTime
              : oldRow.checkOutTime;
        }

        double? workingHours;
        if (mergedCheckIn != null && mergedCheckOut != null) {
          final diff =
              mergedCheckOut.difference(mergedCheckIn).inMinutes / 60.0;
          if (diff > 0) workingHours = double.parse(diff.toStringAsFixed(2));
        }

        await (db.update(db.attendanceTable)
              ..where((t) => t.id.equals(target.id)))
            .write(
          AttendanceTableCompanion(
            checkInTime: Value(mergedCheckIn),
            checkOutTime: Value(mergedCheckOut),
            status: target.status == 'absent' && mergedCheckIn != null
                ? const Value('present')
                : const Value.absent(),
            workingHours: workingHours != null
                ? Value(workingHours)
                : const Value.absent(),
            updatedAt: Value(DateTime.now()),
          ),
        );

        await (db.delete(db.attendanceTable)
              ..where((t) => t.id.equals(oldRow.id)))
            .go();
      }
    }
  }

  /// يربط رقم بصمة بالموظف ذرياً على جميع الأجهزة النشطة وينقل أي حضور أو أحداث معلقة
  Future<void> reconcileAndLinkBiometricId({
    required String staffId,
    required String externalUserId,
    String? staffNameOnDevice,
    String? cardNumber,
    int? preferredDeviceId,
  }) async {
    final cleanExtId = externalUserId.trim();
    if (cleanExtId.isEmpty) return;

    final db = _deviceDao.attachedDatabase;
    final targetDeviceIds = <int>{};

    await db.transaction(() async {
      var devices = await _deviceDao.getAllDevices();
      if (devices.isEmpty) {
        await _deviceDao.addDevice(
          BiometricDevicesCompanion.insert(
            deviceCode: 'FILE-IMPORT',
            name: 'استيراد ملفات',
            connectionType: 'file_import',
            isActive: const Value(false),
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );
        devices = await _deviceDao.getAllDevices();
      }

      final activeTcpDevices = devices
          .where((d) => d.isActive && d.connectionType == 'tcp_ip')
          .toList();
      final activeNonFileDevices = devices
          .where((d) => d.isActive && d.connectionType != 'file_import')
          .toList();
      final realDevices =
          activeTcpDevices.isNotEmpty ? activeTcpDevices : activeNonFileDevices;

      for (final d in realDevices) {
        targetDeviceIds.add(d.id);
      }

      if (preferredDeviceId != null) {
        final prefDevice = devices.firstWhere(
          (d) => d.id == preferredDeviceId,
          orElse: () => devices.first,
        );
        final isPrefFileImport = prefDevice.connectionType == 'file_import';
        final hasRealDevices = realDevices.isNotEmpty;

        if (!isPrefFileImport || !hasRealDevices) {
          targetDeviceIds.add(preferredDeviceId);
        } else {
          final existingPrefMapping = await (db.select(db.staffBiometricMappings)
                ..where((t) =>
                    t.deviceId.equals(preferredDeviceId) &
                    t.staffId.equals(staffId)))
              .getSingleOrNull();
          if (existingPrefMapping != null) {
            targetDeviceIds.add(preferredDeviceId);
          }
        }
      }

      final mappingsWithExtId = await (db.select(db.staffBiometricMappings)
            ..where((t) => t.externalUserId.equals(cleanExtId)))
          .get();
      for (final m in mappingsWithExtId) {
        targetDeviceIds.add(m.deviceId);
      }

      final mappingsWithStaffId = await (db.select(db.staffBiometricMappings)
            ..where((t) => t.staffId.equals(staffId)))
          .get();
      for (final m in mappingsWithStaffId) {
        targetDeviceIds.add(m.deviceId);
      }

      if (targetDeviceIds.isEmpty) {
        final fallback = devices.firstWhere(
          (d) => d.isActive,
          orElse: () => devices.first,
        );
        targetDeviceIds.add(fallback.id);
      }

      final processedOldStaffIds = <String>{};
      for (final row in mappingsWithExtId) {
        if (row.staffId == staffId) continue;
        final oldStaffId = row.staffId;
        if (processedOldStaffIds.contains(oldStaffId)) continue;
        processedOldStaffIds.add(oldStaffId);

        final oldStaff = await _staffDao.getStaffById(oldStaffId);
        final isPlaceholder = _isAutoCreatedPlaceholder(oldStaff, cleanExtId);
        final isInactiveOrDeleted =
            oldStaff == null || !oldStaff.isActive || oldStaff.status != 'active';

        if (isPlaceholder || isInactiveOrDeleted) {
          await _mergeStaffAttendanceRecords(
            fromStaffId: oldStaffId,
            toStaffId: staffId,
          );

          await (db.update(db.attendanceRawEvents)
                ..where((t) =>
                    t.externalUserId.equals(cleanExtId) &
                    t.matchedStaffId.equals(oldStaffId)))
              .write(
            AttendanceRawEventsCompanion(
              matchedStaffId: Value(staffId),
              status: const Value('pending'),
              processedAt: const Value(null),
              errorMessage: const Value(null),
            ),
          );

          await (db.delete(db.staffBiometricMappings)
                ..where((t) =>
                    t.staffId.equals(oldStaffId) &
                    t.externalUserId.equals(cleanExtId)))
              .go();

          if (isPlaceholder) {
            await _staffDao.deleteStaff(oldStaffId);
          }
        }
      }

      final now = DateTime.now();
      for (final devId in targetDeviceIds) {
        final existingByExt =
            await _deviceDao.getMappingRecordByExternalId(devId, cleanExtId);
        final existingForStaff = await (db.select(db.staffBiometricMappings)
              ..where((t) => t.deviceId.equals(devId) & t.staffId.equals(staffId)))
            .get();

        if (existingByExt != null) {
          await (db.update(db.staffBiometricMappings)
                ..where((t) => t.id.equals(existingByExt.id)))
              .write(
            StaffBiometricMappingsCompanion(
              staffId: Value(staffId),
              enrollmentStatus: const Value('enrolled'),
              deviceUserName: staffNameOnDevice != null
                  ? Value(staffNameOnDevice)
                  : const Value.absent(),
              cardNumber: cardNumber != null
                  ? Value(cardNumber)
                  : const Value.absent(),
              updatedAt: Value(now),
            ),
          );

          for (final other in existingForStaff) {
            if (other.id != existingByExt.id) {
              await _deviceDao.deleteMapping(other.id);
            }
          }
        } else if (existingForStaff.isNotEmpty) {
          final firstStaffMap = existingForStaff.first;
          await (db.update(db.staffBiometricMappings)
                ..where((t) => t.id.equals(firstStaffMap.id)))
              .write(
            StaffBiometricMappingsCompanion(
              externalUserId: Value(cleanExtId),
              enrollmentStatus: const Value('enrolled'),
              deviceUserName: staffNameOnDevice != null
                  ? Value(staffNameOnDevice)
                  : const Value.absent(),
              cardNumber: cardNumber != null
                  ? Value(cardNumber)
                  : const Value.absent(),
              updatedAt: Value(now),
            ),
          );

          for (int i = 1; i < existingForStaff.length; i++) {
            await _deviceDao.deleteMapping(existingForStaff[i].id);
          }
        } else {
          await _deviceDao.addMapping(
            StaffBiometricMappingsCompanion.insert(
              staffId: staffId,
              deviceId: devId,
              externalUserId: cleanExtId,
              deviceUserName: Value(staffNameOnDevice),
              cardNumber: Value(cardNumber),
              enrollmentStatus: 'enrolled',
              enrolledAt: Value(now),
              createdAt: now,
              updatedAt: now,
            ),
          );
        }

        await _deviceDao.requeueUnmatchedEventsForExternalId(devId, cleanExtId);
      }
    });

    for (final devId in targetDeviceIds) {
      await processPendingEvents(devId);
    }
  }

  /// Processes raw events for a specific device, matches them to staff, and creates attendance records.
  Future<SyncResult> processPendingEvents(int deviceId) async {
    final retryableEvents = await _deviceDao.getRetryableEventsForDevice(
      deviceId,
    );
    retryableEvents.sort(_compareRawEvents);

    final groups = <_ResolvedGroup>[];
    final schedules = <String, ScheduleConfig>{};
    var unmatched = 0;

    for (final rawEvent in retryableEvents) {
      StaffBiometricMapping? mapping;
      try {
        mapping = await _deviceDao.getMappingRecordByExternalId(
          deviceId,
          rawEvent.externalUserId,
        );
      } catch (error) {
        await _markRetryError(rawEvent, error);
        unmatched++;
        continue;
      }

      if (mapping == null) {
        try {
          final anyMapping =
              await _deviceDao.getEnrolledMappingByExternalIdAnyDevice(
            rawEvent.externalUserId,
          );
          if (anyMapping != null) {
            final candidateStaff =
                await _staffDao.getStaffById(anyMapping.staffId);
            if (candidateStaff != null &&
                candidateStaff.isActive &&
                candidateStaff.status == 'active') {
              final now = DateTime.now();
              await _deviceDao.addMapping(
                StaffBiometricMappingsCompanion.insert(
                  staffId: candidateStaff.staffId,
                  deviceId: deviceId,
                  externalUserId: rawEvent.externalUserId,
                  enrollmentStatus: 'enrolled',
                  enrolledAt: Value(now),
                  createdAt: now,
                  updatedAt: now,
                ),
              );
              mapping = await _deviceDao.getMappingRecordByExternalId(
                deviceId,
                rawEvent.externalUserId,
              );
            }
          }
          if (mapping == null) {
            await _autoCreateStaffForExternalId(
              deviceId,
              rawEvent.externalUserId,
            );
            mapping = await _deviceDao.getMappingRecordByExternalId(
              deviceId,
              rawEvent.externalUserId,
            );
            if (mapping == null) {
              throw StateError('mapping not created');
            }
          }
        } catch (error) {
          await _markRetryError(rawEvent, error);
          unmatched++;
          continue;
        }
      }

      if (mapping.enrollmentStatus != 'enrolled') {
        await _markUnmatched(
          rawEvent,
          'تعذر استخدام ربط البصمة: enrollmentStatus=${mapping.enrollmentStatus}',
          mapping.staffId,
        );
        unmatched++;
        continue;
      }

      var staffId = mapping.staffId;
      try {
        var staff = await _staffDao.getStaffById(staffId);
        if (staff == null || !staff.isActive || staff.status != 'active') {
          final allMaps = await (_deviceDao.attachedDatabase.select(
                  _deviceDao.attachedDatabase.staffBiometricMappings)
                ..where((t) =>
                    t.externalUserId.equals(rawEvent.externalUserId) &
                    t.enrollmentStatus.equals('enrolled')))
              .get();
          Staff? activeStaffCandidate;
          for (final m in allMaps) {
            if (m.staffId != staffId) {
              final s = await _staffDao.getStaffById(m.staffId);
              if (s != null && s.isActive && s.status == 'active') {
                activeStaffCandidate = s;
                break;
              }
            }
          }

          if (activeStaffCandidate != null) {
            staff = activeStaffCandidate;
            staffId = staff.staffId;
            final now = DateTime.now();
            await _deviceDao.updateMapping(
              mapping.copyWith(
                staffId: staffId,
                updatedAt: now,
              ),
            );
            mapping = await _deviceDao.getMappingRecordByExternalId(
              deviceId,
              rawEvent.externalUserId,
            );
          } else if (staff == null || staff.status == 'deleted') {
            await _deviceDao.deleteMapping(mapping.id);
            staffId = await _autoCreateStaffForExternalId(
              deviceId,
              rawEvent.externalUserId,
            );
            mapping = await _deviceDao.getMappingRecordByExternalId(
              deviceId,
              rawEvent.externalUserId,
            );
            staff = await _staffDao.getStaffById(staffId);
          }
        }

        if (staff != null &&
            _isAutoCreatedPlaceholder(staff, rawEvent.externalUserId)) {
          final allMaps = await (_deviceDao.attachedDatabase.select(
                  _deviceDao.attachedDatabase.staffBiometricMappings)
                ..where((t) =>
                    t.externalUserId.equals(rawEvent.externalUserId) &
                    t.enrollmentStatus.equals('enrolled')))
              .get();
          Staff? namedStaffCandidate;
          for (final m in allMaps) {
            if (m.staffId != staffId) {
              final s = await _staffDao.getStaffById(m.staffId);
              if (s != null &&
                  s.isActive &&
                  s.status == 'active' &&
                  !_isAutoCreatedPlaceholder(s, rawEvent.externalUserId)) {
                namedStaffCandidate = s;
                break;
              }
            }
          }

          if (namedStaffCandidate != null) {
            final oldPlaceholderId = staffId;
            staff = namedStaffCandidate;
            staffId = staff.staffId;
            await _mergeStaffAttendanceRecords(
              fromStaffId: oldPlaceholderId,
              toStaffId: staffId,
            );
            await (_deviceDao.attachedDatabase.update(
                    _deviceDao.attachedDatabase.attendanceRawEvents)
                  ..where((t) =>
                      t.externalUserId.equals(rawEvent.externalUserId) &
                      t.matchedStaffId.equals(oldPlaceholderId)))
                .write(
              AttendanceRawEventsCompanion(
                matchedStaffId: Value(staffId),
              ),
            );
            await _deviceDao.updateMapping(
              mapping!.copyWith(
                staffId: staffId,
                updatedAt: DateTime.now(),
              ),
            );
            mapping = await _deviceDao.getMappingRecordByExternalId(
              deviceId,
              rawEvent.externalUserId,
            );
            await _staffDao.deleteStaff(oldPlaceholderId);
          }
        }

        if (staff == null || !staff.isActive || staff.status != 'active') {
          await _markUnmatched(
            rawEvent,
            staff == null
                ? 'Staff record not found: $staffId'
                : 'Staff is inactive or terminated (${staff.status})',
            staffId,
          );
          unmatched++;
          continue;
        }

        if (_isNonBiometric(rawEvent)) {
          await _markUnmatched(
            rawEvent,
            'تحقق يدوي: بصمة غير بيومترية (كارت/باسورد)',
            staffId,
          );
          unmatched++;
          continue;
        }

        if (!schedules.containsKey(staffId)) {
          schedules[staffId] = await _engine.getScheduleForStaff(staffId);
        }
        final schedule = schedules[staffId]!;
        final workDate = await _resolveWorkDate(
          staffId: staffId,
          eventTime: rawEvent.eventTime,
          schedule: schedule,
        );
        _ResolvedGroup? group;
        for (final candidateGroup in groups) {
          if (candidateGroup.staffId == staffId &&
              candidateGroup.workDate == workDate) {
            group = candidateGroup;
            break;
          }
        }
        if (group == null) {
          group = _ResolvedGroup(
            staffId: staffId,
            workDate: workDate,
            schedule: schedule,
          );
          groups.add(group);
        }
        group.add(
          _ResolvedEvent(raw: rawEvent, staffId: staffId, workDate: workDate),
        );
      } catch (error) {
        await _markRetryError(rawEvent, error, staffId: staffId);
        unmatched++;
      }
    }

    groups.sort((a, b) {
      final staffOrder = a.staffId.compareTo(b.staffId);
      if (staffOrder != 0) return staffOrder;
      return a.workDate.compareTo(b.workDate);
    });

    var matched = 0;
    for (final group in groups) {
      try {
        final attendanceRows = await _staffDao.getAttendanceOnDate(
          group.staffId,
          group.workDate,
        );
        if (_hasManualAbsent(attendanceRows)) {
          for (final event in group.events) {
            await _markUnmatched(
              event.raw,
              'سجل غياب يدوي: لم يتم تعديل الحضور',
              event.staffId,
            );
          }
          unmatched += group.events.length;
          continue;
        }
        if (_hasProtectedAttendance(attendanceRows)) {
          for (final event in group.events) {
            await _markUnmatched(
              event.raw,
              'سجل حضور محفوظ مسبقًا: يحتاج مراجعة يدوية',
              event.staffId,
            );
          }
          unmatched += group.events.length;
          continue;
        }

        await _deviceDao.attachedDatabase.transaction(() async {
          await _processGroup(
            deviceId: deviceId,
            staffId: group.staffId,
            workDate: group.workDate,
            schedule: group.schedule,
            newEvents: group.events,
          );
        });
        matched += group.events.length;
      } on _ProtectedAttendanceException catch (error) {
        for (final event in group.events) {
          await _markUnmatched(event.raw, error.message, event.staffId);
        }
        unmatched += group.events.length;
      } catch (error) {
        await _markGroupError(group, error);
        unmatched += group.events.length;
      }
    }

    return SyncResult(
      fetched: retryableEvents.length,
      matched: matched,
      unmatched: unmatched,
      duplicate: 0,
    );
  }

  int _compareRawEvents(AttendanceRawEvent a, AttendanceRawEvent b) {
    final timeOrder = a.eventTime.compareTo(b.eventTime);
    if (timeOrder != 0) return timeOrder;
    final deviceOrder = a.deviceId.compareTo(b.deviceId);
    if (deviceOrder != 0) return deviceOrder;
    return a.id.compareTo(b.id);
  }

  bool _isNonBiometric(AttendanceRawEvent event) {
    final payload = event.rawPayload;
    if (payload == null || payload.isEmpty) return false;

    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map) {
        final value = decoded['verifyType'] ?? decoded['verify_type'];
        final verifyType = value is num
            ? value.toInt()
            : int.tryParse('$value');
        if (verifyType == 2 || verifyType == 3) return true;
      }
    } catch (_) {}

    return RegExp(r'"verifyType"\s*:\s*[23](?:\D|$)').hasMatch(payload) ||
        RegExp(r'"verify_type"\s*:\s*[23](?:\D|$)').hasMatch(payload);
  }

  Future<DateTime> _resolveWorkDate({
    required String staffId,
    required DateTime eventTime,
    required ScheduleConfig schedule,
  }) async {
    final date = _dateOnly(eventTime);
    if (eventTime.hour >= 4) return date;

    final previousDate = date.subtract(const Duration(days: 1));
    if (_isOvernightSchedule(schedule)) return previousDate;

    final previousRows = await _staffDao.getAttendanceOnDate(
      staffId,
      previousDate,
    );
    final hasOpenPrevious = previousRows.any(
      (row) =>
          (row.checkInTime != null && row.checkOutTime == null) ||
          (row.source == 'auto_generated' &&
              row.status == 'absent' &&
              (row.checkInTime != null || row.checkOutTime != null)),
    );
    return hasOpenPrevious ? previousDate : date;
  }

  bool _hasManualAbsent(List<Attendance> rows) {
    return rows.any(
      (row) =>
          row.status == 'absent' &&
          row.checkInTime == null &&
          row.source != 'auto_generated',
    );
  }

  bool _hasProtectedAttendance(List<Attendance> rows) {
    return rows.any((row) {
      if (row.source == 'admin_override') return true;
      if (row.checkOutTime == null) return false;
      return row.source == 'manual' ||
          row.source == 'import' ||
          row.source == null;
    });
  }

  Attendance _selectAttendanceRow(List<Attendance> rows) {
    int priority(Attendance row) {
      return switch (row.source) {
        'admin_override' => 0,
        'manual' => 1,
        null => 2,
        'auto_generated' => 3,
        'device' => 4,
        _ => 5,
      };
    }

    rows.sort((left, right) {
      final sourceOrder = priority(left).compareTo(priority(right));
      if (sourceOrder != 0) return sourceOrder;
      final leftUpdated = left.updatedAt;
      final rightUpdated = right.updatedAt;
      final updatedOrder = rightUpdated.compareTo(leftUpdated);
      if (updatedOrder != 0) return updatedOrder;
      return right.id.compareTo(left.id);
    });
    return rows.first;
  }

  DateTime _dateOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  Future<void> _markUnmatched(
    AttendanceRawEvent event,
    String message,
    String? staffId,
  ) async {
    await _deviceDao.updateRawEvent(
      event.copyWith(
        matchedStaffId: Value<String?>(staffId),
        resultingAttendanceId: const Value<int?>(null),
        status: 'unmatched',
        errorMessage: Value<String?>(message),
        processedAt: Value<DateTime?>(DateTime.now()),
      ),
    );
  }

  Future<void> _markRetryError(
    AttendanceRawEvent event,
    Object error, {
    String? staffId,
  }) async {
    await _deviceDao.updateRawEvent(
      event.copyWith(
        matchedStaffId: Value<String?>(staffId),
        resultingAttendanceId: const Value<int?>(null),
        status: 'error',
        errorMessage: Value<String?>('فشل معالجة الحضور: $error'),
        processedAt: Value<DateTime?>(DateTime.now()),
      ),
    );
  }

  Future<void> _markGroupError(_ResolvedGroup group, Object error) async {
    for (final event in group.events) {
      try {
        await _markRetryError(event.raw, error, staffId: event.staffId);
      } catch (_) {}
    }
  }

  Future<List<AttendanceRawEvent>> _historyForGroup(
    String staffId,
    DateTime workDate,
    ScheduleConfig schedule,
  ) async {
    final from = _dateOnly(workDate);
    final nextDay = from.add(const Duration(days: 1));
    final to = _isOvernightSchedule(schedule)
        ? nextDay.add(const Duration(hours: 4, minutes: 1))
        : from.add(const Duration(hours: 28));
    final history = await _deviceDao.getMatchedEventsForStaff(
      staffId,
      from,
      to,
    );
    final relevant = <AttendanceRawEvent>[];

    for (final event in history) {
      final linkedId = event.resultingAttendanceId;
      if (linkedId == null) {
        relevant.add(event);
        continue;
      }
      final eventDate = _dateOnly(event.eventTime);
      final isEarlyNextDay =
          _isOvernightSchedule(schedule) &&
          eventDate == nextDay &&
          event.eventTime.hour < 4;
      final linkedAttendance = await _staffDao.getAttendanceById(linkedId);
      final isReparentableDeviceRow =
          linkedAttendance?.staffId == staffId &&
          linkedAttendance?.source == 'device' &&
          linkedAttendance?.sourceDeviceId == event.deviceId &&
          linkedAttendance?.checkOutTime == null;
      if (linkedAttendance == null ||
          _dateOnly(linkedAttendance.date) == workDate ||
          (isEarlyNextDay && isReparentableDeviceRow)) {
        relevant.add(event);
      }
    }

    return relevant;
  }

  _AttendanceCandidate? _earliestCandidate(
    Iterable<_AttendanceCandidate> candidates,
  ) {
    _AttendanceCandidate? selected;
    for (final candidate in candidates) {
      if (selected == null ||
          candidate.time.isBefore(selected.time) ||
          (candidate.time == selected.time &&
              candidate.isExisting &&
              !selected.isExisting)) {
        selected = candidate;
      }
    }
    return selected;
  }

  _AttendanceCandidate? _latestCandidate(
    Iterable<_AttendanceCandidate> candidates,
  ) {
    _AttendanceCandidate? selected;
    for (final candidate in candidates) {
      if (selected == null ||
          candidate.time.isAfter(selected.time) ||
          (candidate.time == selected.time &&
              candidate.protectedExisting &&
              !selected.protectedExisting)) {
        selected = candidate;
      }
    }
    return selected;
  }

  bool _isOvernightSchedule(ScheduleConfig schedule) {
    return schedule.workEndMinutesSinceMidnight <=
        schedule.workStartMinutesSinceMidnight;
  }

  DateTime _scheduleEndFor(DateTime workDate, ScheduleConfig schedule) {
    var end = DateTime(
      workDate.year,
      workDate.month,
      workDate.day,
      schedule.workEndHour,
      schedule.workEndMinute,
    );
    if (_isOvernightSchedule(schedule)) {
      end = end.add(const Duration(days: 1));
    }
    return end;
  }

  Future<void> _processGroup({
    required int deviceId,
    required String staffId,
    required DateTime workDate,
    required ScheduleConfig schedule,
    required List<_ResolvedEvent> newEvents,
  }) async {
    final attendanceRows = await _staffDao.getAttendanceOnDate(
      staffId,
      workDate,
    );
    if (_hasManualAbsent(attendanceRows)) {
      throw const _ProtectedAttendanceException(
        'سجل غياب يدوي: لم يتم تعديل الحضور',
      );
    }
    if (_hasProtectedAttendance(attendanceRows)) {
      throw const _ProtectedAttendanceException(
        'سجل حضور محفوظ مسبقًا: يحتاج مراجعة يدوية',
      );
    }
    final existing = attendanceRows.isEmpty
        ? null
        : _selectAttendanceRow(attendanceRows);

    final history = await _historyForGroup(staffId, workDate, schedule);
    final allById = <int, AttendanceRawEvent>{
      for (final event in history) event.id: event,
      for (final event in newEvents) event.raw.id: event.raw,
    };
    final allEvents = allById.values.toList()..sort(_compareRawEvents);

    final retainedEvents = <AttendanceRawEvent>[];
    final duplicateIds = <int>{};
    DateTime? previousTime;
    for (final event in allEvents) {
      if (previousTime != null &&
          event.eventTime.difference(previousTime) < _duplicateWindow) {
        duplicateIds.add(event.id);
      } else {
        retainedEvents.add(event);
        previousTime = event.eventTime;
      }
    }

    final isAutoAbsent =
        existing?.source == 'auto_generated' &&
        existing?.status == 'absent' &&
        existing?.checkInTime == null;
    final checkinCandidates = <_AttendanceCandidate>[];
    if (existing != null && existing.checkInTime != null) {
      checkinCandidates.add(
        _AttendanceCandidate(time: existing.checkInTime!, isExisting: true),
      );
    }
    if (isAutoAbsent && existing?.checkOutTime != null) {
      checkinCandidates.add(
        _AttendanceCandidate(time: existing!.checkOutTime!, isExisting: true),
      );
    }
    for (final event in retainedEvents) {
      checkinCandidates.add(
        _AttendanceCandidate(time: event.eventTime, raw: event),
      );
    }

    final checkin = _earliestCandidate(checkinCandidates);
    if (checkin == null) {
      throw StateError('attendance group has no check-in candidate');
    }

    final scheduleEnd = _scheduleEndFor(workDate, schedule);
    final thresholdByDuration = checkin.time.add(_minCheckoutAfterCheckIn);
    final thresholdBySchedule = scheduleEnd.subtract(
      _checkoutThresholdBeforeEnd,
    );
    final checkoutThreshold = thresholdByDuration.isAfter(thresholdBySchedule)
        ? thresholdByDuration
        : thresholdBySchedule;

    final checkoutCandidates = <_AttendanceCandidate>[];
    for (final event in retainedEvents) {
      if (event.eventTime.isAfter(checkin.time) &&
          !event.eventTime.isBefore(checkoutThreshold)) {
        checkoutCandidates.add(
          _AttendanceCandidate(time: event.eventTime, raw: event),
        );
      }
    }
    if (_isOvernightSchedule(schedule)) {
      final nextDayStart = _dateOnly(workDate).add(const Duration(days: 1));
      final earlyWindowEnd = nextDayStart.add(const Duration(hours: 4));
      for (final event in retainedEvents) {
        if (!event.eventTime.isBefore(nextDayStart) &&
            event.eventTime.isBefore(earlyWindowEnd) &&
            event.eventTime.isAfter(checkin.time)) {
          checkoutCandidates.add(
            _AttendanceCandidate(time: event.eventTime, raw: event),
          );
        }
      }
    }
    if (existing != null &&
        existing.checkOutTime != null &&
        !isAutoAbsent &&
        existing.checkOutTime!.isAfter(checkin.time)) {
      checkoutCandidates.add(
        _AttendanceCandidate(
          time: existing.checkOutTime!,
          isExisting: true,
          protectedExisting: existing.source != 'device',
        ),
      );
    }
    final checkout = _latestCandidate(checkoutCandidates);

    final notes = <int, String>{};
    void addNote(int eventId, String note) {
      final current = notes[eventId];
      if (current == null) {
        notes[eventId] = note;
      } else if (!current.split('; ').contains(note)) {
        notes[eventId] = '$current; $note';
      }
    }

    for (final event in allEvents) {
      if (duplicateIds.contains(event.id)) {
        addNote(event.id, 'duplicate within 10min window — ignored');
        continue;
      }
      if (event.id == checkin.raw?.id || event.id == checkout?.raw?.id) {
        continue;
      }
      if (!event.eventTime.isAfter(checkin.time)) continue;
      if (event.eventTime.isBefore(checkoutThreshold)) {
        addNote(event.id, 'before checkout threshold — kept open for review');
      } else if (checkout != null) {
        if (event.eventTime == checkout.time) {
          addNote(event.id, 'matches existing check-out');
        } else if (event.eventTime.isBefore(checkout.time)) {
          addNote(event.id, 'superseded by later event');
        }
      }
    }

    final checkoutTime = checkout != null && checkout.time.isAfter(checkin.time)
        ? checkout.time
        : null;
    final result = _engine.calculateAttendance(
      checkInTime: checkin.time,
      checkOutTime: checkoutTime,
      schedule: schedule,
    );
    var status = result.status;
    double? workingHours = existing?.workingHours;
    var overtimeHours = existing?.overtimeHours ?? 0.0;
    if (checkoutTime != null) {
      workingHours = result.workingHours;
      overtimeHours = result.overtimeHours;
    }

    final origin = checkin.raw ?? retainedEvents.first;
    final now = DateTime.now();
    late final Attendance attendance;
    if (existing == null) {
      final newId = await _staffDao.addAttendanceReturningId(
        AttendanceTableCompanion.insert(
          staffId: staffId,
          date: workDate,
          status: status,
          checkInTime: Value<DateTime?>(checkin.time),
          checkOutTime: Value<DateTime?>(checkout?.time),
          workingHours: Value<double?>(workingHours),
          overtimeHours: Value<double>(overtimeHours),
          source: const Value('device'),
          sourceDeviceId: Value<int?>(deviceId),
          rawEventId: Value<int?>(origin.id),
          createdAt: now,
          updatedAt: now,
        ),
      );
      final inserted = await _staffDao.getAttendanceById(newId);
      if (inserted == null) {
        throw StateError('inserted attendance could not be loaded');
      }
      attendance = inserted;
    } else {
      final useDeviceOrigin = isAutoAbsent;
      attendance = existing.copyWith(
        checkInTime: Value<DateTime?>(checkin.time),
        checkOutTime: Value<DateTime?>(checkout?.time),
        workingHours: Value<double?>(workingHours),
        status: status,
        overtimeHours: overtimeHours,
        source: isAutoAbsent
            ? const Value<String?>('device')
            : const Value<String?>.absent(),
        sourceDeviceId: useDeviceOrigin
            ? Value<int?>(deviceId)
            : const Value<int?>.absent(),
        rawEventId: useDeviceOrigin
            ? Value<int?>(origin.id)
            : const Value<int?>.absent(),
        updatedAt: now,
      );
      await _staffDao.updateAttendance(attendance);
    }

    final processedAt = DateTime.now();
    for (final event in allEvents) {
      await _deviceDao.updateRawEvent(
        event.copyWith(
          matchedStaffId: Value<String?>(staffId),
          resultingAttendanceId: Value<int?>(attendance.id),
          status: 'matched',
          errorMessage: Value<String?>(notes[event.id]),
          processedAt: Value<DateTime?>(processedAt),
        ),
      );
    }

    // v72: the stale-attendance DELETE is intentionally removed.
    //
    // It used to hard-delete any attendance row a re-matched raw event had
    // previously produced. Two ways that destroys real data: a re-punch on a
    // day an admin had marked with a permission erased that permission, and
    // an attendance row that had already fed a payslip silently disappeared
    // with no trace. Baseline 5eb58db has no such deletion either.
    //
    // The raw events keep pointing at the surviving attendance row, so nothing
    // is orphaned; superseded rows simply stay and remain visible in the
    // employee's history for a human to reconcile.
    //
    // Reinstating this needs its own reviewed change plus a proof that no
    // already-paid payroll period references the rows being removed.
  }

  /// ينشئ موظف جديد تلقائياً من بصمة الجهاز ويربطه مباشرة.
  /// الاسم الافتراضي "موظف {externalId}" ويمكن تعديله لاحقاً من إدارة الموظفين.
  Future<String> _autoCreateStaffForExternalId(
    int deviceId,
    String externalUserId,
  ) async {
    return _deviceDao.attachedDatabase.transaction(() async {
      final existing = await _deviceDao.getMappingRecordByExternalId(
        deviceId,
        externalUserId,
      );
      if (existing != null) return existing.staffId;

      final allStaff = await _staffDao.getAllStaff();
      var maxId = 0;
      for (final staff in allStaff) {
        final numericId =
            int.tryParse(staff.staffId.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
        if (numericId > maxId) maxId = numericId;
      }
      final newStaffId = 'STAFF${(maxId + 1).toString().padLeft(4, '0')}';
      final now = DateTime.now();

      await _staffDao.addStaff(
        StaffTableCompanion.insert(
          staffId: newStaffId,
          name: 'موظف $externalUserId',
          position: 'موظف',
          employmentType: 'full_time',
          basicSalary: 0,
          hireDate: now,
          status: 'active',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await _deviceDao.addMapping(
        StaffBiometricMappingsCompanion.insert(
          staffId: newStaffId,
          deviceId: deviceId,
          externalUserId: externalUserId,
          enrollmentStatus: 'enrolled',
          createdAt: now,
          updatedAt: now,
        ),
      );
      return newStaffId;
    });
  }
}
