import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/dao/attendance_device_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/staff_management_dao.dart';
import 'package:pos_offline_desktop/services/attendance/attendance_calculation_engine.dart';
import 'package:pos_offline_desktop/services/attendance/attendance_sync_service.dart';
import 'package:pos_offline_desktop/services/attendance/zkteco/zkteco_client.dart';
import 'package:pos_offline_desktop/services/attendance/zkteco/zkteco_packet_codec.dart';

/// يتحقق أن مسار الحضور من جهاز البصمة يستخدم نفس محرك الحساب (AttendanceCalculationEngine)
/// المستخدم في المسار اليدوي: بصمة الساعة 12 تبقى 'late'، والخروج بعد 9 ساعات يعطي overtime.
void main() {
  late AppDatabase db;
  late StaffManagementDao staffDao;
  late AttendanceDeviceDao deviceDao;
  late AttendanceSyncService syncService;
  late AttendanceCalculationEngine engine;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    staffDao = db.staffManagementDao;
    deviceDao = db.attendanceDeviceDao;
    engine = AttendanceCalculationEngine(db, deviceDao, staffDao);
    await insertDefaultAttendanceSettings(db);
    syncService = AttendanceSyncService(deviceDao, staffDao, engine);
  });

  tearDown(() async {
    await db.close();
  });

  test(
    'fingerprint at 12:00 is late, not present (default schedule 9:00 + 15 min grace)',
    () async {
      final staffId = await addStaff(staffDao, 'STAFF0001');
      final deviceId = await addDevice(deviceDao);
      await addMapping(deviceDao, deviceId, staffId, 'UID-001');

      final checkInTime = DateTime(2026, 1, 14, 12, 0);
      await addRawEvent(
        deviceDao,
        deviceId,
        'UID-001',
        checkInTime,
        'hash-checkin-1',
      );

      final result = await syncService.processPendingEvents(deviceId);
      expect(result.matched, 1);

      final records = await staffDao.getAttendanceByStaff(staffId);
      expect(records, hasLength(1));
      expect(records.first.status, 'late');
      expect(records.first.checkInTime, checkInTime);
      expect(records.first.source, 'device');
      expect(records.first.sourceDeviceId, deviceId);
      expect(records.first.rawEventId, isNotNull);
    },
  );

  test('duplicate attendance rows for the same day are ALLOWED (v72)', () async {
    // ───────────────────────────────────────────────────────────────────────
    // Why this test now asserts the OPPOSITE of what it used to:
    //
    // The v59 work added UNIQUE(staff_id, date) to attendance_table and made
    // this test prove the constraint threw. That constraint is FROZEN OUT by
    // the v72 restoration and must not be reintroduced to satisfy a test.
    //
    // A device sync and a historical file import can both legitimately produce
    // a row for the same staff/date. Under the constraint the second INSERT
    // raised a SqliteException and the punch was silently lost, which is worse
    // than a duplicate row a human can see and reconcile.
    //
    // What still matters, and is what this test now pins: the DAO normalises
    // the stored `date` to local midnight, so 12:00 and 12:30 on the same day
    // both land on the same day value.
    // ───────────────────────────────────────────────────────────────────────
    final staffId = await addStaff(staffDao, 'STAFF0013');
    final firstNoon = DateTime(2026, 1, 14, 12);
    final secondNoon = DateTime(2026, 1, 14, 12, 30);

    await staffDao.addAttendance(
      AttendanceTableCompanion.insert(
        staffId: staffId,
        date: firstNoon,
        status: 'present',
        createdAt: firstNoon,
        updatedAt: firstNoon,
      ),
    );

    // Must NOT throw.
    final secondId = await staffDao.addAttendanceReturningId(
      AttendanceTableCompanion.insert(
        staffId: staffId,
        date: secondNoon,
        status: 'present',
        createdAt: secondNoon,
        updatedAt: secondNoon,
      ),
    );
    expect(secondId, greaterThan(0));

    // Both rows survive: no silent data loss.
    final records = await staffDao.getAttendanceByStaff(staffId);
    expect(records, hasLength(2));
    // ...and the date normalisation still holds for both.
    for (final r in records) {
      expect(r.date, DateTime(2026, 1, 14));
    }

    // No UNIQUE index on (staff_id, date) exists.
    final indexes = await staffDao.attachedDatabase.customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'index' "
      "AND name = 'idx_attendance_staff_date'",
    ).get();
    expect(indexes, isEmpty);
  });

  test(
    'check-out past end + grace writes overtime from scheduled end (old rule)',
    () async {
      final staffId = await addStaff(staffDao, 'STAFF0002');
      final deviceId = await addDevice(deviceDao);
      await addMapping(deviceDao, deviceId, staffId, 'UID-002');

      final checkInTime = DateTime(2026, 1, 14, 12, 0);
      final checkOutTime = DateTime(2026, 1, 14, 21, 0); // 9 hours later
      await addRawEvent(
        deviceDao,
        deviceId,
        'UID-002',
        checkInTime,
        'hash-checkin-2',
      );
      await addRawEvent(
        deviceDao,
        deviceId,
        'UID-002',
        checkOutTime,
        'hash-checkout-2',
      );

      final expected = await engine.processCheckOut(
        staffId,
        checkInTime: checkInTime,
        checkOutTime: checkOutTime,
      );

      await syncService.processPendingEvents(deviceId);

      final records = await staffDao.getAttendanceByStaff(staffId);
      expect(records, hasLength(1));
      final record = records.first;
      expect(record.status, expected.status);
      expect(record.workingHours, expected.workingHours);
      expect(record.overtimeHours, expected.overtimeHours);
      // 12:00 → 21:00, end 17:00 + 30 min grace → overtime from 17:00 = 4h
      expect(record.workingHours, 9.0);
      expect(record.overtimeHours, greaterThan(0));
      expect(record.overtimeHours, 4.0);
      expect(record.checkOutTime, checkOutTime);
      expect(record.source, 'device');
      expect(record.sourceDeviceId, deviceId);
      expect(record.rawEventId, isNotNull);
    },
  );

  test(
    'device path and manual path produce identical status and working hours for the same times',
    () async {
      final manualStaff = await addStaff(staffDao, 'STAFF0003');
      final deviceStaff = await addStaff(staffDao, 'STAFF0004');
      final deviceId = await addDevice(deviceDao);
      await addMapping(deviceDao, deviceId, deviceStaff, 'UID-003');

      final manualCheckIn = DateTime(2026, 1, 14, 9);
      final manualCheckOut = DateTime(2026, 1, 14, 17);
      await staffDao.addAttendanceReturningId(
        AttendanceTableCompanion.insert(
          staffId: manualStaff,
          date: DateTime(2026, 1, 14),
          status: 'present',
          checkInTime: Value(manualCheckIn),
          checkOutTime: Value(manualCheckOut),
          workingHours: const Value(8.0),
          overtimeHours: const Value(0.0),
          source: const Value('manual'),
          createdAt: manualCheckIn,
          updatedAt: manualCheckOut,
        ),
      );
      final manualRecord = (await staffDao.getAttendanceOnDate(
        manualStaff,
        DateTime(2026, 1, 14),
      )).single;

      await addRawEvent(
        deviceDao,
        deviceId,
        'UID-003',
        manualCheckIn,
        'hash-manual-dev-1',
      );
      await addRawEvent(
        deviceDao,
        deviceId,
        'UID-003',
        manualCheckOut,
        'hash-manual-dev-2',
      );
      await syncService.processPendingEvents(deviceId);

      final deviceRecords = await staffDao.getAttendanceByStaff(deviceStaff);
      expect(deviceRecords, hasLength(1));
      final deviceRecord = deviceRecords.first;

      expect(
        deviceRecord.status,
        manualRecord.status,
        reason:
            'device and manual paths must compute the same status for the same times',
      );
      expect(
        deviceRecord.workingHours,
        manualRecord.workingHours,
        reason:
            'device and manual paths must compute the same working hours for the same times',
      );
      expect(
        deviceRecord.overtimeHours,
        manualRecord.overtimeHours,
        reason:
            'device and manual paths must compute the same overtime for the same times',
      );
      expect(deviceRecord.source, 'device');
      expect(deviceRecord.sourceDeviceId, deviceId);
      expect(deviceRecord.rawEventId, isNotNull);
    },
  );

  test(
    'processPendingEvents creates check-in and check-out rows for each previously empty day',
    () async {
      final staffId = await addStaff(staffDao, 'STAFF0005');
      final deviceId = await addDevice(deviceDao);
      await addMapping(deviceDao, deviceId, staffId, 'UID-005');

      expect(await staffDao.getAttendanceByStaff(staffId), isEmpty);

      final firstDay = DateTime(2026, 1, 14);
      final firstCheckIn = DateTime(2026, 1, 14, 9);
      final firstCheckOut = DateTime(2026, 1, 14, 17);
      final secondDay = DateTime(2026, 1, 15);
      final secondCheckIn = DateTime(2026, 1, 15, 9);
      final secondCheckOut = DateTime(2026, 1, 15, 17);
      await addRawEvent(
        deviceDao,
        deviceId,
        'UID-005',
        firstCheckIn,
        'hash-multiday-check-in-1',
      );
      await addRawEvent(
        deviceDao,
        deviceId,
        'UID-005',
        firstCheckOut,
        'hash-multiday-check-out-1',
      );
      await addRawEvent(
        deviceDao,
        deviceId,
        'UID-005',
        secondCheckIn,
        'hash-multiday-check-in-2',
      );
      await addRawEvent(
        deviceDao,
        deviceId,
        'UID-005',
        secondCheckOut,
        'hash-multiday-check-out-2',
      );

      await syncService.processPendingEvents(deviceId);

      final records = await staffDao.getAttendanceByStaff(staffId);
      expect(records, hasLength(2));

      final firstDayRecords = await staffDao.getAttendanceOnDate(
        staffId,
        firstDay,
      );
      expect(firstDayRecords, hasLength(1));
      expect(firstDayRecords.single.checkInTime, firstCheckIn);
      expect(firstDayRecords.single.checkOutTime, firstCheckOut);

      final secondDayRecords = await staffDao.getAttendanceOnDate(
        staffId,
        secondDay,
      );
      expect(secondDayRecords, hasLength(1));
      expect(secondDayRecords.single.checkInTime, secondCheckIn);
      expect(secondDayRecords.single.checkOutTime, secondCheckOut);
    },
  );

  test(
    'processPendingEvents does not create check-out less than four hours after check-in',
    () async {
      final staffId = await addStaff(staffDao, 'STAFF0006');
      final deviceId = await addDevice(deviceDao);
      await addMapping(deviceDao, deviceId, staffId, 'UID-006');
      final checkInTime = DateTime(2026, 1, 14, 9);
      await addRawEvent(
        deviceDao,
        deviceId,
        'UID-006',
        checkInTime,
        'hash-short-session-check-in',
      );
      await addRawEvent(
        deviceDao,
        deviceId,
        'UID-006',
        DateTime(2026, 1, 14, 10, 5),
        'hash-short-session-check-out',
      );

      await syncService.processPendingEvents(deviceId);

      final records = await staffDao.getAttendanceByStaff(staffId);
      expect(records, hasLength(1));
      expect(records.single.checkInTime, checkInTime);
      expect(records.single.checkOutTime, isNull);
    },
  );

  test(
    'processPendingEvents converges a late first event with later earlier events',
    () async {
      final staffId = await addStaff(staffDao, 'STAFF0007');
      final deviceId = await addDevice(deviceDao);
      await addMapping(deviceDao, deviceId, staffId, 'UID-007');
      final lateEvent = DateTime(2026, 1, 14, 17);
      final earlyEvent = DateTime(2026, 1, 14, 9);
      final nearEarlyEvent = DateTime(2026, 1, 14, 9, 5);
      await addRawEvent(
        deviceDao,
        deviceId,
        'UID-007',
        lateEvent,
        'hash-convergence-late',
      );

      await syncService.processPendingEvents(deviceId);
      final afterFirstRun = await staffDao.getAttendanceByStaff(staffId);
      expect(afterFirstRun, hasLength(1));
      expect(afterFirstRun.single.checkInTime, lateEvent);
      expect(afterFirstRun.single.checkOutTime, isNull);

      await addRawEvent(
        deviceDao,
        deviceId,
        'UID-007',
        earlyEvent,
        'hash-convergence-early',
      );
      await addRawEvent(
        deviceDao,
        deviceId,
        'UID-007',
        nearEarlyEvent,
        'hash-convergence-near-early',
      );
      await syncService.processPendingEvents(deviceId);

      final records = await staffDao.getAttendanceByStaff(staffId);
      expect(records, hasLength(1));
      expect(records.single.checkInTime, earlyEvent);
      expect(records.single.checkOutTime, lateEvent);
    },
  );

  test(
    'processPendingEvents preserves a later manual check-out and manual source',
    () async {
      final staffId = await addStaff(staffDao, 'STAFF0008');
      final deviceId = await addDevice(deviceDao);
      await addMapping(deviceDao, deviceId, staffId, 'UID-008');
      final checkInTime = DateTime(2026, 1, 14, 9);
      final manualCheckOut = DateTime(2026, 1, 14, 18);
      await staffDao.addAttendanceReturningId(
        AttendanceTableCompanion.insert(
          staffId: staffId,
          date: DateTime(2026, 1, 14),
          status: 'present',
          checkInTime: Value(checkInTime),
          checkOutTime: Value(manualCheckOut),
          source: const Value('manual'),
          createdAt: checkInTime,
          updatedAt: manualCheckOut,
        ),
      );
      await addRawEvent(
        deviceDao,
        deviceId,
        'UID-008',
        DateTime(2026, 1, 14, 17),
        'hash-earlier-device-check-out',
      );

      final result = await syncService.processPendingEvents(deviceId);

      expect(result.matched, 0);
      expect(result.unmatched, 1);
      final records = await staffDao.getAttendanceByStaff(staffId);
      expect(records, hasLength(1));
      expect(records.single.checkInTime, checkInTime);
      expect(records.single.checkOutTime, manualCheckOut);
      expect(records.single.source, 'manual');
    },
  );

  test(
    'processPendingEvents closes a manual check-in from a device event and preserves manual source',
    () async {
      final staffId = await addStaff(staffDao, 'STAFF0009');
      final deviceId = await addDevice(deviceDao);
      await addMapping(deviceDao, deviceId, staffId, 'UID-009');
      final checkInTime = DateTime(2026, 1, 14, 9);
      final checkOutTime = DateTime(2026, 1, 14, 17);
      await staffDao.addAttendanceReturningId(
        AttendanceTableCompanion.insert(
          staffId: staffId,
          date: DateTime(2026, 1, 14),
          status: 'present',
          checkInTime: Value(checkInTime),
          source: const Value('manual'),
          createdAt: checkInTime,
          updatedAt: checkInTime,
        ),
      );
      await addRawEvent(
        deviceDao,
        deviceId,
        'UID-009',
        checkOutTime,
        'hash-manual-check-in-device-check-out',
      );

      await syncService.processPendingEvents(deviceId);

      final records = await staffDao.getAttendanceByStaff(staffId);
      expect(records, hasLength(1));
      expect(records.single.checkInTime, checkInTime);
      expect(records.single.checkOutTime, checkOutTime);
      expect(records.single.source, 'manual');
    },
  );

  test('processPendingEvents preserves an admin override row', () async {
    final staffId = await addStaff(staffDao, 'STAFF0010');
    final deviceId = await addDevice(deviceDao);
    await addMapping(deviceDao, deviceId, staffId, 'UID-010');
    final checkInTime = DateTime(2026, 1, 14, 9);
    final checkOutTime = DateTime(2026, 1, 14, 16);
    await staffDao.addAttendanceReturningId(
      AttendanceTableCompanion.insert(
        staffId: staffId,
        date: DateTime(2026, 1, 14),
        status: 'excused',
        checkInTime: Value(checkInTime),
        checkOutTime: Value(checkOutTime),
        workingHours: const Value(7.0),
        overtimeHours: const Value(0.0),
        notes: const Value('اعتماد مدير'),
        source: const Value('admin_override'),
        overrideReason: const Value('قرار يدوي'),
        createdAt: checkInTime,
        updatedAt: checkOutTime,
      ),
    );
    await addRawEvent(
      deviceDao,
      deviceId,
      'UID-010',
      DateTime(2026, 1, 14, 18),
      'hash-admin-override',
    );

    final result = await syncService.processPendingEvents(deviceId);

    expect(result.matched, 0);
    expect(result.unmatched, 1);
    final record = (await staffDao.getAttendanceOnDate(
      staffId,
      DateTime(2026, 1, 14),
    )).single;
    expect(record.status, 'excused');
    expect(record.checkInTime, checkInTime);
    expect(record.checkOutTime, checkOutTime);
    expect(record.workingHours, 7.0);
    expect(record.overtimeHours, 0.0);
    expect(record.notes, 'اعتماد مدير');
    expect(record.overrideReason, 'قرار يدوي');
    expect(record.source, 'admin_override');
  });

  test('revoked mapping is not replaced as a new employee', () async {
    final staffId = await addStaff(staffDao, 'STAFF0011');
    final deviceId = await addDevice(deviceDao);
    await deviceDao.addMapping(
      StaffBiometricMappingsCompanion.insert(
        staffId: staffId,
        deviceId: deviceId,
        externalUserId: 'UID-011',
        enrollmentStatus: 'revoked',
        createdAt: DateTime(2026, 1, 14),
        updatedAt: DateTime(2026, 1, 14),
      ),
    );
    await addRawEvent(
      deviceDao,
      deviceId,
      'UID-011',
      DateTime(2026, 1, 14, 9),
      'hash-revoked-mapping',
    );

    final result = await syncService.processPendingEvents(deviceId);

    expect(result.matched, 0);
    expect(result.unmatched, 1);
    expect(await staffDao.getStaffCount(), 1);
    expect(await staffDao.getAttendanceByStaff(staffId), isEmpty);
    final rawEvents = await deviceDao.getUnmatchedEvents();
    expect(rawEvents, hasLength(1));
    expect(rawEvents.single.status, 'unmatched');
  });

  test(
    're-enrolling a revoked mapping requeues its unmatched raw event',
    () async {
      final staffId = await addStaff(staffDao, 'STAFF0014');
      final deviceId = await addDevice(deviceDao);
      await deviceDao.addMapping(
        StaffBiometricMappingsCompanion.insert(
          staffId: staffId,
          deviceId: deviceId,
          externalUserId: 'UID-014',
          enrollmentStatus: 'revoked',
          createdAt: DateTime(2026, 1, 14),
          updatedAt: DateTime(2026, 1, 14),
        ),
      );
      final rawEventId = await deviceDao.addRawEvent(
        AttendanceRawEventsCompanion.insert(
          deviceId: deviceId,
          externalUserId: 'UID-014',
          eventTime: DateTime(2026, 1, 14, 9),
          dedupHash: 'hash-revoked-requeue',
          status: 'unmatched',
          matchedStaffId: const Value<String?>('STAFF0013'),
          resultingAttendanceId: const Value<int?>(999),
          errorMessage: const Value<String?>('mapping revoked'),
          createdAt: DateTime(2026, 1, 14),
          processedAt: Value(DateTime(2026, 1, 14, 9, 1)),
        ),
      );

      await db.transaction(() async {
        final mapping = await deviceDao.getMappingRecordByExternalId(
          deviceId,
          'UID-014',
        );
        await deviceDao.updateMapping(
          mapping!.copyWith(
            enrollmentStatus: 'enrolled',
            enrolledAt: Value(DateTime(2026, 1, 14, 9, 2)),
            updatedAt: DateTime(2026, 1, 14, 9, 2),
          ),
        );
        final requeued = await deviceDao.requeueUnmatchedEventsForExternalId(
          deviceId,
          'UID-014',
        );
        expect(requeued, 1);
      });

      final pending = await deviceDao.getUnprocessedEventsForDevice(deviceId);
      expect(pending, hasLength(1));
      expect(pending.single.id, rawEventId);
      expect(pending.single.matchedStaffId, isNull);
      expect(pending.single.resultingAttendanceId, isNull);
      expect(pending.single.errorMessage, isNull);
      expect(pending.single.processedAt, isNull);

      final result = await syncService.processPendingEvents(deviceId);

      expect(result.matched, 1);
      expect(result.unmatched, 0);
      final records = await staffDao.getAttendanceByStaff(staffId);
      expect(records, hasLength(1));
      final rawEvents = await db.select(db.attendanceRawEvents).get();
      final processed = rawEvents.singleWhere((e) => e.id == rawEventId);
      expect(processed.status, 'matched');
      expect(processed.matchedStaffId, staffId);
      expect(processed.resultingAttendanceId, records.single.id);
      expect(processed.errorMessage, isNull);
    },
  );

  test('error raw events are retried on the next processing run', () async {
    final staffId = await addStaff(staffDao, 'STAFF0012');
    final deviceId = await addDevice(deviceDao);
    await addMapping(deviceDao, deviceId, staffId, 'UID-012');
    await deviceDao.addRawEvent(
      AttendanceRawEventsCompanion.insert(
        deviceId: deviceId,
        externalUserId: 'UID-012',
        eventTime: DateTime(2026, 1, 14, 9),
        dedupHash: 'hash-retryable-error',
        status: 'error',
        createdAt: DateTime(2026, 1, 14),
      ),
    );

    final result = await syncService.processPendingEvents(deviceId);

    expect(result.matched, 1);
    expect(result.unmatched, 0);
    expect(await staffDao.getAttendanceByStaff(staffId), hasLength(1));
  });

  test('confirmed empty attendance response remains a valid zero', () async {
    await _withFakeZkServer(
      [_zkReply(ZkCommand.ackOk), _zkReply(ZkCommand.ackOk, replyId: 2)],
      (client) async {
        final records = await client.getAttendanceRecords();
        expect(records, isEmpty);
        expect(client.lastFetchReport?.fetchOk, isTrue);
        expect(client.lastFetchReport?.droppedChunks, 0);
      },
    );
  });

  test('stale acknowledgement cannot satisfy the next command', () async {
    await _withFakeZkServer(
      [
        _zkReply(ZkCommand.ackOk),
        _zkReply(ZkCommand.ackOk),
        _zkReply(ZkCommand.ackOk, replyId: 2),
      ],
      (client) async {
        final records = await client.getAttendanceRecords();
        expect(records, isEmpty);
        expect(client.lastFetchReport?.fetchOk, isTrue);
      },
    );
  });

  test(
    'early device acknowledgement does not become a successful zero',
    () async {
      final size = ByteData(4)..setUint32(0, 80, Endian.little);
      await _withFakeZkServer(
        [
          _zkReply(ZkCommand.ackOk),
          _zkReply(
            ZkCommand.cmdPrepareData,
            payload: size.buffer.asUint8List(),
            replyId: 2,
          ),
          _zkReply(ZkCommand.ackOk, replyId: 2),
        ],
        (client) async {
          await expectLater(
            client.getAttendanceRecords(),
            throwsA(isA<ZkTransportException>()),
          );
        },
      );
    },
  );

  test(
    'unparsed attendance payload is reported instead of silently dropped',
    () async {
      final payload = Uint8List(40);
      ByteData.sublistView(payload).setUint16(0, 7, Endian.little);
      await _withFakeZkServer(
        [
          _zkReply(ZkCommand.ackOk),
          _zkReply(ZkCommand.ackData, payload: payload, replyId: 2),
        ],
        (client) async {
          final records = await client.getAttendanceRecords();
          expect(records, isEmpty);
          expect(client.lastFetchReport?.rawBytes, 40);
          expect(client.lastFetchReport?.droppedChunks, 1);
          expect(client.lastFetchReport?.debugSample, isNotEmpty);
        },
      );
    },
  );

  test('invalid legacy attendance timestamp is reported as a drop', () async {
    final payload = Uint8List(8);
    ByteData.sublistView(payload).setUint16(0, 7, Endian.little);
    await _withFakeZkServer(
      [
        _zkReply(ZkCommand.ackOk),
        _zkReply(ZkCommand.ackData, payload: payload, replyId: 2),
      ],
      (client) async {
        final records = await client.getAttendanceRecords();
        expect(records, isEmpty);
        expect(client.lastFetchReport?.droppedChunks, 1);
      },
    );
  });

  test('40-byte attendance record uses the device layout', () async {
    final timestamp = DateTime(2026, 1, 14, 12);
    final payload = Uint8List(40);
    final view = ByteData.sublistView(payload);
    view.setUint16(0, 7, Endian.little);
    view.setUint8(26, 4);
    view.setUint32(
      27,
      ZkPacketCodec.encodeZkTimestamp(timestamp),
      Endian.little,
    );
    view.setUint8(31, 1);

    await _withFakeZkServer(
      [
        _zkReply(ZkCommand.ackOk),
        _zkReply(ZkCommand.ackData, payload: payload, replyId: 2),
      ],
      (client) async {
        final records = await client.getAttendanceRecords();
        expect(records, hasLength(1));
        expect(records.single.userId, '7');
        expect(records.single.timestamp, timestamp);
        expect(records.single.status, 1);
        expect(records.single.verifyType, 4);
        expect(records.single.eventType, 'check_out');
        expect(client.lastFetchReport?.droppedChunks, 0);
      },
    );
  });

  test(
    'streamed attendance waits for the correlated free-data response',
    () async {
      final timestamp = DateTime(2026, 1, 14, 12);
      final payload = Uint8List(40);
      final view = ByteData.sublistView(payload);
      view.setUint16(0, 7, Endian.little);
      view.setUint8(26, 1);
      view.setUint32(
        27,
        ZkPacketCodec.encodeZkTimestamp(timestamp),
        Endian.little,
      );
      view.setUint8(31, 0);
      final size = ByteData(4)..setUint32(0, payload.length, Endian.little);

      await _withFakeZkServer(
        [
          _zkReply(ZkCommand.ackOk),
          _zkReply(
            ZkCommand.cmdPrepareData,
            payload: size.buffer.asUint8List(),
            replyId: 2,
          ),
          _zkReply(ZkCommand.cmdData, payload: payload, replyId: 2),
          _zkReply(ZkCommand.ackOk, replyId: 2),
          _zkReply(ZkCommand.ackOk, replyId: 3),
        ],
        (client) async {
          final records = await client.getAttendanceRecords();
          expect(records, hasLength(1));
          expect(records.single.userId, '7');
        },
      );
    },
  );

  test('failed free-data response fails the attendance fetch', () async {
    final payload = Uint8List(40);
    ByteData.sublistView(payload).setUint16(0, 7, Endian.little);
    ByteData.sublistView(payload).setUint32(
      27,
      ZkPacketCodec.encodeZkTimestamp(DateTime(2026, 1, 14, 12)),
      Endian.little,
    );
    final size = ByteData(4)..setUint32(0, payload.length, Endian.little);

    await _withFakeZkServer(
      [
        _zkReply(ZkCommand.ackOk),
        _zkReply(
          ZkCommand.cmdPrepareData,
          payload: size.buffer.asUint8List(),
          replyId: 2,
        ),
        _zkReply(ZkCommand.cmdData, payload: payload, replyId: 2),
        _zkReply(ZkCommand.ackOk, replyId: 2),
        _zkReply(ZkCommand.ackError, replyId: 3),
      ],
      (client) async {
        await expectLater(
          client.getAttendanceRecords(),
          throwsA(isA<ZkTransportException>()),
        );
      },
    );
  });
}

