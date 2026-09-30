import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/models/user_model.dart';
import 'package:pos_offline_desktop/services/staff_management_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (MethodCall methodCall) async => '.',
      );

  User admin() => User(
        username: 'admin',
        passwordHash: 'x',
        fullName: 'Admin',
        role: UserRole.admin,
        createdAt: DateTime(2026, 1, 1),
      );

  late AppDatabase db;
  late StaffManagementService service;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    service = StaffManagementService(db.staffManagementDao, db);

    await db.into(db.staffTable).insert(
          StaffTableCompanion.insert(
            staffId: 'ST-01',
            name: 'أحمد علي',
            position: 'Cashier',
            employmentType: 'full_time',
            basicSalary: 6000,
            hireDate: DateTime(2026, 1, 1),
            status: 'active',
            createdAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 1),
          ),
        );
  });

  tearDown(() => db.close());

  group('Advance period filtering in calculatePayroll', () {
    test('advance from August (month 8) is NOT deducted in September (month 9) payroll', () async {
      // Advance requested and paid in August
      await db.into(db.staffAdvances).insert(
            StaffAdvancesCompanion.insert(
              staffId: 'ST-01',
              amount: 500,
              requestDate: DateTime(2026, 8, 15),
              status: 'approved',
              paymentDate: Value(DateTime(2026, 8, 15)),
              createdAt: DateTime(2026, 8, 15),
              updatedAt: DateTime(2026, 8, 15),
            ),
          );

      await service.calculatePayroll(admin(), 'ST-01', '2026-09');

      final slip = await (db.select(db.payrollTable)
            ..where((t) => t.staffId.equals('ST-01') & t.payrollPeriod.equals('2026-09')))
          .getSingle();

      expect(slip.advances, 0.0);
      expect(slip.netSalary, 6000.0);
    });

    test('advance from September (month 9) IS deducted in September (month 9) payroll', () async {
      await db.into(db.staffAdvances).insert(
            StaffAdvancesCompanion.insert(
              staffId: 'ST-01',
              amount: 500,
              requestDate: DateTime(2026, 9, 5),
              status: 'approved',
              paymentDate: Value(DateTime(2026, 9, 5)),
              createdAt: DateTime(2026, 9, 5),
              updatedAt: DateTime(2026, 9, 5),
            ),
          );

      await service.calculatePayroll(admin(), 'ST-01', '2026-09');

      final slip = await (db.select(db.payrollTable)
            ..where((t) => t.staffId.equals('ST-01') & t.payrollPeriod.equals('2026-09')))
          .getSingle();

      expect(slip.advances, 500.0);
      expect(slip.netSalary, 5500.0);
    });

    test('installment advance covers multiple months accurately', () async {
      // 1500 total, 500 per month for 3 months (August, September, October)
      await db.into(db.staffAdvances).insert(
            StaffAdvancesCompanion.insert(
              staffId: 'ST-01',
              amount: 1500,
              requestDate: DateTime(2026, 8, 1),
              status: 'approved',
              paymentDate: Value(DateTime(2026, 8, 1)),
              installmentMonths: const Value(3),
              monthlyDeduction: const Value(500),
              createdAt: DateTime(2026, 8, 1),
              updatedAt: DateTime(2026, 8, 1),
            ),
          );

      // September is month index 1 of 3 (active)
      await service.calculatePayroll(admin(), 'ST-01', '2026-09');

      final sepSlip = await (db.select(db.payrollTable)
            ..where((t) => t.staffId.equals('ST-01') & t.payrollPeriod.equals('2026-09')))
          .getSingle();

      expect(sepSlip.advances, 500.0);

      // November is month index 3 (0=Aug, 1=Sep, 2=Oct, 3=Nov => expired)
      await service.calculatePayroll(admin(), 'ST-01', '2026-11');

      final novSlip = await (db.select(db.payrollTable)
            ..where((t) => t.staffId.equals('ST-01') & t.payrollPeriod.equals('2026-11')))
          .getSingle();

      expect(novSlip.advances, 0.0);
    });
  });

  group('Attendance regularity bonus (إضافة انتظام)', () {
    test('awarded when employee has 0 absence days', () async {
      // Add present days
      await db.staffManagementDao.addAttendance(
        AttendanceTableCompanion.insert(
          staffId: 'ST-01',
          date: DateTime(2026, 9, 1),
          status: 'present',
          checkInTime: Value(DateTime(2026, 9, 1, 9)),
          checkOutTime: Value(DateTime(2026, 9, 1, 17)),
          createdAt: DateTime(2026, 9, 1),
          updatedAt: DateTime(2026, 9, 1),
        ),
      );

      await service.calculatePayroll(
        admin(),
        'ST-01',
        '2026-09',
        attendanceBonus: 300.0,
      );

      final slip = await (db.select(db.payrollTable)
            ..where((t) => t.staffId.equals('ST-01') & t.payrollPeriod.equals('2026-09')))
          .getSingle();

      expect(slip.bonus, 300.0);
      expect(slip.netSalary, 6300.0);
    });

    test('NOT awarded when employee has absence days', () async {
      // Add an absent day
      await db.staffManagementDao.addAttendance(
        AttendanceTableCompanion.insert(
          staffId: 'ST-01',
          date: DateTime(2026, 9, 2),
          status: 'absent',
          createdAt: DateTime(2026, 9, 2),
          updatedAt: DateTime(2026, 9, 2),
        ),
      );

      await service.calculatePayroll(
        admin(),
        'ST-01',
        '2026-09',
        attendanceBonus: 300.0,
      );

      final slip = await (db.select(db.payrollTable)
            ..where((t) => t.staffId.equals('ST-01') & t.payrollPeriod.equals('2026-09')))
          .getSingle();

      // Attendance bonus is NOT added because of absence
      expect(slip.bonus, 0.0);
    });
  });
}
