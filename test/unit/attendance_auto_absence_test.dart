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

/// أحدث يوم مغلق (قبل اليوم) بواقع يوم أسبوع معيّن.
/// weekday: 7=أحد ... 4=خميس أيام عمل، 5=جمعة، 6=سبت.
DateTime recentPastWeekday(int weekday) {
  var d = DateTime.now().subtract(const Duration(days: 1));
  while (d.weekday != weekday) {
    d = d.subtract(const Duration(days: 1));
  }
  return DateTime(d.year, d.month, d.day);
}

/// مثل [recentPastWeekday] لكن يضمن ألّا يقلّ اليوم المُعاد عن [minDaysAgo] يوم،
/// ليبقى يومه التالي داخل نطاق "الأيام المغلقة".
///
/// [recentPastWeekday] وحدها قد ترجع بأمس، فيصير اليوم التالي هو اليوم الحالي
/// تماماً — والمحرك يقصّ اليوم الحالي عمداً (اليوم مفتوح)، فتفشل التوقعات.
DateTime recentClosedWeekday(int weekday, {int minDaysAgo = 2}) {
  var d = DateTime.now().subtract(Duration(days: minDaysAgo));
  while (d.weekday != weekday) {
    d = d.subtract(const Duration(days: 1));
  }
  return DateTime(d.year, d.month, d.day);
}

class _FakeSource extends AttendanceSource {
  final List<RawAttendanceEvent> events;
  _FakeSource(this.events) : super(deviceIdentifier: 'fake-absence');

  @override
  AttendanceSourceStatus get status => AttendanceSourceStatus.connected;

  @override
  Future<bool> connect() async => true;

  @override
  Future<void> disconnect() async {}

  @override
  Future<List<RawAttendanceEvent>> fetchEvents({DateTime? since}) async {
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

  Future<(AttendanceDeviceDao, StaffManagementDao,
      AttendanceCalculationEngine)> setupDb() async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final deviceDao = AttendanceDeviceDao(db);
    final staffDao = StaffManagementDao(db);
    final engine = AttendanceCalculationEngine(db, deviceDao, staffDao);
    return (deviceDao, staffDao, engine);
  }

  Future<String> addStaff(
    StaffManagementDao dao,
    String staffId,
    String name, {
    DateTime? hireDate,
  }) async {
    final now = DateTime.now();
    await dao.addStaff(
      StaffTableCompanion.insert(
        staffId: staffId,
        name: name,
        position: 'موظف',
        employmentType: 'full_time',
        basicSalary: 1000,
        hireDate: hireDate ?? DateTime(2026, 1, 1),
        status: 'active',
        createdAt: now,
        updatedAt: now,
      ),
    );
    return staffId;
  }