Future<T> _withFakeZkServer<T>(
  List<Uint8List> replies,
  Future<T> Function(ZKTecoClient client) action,
) async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final sockets = <Socket>[];
  server.listen((socket) async {
    sockets.add(socket);
    for (final reply in replies) {
      socket.add(reply);
      await socket.flush();
    }
  });

  final client = ZKTecoClient(
    host: InternetAddress.loopbackIPv4.address,
    port: server.port,
    timeout: const Duration(milliseconds: 100),
  );

  try {
    if (!await client.connect()) {
      throw StateError('fake ZKTeco connection failed');
    }
    return await action(client);
  } finally {
    await client.disconnect();
    for (final socket in sockets) {
      socket.destroy();
    }
    await server.close();
  }
}

Uint8List _zkReply(int command, {Uint8List? payload, int replyId = 1}) {
  return ZkPacketCodec.encodeTcpPacket(
    command: command,
    sessionId: 1,
    replyId: replyId,
    payload: payload,
  );
}

Future<String> addStaff(StaffManagementDao staffDao, String staffId) async {
  await staffDao.addStaff(
    StaffTableCompanion.insert(
      staffId: staffId,
      name: 'Test Staff',
      position: 'Cashier',
      employmentType: 'Full',
      basicSalary: 3000,
      hireDate: DateTime.now(),
      status: 'active',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ),
  );
  return staffId;
}

