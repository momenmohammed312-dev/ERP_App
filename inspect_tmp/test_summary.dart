import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/database/dao/staff_management_dao.dart';
import 'package:pos_offline_desktop/services/staff_management_service.dart';
import 'package:drift/native.dart';
import 'dart:io';

void main() async {
  final dbPath = r'G:\flutter\Downloads\pos_offline_desktop_database.sqlite';
  final db = AppDatabase(NativeDatabase(File(dbPath)));
  final dao = StaffManagementDao(db);
  final service = StaffManagementService(dao, db);
  final staffId = 'STAFF0061';
  final summary = await service.getAttendanceSummary(staffId, DateTime(2026,8,1), DateTime(2026,8,31,23,59,59));
  print('totalLateMinutes=${summary.totalLateMinutes} totalLateHours=${summary.totalLateHours} totalPermissionHours=${summary.totalPermissionHours} lateDays=${summary.lateDays} present=${summary.presentDays}');
  print('totalEarlyMinutes=${summary.totalEarlyMinutes} totalEarlyExcused=${summary.totalEarlyExcusedMinutes}');
  await db.close();
}