  group('generateAbsencesForRange', () {
    test('creates absents only for missing staff on closed workdays',
        () async {
      final (_, staffDao, engine) = await setupDb();
      final d1 = recentClosedWeekday(DateTime.wednesday);
      final d2 = d1.add(const Duration(days: 1)); // الخميس
      await addStaff(staffDao, 'A', 'حاضر');
      await addStaff(staffDao, 'B', 'غايب');
      final now = DateTime.now();
      // A حاضر في اليوم الأول فقط
      await staffDao.addAttendance(
        AttendanceTableCompanion.insert(
          staffId: 'A',
          date: d1,
          status: 'present',
          checkInTime: Value(DateTime(d1.year, d1.month, d1.day, 8)),
          createdAt: now,
          updatedAt: now,
        ),
      );

      final created = await engine.generateAbsencesForRange(d1, d2);

      // B يومان + A اليوم الثاني = 3
      expect(created, 3);
      final bRows = await staffDao.getAttendanceByStaff('B');
      expect(bRows.length, 2);
      expect(bRows.every((r) => r.status == 'absent'), isTrue);
      expect(
        bRows.every((r) => r.source == 'auto_generated'),
        isTrue,
      );
      final aRows = await staffDao.getAttendanceByStaff('A');
      expect(aRows.length, 2);
      expect(
        aRows.where((r) => r.status == 'present').length,
        1,
        reason: 'سجل الحضور الأصلي لا يُمس',
      );
    });

    test('never touches today or the future', () async {
      final (_, staffDao, engine) = await setupDb();
      await addStaff(staffDao, 'A', 'موظف');
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      final created = await engine.generateAbsencesForRange(
        today.subtract(const Duration(days: 1)),
        today.add(const Duration(days: 5)),
      );

      final rows = await staffDao.getAttendanceByStaff('A');
      expect(
        rows.every((r) => r.date.isBefore(today)),
        isTrue,
        reason: 'لا غياب لليوم المفتوح ولا المستقبل',
      );
      expect(created, rows.length);
    });

    test('skips the weekend', () async {
      final (_, staffDao, engine) = await setupDb();
      await addStaff(staffDao, 'A', 'موظف');
      final friday = recentPastWeekday(DateTime.friday);

      final created =
          await engine.generateAbsencesForRange(friday, friday);

      expect(created, 0, reason: 'الجمعة عطلة افتراضية');
      expect(await staffDao.getAttendanceByStaff('A'), isEmpty);
    });

    test('skips days before hire date', () async {
      final (_, staffDao, engine) = await setupDb();
      final d1 = recentClosedWeekday(DateTime.wednesday);
      final d2 = d1.add(const Duration(days: 1));
      await addStaff(staffDao, 'A', 'جديد', hireDate: d2);

      final created = await engine.generateAbsencesForRange(d1, d2);

      expect(created, 1);
      final rows = await staffDao.getAttendanceByStaff('A');
      expect(rows.single.date, d2);
    });

    test('does not duplicate existing rows (any status)', () async {
      final (_, staffDao, engine) = await setupDb();
      final d1 = recentPastWeekday(DateTime.wednesday);
      await addStaff(staffDao, 'A', 'موظف');
      final now = DateTime.now();
      await staffDao.addAttendance(
        AttendanceTableCompanion.insert(
          staffId: 'A',
          date: d1,
          status: 'absent',
          source: const Value('manual'),
          createdAt: now,
          updatedAt: now,
        ),
      );

      final created = await engine.generateAbsencesForRange(d1, d1);

      expect(created, 0);
      expect((await staffDao.getAttendanceByStaff('A')).length, 1);
    });
  });

  group('absence hook in syncDevice', () {
    test('sync with new punches marks other staff absent on closed days',
        () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final deviceDao = AttendanceDeviceDao(db);
      final staffDao = StaffManagementDao(db);
      final engine = AttendanceCalculationEngine(db, deviceDao, staffDao);
      final d = recentPastWeekday(DateTime.wednesday);
      final punchTime = DateTime(d.year, d.month, d.day, 8, 5);
      final svc = AttendanceSyncService(deviceDao, staffDao, engine,
          sourceFactory: (_) => _FakeSource([
                RawAttendanceEvent(
                  externalUserId: '901',
                  eventTime: punchTime,
                  eventType: 'check_in',
                ),
              ]));
      await addStaff(staffDao, 'B', 'غايب');

      final now = DateTime.now();
      final deviceId = await deviceDao.addDevice(
        BiometricDevicesCompanion.insert(
          deviceCode: 'T-ABS',
          name: 'جهاز',
          connectionType: 'tcp_ip',
          createdAt: now,
          updatedAt: now,
        ),
      );
      final device = (await deviceDao.getDeviceById(deviceId))!;
      final result = await svc.syncDevice(device);

      expect(result.error, isNull);
      expect(result.matched, 1);
      expect(result.info, contains('غياب تلقائي'));
      final bRows = await staffDao.getAttendanceOnDate('B', d);
      expect(bRows.length, 1);
      expect(bRows.first.status, 'absent');
      expect(bRows.first.source, 'auto_generated');
    });
  });
}
