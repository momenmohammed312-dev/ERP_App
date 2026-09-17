import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/dao/staff_management_dao.dart';
import 'package:pos_offline_desktop/core/models/user_model.dart';
import 'package:pos_offline_desktop/services/staff_management_service.dart';

void main() {
  late AppDatabase db;
  late StaffManagementDao dao;
  late StaffManagementService service;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    dao = StaffManagementDao(db);
    service = StaffManagementService(dao, db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<String> addStaff() async {
    final staffId = 'STAFF0001';
    await dao.addStaff(
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

  test('recordCheckInTodayOnce refuses a second check-in on the same day',
      () async {
    final staffId = await addStaff();

    final first = await service.recordCheckInTodayOnce(staffId);
    expect(first, isTrue);

    final second = await service.recordCheckInTodayOnce(staffId);
    expect(second, isFalse);

    final records = await dao.getAttendanceOnDate(staffId, DateTime.now());
    expect(records.length, 1);
  });

  test('hasAttendanceOnDate reflects existence correctly', () async {
    final staffId = await addStaff();
    final today = DateTime.now();
    final yesterday = today.subtract(const Duration(days: 1));

    expect(await service.hasAttendanceOnDate(staffId, today), isFalse);

    await service.recordCheckInTodayOnce(staffId);
    expect(await service.hasAttendanceOnDate(staffId, today), isTrue);
    expect(await service.hasAttendanceOnDate(staffId, yesterday), isFalse);
  });

  test('deleteAttendanceByDate deletes all records for the day only',
      () async {
    final staffId = await addStaff();
    final today = DateTime.now();

    await service.recordCheckInTodayOnce(staffId);
    expect((await dao.getAttendanceOnDate(staffId, today)).length, 1);

    final deleted = await dao.deleteAttendanceByDate(staffId, today);
    expect(deleted, 1);
    expect(await service.hasAttendanceOnDate(staffId, today), isFalse);

    // A record on a different day is untouched
    await dao.addAttendance(
      AttendanceTableCompanion.insert(
        staffId: staffId,
        date: today.subtract(const Duration(days: 1)),
        status: 'present',
        checkInTime: Value(DateTime.now().subtract(const Duration(hours: 9))),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
    expect(
      (await dao.getAttendanceOnDate(
        staffId,
        today.subtract(const Duration(days: 1)),
      ))
          .length,
      1,
    );
  });

  test('deleteAttendanceDay requires manageAttendance permission', () async {
    final staffId = await addStaff();
    final today = DateTime.now();
    await service.recordCheckInTodayOnce(staffId);

    final admin = User(
      username: 'admin',
      passwordHash: 'x',
      fullName: 'Admin',
      role: UserRole.admin,
      createdAt: DateTime.now(),
    );
    await service.deleteAttendanceDay(admin, staffId, today);
    expect(await service.hasAttendanceOnDate(staffId, today), isFalse);

    final viewer = User(
      username: 'viewer',
      passwordHash: 'x',
      fullName: 'Viewer',
      role: UserRole.cashier,
      createdAt: DateTime.now(),
    );
    await service.recordCheckInTodayOnce(staffId);
    expect(
      () => service.deleteAttendanceDay(viewer, staffId, today),
      throwsException,
    );
  });
}