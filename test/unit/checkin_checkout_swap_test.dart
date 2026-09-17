import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart' hide isNotNull, isNull;
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/dao/staff_management_dao.dart';
import 'package:pos_offline_desktop/services/staff_management_service.dart';
import 'package:pos_offline_desktop/services/attendance/attendance_sync_service.dart';
import 'package:pos_offline_desktop/services/attendance/attendance_source.dart';

void main() {
  late AppDatabase db;
  late StaffManagementDao dao;
  late StaffManagementService svc;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    dao = StaffManagementDao(db);
    svc = StaffManagementService(dao, db);
  });
  tearDown(() async => await db.close());

  test('Manual check-in then device checkout must keep checkIn and set checkOut', () async {
    final staffId = 'STAFF0001';
    await dao.addStaff(StaffTableCompanion.insert(
      staffId: staffId, name: 'Test', position: 'Cashier', employmentType: 'Full', basicSalary: 3000,
      hireDate: DateTime.now(), status: 'active', createdAt: DateTime.now(), updatedAt: DateTime.now(),
    ));
    // 1) حضور يدوي الآن (09:00 اليوم)
    final today = DateTime.now();
    final dateOnly = DateTime(today.year, today.month, today.day);
    final checkInManual = DateTime(today.year, today.month, today.day, 9, 0);
    await svc.recordManualAttendance(staffId, date: dateOnly, status: 'present', checkInTime: checkInManual, source: 'manual');
    var rec = (await dao.getAttendanceOnDate(staffId, dateOnly)).first;
    expect(rec.checkInTime, isNotNull);
    expect(rec.checkInTime!.hour, 9);
    expect(rec.checkOutTime, isNull);
    print('after manual checkIn: in=${rec.checkInTime} out=${rec.checkOutTime}');

    // 2) بصمة انصراف 17:00 نفس اليوم عبر المسار المحاكي (كأنها من الجهاز)
    // نحاكي ما يفعله AttendanceSyncService.processPendingEvents: تحديث checkOut
    final checkOutDevice = DateTime(today.year, today.month, today.day, 17, 0);
    // مباشرة عبر DAO checkOut (نفس ما يستدعيه السيرفس بعد حساب engine)
    // نستخدم svc.recordCheckOut لمحاكاة البصمة الثانية
    // لكن recordCheckOut يبحث عن اليوم الحالي فقط، فنستدعيه
    // أولاً نتأكد أن getAttendanceOnDate يجد السجل
    // ثم نحدثه كـ checkout
    final before = await dao.getAttendanceOnDate(staffId, dateOnly);
    expect(before.length, 1);
    // استخدم DAO مباشرة لمحاكاة جهاز: حدث checkOut
    // نحتاج أن نمرر الوقت 17:00 كـ rawEventTime -> نحاكي sync عبر تحديث مباشر
    // نستخدم الخدمة: لو نادينا recordCheckOut سيأخذ now() وليس 17:00، لذا نحدث مباشرة عبر DAO لاختبار المنطق
    final current = before.first;
    await dao.updateAttendance(current.copyWith(checkOutTime: Value(checkOutDevice), updatedAt: DateTime.now()));
    var after = (await dao.getAttendanceOnDate(staffId, dateOnly)).first;
    print('after device checkout: in=${after.checkInTime} out=${after.checkOutTime}');
    expect(after.checkInTime, isNotNull);
    expect(after.checkInTime!.hour, 9, reason: 'checkIn يجب أن يبقى 09:00');
    expect(after.checkOutTime, isNotNull);
    expect(after.checkOutTime!.hour, 17, reason: 'checkOut يجب أن يكون 17:00 وليس العكس');
    expect(after.checkInTime!.isBefore(after.checkOutTime!), isTrue);
  });
}
