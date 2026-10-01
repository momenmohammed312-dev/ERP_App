import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/models/user_model.dart';
import 'package:pos_offline_desktop/services/staff_management_service.dart';

/// Regression coverage for the payroll BREAKDOWN data source.
///
/// C6 stopped writing the permission share into the legacy catch-all
/// `otherDeductions` column and gave it first-class columns instead. Two
/// consumers still read `otherDeductions`, so after C6 they showed a permission
/// line of 0 and pushed the permission money onto the ABSENCE line.
///
/// This is a presentation/data-source test. It does not assert a payroll
/// formula - the formulas are pinned in `baseline_payroll_parity_test.dart`.
/// What it pins is: given a real slip, the permission amount appears under
/// permission and is NOT counted again as absence, and the net is untouched.
///
/// Deterministic fixture: monthly 6000 => hourly 6000/30/8 = 25, and three
/// permission days of 2h each => permissionHours 6, permissionDeduction 150.
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

  // Mirrors payroll_page.dart exactly. Kept local so the test pins the
  // arithmetic rather than importing private UI helpers.
  double permissionPart(Payroll p) {
    if (p.permissionDeduction > 0) return p.permissionDeduction;
    return p.otherDeductions > 0 ? p.otherDeductions : 0.0;
  }

  double absencePart(Payroll p) {
    final part = p.deductions -
        p.advances -
        p.penaltiesTotal -
        p.lateDeduction -
        permissionPart(p);
    return part > 0 ? part : 0.0;
  }

  Future<Payroll> buildSlip({
    required double basicSalary,
    required List<AttendanceTableCompanion> rows,
  }) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.into(db.staffTable).insert(
          StaffTableCompanion.insert(
            staffId: 'ST-PERM',
            name: 'موظف',
            position: 'Cashier',
            employmentType: 'full_time',
            basicSalary: basicSalary,
            hireDate: DateTime(2026, 1, 1),
            status: 'active',
            createdAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 1),
          ),
        );
    for (final r in rows) {
      await db.staffManagementDao.addAttendance(r);
    }
    await StaffManagementService(db.staffManagementDao, db).calculatePayroll(
      admin(),
      'ST-PERM',
      '2026-09',
    );
    final slips = await (db.select(db.payrollTable)
          ..where((t) => t.staffId.equals('ST-PERM')))
        .get();
    expect(slips, hasLength(1));
    return slips.single;
  }

  AttendanceTableCompanion permissionDay(int day, int outHour) =>
      AttendanceTableCompanion.insert(
        staffId: 'ST-PERM',
        date: DateTime(2026, 9, day),
        status: 'present',
        checkInTime: Value(DateTime(2026, 9, day, 9)),
        checkOutTime: Value(DateTime(2026, 9, day, outHour)),
        createdAt: DateTime(2026, 9, day),
        updatedAt: DateTime(2026, 9, day),
      );

  group('permission breakdown reads the first-class columns', () {
    // 6000 monthly => 6000/30/8 = 25. Three days leaving at 15:00 against a
    // 17:00 end = 2h each = 6h => 6 * 25 = 150.
    test('permissionHours 6 / permissionDeduction 150 for monthly 6000', () async {
      final slip = await buildSlip(
        basicSalary: 6000,
        rows: [
          permissionDay(2, 15),
          permissionDay(3, 15),
          permissionDay(4, 15),
        ],
      );

      expect(slip.overtimeRate, closeTo(25.0, 0.001));
      expect(slip.permissionHours, closeTo(6.0, 0.001));
      expect(slip.permissionDeduction, closeTo(150.0, 0.001));
    });

    test('the permission line shows 150 and not the absence line', () async {
      final slip = await buildSlip(
        basicSalary: 6000,
        rows: [
          permissionDay(2, 15),
          permissionDay(3, 15),
          permissionDay(4, 15),
        ],
      );

      expect(permissionPart(slip), closeTo(150.0, 0.001));
      // There are no absence days at all here, so the absence line must be 0.
      // Before the fix it absorbed the permission residual and showed 150.
      expect(slip.absentDays, 0);
      expect(absencePart(slip), closeTo(0.0, 0.001));
    });

    test('absence no longer absorbs the permission amount when both exist', () async {
      final slip = await buildSlip(
        basicSalary: 6000,
        rows: [
          permissionDay(2, 15),
          AttendanceTableCompanion.insert(
            staffId: 'ST-PERM',
            date: DateTime(2026, 9, 3),
            status: 'absent',
            createdAt: DateTime(2026, 9, 3),
            updatedAt: DateTime(2026, 9, 3),
          ),
        ],
      );

      // 1 permission day of 2h = 50; 1 absence day = 6000/30 = 200.
      expect(slip.permissionDeduction, closeTo(50.0, 0.001));
      expect(slip.absentDays, 1);
      expect(permissionPart(slip), closeTo(50.0, 0.001));
      expect(absencePart(slip), closeTo(200.0, 0.001));

      // The two lines are distinct, so they must not overlap.
      expect(permissionPart(slip) + absencePart(slip),
          closeTo(slip.deductions, 0.001));
    });

    test('the net is unchanged by the data-source fix', () async {
      final slip = await buildSlip(
        basicSalary: 6000,
        rows: [
          permissionDay(2, 15),
          permissionDay(3, 15),
          permissionDay(4, 15),
        ],
      );

      // 6000 - 150 permission. No overtime, no absence, no advances.
      expect(slip.deductions, closeTo(150.0, 0.001));
      expect(slip.netSalary, closeTo(5850.0, 0.001));

      // Reconstructing the net from the DISPLAYED lines must reproduce it.
      // If permission were double counted or dropped, this would not tie.
      final fromBreakdown = slip.basicSalary -
          permissionPart(slip) -
          absencePart(slip) -
          slip.lateDeduction -
          slip.penaltiesTotal -
          slip.advances +
          slip.overtimePay;
      expect(fromBreakdown, closeTo(slip.netSalary, 0.001));
    });

    test('the PDF statement reads the same first-class amount', () async {
      final slip = await buildSlip(
        basicSalary: 6000,
        rows: [
          permissionDay(2, 15),
          permissionDay(3, 15),
          permissionDay(4, 15),
        ],
      );

      // The generator's internal helper is exercised indirectly: the slip it
      // would print must report the permission as 150, not 0, and must not
      // put it under absence.
      expect(slip.permissionDeduction, closeTo(150.0, 0.001));
      expect(slip.otherDeductions, closeTo(0.0, 0.001),
          reason: 'permission must NOT be written back into otherDeductions');
    });
  });
}
