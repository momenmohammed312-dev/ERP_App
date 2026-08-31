import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/services/historical_attendance_import_service.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:drift/native.dart';

void main() {
  group('HistoricalAttendanceImportService - matching', () {
    test('تطابق بعد trim', () async {
      final db = AppDatabase(NativeDatabase.memory());
      await db.staffManagementDao.addStaff(StaffTableCompanion.insert(staffId: 'STAFF0001', name: 'محمد السادات', position: 'موظف', employmentType: 'full_time', basicSalary: 5000, hireDate: DateTime.now(), status: 'active', createdAt: DateTime.now(), updatedAt: DateTime.now()));
      await db.staffManagementDao.addStaff(StaffTableCompanion.insert(staffId: 'STAFF0002', name: 'دنيا خميس', position: 'موظف', employmentType: 'full_time', basicSalary: 5000, hireDate: DateTime.now(), status: 'active', createdAt: DateTime.now(), updatedAt: DateTime.now()));
      final staffList = await db.staffManagementDao.getAllStaff();
      final service = HistoricalAttendanceImportService(db);
      final match = service.matchSheetsToStaff([' محمد السادات ', ' دنيا خميس', 'غير موجود'], staffList);
      expect(match[' محمد السادات ']!.staffId, 'STAFF0001');
      expect(match[' دنيا خميس']!.staffId, 'STAFF0002');
      expect(match['غير موجود'], isNull);
      await db.close();
    });
  });

  group('parse', () {
    test('parseDateCell', () async {
      final db = AppDatabase(NativeDatabase.memory());
      final service = HistoricalAttendanceImportService(db);
      expect(service.parseDateCell('2026-08-01'), DateTime(2026, 8, 1));
      expect(service.parseDateCell(DateTime(2026, 8, 15)), DateTime(2026, 8, 15));
      await db.close();
    });
  });

  group('idempotency', () {
    test('تشغيل مرتين لا يضاعف', () async {
      final db = AppDatabase(NativeDatabase.memory());
      await db.staffManagementDao.addStaff(StaffTableCompanion.insert(staffId: 'STAFF0001', name: 'موظف 1', position: 'موظف', employmentType: 'full_time', basicSalary: 5000, hireDate: DateTime(2026, 8, 1), status: 'active', createdAt: DateTime.now(), updatedAt: DateTime.now()));
      final staff = (await db.select(db.staffTable).get()).first;
      final service = HistoricalAttendanceImportService(db);
      final date = DateTime(2026, 8, 1);
      final rows = [RowParseResult(rowIndex: 3, date: date, checkInTime: DateTime(2026, 8, 1, 8, 28), checkOutTime: DateTime(2026, 8, 1, 17, 0), workingHours: 8.5, status: 'present', error: null, rawPresence: '08:28:00', rawCheckout: '17:00:00')];
      final rep1 = await service.importSheet('موظف 1', staff, rows);
      expect(rep1.imported, 1);
      final rep2 = await service.importSheet('موظف 1', staff, rows);
      expect(rep2.imported, 0);
      expect(rep2.skippedExists, 1);
      final count = await db.select(db.attendanceTable).get();
      expect(count.length, 1);
      await db.close();
    });
  });
}
