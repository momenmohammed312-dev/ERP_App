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

  /// Starts periodic auto-sync for all active devices — يعمل في الخلفية حتى مع Wi-Fi/نت متقطع
  void startAutoSync({Duration interval = const Duration(minutes: 2)}) {
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

        // 2. Connect — مع تمرير السبب الحقيقي (packet loss / CommKey / timeout)
        final connected = await source.connect();
        if (!connected) {
          String detail = 'فشل الاتصال بالجهاز ${device.ipAddress}:${device.port}';
          if (source is ZKTecoTcpAttendanceSource && source.lastError != null) {
            detail = source.lastError!;
          }
          throw Exception(detail);
        }

        // مزامنة وقت الجهاز إذا انحرف أكثر من دقيقتين (سبب 8:10 → 8:18)
        try {
          if (source is ZKTecoTcpAttendanceSource) {
            final info = await source.getDeviceInfo();
            if (info.deviceTime != null) {
              final drift = DateTime.now().difference(info.deviceTime!).abs();
              if (drift > const Duration(minutes: 2)) {
                await source.setDeviceTime(DateTime.now());
              }
            }
          }
        } catch (_) {}

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
      // Find staff mapping — لو مفيش ربط، أنشئ موظف تلقائي من الجهاز
      var mapping = await _deviceDao.getMappingByExternalId(
        deviceId,
        rawEvent.externalUserId,
      );

      if (mapping == null) {
        try {
          final newStaffId = await _autoCreateStaffForExternalId(
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
          unmatched++;
          continue;
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
        unmatched++;
        continue;
      }

      // منع البصمة الوهمية: كارت/باسورد بدون بصمة/وجه يتطلب مراجعة
      if (rawEvent.rawPayload != null && (rawEvent.rawPayload!.contains('"verifyType":2') || rawEvent.rawPayload!.contains('"verifyType":3'))) {
        await _deviceDao.updateRawEvent(rawEvent.copyWith(matchedStaffId: Value(staffId), status: 'unmatched', errorMessage: Value('تحقق يدوي: بصمة غير بيومترية (كارت/باسورد)'), processedAt: Value(DateTime.now())));
        unmatched++;
        continue;
      }
      final date = DateTime(rawEvent.eventTime.year, rawEvent.eventTime.month, rawEvent.eventTime.day);

      // منع التكرار السريع (anti-passback 2 دقيقة)
      if (rawEvent.eventType != null && rawEvent.eventTime.difference(date).inMinutes < 2) {
        // سيتم فحصه عبر dedupHash أصلاً
      }

      var updatedEvent = rawEvent.copyWith(matchedStaffId: Value(staffId));

      // حل جذري لانصراف 5 صباحاً: بصمة 00:00-04:00 تُحسب لليوم السابق إذا له حضور مفتوح
      if (rawEvent.eventTime.hour < 4) {
        final prevDate = date.subtract(const Duration(days: 1));
        final prevRecords = await _staffDao.getAttendanceOnDate(staffId, prevDate);
        final openPrev = prevRecords.where((a) => a.checkOutTime == null && a.checkInTime != null).toList();
        if (openPrev.isNotEmpty) {
          final prevRec = openPrev.first;
          final result = await _engine.processCheckOut(staffId, checkInTime: prevRec.checkInTime!, checkOutTime: rawEvent.eventTime);
          final updatedPrev = prevRec.copyWith(
            checkOutTime: Value(rawEvent.eventTime),
            workingHours: Value(result.workingHours),
            overtimeHours: result.overtimeHours,
            status: result.status,
            updatedAt: DateTime.now(),
          );
          await _staffDao.updateAttendance(updatedPrev);
          updatedEvent = updatedEvent.copyWith(status: 'matched', resultingAttendanceId: Value(updatedPrev.id), processedAt: Value(DateTime.now()));
          await _deviceDao.updateRawEvent(updatedEvent);
          matched++;
          continue;
        }
      }

      final nextDay = date.add(const Duration(days: 1));
      final attendanceRecords = await _staffDao.getAttendanceByStaff(staffId, startDate: date, endDate: nextDay);
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
