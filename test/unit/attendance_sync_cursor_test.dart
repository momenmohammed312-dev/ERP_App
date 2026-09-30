import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/dao/attendance_device_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/staff_management_dao.dart';
import 'package:pos_offline_desktop/services/attendance/attendance_calculation_engine.dart';
import 'package:pos_offline_desktop/services/attendance/attendance_source.dart';
import 'package:pos_offline_desktop/services/attendance/attendance_sync_service.dart';

/// مصدر وهمي يحاكي فلتر `since` الخاص بالجهاز (isAfter صارم).
class FakeSource extends AttendanceSource {
  final List<RawAttendanceEvent> events;
  final bool connectOk;
  DateTime? lastSince;

  FakeSource({required this.events, this.connectOk = true})
      : super(deviceIdentifier: 'fake-test');

  @override
  AttendanceSourceStatus get status => AttendanceSourceStatus.connected;

  @override
  Future<bool> connect() async => connectOk;

  @override
  Future<void> disconnect() async {}

  @override
  Future<List<RawAttendanceEvent>> fetchEvents({DateTime? since}) async {
    lastSince = since;
    if (since == null) return List.of(events);
    return events.where((e) => e.eventTime.isAfter(since)).toList();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (MethodCall methodCall) async => '.',
      );

  Future<(AppDatabase, AttendanceDeviceDao, AttendanceSyncService, FakeSource,
      int)> setup({
    required List<RawAttendanceEvent> events,
    DateTime? lastSyncAt,
  }) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final deviceDao = AttendanceDeviceDao(db);
    final staffDao = StaffManagementDao(db);
    final engine = AttendanceCalculationEngine(db, deviceDao, staffDao);
    final fake = FakeSource(events: events);
    final svc = AttendanceSyncService(deviceDao, staffDao, engine,
        sourceFactory: (_) => fake);
    final now = DateTime.now();
    final deviceId = await deviceDao.addDevice(
      BiometricDevicesCompanion.insert(
        deviceCode: 'TEST-1',
        name: 'جهاز اختبار',
        connectionType: 'tcp_ip',
        ipAddress: const Value('192.168.1.201'),
        port: const Value(4370),
        createdAt: now,
        updatedAt: now,
      ),
    );
    if (lastSyncAt != null) {
      await deviceDao.updateDeviceSyncState(
        deviceId,
        lastSyncAt: lastSyncAt,
        status: 'success',
      );
    }
    final device = (await deviceDao.getDeviceById(deviceId))!;
    return (db, deviceDao, svc, fake, device.id);
  }

  RawAttendanceEvent punch(String id, DateTime t) => RawAttendanceEvent(
        externalUserId: id,
        eventTime: t,
        eventType: 'check_in',
      );

  group('sync cursor', () {
    test('empty fetch does not advance the cursor', () async {
      final t0 = DateTime(2026, 9, 21, 8);
      final (_, deviceDao, svc, fake, deviceId) =
          await setup(events: const [], lastSyncAt: t0);
      final device =
          (await deviceDao.getDeviceById(deviceId))!;
      final result = await svc.syncDevice(device);

      expect(result.error, isNull);
      expect(result.fetched, 0);
      expect(result.info, isNotNull);
      final after = (await deviceDao.getDeviceById(deviceId))!;
      expect(after.lastSyncAt, t0,
          reason: 'السحب الفارغ لا يحرك الكيرسور');
      expect(fake.lastSince, isNotNull);
    });

    test('poisoned future cursor resets to a full pull', () async {
      final real = DateTime(2026, 9, 26, 12);
      final t1 = DateTime(2026, 9, 22, 8, 5);
      final (_, deviceDao, svc, fake, deviceId) = await setup(
        events: [punch('77', t1)],
        lastSyncAt: real.add(const Duration(days: 2)),
      );
      final device =
          (await deviceDao.getDeviceById(deviceId))!;
      final result = await svc.syncDevice(device);

      expect(result.error, isNull);
      // سحب كامل رغم الكيرسور المسموم
      expect(fake.lastSince, isNull);
      expect(result.fetched, 1);
      expect(result.matched, 1);
      expect(result.info, contains('مسموم'));
      final after = (await deviceDao.getDeviceById(deviceId))!;
      expect(after.lastSyncAt, t1,
          reason: 'الكيرسور = آخر حدث فعلي، لا وقت الحيطة ولا المستقبل');
    });

    test('cursor advances to newest seen event and never moves back', () async {
      final t0 = DateTime(2026, 9, 21, 8);
      final (_, deviceDao, svc, fake, deviceId) = await setup(
        events: [
          punch('77', t0.add(const Duration(hours: 2))),
          punch('77', t0.add(const Duration(hours: 1))),
        ],
        lastSyncAt: t0,
      );
      var device = (await deviceDao.getDeviceById(deviceId))!;
      final first = await svc.syncDevice(device);
      expect(first.matched, 2);
      device = (await deviceDao.getDeviceById(deviceId))!;
      expect(device.lastSyncAt, t0.add(const Duration(hours: 2)));

      // سحب ثانٍ: نافذة الـoverlap (15 دقيقة) تعيد أحدث حدث فقط —
      // يُحتسب مكرراً، والكيرسور ثابت لا يرجع.
      final second = await svc.syncDevice(device);
      expect(second.fetched, 1);
      expect(second.duplicate, 1);
      expect(second.matched, 0);
      device = (await deviceDao.getDeviceById(deviceId))!;
      expect(device.lastSyncAt, t0.add(const Duration(hours: 2)));
      expect(fake.lastSince, isNotNull);
    });

    test('re-pull counts duplicates truthfully and creates nothing new',
        () async {
      final t0 = DateTime(2026, 9, 21, 8);
      final events = [
        punch('77', t0.add(const Duration(hours: 9))),
        punch('77', t0.add(const Duration(hours: 9, minutes: 5))),
      ];
      final (_, deviceDao, svc, _, deviceId) =
          await setup(events: events);
      var device = (await deviceDao.getDeviceById(deviceId))!;
      final first = await svc.syncDevice(device);
      expect(first.matched, 2);

      device = (await deviceDao.getDeviceById(deviceId))!;
      final second = await svc.syncDevice(device);
      expect(second.error, isNull);
      expect(second.duplicate, 2,
          reason: 'نفس البصمات تُحتسب مكررة لا مسجلة');
      expect(second.matched, 0);
    });

    test('resetDeviceSyncCursor nulls the cursor for a full re-pull',
        () async {
      final (_, deviceDao, _, _, deviceId) = await setup(
        events: const [],
        lastSyncAt: DateTime(2026, 9, 21, 8),
      );
      await deviceDao.resetDeviceSyncCursor(deviceId);
      final after = (await deviceDao.getDeviceById(deviceId))!;
      expect(after.lastSyncAt, isNull);
    });

    test('unreachable device reports an actionable Arabic error', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final deviceDao = AttendanceDeviceDao(db);
      final staffDao = StaffManagementDao(db);
      final engine = AttendanceCalculationEngine(db, deviceDao, staffDao);
      final svc = AttendanceSyncService(deviceDao, staffDao, engine,
          sourceFactory: (_) => FakeSource(events: const [], connectOk: false));
      final now = DateTime.now();
      final deviceId = await deviceDao.addDevice(
        BiometricDevicesCompanion.insert(
          deviceCode: 'TEST-9',
          name: 'جهاز وهمي',
          connectionType: 'tcp_ip',
          ipAddress: const Value('192.168.1.201'),
          port: const Value(4370),
          createdAt: now,
          updatedAt: now,
        ),
      );
      final device = (await deviceDao.getDeviceById(deviceId))!;
      final result = await svc.syncDevice(device);
      // connectOk=false → connected=false → detail generic (لا lastError)
      expect(result.error, isNotNull);
      expect(result.fetched, 0);
      final after = (await deviceDao.getDeviceById(deviceId))!;
      expect(after.lastSyncStatus, 'failed');
      // الفشل لا يحرك الكيرسور
      expect(after.lastSyncAt, isNull);
    });
  });
}
