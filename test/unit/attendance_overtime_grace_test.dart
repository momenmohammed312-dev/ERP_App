import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/dao/attendance_device_dao.dart';
import 'package:pos_offline_desktop/core/database/dao/staff_management_dao.dart';
import 'package:pos_offline_desktop/core/models/user_model.dart';
import 'package:pos_offline_desktop/services/attendance/attendance_calculation_engine.dart';
import 'package:pos_offline_desktop/services/staff_management_service.dart';

/// مهلة بدء الوقت الإضافي (overtime_grace_minutes):
/// - الحدود 29/30/31 دقيقة بعد الانصراف
/// - التعديل اليدوي (صريح/تلقائي)
/// - إعادة حساب الفترة (تخطي المعدل يدوياً والمدفوع)
/// - Migration v66 → v67 تبذر المفتاح بأمان
void main() {
  late AppDatabase db;
  late StaffManagementDao dao;
  late StaffManagementService svc;
  late AttendanceCalculationEngine engine;
  late User admin;

  Future<String> addStaff() async {
    final id = 'STAFF${DateTime.now().microsecondsSinceEpoch % 1000000}';
    await dao.addStaff(
      StaffTableCompanion.insert(
        staffId: id,
        name: 'Overtime Tester',
        position: 'Cashier',
        employmentType: 'full_time',
        basicSalary: 9000,
        hireDate: DateTime.now(),
        status: 'active',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
    return id;
  }

  Future<void> setGrace(String minutes) async {
    final existing =
        await (db.select(db.attendanceSettings)
              ..where((s) => s.settingKey.equals('overtime_grace_minutes')))
            .getSingleOrNull();
    final now = DateTime.now();
    if (existing == null) {
      await db
          .into(db.attendanceSettings)
          .insert(
            AttendanceSettingsCompanion.insert(
              settingKey: 'overtime_grace_minutes',
              settingValue: minutes,
              createdAt: now,
              updatedAt: now,
            ),
          );
    } else {
      await db
          .update(db.attendanceSettings)
          .replace(existing.copyWith(settingValue: minutes, updatedAt: now));
    }
  }

  /// انصراف 17:00 + [extraMinutes] مع حضور 09:00.
  Future<double> overtimeAfter(int extraMinutes) async {
    final staffId = await addStaff();
    final schedule = await engine.getScheduleForStaff(staffId);
    final today = DateTime.now();
    final result = engine.calculateAttendance(
      checkInTime: DateTime(today.year, today.month, today.day, 9, 0),
      checkOutTime: DateTime(
        today.year,
        today.month,
        today.day,
        17,
        0,
      ).add(Duration(minutes: extraMinutes)),
      schedule: schedule,
    );
    return result.overtimeHours;
  }

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    dao = StaffManagementDao(db);
    svc = StaffManagementService(dao, db);
    engine = AttendanceCalculationEngine(db, AttendanceDeviceDao(db), dao);
    admin = User(
      username: 'admin',
      passwordHash: 'x',
      fullName: 'Admin',
      role: UserRole.admin,
      createdAt: DateTime.now(),
    );
  });
  tearDown(() async => await db.close());

  group('حدود المهلة (افتراضي 30 دقيقة)', () {
    test('29 دقيقة بعد الانصراف = صفر إضافي', () async {
      expect(await overtimeAfter(29), 0);
    });

    test('30 دقيقة تماماً = صفر إضافي (مقارنة صارمة)', () async {
      expect(await overtimeAfter(30), 0);
    });

    test('31 دقيقة = دقيقة واحدة إضافي', () async {
      expect(await overtimeAfter(31), closeTo(1 / 60, 1e-9));
    });

    test('90 دقيقة = ساعة إضافي', () async {
      expect(await overtimeAfter(90), closeTo(1.0, 1e-9));
    });

    test('بدون صف إعداد = fallback ثلاثون دقيقة', () async {
      // لا نزرع المفتاح — يجب أن تسري القاعدة الجديدة لا الـ15 القديمة
      expect(await overtimeAfter(20), 0);
      expect(await overtimeAfter(45), closeTo(15 / 60, 1e-9));
    });
  });

  group('مهلة مخصصة من الإعدادات', () {
    test('مهلة 15 دقيقة تُحترم عند ضبطها', () async {
      await setGrace('15');
      expect(await overtimeAfter(20), closeTo(5 / 60, 1e-9));
      expect(await overtimeAfter(15), 0);
    });
  });

  group('التعديل اليدوي', () {
    test('قيمة صريحة تُعتمد كما هي', () async {
      final staffId = await addStaff();
      final day = DateTime.now();
      final dateOnly = DateTime(day.year, day.month, day.day);
      await svc.recordManualOverride(
        admin,
        staffId,
        date: dateOnly,
        status: 'present',
        reason: 'اختبار صريح',
        checkInTime: DateTime(day.year, day.month, day.day, 9, 0),
        checkOutTime: DateTime(day.year, day.month, day.day, 17, 10),
        overtimeHours: 2.5,
      );
      final rec = (await dao.getAttendanceOnDate(staffId, dateOnly)).first;
      expect(rec.overtimeHours, 2.5);
      expect(rec.source, 'admin_override');
    });

    test('بدون قيمة صريحة يُعاد الحساب تلقائياً من الأوقات', () async {
      final staffId = await addStaff();
      final day = DateTime.now();
      final dateOnly = DateTime(day.year, day.month, day.day);
      await svc.recordManualOverride(
        admin,
        staffId,
        date: dateOnly,
        status: 'present',
        reason: 'اختبار تلقائي',
        checkInTime: DateTime(day.year, day.month, day.day, 9, 0),
        checkOutTime: DateTime(day.year, day.month, day.day, 18, 0),
      );
      final rec = (await dao.getAttendanceOnDate(staffId, dateOnly)).first;
      // 18:00 = +60 بعد 17:00 ناقص مهلة 30 = 30 دقيقة = 0.5 ساعة
      expect(rec.overtimeHours, closeTo(0.5, 1e-9));
    });
  });

  group('إعادة حساب الفترة', () {
    test('تُعيد الحساب وتتخطى المعدل يدوياً والمدفوع', () async {
      final staffId = await addStaff();
      final day = DateTime.now();
      final d1 = DateTime(day.year, day.month, day.day);
      final d2 = d1.subtract(const Duration(days: 1));
      final d3 = d1.subtract(const Duration(days: 2));

      // سجل عادي بإضافي قديم (كأنه محسوب بقاعدة 15): انصراف 17:20 → نخزن 0.5 يدوياً
      await dao.addAttendance(
        AttendanceTableCompanion.insert(
          staffId: staffId,
          date: d1,
          status: 'present',
          checkInTime: Value(DateTime(d1.year, d1.month, d1.day, 9, 0)),
          checkOutTime: Value(DateTime(d1.year, d1.month, d1.day, 17, 20)),
          overtimeHours: const Value(0.5),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
      // سجل معدل يدوياً — يجب تخطيه
      await dao.addAttendance(
        AttendanceTableCompanion.insert(
          staffId: staffId,
          date: d2,
          status: 'present',
          checkInTime: Value(DateTime(d2.year, d2.month, d2.day, 9, 0)),
          checkOutTime: Value(DateTime(d2.year, d2.month, d2.day, 19, 0)),
          overtimeHours: const Value(9.9),
          source: const Value('admin_override'),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
      // سجل داخل فترة مرتب مدفوع — يجب تخطيه
      await dao.addAttendance(
        AttendanceTableCompanion.insert(
          staffId: staffId,
          date: d3,
          status: 'present',
          checkInTime: Value(DateTime(d3.year, d3.month, d3.day, 9, 0)),
          checkOutTime: Value(DateTime(d3.year, d3.month, d3.day, 18, 0)),
          overtimeHours: const Value(0.7),
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
      await db
          .into(db.payrollTable)
          .insert(
            PayrollTableCompanion.insert(
              staffId: staffId,
              payrollPeriod: '2099-01',
              periodStart: d3.subtract(const Duration(days: 1)),
              periodEnd: d3.add(const Duration(days: 1)),
              basicSalary: 9000,
              netSalary: 9000,
              status: 'paid',
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          );

      final result = await svc.recomputeOvertimeForPeriod(
        admin,
        staffId,
        d3,
        d1,
      );
      expect(result.recomputed, 1);
      expect(result.skipped, 2);

      final r1 = (await dao.getAttendanceOnDate(staffId, d1)).first;
      // 17:20 مع مهلة 30 = صفر
      expect(r1.overtimeHours, 0);
      final r2 = (await dao.getAttendanceOnDate(staffId, d2)).first;
      expect(r2.overtimeHours, 9.9);
      final r3 = (await dao.getAttendanceOnDate(staffId, d3)).first;
      expect(r3.overtimeHours, 0.7);
    });
  });
}
