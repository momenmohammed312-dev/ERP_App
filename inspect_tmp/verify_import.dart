import 'dart:io';
import 'package:excel/excel.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/services/historical_attendance_import_service.dart';
import 'package:drift/native.dart';

void main() async {
  final dbPath = r'G:\flutter\Documents\pos_offline_desktop_database.sqlite';
  final excelPath = r'G:\flutter\Downloads\attendance_import_filled (1).xlsx';
  final db = AppDatabase(NativeDatabase(File(dbPath)));
  final bytes = File(excelPath).readAsBytesSync();
  final excel = Excel.decodeBytes(bytes);
  print('sheets: ${excel.tables.keys.toList()}');
  final service = HistoricalAttendanceImportService(db);
  final reports = await service.importFromExcel(excel);
  for (final r in reports) {
    print('sheet=${r.sheetName} staff=${r.staff?.name} imported=${r.imported} errors=${r.errors}');
  }
  final rows = await db.select(db.monthlyAttendanceSummaryTable).get();
  print('monthly rows: ${rows.length}');
  for (final row in rows.take(5)) {
    print('${row.staffId} ${row.period} late=${row.lateHours} over=${row.overtimeHours} exc=${row.excusedHours} absent=${row.absentDays}');
  }
  await db.close();
}
