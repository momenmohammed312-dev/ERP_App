import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/dao/staff_management_dao.dart';

void main() {
  late AppDatabase db;
  late StaffManagementDao staffDao;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    staffDao = StaffManagementDao(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('Insert staff works', () async {
    final staffId = 'STAFF0001';
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

    final staff = await staffDao.getStaffById(staffId);
    expect(staff?.name, 'Test Staff');
    expect(staff?.position, 'Cashier');
  });

  test('Update staff info', () async {
    final staffId = 'STAFF0002';
    await staffDao.addStaff(
      StaffTableCompanion.insert(
        staffId: staffId,
        name: 'Old Name',
        position: 'Cashier',
        employmentType: 'Full',
        basicSalary: 3000,
        hireDate: DateTime.now(),
        status: 'active',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    final staff = await staffDao.getStaffById(staffId);
    expect(staff != null, true);

    final updatedStaff = staff!.copyWith(name: 'New Name');
    await staffDao.updateStaff(updatedStaff);

    final finalStaff = await staffDao.getStaffById(staffId);
    expect(finalStaff?.name, 'New Name');
  });
}
