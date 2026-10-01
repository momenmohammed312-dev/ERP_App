import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/models/user_model.dart';
import 'package:pos_offline_desktop/services/attendance/attendance_deduction_calculator.dart';
import 'package:pos_offline_desktop/services/staff_management_service.dart';

/// خصومات الحضور ليها مصدر واحد بس.
///
/// السبب في الـtest ده: كارت الحضور وكشف المرتب كان كل واحد فيهم بيتحسب
/// بصيغته (سعر ساعة مختلف، نقطة بدء التأخير مختلفة، وخصم الإذن موجود في
/// واحد ومش موجود في التاني) — فبيطلع رقمين مختلفين لنفس الموظف ونفس
/// الفترة. الاختبارات دي بتقفل القاعدة الواحدة وتشوف إن الحاجتين اتحسبوا
/// بنفس القيمة.
///
/// **[القواعد المقفولة — معتمدة v72]**
/// * سعر الساعة الشهري = الأساسي ÷ 30 ÷ 8 = الأساسي ÷ 240،
///   أي 41.6667 لراتب 10000. Was ÷ 160 (20 يوم × 8 ساعات) before v72; the
///   divisor and the overtime multiplier must always move together.
/// * التأخير: فترة السماح بتحدد فقط «هل اليوم متأخر؟» — الوصول جوه السماح
///   = مش متأخر. أما لو متأخر، الدقائق بتتحسب من بداية الدوام،
///   يعني 9:20 مع سماح 15 دقيقة = 20 دقيقة، مش 5.
/// * مضاعف التأخير بيتقرأ من `late_penalty_per_hour` ويتحلّد مرة واحدة
///   عبر resolveLateMultiplier() (0 أو غير مضبوط = 1.5)، ونفس القيمة
///   بتستخدمها شاشة الحضور وكشف المرتب.
/// * الإذن الساعي = المدة المتفق عليها × السعر، والمخزّنة في الملاحظات
///   بالصيغة 'من HH:MM إلى HH:MM'.
/// * الغياب = عدد الأيام × أجر اليوم (الأساسي ÷ 30) × المضاعف.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (MethodCall methodCall) async => '.',
      );

  const workStart = 9 * 60;
  const workEnd = 17 * 60;
  const grace = 15;

  final monthly = Staff(
    id: 1,
    staffId: 'ST-1',
    name: 'موظف',
    position: 'Cashier',
    employmentType: 'full_time',
    basicSalary: 10000,
    hireDate: DateTime(2026, 1, 1),
    status: 'active',
    isActive: true,
    useDefaultSchedule: true,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  Attendance row({
    required int day,
    required String status,
    int? inHour,
    int? inMinute,
    int? outHour,
    int? outMinute,
    String? notes,
    String? leaveType,
    bool excused = false,
    double excusedHours = 0.0,
    double permissionHours = 0.0,
    int lateMinutes = 0,
  }) {
    return Attendance(
      id: day,
      staffId: 'ST-1',
      date: DateTime(2026, 9, day),
      status: status,
      checkInTime: inHour == null
          ? null
          : DateTime(2026, 9, day, inHour, inMinute ?? 0),
      checkOutTime: outHour == null
          ? null
          : DateTime(2026, 9, day, outHour, outMinute ?? 0),
      excused: excused,
      excusedHours: excusedHours,
      leaveType: leaveType,
      notes: notes,
      workingHours: 0,
      overtimeHours: 0,
      permissionHours: permissionHours,
      lateMinutes: lateMinutes,
      createdAt: DateTime(2026, 9, day),
      updatedAt: DateTime(2026, 9, day),
    );
  }

  AttendanceDeductionResult compute(List<Attendance> records) {
    return computeAttendanceDeductions(
      records: records,
      staff: monthly,
      weeklyPeriod: false,
      workStartMinutes: workStart,
      workEndMinutes: workEnd,
      graceMinutes: grace,
    );
  }

  group('hourly rate', () {
    test('monthly basic ÷ 240 (30 days × 8h)', () {
      expect(AttendanceDeductionRules.hourlyOf(monthly, weeklyPeriod: false),
          closeTo(10000 / 30 / 8, 0.001));
    });

    test('a stored zero hourlyRate means "unset", not "free"', () {
      final staff = monthly.copyWith(hourlyRate: const Value(0));
      expect(AttendanceDeductionRules.hourlyOf(staff, weeklyPeriod: false),
          closeTo(10000 / 30 / 8, 0.001));
    });

    test('a real hourlyRate wins over the derived one', () {
      final staff = monthly.copyWith(hourlyRate: const Value(80));
      expect(AttendanceDeductionRules.hourlyOf(staff, weeklyPeriod: false), 80);
    });

    test('day wage is basic ÷ 30 for monthly staff', () {
      expect(AttendanceDeductionRules.dayWageOf(monthly, weeklyPeriod: false),
          closeTo(333.333, 0.001));
    });
  });

  group('late minutes — grace decides IF, shift start decides HOW MUCH', () {
    test('9:20 with 15 grace is late and costs 20 minutes', () {
      final r = compute([row(day: 1, status: 'late', inHour: 9, inMinute: 20)]);
      expect(r.totalLateMinutes, 20);
      expect(r.lateDeduction,
          closeTo(20 / 60 * (10000 / 30 / 8) * 1.5, 0.001));
    });

    test('9:10 is inside the grace = 0', () {
      final r = compute([row(day: 1, status: 'late', inHour: 9, inMinute: 10)]);
      expect(r.totalLateMinutes, 0);
      expect(r.lateDeduction, 0);
    });

    test('excused never counts as late', () {
      final r = compute([
        row(day: 1, status: 'excused', inHour: 9, inMinute: 45),
      ]);
      expect(r.totalLateMinutes, 0);
    });
  });

  group('permission / early leave', () {
    test('hourly permission from the notes window is deducted', () {
      final r = compute([
        row(
          day: 1,
          status: 'excused',
          notes: '[إذن شخصي - من 15:00 إلى 16:00]',
        ),
      ]);
      expect(r.totalPermissionMinutes, 60);
      expect(r.permissionDeduction, closeTo(10000 / 30 / 8, 0.001));
    });

    test('early checkout is deducted by the hours actually missed', () {
      final r = compute([
        row(day: 1, status: 'present', inHour: 9, outHour: 15),
      ]);
      expect(r.totalPermissionMinutes, 120);
      expect(r.permissionDeduction, closeTo(2 * (10000 / 30 / 8), 0.001));
    });

    test('a full exempt day deducts nothing', () {
      final r = compute([
        row(day: 1, status: 'excused', notes: '[إذن شخصي - يوم كامل معفي]'),
      ]);
      expect(r.totalPermissionMinutes, 0);
      expect(r.permissionDeduction, 0);
    });

    test('approved leave is never a deduction', () {
      final r = compute([
        row(day: 1, status: 'leave', outHour: 12, leaveType: 'sick'),
      ]);
      expect(r.totalPermissionMinutes, 0);
    });

    test('custom hours permission with deduction is deducted by exact hours', () {
      final r = compute([
        row(
          day: 1,
          status: 'present',
          excused: false,
          excusedHours: 2.5,
          permissionHours: 2.5,
          notes: '[إذن مخصص - مع الخصم - 2.5 ساعة]',
        ),
      ]);
      expect(r.totalPermissionMinutes, 150);
      expect(r.permissionDeduction, closeTo(2.5 * (10000 / 30 / 8), 0.001));
    });

    test('custom hours permission without deduction (approved) deducts nothing', () {
      final r = compute([
        row(
          day: 1,
          status: 'excused',
          excused: true,
          excusedHours: 0.0,
          permissionHours: 3.0,
          notes: '[إذن عام - بدون خصم - 3 ساعات]',
        ),
      ]);
      expect(r.totalPermissionMinutes, 0);
      expect(r.permissionDeduction, 0.0);
    });

    test('custom hours permission parsed from notes when explicit column is 0', () {
      final r = compute([
        row(
          day: 1,
          status: 'present',
          excused: false,
          notes: '[إذن مخصص - مع الخصم - 2 ساعة]',
        ),
      ]);
      expect(r.totalPermissionMinutes, 120);
      expect(r.permissionDeduction, closeTo(2 * (10000 / 30 / 8), 0.001));
    });
  });

  group('absence', () {
    test('day_wage mode: days × basic ÷ 30', () {
      final r = compute([
        row(day: 1, status: 'absent'),
        row(day: 2, status: 'absent'),
        row(day: 3, status: 'absent'),
      ]);
      expect(r.absentDays, 3);
      expect(r.absenceDeduction, closeTo(3 * 10000 / 30, 0.001));
    });

    test('fixed mode with amount 0 legitimately deducts nothing', () {
      final r = computeAttendanceDeductions(
        records: [row(day: 1, status: 'absent')],
        staff: monthly,
        weeklyPeriod: false,
        workStartMinutes: workStart,
        workEndMinutes: workEnd,
        graceMinutes: grace,
        absenceMode: 'fixed',
        fixedAbsenceAmount: 0,
      );
      expect(r.absenceDeduction, 0);
    });
  });

  group('the attendance card and the payroll slip must agree', () {
    late AppDatabase db;
    late User admin;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      await db.into(db.staffTable).insert(
            StaffTableCompanion.insert(
              staffId: 'ST-1',
              name: 'موظف',
              position: 'Cashier',
              employmentType: 'full_time',
              basicSalary: 10000.0,
              hireDate: DateTime(2026, 1, 1),
              status: 'active',
              createdAt: DateTime(2026, 1, 1),
              updatedAt: DateTime(2026, 1, 1),
            ),
          );
      await db.into(db.attendanceSettings).insert(
            AttendanceSettingsCompanion.insert(
              settingKey: 'grace_period_minutes',
              settingValue: '15',
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          );
      await db.into(db.attendanceSettings).insert(
            AttendanceSettingsCompanion.insert(
              settingKey: 'default_work_start',
              settingValue: '09:00',
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          );
      await db.into(db.attendanceSettings).insert(
            AttendanceSettingsCompanion.insert(
              settingKey: 'default_work_end',
              settingValue: '17:00',
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          );
      admin = User(
        username: 'admin',
        passwordHash: 'x',
        fullName: 'Admin',
        role: UserRole.admin,
        createdAt: DateTime(2026, 1, 1),
      );
    });

    tearDown(() async => db.close());

    Future<Payroll> calculate() async {
      await StaffManagementService(db.staffManagementDao, db).calculatePayroll(
        admin,
        'ST-1',
        '2026-09',
      );
      final rows = await (db.select(db.payrollTable)
            ..where((t) => t.staffId.equals('ST-1')))
          .get();
      expect(rows.length, 1);
      return rows.first;
    }

    Future<AttendanceDeductionResult> cardValue() async {
      final records =
          await db.staffManagementDao.getAttendanceByStaff('ST-1');
      return computeAttendanceDeductions(
        records: records,
        staff: monthly,
        weeklyPeriod: false,
        workStartMinutes: workStart,
        workEndMinutes: workEnd,
        graceMinutes: grace,
      );
    }

    test('permission time is now actually deducted from the net', () async {
      // Permission 15:00 → 16:00 = 1 hour × 10000/30/8, plus one absence.
      await db.staffManagementDao.addAttendance(
        AttendanceTableCompanion.insert(
          staffId: 'ST-1',
          date: DateTime(2026, 9, 2),
          status: 'excused',
          notes: const Value('[إذن شخصي - من 15:00 إلى 16:00]'),
          createdAt: DateTime(2026, 9, 2),
          updatedAt: DateTime(2026, 9, 2),
        ),
      );
      await db.staffManagementDao.addAttendance(
        AttendanceTableCompanion.insert(
          staffId: 'ST-1',
          date: DateTime(2026, 9, 3),
          status: 'absent',
          createdAt: DateTime(2026, 9, 3),
          updatedAt: DateTime(2026, 9, 3),
        ),
      );

      final slip = await calculate();
      final card = await cardValue();

      // The slip used to drop permission entirely — the amount was previewed on
      // the attendance card and printed in a PDF column but never subtracted.
      // v72: it lives in its own first-class column, not in otherDeductions.
      const hourly = 10000 / 30 / 8;
      expect(slip.permissionDeduction, closeTo(hourly, 0.001));
      expect(slip.permissionHours, closeTo(1.0, 0.001));
      expect(slip.deductions, closeTo(hourly + 10000 / 30, 0.001));
      expect(slip.netSalary, closeTo(10000 - hourly - 10000 / 30, 0.001));

      expect(card.total, closeTo(slip.deductions, 0.001));
      expect(card.permissionDeduction, closeTo(hourly, 0.001));
    });

    test('late + absence + permission all reconcile', () async {
      await db.staffManagementDao.addAttendance(
        AttendanceTableCompanion.insert(
          staffId: 'ST-1',
          date: DateTime(2026, 9, 2),
          status: 'late',
          checkInTime: Value(DateTime(2026, 9, 2, 9, 20)),
          createdAt: DateTime(2026, 9, 2),
          updatedAt: DateTime(2026, 9, 2),
        ),
      );
      await db.staffManagementDao.addAttendance(
        AttendanceTableCompanion.insert(
          staffId: 'ST-1',
          date: DateTime(2026, 9, 3),
          status: 'present',
          checkInTime: Value(DateTime(2026, 9, 3, 9)),
          checkOutTime: Value(DateTime(2026, 9, 3, 15)),
          createdAt: DateTime(2026, 9, 3),
          updatedAt: DateTime(2026, 9, 3),
        ),
      );
      await db.staffManagementDao.addAttendance(
        AttendanceTableCompanion.insert(
          staffId: 'ST-1',
          date: DateTime(2026, 9, 4),
          status: 'absent',
          createdAt: DateTime(2026, 9, 4),
          updatedAt: DateTime(2026, 9, 4),
        ),
      );

      final slip = await calculate();
      final card = await cardValue();

      expect(card.lateDeduction,
          closeTo(20 / 60 * (10000 / 30 / 8) * 1.5, 0.001));
      expect(card.permissionDeduction, closeTo(2 * (10000 / 30 / 8), 0.001));
      expect(card.absenceDeduction, closeTo(10000 / 30, 0.001));
      expect(card.total, closeTo(slip.deductions, 0.001));
    });
  });
}