Future<int> addDevice(AttendanceDeviceDao deviceDao) async {
  return deviceDao.addDevice(
    BiometricDevicesCompanion.insert(
      deviceCode: 'BIO-001',
      name: 'Test Device',
      connectionType: 'tcp_ip',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ),
  );
}

Future<void> addMapping(
  AttendanceDeviceDao deviceDao,
  int deviceId,
  String staffId,
  String externalUserId,
) async {
  await deviceDao.addMapping(
    StaffBiometricMappingsCompanion.insert(
      staffId: staffId,
      deviceId: deviceId,
      externalUserId: externalUserId,
      enrollmentStatus: 'enrolled',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ),
  );
}

Future<void> addRawEvent(
  AttendanceDeviceDao deviceDao,
  int deviceId,
  String externalUserId,
  DateTime eventTime,
  String hash,
) async {
  await deviceDao.addRawEvent(
    AttendanceRawEventsCompanion.insert(
      deviceId: deviceId,
      externalUserId: externalUserId,
      eventTime: eventTime,
      dedupHash: hash,
      status: 'pending',
      createdAt: DateTime.now(),
    ),
  );
}

Future<void> insertDefaultAttendanceSettings(AppDatabase appDb) async {
  // نفس القيم الافتراضية المدخلة في migration v48
  final now = DateTime.now();
  final settings = [
    ('default_work_start', '09:00'),
    ('default_work_end', '17:00'),
    ('default_work_days', 'sun,mon,tue,wed,thu'),
    ('default_weekend', 'fri'),
    ('grace_period_minutes', '15'),
    ('overtime_threshold_hours', '8'),
    ('overtime_rate_multiplier', '1.5'),
  ];
  for (final entry in settings) {
    await appDb
        .into(appDb.attendanceSettings)
        .insert(
          AttendanceSettingsCompanion.insert(
            settingKey: entry.$1,
            settingValue: entry.$2,
            createdAt: now,
            updatedAt: now,
          ),
        );
  }
}
