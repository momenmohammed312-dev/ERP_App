import 'dart:io';
import 'dart:typed_data';

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
import 'package:pos_offline_desktop/services/attendance/zkteco/zkteco_client.dart';
import 'package:pos_offline_desktop/services/attendance/zkteco/zkteco_packet_codec.dart';

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

RawAttendanceEvent _punch(String id, DateTime t) => RawAttendanceEvent(
      externalUserId: id,
      eventTime: t,
      eventType: 'check_in',
    );

Future<String> _addStaff(
  StaffManagementDao staffDao,
  String staffId,
  String name, {
  double basicSalary = 3000,
  String status = 'active',
  bool isActive = true,
}) async {
  await staffDao.addStaff(
    StaffTableCompanion.insert(
      staffId: staffId,
      name: name,
      position: 'Cashier',
      employmentType: 'Full',
      basicSalary: basicSalary,
      hireDate: DateTime.now(),
      status: status,
      isActive: Value(isActive),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ),
  );
  return staffId;
}

Future<int> _addDevice(
  AttendanceDeviceDao deviceDao, {
  required String deviceCode,
  required String connectionType,
  bool isActive = true,
}) async {
  final now = DateTime.now();
  return deviceDao.addDevice(
    BiometricDevicesCompanion.insert(
      deviceCode: deviceCode,
      name: deviceCode,
      connectionType: connectionType,
      isActive: Value(isActive),
      createdAt: now,
      updatedAt: now,
    ),
  );
}

