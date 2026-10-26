import '../helpers/license_grant.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/dao/staff_management_dao.dart';
import 'package:pos_offline_desktop/core/models/user_model.dart';
import 'package:pos_offline_desktop/core/services/validation/permission_validator.dart';
import 'package:pos_offline_desktop/services/staff_management_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (MethodCall methodCall) async => '.',
  );

  late AppDatabase db;
  late StaffManagementDao dao;
  late StaffManagementService service;

  setUp(() async {
    grantLicensedModules();
    db = AppDatabase(NativeDatabase.memory());
    dao = StaffManagementDao(db);
    service = StaffManagementService(dao, db);
  });

  tearDown(() async {
    await db.close();
    revokeLicensedModules();
  });

  StaffTableCompanion createStaffCompanion({
    required String staffId,
    required String name,
    String status = 'active',
    bool isActive = true,
  }) {
    final now = DateTime.now();
    return StaffTableCompanion.insert(
      staffId: staffId,
      name: name,
      position: 'محاسب',
      employmentType: 'full_time',
      basicSalary: 5000.0,
      hireDate: now,
      status: status,
      createdAt: now,
      updatedAt: now,
      isActive: Value(isActive),
    );
  }

  group('FEAT-027 — Staff Deletion with Protection & Real-time Refresh', () {
    test('1. deleteStaff soft-deletes staff and excludes them from active lists and count', () async {
      await dao.addStaff(createStaffCompanion(staffId: 'EMP-001', name: 'أحمد محمود'));
      await dao.addStaff(createStaffCompanion(staffId: 'EMP-002', name: 'سارة علي'));

      expect(await dao.getStaffCount(), equals(2));
      final initialList = await dao.getAllStaff();
      expect(initialList.length, equals(2));

      // Perform deletion on EMP-001
      await dao.deleteStaff('EMP-001');

      // 1. Count must decrease to 1
      expect(await dao.getStaffCount(), equals(1));

      // 2. getAllStaff must only contain EMP-002
      final remainingStaff = await dao.getAllStaff();
      expect(remainingStaff.length, equals(1));
      expect(remainingStaff.first.staffId, equals('EMP-002'));

      // 3. watchAllStaff stream must emit the filtered list
      final streamList = await dao.watchAllStaff().first;
      expect(streamList.length, equals(1));
      expect(streamList.first.staffId, equals('EMP-002'));

      // 4. getStaffById still retrieves the soft-deleted record with status='deleted' and isActive=false
      final deletedRecord = await dao.getStaffById('EMP-001');
      expect(deletedRecord, isNotNull);
      expect(deletedRecord!.status, equals('deleted'));
      expect(deletedRecord.isActive, isFalse);
    });

    test('2. deleteStaff unlinks and removes associated biometric mappings', () async {
      await dao.addStaff(createStaffCompanion(staffId: 'EMP-010', name: 'كريم عادل'));

      // Create a biometric mapping for EMP-010
      await db.into(db.staffBiometricMappings).insert(
        StaffBiometricMappingsCompanion.insert(
          deviceId: 1,
          externalUserId: '9901',
          staffId: 'EMP-010',
          enrollmentStatus: 'enrolled',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );

      final mappingBefore = await (db.select(db.staffBiometricMappings)
            ..where((m) => m.staffId.equals('EMP-010')))
          .get();
      expect(mappingBefore.length, equals(1));

      // Delete the employee
      await dao.deleteStaff('EMP-010');

      // Biometric mapping must be deleted
      final mappingAfter = await (db.select(db.staffBiometricMappings)
            ..where((m) => m.staffId.equals('EMP-010')))
          .get();
      expect(mappingAfter, isEmpty);
    });

    test('3. deleteStaff blocks deletion if employee has an open cash custody', () async {
      await dao.addStaff(createStaffCompanion(staffId: 'EMP-020', name: 'طارق حسام'));

      // Insert an open cash custody
      await db.into(db.cashCustodies).insert(
        CashCustodiesCompanion.insert(
          custodyNumber: 'CUST-001',
          staffId: 'EMP-020',
          staffName: 'طارق حسام',
          date: DateTime.now(),
          amount: 1500.0,
          remainingAmount: 1500.0,
          status: const Value('open'),
        ),
      );

      // Attempt deletion -> Expect failure with clear message
      expect(
        () => dao.deleteStaff('EMP-020'),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('لا يمكن حذف الموظف لوجود عهدة مالية مفتوحة مسجلة باسمه'),
          ),
        ),
      );

      // Employee must still exist in getAllStaff
      final staffList = await dao.getAllStaff();
      expect(staffList.any((s) => s.staffId == 'EMP-020'), isTrue);

      // Once the custody is settled, deletion succeeds
      await (db.update(db.cashCustodies)
            ..where((c) => c.custodyNumber.equals('CUST-001')))
          .write(const CashCustodiesCompanion(status: Value('settled')));

      await dao.deleteStaff('EMP-020');
      final staffListAfter = await dao.getAllStaff();
      expect(staffListAfter.any((s) => s.staffId == 'EMP-020'), isFalse);
    });

    test('4. StaffManagementService.deleteStaff validates user permissions', () async {
      await dao.addStaff(createStaffCompanion(staffId: 'EMP-030', name: 'منى جمال'));

      // User without deleteEmployee permission
      final unauthorizedUser = User(
        id: 10,
        username: 'cashier1',
        passwordHash: 'dummy',
        fullName: 'كاشير عادي',
        role: UserRole.cashier,
        customPermissions: const [Permission.viewEmployees],
        createdAt: DateTime.now(),
      );

      expect(
        () => service.deleteStaff(unauthorizedUser, 'EMP-030'),
        throwsA(isA<PermissionException>()),
      );

      // User with deleteEmployee permission
      final authorizedUser = User(
        id: 2,
        username: 'hr_manager',
        passwordHash: 'dummy',
        fullName: 'مدير الموارد البشرية',
        role: UserRole.cashier, // using non-admin role with customPermission
        customPermissions: const [Permission.deleteEmployee, Permission.viewEmployees],
        createdAt: DateTime.now(),
      );

      await service.deleteStaff(authorizedUser, 'EMP-030');
      final all = await dao.getAllStaff();
      expect(all.any((s) => s.staffId == 'EMP-030'), isFalse);
    });
  });
}
