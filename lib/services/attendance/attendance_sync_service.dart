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

  /// Per-event processing failures (raw status 'error', retryable).
  /// Folded into `unmatched` for sync-status purposes by the caller.
  final int errorCount;

  const SyncResult({
    required this.fetched,
    required this.matched,
    required this.unmatched,
    required this.duplicate,
    this.error,
    this.errorCount = 0,
  });
}

/// One raw event with its resolved owner and payroll work-date (pass 1 output).
class _ResolvedEvent {
  final AttendanceRawEvent raw;
  final String staffId;
  final DateTime workDate;
  const _ResolvedEvent(this.raw, this.staffId, this.workDate);
}

class AttendanceSyncService {
  final AttendanceDeviceDao _deviceDao;
  final StaffManagementDao _staffDao;
  final AttendanceCalculationEngine _engine;

  /// Prevents concurrent syncs for the same device
  final Set<int> _syncingDevices = {};

  /// Auto-sync timer
  Timer? _autoSyncTimer;
  bool _isAutoSyncEnabled = false;

  AttendanceSyncService(this._deviceDao, this._staffDao, this._engine);

  /// Whether auto-sync is currently running
  bool get isAutoSyncEnabled => _isAutoSyncEnabled;

  /// Starts periodic auto-sync for all active devices — يعمل في الخلفية حتى مع Wi-Fi/نت متقطع
  /// Interval is 5 minutes to reduce overlap with manual syncs and device load.
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

  /// Triggers a sync for all active devices
  Future<void> syncAllDevices({String triggeredBy = 'manual'}) async {
    // Crash recovery: a 'running' log older than 10min means its sync died
    // mid-run — close it as failed so it never blocks future syncs.
    await _deviceDao.markStaleRunningFailed(
      DateTime.now().subtract(const Duration(minutes: 10)),
      'stale lock recovered: sync did not finish within 10min',
    );
    final devices = await _deviceDao.getAllDevices();
    for (final device in devices.where((d) => d.isActive)) {
      // DB-backed guard: skip a device another sync (manual vs auto) is
      // currently processing. In-memory _syncingDevices covers same-process
      // re-entry; this covers cross-trigger overlap.
      final running = await _deviceDao.getRunningLogForDevice(
        device.id,
        DateTime.now().subtract(const Duration(minutes: 10)),
      );
      if (running != null) continue;
      await syncDevice(device, triggeredBy: triggeredBy);
    }
  }