Future<void> _addMapping(
  AttendanceDeviceDao deviceDao,
  int deviceId,
  String staffId,
  String externalUserId,
) async {
  final now = DateTime.now();
  await deviceDao.addMapping(
    StaffBiometricMappingsCompanion.insert(
      staffId: staffId,
      deviceId: deviceId,
      externalUserId: externalUserId,
      enrollmentStatus: 'enrolled',
      createdAt: now,
      updatedAt: now,
    ),
  );
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
    timeout: const Duration(milliseconds: 500),
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (MethodCall methodCall) async => '.',
  );

  group('BUG-029: Biometric new employee linking & sync', () {
    test(
        '1. Editing auto-created staff name when FILE-IMPORT is first device preserves TCP/IP mapping and records subsequent punches',
        () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final deviceDao = AttendanceDeviceDao(db);
      final staffDao = StaffManagementDao(db);
      final engine = AttendanceCalculationEngine(db, deviceDao, staffDao);

      await _addDevice(
        deviceDao,
        deviceCode: 'FILE-IMPORT',
        connectionType: 'file_import',
        isActive: false,
      );
      await _addDevice(
        deviceDao,
        deviceCode: 'ZK-MAIN',
        connectionType: 'tcp_ip',
        isActive: true,
      );

      final events1 = [_punch('105', DateTime(2026, 10, 20, 9, 0))];
      final fake1 = FakeSource(events: events1);
      final syncService = AttendanceSyncService(deviceDao, staffDao, engine,
          sourceFactory: (_) => fake1);

      final device2 = (await deviceDao.getDeviceById(2))!;
      final result1 = await syncService.syncDevice(device2);
      expect(result1.error, isNull);

      final autoStaff = await (db.select(db.staffTable)
            ..where((t) => t.name.equals('موظف 105')))
          .getSingleOrNull();
      expect(autoStaff, isNotNull);
      expect(autoStaff!.basicSalary, equals(0));

      final mapping1 =
          await deviceDao.getMappingRecordByExternalId(2, '105');
      expect(mapping1, isNotNull);
      expect(mapping1!.staffId, equals(autoStaff.staffId));
      expect(mapping1.enrollmentStatus, equals('enrolled'));

      await (db.update(db.staffTable)
            ..where((t) => t.staffId.equals(autoStaff.staffId)))
          .write(StaffTableCompanion(
        name: const Value('أحمد محمود'),
        updatedAt: Value(DateTime.now()),
      ));

      await syncService.reconcileAndLinkBiometricId(
        staffId: autoStaff.staffId,
        externalUserId: '105',
        staffNameOnDevice: 'أحمد محمود',
        preferredDeviceId: 2,
      );

      final mapping2 =
          await deviceDao.getMappingRecordByExternalId(2, '105');
      expect(mapping2, isNotNull);
      expect(mapping2!.staffId, equals(autoStaff.staffId));
      expect(mapping2.enrollmentStatus, equals('enrolled'));

      final events2 = [_punch('105', DateTime(2026, 10, 20, 17, 0))];
      final fake2 = FakeSource(events: events2);
      final syncService2 = AttendanceSyncService(deviceDao, staffDao, engine,
          sourceFactory: (_) => fake2);
      final device2b = (await deviceDao.getDeviceById(2))!;
      final result2 = await syncService2.syncDevice(device2b);
      expect(result2.matched, equals(1));

      final attendance =
          await staffDao.getAttendanceByStaff(autoStaff.staffId);
      expect(attendance, isNotEmpty);
      final record = attendance.firstWhere(
        (a) => a.date == DateTime(2026, 10, 20),
      );
      expect(record.checkInTime, isNotNull);
      expect(record.checkOutTime, isNotNull);
      expect(record.workingHours, equals(8.0));
    });

    test(
        '2. Linking a newly added named staff to an ID already auto-created as موظف <ID> merges attendance and transfers mapping',
        () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final deviceDao = AttendanceDeviceDao(db);
      final staffDao = StaffManagementDao(db);
      final engine = AttendanceCalculationEngine(db, deviceDao, staffDao);

      await _addDevice(
        deviceDao,
        deviceCode: 'ZK-MAIN',
        connectionType: 'tcp_ip',
        isActive: true,
      );

      final events1 = [_punch('205', DateTime(2026, 10, 21, 9, 10))];
      final fake1 = FakeSource(events: events1);
      final syncService = AttendanceSyncService(deviceDao, staffDao, engine,
          sourceFactory: (_) => fake1);
      final device1 = (await deviceDao.getDeviceById(1))!;
      await syncService.syncDevice(device1);

      final placeholder = await (db.select(db.staffTable)
            ..where((t) => t.name.equals('موظف 205')))
          .getSingleOrNull();
      expect(placeholder, isNotNull);

      await _addStaff(staffDao, 'EMP-205', 'محمد حسن', basicSalary: 4500);

      await syncService.reconcileAndLinkBiometricId(
        staffId: 'EMP-205',
        externalUserId: '205',
        staffNameOnDevice: 'محمد حسن',
      );

      final mapping =
          await deviceDao.getMappingRecordByExternalId(1, '205');
      expect(mapping, isNotNull);
      expect(mapping!.staffId, equals('EMP-205'));

      final placeholderAfter = await (db.select(db.staffTable)
            ..where((t) => t.staffId.equals(placeholder!.staffId)))
          .getSingleOrNull();
      expect(placeholderAfter, isNotNull);
      expect(placeholderAfter!.status, equals('deleted'));
      expect(placeholderAfter.isActive, equals(false));

      final attendanceEmp =
          await staffDao.getAttendanceByStaff('EMP-205');
      expect(attendanceEmp, isNotEmpty);
      final rec = attendanceEmp.firstWhere(
        (a) => a.date == DateTime(2026, 10, 21),
      );
      expect(rec.checkInTime, equals(DateTime(2026, 10, 21, 9, 10)));

      final events2 = [_punch('205', DateTime(2026, 10, 21, 17, 10))];
      final fake2 = FakeSource(events: events2);
      final syncService2 = AttendanceSyncService(deviceDao, staffDao, engine,
          sourceFactory: (_) => fake2);
      final device1b = (await deviceDao.getDeviceById(1))!;
      final result2 = await syncService2.syncDevice(device1b);
      expect(result2.matched, equals(1));
    });

    test(
        '3. Deleting placeholder staff frees biometric mapping and allows re-linking without UNIQUE constraint failure',
        () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final deviceDao = AttendanceDeviceDao(db);
      final staffDao = StaffManagementDao(db);
      final engine = AttendanceCalculationEngine(db, deviceDao, staffDao);

      await _addDevice(
        deviceDao,
        deviceCode: 'ZK-MAIN',
        connectionType: 'tcp_ip',
        isActive: true,
      );

      final events1 = [_punch('305', DateTime(2026, 10, 19, 9, 0))];
      final fake1 = FakeSource(events: events1);
      final syncService = AttendanceSyncService(deviceDao, staffDao, engine,
          sourceFactory: (_) => fake1);
      final device1 = (await deviceDao.getDeviceById(1))!;
      await syncService.syncDevice(device1);

      final placeholder = await (db.select(db.staffTable)
            ..where((t) => t.name.equals('موظف 305')))
          .getSingleOrNull();
      expect(placeholder, isNotNull);

      await staffDao.deleteStaff(placeholder!.staffId);

      final mappingAfterDelete =
          await deviceDao.getMappingRecordByExternalId(1, '305');
      expect(mappingAfterDelete, isNull);

      await _addStaff(staffDao, 'EMP-305', 'رامي عادل');
      await syncService.reconcileAndLinkBiometricId(
        staffId: 'EMP-305',
        externalUserId: '305',
      );

      final events2 = [_punch('305', DateTime(2026, 10, 19, 17, 0))];
      final fake2 = FakeSource(events: events2);
      final syncService2 = AttendanceSyncService(deviceDao, staffDao, engine,
          sourceFactory: (_) => fake2);
      final device1b = (await deviceDao.getDeviceById(1))!;
      final result2 = await syncService2.syncDevice(device1b);
      expect(result2.matched, equals(1));
    });

    test(
        '4. Cross-device mapping: staff linked on FILE-IMPORT is automatically enrolled on TCP/IP device when punching',
        () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final deviceDao = AttendanceDeviceDao(db);
      final staffDao = StaffManagementDao(db);
      final engine = AttendanceCalculationEngine(db, deviceDao, staffDao);

      await _addDevice(
        deviceDao,
        deviceCode: 'FILE-IMPORT',
        connectionType: 'file_import',
        isActive: false,
      );
      await _addDevice(
        deviceDao,
        deviceCode: 'ZK-TCP',
        connectionType: 'tcp_ip',
        isActive: true,
      );

      await _addStaff(staffDao, 'EMP-405', 'سارة علي');
      await _addMapping(deviceDao, 1, 'EMP-405', '405');

      final events = [_punch('405', DateTime(2026, 10, 22, 8, 55))];
      final fake = FakeSource(events: events);
      final syncService = AttendanceSyncService(deviceDao, staffDao, engine,
          sourceFactory: (_) => fake);
      final device2 = (await deviceDao.getDeviceById(2))!;
      final result = await syncService.syncDevice(device2);

      expect(result.matched, equals(1));
      final dup = await (db.select(db.staffTable)
            ..where((t) => t.name.like('موظف 405')))
          .get();
      expect(dup, isEmpty);

      final mapping2 =
          await deviceDao.getMappingRecordByExternalId(2, '405');
      expect(mapping2, isNotNull);
      expect(mapping2!.staffId, equals('EMP-405'));
      expect(mapping2.enrollmentStatus, equals('enrolled'));

      final attendance =
          await staffDao.getAttendanceByStaff('EMP-405');
      expect(attendance, isNotEmpty);
    });

    test(
        '5. Future cursor within 20 minutes (clock drift scenario) is reset so new employee punch is not skipped as 0',
        () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final deviceDao = AttendanceDeviceDao(db);
      final staffDao = StaffManagementDao(db);
      final engine = AttendanceCalculationEngine(db, deviceDao, staffDao);

      await _addDevice(
        deviceDao,
        deviceCode: 'ZK-MAIN',
        connectionType: 'tcp_ip',
        isActive: true,
      );

      await deviceDao.updateDeviceSyncState(
        1,
        lastSyncAt: DateTime.now().add(const Duration(minutes: 25)),
        status: 'success',
      );

      final events = [_punch('505', DateTime.now().subtract(const Duration(minutes: 1)))];
      final fake = FakeSource(events: events);
      final syncService = AttendanceSyncService(deviceDao, staffDao, engine,
          sourceFactory: (_) => fake);
      final device = (await deviceDao.getDeviceById(1))!;
      final result = await syncService.syncDevice(device);

      expect(result.fetched, equals(1));
      expect(result.matched, equals(1));
    });

    test(
        '6. ZKTecoClient.getUsers and fetchAttendanceReport strip 4-byte size prefix without shifting userId to 0',
        () async {
      final users72Payload = Uint8List(144);
      final users72View = ByteData.sublistView(users72Payload);
      users72View.setUint16(0, 1, Endian.little);
      final name1 = 'User1'.codeUnits;
      for (var i = 0; i < name1.length && i < 24; i++) {
        users72Payload[11 + i] = name1[i];
      }
      final userId1 = '101'.codeUnits;
      for (var i = 0; i < userId1.length && i < 24; i++) {
        users72Payload[48 + i] = userId1[i];
      }
      users72View.setUint16(72, 2, Endian.little);
      final name2 = 'NewEmp'.codeUnits;
      for (var i = 0; i < name2.length && i < 24; i++) {
        users72Payload[72 + 11 + i] = name2[i];
      }
      final userId2 = '105'.codeUnits;
      for (var i = 0; i < userId2.length && i < 24; i++) {
        users72Payload[72 + 48 + i] = userId2[i];
      }

      final sizeHeader72 = ByteData(4)..setUint32(0, 144, Endian.little);
      final full72 = Uint8List(148);
      full72.setAll(0, sizeHeader72.buffer.asUint8List());
      full72.setAll(4, users72Payload);

      await _withFakeZkServer(
        [
          _zkReply(ZkCommand.ackOk),
          _zkReply(ZkCommand.ackData, payload: full72, replyId: 2),
        ],
        (client) async {
          final users = await client.getUsers();
          expect(users.length, equals(2));
          expect(users[0].userId, equals('101'));
          expect(users[1].userId, equals('105'));
          expect(users[1].uid, equals(2));
        },
      );

      final users28Payload = Uint8List(28);
      final users28View = ByteData.sublistView(users28Payload);
      users28View.setUint16(0, 3, Endian.little);
      users28View.setUint32(24, 305, Endian.little);

      final sizeHeader28 = ByteData(4)..setUint32(0, 28, Endian.little);
      final full28 = Uint8List(32);
      full28.setAll(0, sizeHeader28.buffer.asUint8List());
      full28.setAll(4, users28Payload);

      await _withFakeZkServer(
        [
          _zkReply(ZkCommand.ackOk),
          _zkReply(ZkCommand.ackData, payload: full28, replyId: 2),
        ],
        (client) async {
          final users = await client.getUsers();
          expect(users.length, equals(1));
          expect(users.single.userId, equals('305'));
        },
      );
    });
  });
}
