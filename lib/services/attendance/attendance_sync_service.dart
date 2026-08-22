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
import 'zkteco_tcp_attendance_source.dart';

class SyncResult {
  final int fetched;
  final int matched;
  final int unmatched;
  final int duplicate;
  final String? error;

  const SyncResult({
    required this.fetched,
    required this.matched,
    required this.unmatched,
    required this.duplicate,
    this.error,
  });
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

  /// Triggers a sync for all active devices
  Future<void> syncAllDevices({String triggeredBy = 'manual'}) async {
    final devices = await _deviceDao.getAllDevices();
    for (final device in devices.where((d) => d.isActive)) {
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

        // 2. Connect
        final connected = await source.connect();
        if (!connected) {
          throw Exception('Failed to connect to device');
        }

        // 3. Fetch events (passing lastSyncAt as an optimization hint)
        final events = await source.fetchEvents(since: device.lastSyncAt);
        fetched = events.length;

        // 4. Ingest raw events
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

        // 5. Process pending events (Matching & Heuristics)
        final processResult = await processPendingEvents(device.id);
        matched = processResult.matched;
        unmatched = processResult.unmatched;

        // Update device lastSync status
        await _deviceDao.updateDevice(
          device.copyWith(
            lastSyncAt: Value(DateTime.now()),
            lastSyncStatus: Value('success'),
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
          await _deviceDao.updateSyncLog(
            currentLog.copyWith(
              finishedAt: Value(DateTime.now()),
              status: error == null ? 'success' : 'failed',
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

  /// Processes raw events for a specific device, matches them to staff, and creates attendance records.
  Future<SyncResult> processPendingEvents(int deviceId) async {
    final pendingEvents = await _deviceDao.getUnprocessedEventsForDevice(
      deviceId,
    );

    // Sort chronologically
    pendingEvents.sort((a, b) => a.eventTime.compareTo(b.eventTime));

    int matched = 0;
    int unmatched = 0;

    for (final rawEvent in pendingEvents) {
      // Find staff mapping
      final mapping = await _deviceDao.getMappingByExternalId(
        deviceId,
        rawEvent.externalUserId,
      );

      if (mapping == null) {
        // Mark as unmatched
        await _deviceDao.updateRawEvent(
          rawEvent.copyWith(
            status: 'unmatched',
            processedAt: Value(DateTime.now()),
          ),
        );
        unmatched++;
        continue;
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
        unmatched++;
        continue;
      }

      // Update raw event with matched staff
      var updatedEvent = rawEvent.copyWith(matchedStaffId: Value(staffId));

      // --- Heuristic: First event of day = check-in, Next event = check-out ---
      // Get today's attendance for this staff
      final date = DateTime(
        rawEvent.eventTime.year,
        rawEvent.eventTime.month,
        rawEvent.eventTime.day,
      );
      final nextDay = date.add(const Duration(days: 1));

      final attendanceRecords = await _staffDao.getAttendanceByStaff(
        staffId,
        startDate: date,
        endDate: nextDay,
      );

      // Filter strictly to today's date (compare date components only)
      final todayRecords = attendanceRecords.where((a) {
        final aDate = DateTime(a.date.year, a.date.month, a.date.day);
        return aDate == date;
      }).toList();

      Attendance? resultingAttendance;

      if (todayRecords.isEmpty) {
        // No attendance today -> This is a check-in (حساب الحالة بنفس محرك المسار اليدوي)
        final status = await _engine.processCheckIn(
          staffId,
          checkInTime: rawEvent.eventTime,
        );
        final companion = AttendanceTableCompanion.insert(
          staffId: staffId,
          date: date,
          status: status,
          checkInTime: Value(rawEvent.eventTime),
          source: const Value('device'),
          sourceDeviceId: Value(deviceId),
          rawEventId: Value(rawEvent.id),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        final newId = await _staffDao.addAttendanceReturningId(companion);
        // Fetch only the inserted record
        resultingAttendance = await _staffDao.getAttendanceById(newId);
        if (resultingAttendance == null) {
          // Fallback: skip this event if we can't fetch the record
          continue;
        }
      } else {
        // Attendance exists -> Update check-out
        final currentRecord = todayRecords.first;
        // Only update if checkout is null OR if this event is LATER than existing checkout
        if (currentRecord.checkOutTime == null ||
            rawEvent.eventTime.isAfter(currentRecord.checkOutTime!)) {
          // حساب ساعات العمل والأوفرتايم بنفس منطق مسار الحضور اليدوي
          final checkInTime = currentRecord.checkInTime;
          final result = checkInTime != null
              ? await _engine.processCheckOut(
                  staffId,
                  checkInTime: checkInTime,
                  checkOutTime: rawEvent.eventTime,
                )
              : null;
          final updatedRecord = currentRecord.copyWith(
            checkOutTime: Value(rawEvent.eventTime),
            workingHours: result == null
                ? const Value(null)
                : Value(result.workingHours),
            overtimeHours: result?.overtimeHours ?? currentRecord.overtimeHours,
            status: result?.status ?? currentRecord.status,
            updatedAt: DateTime.now(),
          );
          await _staffDao.updateAttendance(updatedRecord);
          resultingAttendance = updatedRecord;
        } else {
          resultingAttendance = currentRecord;
        }
      }

      // Mark raw event as processed
      updatedEvent = updatedEvent.copyWith(
        status: 'matched',
        resultingAttendanceId: Value(resultingAttendance.id),
        processedAt: Value(DateTime.now()),
      );
      await _deviceDao.updateRawEvent(updatedEvent);
      matched++;
    }

    return SyncResult(
      fetched: pendingEvents.length,
      matched: matched,
      unmatched: unmatched,
      duplicate: 0,
    );
  }
}