  /// Triggers a sync for a specific device
  Future<void> syncDevice(
    BiometricDevice device, {
    String triggeredBy = 'manual',
  }) async {
    // Prevent concurrent syncs for the same device
    if (_syncingDevices.contains(device.id)) {
      return;
    }
    _syncingDevices.add(device.id);

    try {
      // Cursor rule (locked): the cursor value for THIS run is fixed here.
      // It advances to fetchStartTime only after fetchOk + ingest + process
      // all succeed (zero-record success included — its ingest+process are
      // vacuously successful). Never DateTime.now() after processing.
      final fetchStartTime = DateTime.now();
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

      try {
        // 1. Instantiate the correct source based on connection type
        if (device.connectionType == 'tcp_ip') {
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
          String detail = 'فشل الاتصال بالجهاز ${device.ipAddress}:${device.port}';
          if (source is ZKTecoTcpAttendanceSource && source.lastError != null) {
            detail = source.lastError!;
          }
          throw Exception(detail);
        }

        // مزامنة وقت الجهاز إذا انحرف أكثر من 5 دقائق (best-effort)
        try {
          if (source is ZKTecoTcpAttendanceSource) {
            final info = await source.getDeviceInfo();
            if (info.deviceTime != null) {
              final drift = DateTime.now().difference(info.deviceTime!).abs();
              if (drift > const Duration(minutes: 5)) {
                await source.setDeviceTime(DateTime.now());
              }
            }
          }
        } catch (_) {}

        // 3. Fetch events with 15-minute overlap: late-arriving device events
        // (timestamp <= previous cursor) must be refetched, not lost.
        // Dedup via dedupHash makes the overlap safe.
        final overlapSince = device.lastSyncAt == null
            ? null
            : device.lastSyncAt!.subtract(const Duration(minutes: 15));
        List<RawAttendanceEvent> events;
        try {
          events = await source.fetchEvents(since: overlapSince);
        } on ZkTransportException {
          // One bounded retry for weak-network races, then fail the run
          // (cursor preserved). Business errors are never retried here.
          await Future.delayed(const Duration(seconds: 2));
          events = await source.fetchEvents(since: overlapSince);
        }
        // Parser-ambiguity guard: dropped chunks + zero parsed records means
        // the payload does not match our record layout — this is NOT a
        // legitimate zero. Fail closed so the cursor is preserved.
        if (source is ZKTecoTcpAttendanceSource) {
          final report = source.lastFetchReport;
          if (report != null &&
              report.droppedChunks > 0 &&
              events.isEmpty) {
            throw Exception(
              'parser mismatch: dropped ${report.droppedChunks} chunks '
              'of ${report.rawBytes} bytes'
              '${report.debugSample == null ? '' : ' (sample: ${report.debugSample})'}',
            );
          }
        }
        fetched = events.length;

        // 4. Ingest raw events atomically: all-or-nothing per run, so a
        // mid-ingest crash never leaves a half-ingested batch behind.
        await _deviceDao.attachedDatabase.transaction(() async {
          for (final event in events) {
            // Generate Dedup Hash: sha256(deviceId + externalUserId + eventTime)
            final hashStr =
                '${device.id}_${event.externalUserId}_${event.eventTime.toIso8601String()}';
            final dedupHash = sha256.convert(utf8.encode(hashStr)).toString();

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

            final resultId = await _deviceDao.addRawEvent(rawCompanion);
            if (resultId == 0) {
              duplicate++;
            }
          }
        });

        // 5. Process pending events (Matching & Heuristics)
        final processResult = await processPendingEvents(device.id);
        matched = processResult.matched;
        // Retryable per-event errors keep raw status 'error' (retried next
        // run) but count as unmatched for sync-status/display purposes.
        unmatched = processResult.unmatched + processResult.errorCount;

        // Sync-state rule (locked): success requires zero unmatched;
        // any unmatched/error business outcome is 'partial', never silent
        // success. fetchOkEmpty (fetched == 0) is success — its ingest and
        // process phases are vacuously complete — and still advances the
        // cursor to fetchStartTime. Any exception below skips this block,
        // preserving the old cursor.
        final syncStatus = unmatched == 0 ? 'success' : 'partial';
        await _deviceDao.updateDevice(
          device.copyWith(
            lastSyncAt: Value(fetchStartTime),
            lastSyncStatus: Value(syncStatus),
            lastSyncError: const Value(null),
          ),
        );
      } catch (e) {
        error = e.toString();
        await _deviceDao.updateDevice(
          device.copyWith(
            lastSyncStatus: Value('failed'),
            lastSyncError: Value(error),
          ),
        );
      } finally {
        // Always disconnect the source
        try {
          await source?.disconnect();
        } catch (_) {}

        // Update sync log
        final currentLog = await _deviceDao.getSyncLogById(logId);
        if (currentLog != null) {
          // Truth table (locked): error==null + unmatched==0 → success
          // (fetched==0 included: success_no_new_records at display layer);
          // error==null + unmatched>0 → partial; exception → failed.
          final logStatus =
              error == null ? (unmatched == 0 ? 'success' : 'partial') : 'failed';
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
    } finally {
      _syncingDevices.remove(device.id);
    }
  }

  /// Locked business rules (payroll-safe, see plan patch):
  /// - _duplicateWindow (10min): punches within 10min of the last accepted
  ///   event are ignored — no false morning checkout.
  /// - Checkout threshold: minCheckout = max(checkIn + 4h, scheduledEnd − 2h).
  ///   Events before it never create a checkout (a missing checkout stays
  ///   open for review; a 1-hour false checkout would corrupt payroll).
  /// - Checkout = latest event at/after minCheckout, else none.
  /// - Each (staff, workDate) group recomputes from matched history, so
  ///   retries and late/out-of-order events converge (idempotent).
  static const _duplicateWindow = Duration(minutes: 10);
  static const _minCheckoutAfterCheckIn = Duration(hours: 4);
  static const _checkoutThresholdBeforeEnd = Duration(hours: 2);

  /// Processes raw events for a specific device, matches them to staff, and creates attendance records.
  ///
  /// Pass 1 resolves staff per event; pass 2 recomputes each (staff, workDate)
  /// group in its own transaction. One bad event never aborts the batch.
  Future<SyncResult> processPendingEvents(int deviceId) async {
    // 'pending' + 'error' (retryable). 'matched'/'ignored'/'unmatched' are
    // terminal and never reprocessed here.
    final pendingEvents = await _deviceDao.getRetryableEventsForDevice(
      deviceId,
    );

    // Sort chronologically
    pendingEvents.sort((a, b) => a.eventTime.compareTo(b.eventTime));

    int matched = 0;
    int unmatched = 0;
    int errorCount = 0;
    final resolved = <_ResolvedEvent>[];

    for (final rawEvent in pendingEvents) {
      // Pass 1 — resolve staff + work-date. Business vetos are marked
      // 'unmatched' inside _resolveStaffForEvent (returns null); unexpected
      // failures are marked 'error' here and retried next run.
      try {
        final staffId = await _resolveStaffForEvent(deviceId, rawEvent);
        if (staffId == null) {
          unmatched++;
          continue;
        }
        final workDate = await _resolveWorkDate(staffId, rawEvent.eventTime);
        resolved.add(_ResolvedEvent(rawEvent, staffId, workDate));
      } catch (e) {
        await _deviceDao.updateRawEvent(
          rawEvent.copyWith(
            status: 'error',
            errorMessage: Value('processing failed, will retry: $e'),
            processedAt: Value(DateTime.now()),
          ),
        );
        errorCount++;
        continue;
      }
    } // end Pass 1

    // Pass 2 — group by (staff, workDate); each group recomputes inside its
    // own transaction so the attendance write and all raw markings commit
    // atomically (raw=matched always implies attendance exists).
    final groups = <String, List<_ResolvedEvent>>{};
    for (final r in resolved) {
      groups
          .putIfAbsent('${r.staffId}|${r.workDate.toIso8601String()}', () => [])
          .add(r);
    }
    for (final group in groups.values) {
      try {
        await _processGroup(deviceId, group);
        matched += group.length;
      } catch (e) {
        for (final r in group) {
          await _deviceDao.updateRawEvent(
            r.raw.copyWith(
              matchedStaffId: Value(r.staffId),
              status: 'error',
              errorMessage: Value('group failed, will retry: $e'),
              processedAt: Value(DateTime.now()),
            ),
          );
        }
        errorCount += group.length;
      }
    }

    return SyncResult(
      fetched: pendingEvents.length,
      matched: matched,
      unmatched: unmatched,
      duplicate: 0,
      errorCount: errorCount,
    );
  }

  /// Resolves the staff for one raw event (mapping → auto-create → vetos).
  /// Business vetos are marked 'unmatched' here and yield null.
  /// Unexpected failures throw and are marked 'error' by the caller.
  Future<String?> _resolveStaffForEvent(
    int deviceId,
    AttendanceRawEvent rawEvent,
  ) async {
    // Find staff mapping — لو مفيش ربط، أنشئ موظف تلقائي من الجهاز
    var mapping = await _deviceDao.getMappingByExternalId(
      deviceId,
      rawEvent.externalUserId,
    );

    if (mapping == null) {
      try {
        await _autoCreateStaffForExternalId(
          deviceId,
          rawEvent.externalUserId,
        );
        mapping = await _deviceDao.getMappingByExternalId(
          deviceId,
          rawEvent.externalUserId,
        );
        if (mapping == null) throw Exception('mapping not created');
      } catch (e) {
        await _deviceDao.updateRawEvent(
          rawEvent.copyWith(
            status: 'unmatched',
            errorMessage: Value('فشل الإنشاء التلقائي: $e'),
            processedAt: Value(DateTime.now()),
          ),
        );
        return null;
      }
    }

    final staffId = mapping.staffId;
    final staff = await _staffDao.getStaffById(staffId);

    // Verify that staff is active and not terminated
    if (staff == null || !staff.isActive || staff.status != 'active') {
      await _deviceDao.updateRawEvent(
        rawEvent.copyWith(
          matchedStaffId: Value(staffId),
          status: 'unmatched',
          errorMessage: Value(
            staff == null
                ? 'Staff record not found: $staffId'
                : 'Staff is inactive or terminated (${staff.status})',
          ),
          processedAt: Value(DateTime.now()),
        ),
      );
      return null;
    }

    // منع البصمة الوهمية: كارت/باسورد بدون بصمة/وجه يتطلب مراجعة
    if (rawEvent.rawPayload != null && (rawEvent.rawPayload!.contains('"verifyType":2') || rawEvent.rawPayload!.contains('"verifyType":3'))) {
      await _deviceDao.updateRawEvent(rawEvent.copyWith(matchedStaffId: Value(staffId), status: 'unmatched', errorMessage: Value('تحقق يدوي: بصمة غير بيومترية (كارت/باسورد)'), processedAt: Value(DateTime.now())));
      return null;
    }
    return staffId;
  }

  /// Work-date rule (locked): 00:00–04:00 belongs to the previous day only
  /// when that day has an open record (check-in without check-out);
  /// otherwise it starts a new day.
  Future<DateTime> _resolveWorkDate(
    String staffId,
    DateTime eventTime,
  ) async {
    final date =
        DateTime(eventTime.year, eventTime.month, eventTime.day);
    if (eventTime.hour < 4) {
      final prevDate = date.subtract(const Duration(days: 1));
      final prevRecords =
          await _staffDao.getAttendanceOnDate(staffId, prevDate);
      final hasOpen = prevRecords.any(
        (a) => a.checkOutTime == null && a.checkInTime != null,
      );
      if (hasOpen) return prevDate;
    }
    return date;
  }

  /// Recomputes one (staff, workDate) group from matched history + new events.
  /// Deterministic: same inputs always yield the same attendance row, so
  /// retries and late/out-of-order events converge instead of duplicating.
  Future<void> _processGroup(
    int deviceId,
    List<_ResolvedEvent> group,
  ) async {
    final staffId = group.first.staffId;
    final workDate = group.first.workDate;
    final dayStart =
        DateTime(workDate.year, workDate.month, workDate.day);
    // 28h window covers next-day 00:00–04:00 spill assigned to this date.
    final rangeFrom = dayStart;
    final rangeTo = dayStart.add(const Duration(hours: 28));

    await _deviceDao.attachedDatabase.transaction(() async {
      final history = await _deviceDao.getMatchedEventsForStaff(
        deviceId,
        staffId,
        rangeFrom,
        rangeTo,
      );
      final historyIds = history.map((e) => e.id).toSet();
      final combined = <AttendanceRawEvent>[
        ...history,
        ...group.where((r) => !historyIds.contains(r.raw.id)).map((r) => r.raw),
      ]..sort((a, b) => a.eventTime.compareTo(b.eventTime));

      // Duplicate window: first event accepted; any event <10min after the
      // last accepted one is ignored (morning bursts never become checkout).
      final accepted = <AttendanceRawEvent>[combined.first];
      final windowIgnored = <AttendanceRawEvent>[];
      for (var i = 1; i < combined.length; i++) {
        final ev = combined[i];
        if (ev.eventTime.difference(accepted.last.eventTime) <
            _duplicateWindow) {
          windowIgnored.add(ev);
        } else {
          accepted.add(ev);
        }
      }

      final checkIn = accepted.first.eventTime;
      // Threshold uses the EFFECTIVE check-in: a stored row (e.g. manual
      // 09:00) must not be re-anchored by a later device-only event (17:00),
      // otherwise minCheckout would chase the last event and nothing would
      // ever qualify. Deterministic for the same DB state.
      final existing =
          await _staffDao.getAttendanceOnDate(staffId, workDate);
      final storedCheckIn =
          existing.isEmpty ? null : existing.first.checkInTime;
      var baseCheckIn = checkIn;
      if (storedCheckIn != null && storedCheckIn.isBefore(baseCheckIn)) {
        baseCheckIn = storedCheckIn;
      }
      // Checkout threshold (locked, payroll-safe): an event proves checkout
      // only at/after max(baseCheckIn + 4h, scheduledEnd − 2h). Earlier
      // events leave checkout empty (open for review).
      final schedule = await _engine.getScheduleForStaff(staffId);
      final schedEnd = DateTime(workDate.year, workDate.month, workDate.day,
          schedule.workEndHour, schedule.workEndMinute);
      var minCheckout = baseCheckIn.add(_minCheckoutAfterCheckIn);
      final thresholdEnd = schedEnd.subtract(_checkoutThresholdBeforeEnd);
      if (thresholdEnd.isAfter(minCheckout)) minCheckout = thresholdEnd;
      final candidates = accepted
          .where((e) => !e.eventTime.isBefore(minCheckout))
          .toList();
      final checkOut =
          candidates.isEmpty ? null : candidates.last.eventTime;

      Attendance resulting;
      if (existing.isEmpty) {
        // No row yet — same engine as the manual path.
        String status;
        double? workingHours;
        double overtimeHours = 0;
        int lateMinutes = 0;
        if (checkOut == null) {
          final schedule = await _engine.getScheduleForStaff(staffId);
          final calc = _engine.calculateAttendance(checkInTime: checkIn, schedule: schedule);
          status = calc.status;
          lateMinutes = calc.lateMinutes;
        } else {
          final calc = await _engine.processCheckOut(
            staffId,
            checkInTime: checkIn,
            checkOutTime: checkOut,
          );
          status = calc.status;
          workingHours = calc.workingHours;
          overtimeHours = calc.overtimeHours;
          lateMinutes = calc.lateMinutes;
        }
        final newId = await _staffDao.addAttendanceReturningId(
          AttendanceTableCompanion.insert(
            staffId: staffId,
            date: workDate,
            status: status,
            checkInTime: Value(checkIn),
            checkOutTime:
                checkOut == null ? const Value.absent() : Value(checkOut),
            workingHours: workingHours == null
                ? const Value.absent()
                : Value(workingHours),
            overtimeHours: Value(overtimeHours),
            lateMinutes: Value(lateMinutes),
            source: const Value('device'),
            sourceDeviceId: Value(deviceId),
            rawEventId: Value(group.first.raw.id),
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );
        resulting = (await _staffDao.getAttendanceById(newId))!;
      } else {
        // Row exists (device or manual — manual checkout is preserved, never
        // cleared by recompute; check-in adopts the earliest accepted time).
        final current = existing.first;
        var finalCheckIn = current.checkInTime ?? checkIn;
        if (checkIn.isBefore(finalCheckIn)) finalCheckIn = checkIn;
        var finalCheckOut = current.checkOutTime;
        if (checkOut != null &&
            (finalCheckOut == null || checkOut.isAfter(finalCheckOut))) {
          finalCheckOut = checkOut;
        }
        String status;
        double? workingHours;
        double overtimeHours;
        int lateMinutes = current.lateMinutes;
        if (finalCheckOut == null) {
          final schedule = await _engine.getScheduleForStaff(staffId);
          final calc = _engine.calculateAttendance(checkInTime: finalCheckIn, schedule: schedule);
          status = calc.status;
          lateMinutes = calc.lateMinutes;
          workingHours = current.workingHours;
          overtimeHours = current.overtimeHours;
        } else {
          final calc = await _engine.processCheckOut(
            staffId,
            checkInTime: finalCheckIn,
            checkOutTime: finalCheckOut,
          );
          status = calc.status;
          workingHours = calc.workingHours;
          overtimeHours = calc.overtimeHours;
          lateMinutes = calc.lateMinutes;
        }
        final updated = current.copyWith(
          checkInTime: Value(finalCheckIn),
          checkOutTime: Value(finalCheckOut),
          workingHours: Value(workingHours),
          overtimeHours: overtimeHours,
          lateMinutes: lateMinutes,
          status: status,
          updatedAt: DateTime.now(),
        );
        await _staffDao.updateAttendance(updated);
        resulting = updated;
      }

      // Mark every event of the recompute (history re-marked idempotently).
      for (final ev in combined) {
        String? note;
        if (ev.id != accepted.first.id &&
            (checkOut == null || ev.eventTime != checkOut)) {
          if (windowIgnored.any((w) => w.id == ev.id)) {
            note = 'duplicate within 10min window — ignored';
          } else if (checkOut == null) {
            note = 'before checkout threshold — kept open for review';
          } else {
            note = 'superseded by later event';
          }
        }
        await _deviceDao.updateRawEvent(
          ev.copyWith(
            matchedStaffId: Value(staffId),
            status: 'matched',
            resultingAttendanceId: Value(resulting.id),
            errorMessage:
                note == null ? const Value(null) : Value(note),
            processedAt: Value(DateTime.now()),
          ),
        );
      }
    });
  }

  /// ينشئ موظف جديد تلقائياً من بصمة الجهاز ويربطه مباشرة.
  /// الاسم الافتراضي "موظف {externalId}" ويمكن تعديله لاحقاً من إدارة الموظفين.
  Future<String> _autoCreateStaffForExternalId(
    int deviceId,
    String externalUserId,
  ) async {
    final existing = await _deviceDao.getMappingByExternalId(
      deviceId,
      externalUserId,
    );
    if (existing != null) return existing.staffId;

    final allStaff = await _staffDao.getAllStaff();
    int maxId = 0;
    for (final s in allStaff) {
      final n = int.tryParse(s.staffId.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
      if (n > maxId) maxId = n;
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
  }
}
