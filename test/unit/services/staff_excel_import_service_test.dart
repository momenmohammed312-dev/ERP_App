import 'dart:io';
import 'package:drift/native.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_offline_desktop/core/database/app_database.dart';
import 'package:pos_offline_desktop/core/services/staff_excel_import_service.dart';
import 'package:drift/drift.dart' show Value;

Future<String> _createExcelFile(List<List<dynamic>> rows) async {
  final excel = Excel.createExcel();
  final sheet = excel['Sheet1'];
  for (final r in rows) {
    sheet.appendRow(r.map((v) => v == null ? null : TextCellValue(v.toString())).toList());
  }
  final bytes = excel.encode()!;
  final file = File('${Directory.systemTemp.path}/test_staff_${DateTime.now().millisecondsSinceEpoch}.xlsx');
  await file.writeAsBytes(bytes);
  return file.path;
}

void main() {
  late AppDatabase db;
  late int deviceId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    // إنشاء جهاز وهمي
    deviceId = await db.attendanceDeviceDao.addDevice(BiometricDevicesCompanion.insert(
      deviceCode: 'TEST-001',
      name: 'Test Device',
      connectionType: 'tcp_ip',
      ipAddress: Value('127.0.0.1'),
      port: Value(4370),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ));
    // موظف موجود مسبقاً لاختبار تكرار staffId
    await db.staffManagementDao.addStaff(StaffTableCompanion.insert(
      staffId: 'STAFF0001',
      name: 'موظف موجود',
      position: 'محاسب',
      employmentType: 'full_time',
      basicSalary: 5000,
      hireDate: DateTime.now(),
      status: 'active',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ));
    // mapping موجود لنفس الجهاز لاختبار تكرار externalId
    await db.attendanceDeviceDao.addMapping(StaffBiometricMappingsCompanion.insert(
      staffId: 'STAFF0001',
      deviceId: deviceId,
      externalUserId: '100',
      enrollmentStatus: 'enrolled',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ));
  });

  tearDown(() async => await db.close());

  test('validation rejects missing required fields', () async {
    final path = await _createExcelFile([
      ['الاسم', 'الوظيفة', 'المرتب الأساسي', 'رقم البصمة', 'كود الموظف'],
      ['', 'محاسب', '5000', '101', ''], // اسم فاضي
      ['أحمد', '', '5000', '102', ''], // وظيفة فاضية
      ['سارة', 'كاشير', '', '103', ''], // مرتب فاضي
      ['محمد', 'عامل', '4000', '', ''], // بصمة فاضية
    ]);
    final service = StaffExcelImportService(db);
    final preview = await service.preview(path, deviceId: deviceId);
    expect(preview.rows.length, 4);
    expect(preview.rows.every((r) => !r.isValid), isTrue);
    expect(preview.validCount, 0);
  });

  test('validation rejects duplicate externalId within file and existing mapping', () async {
    final path = await _createExcelFile([
      ['الاسم', 'الوظيفة', 'المرتب الأساسي', 'رقم البصمة'],
      ['أحمد', 'محاسب', '5000', '200'],
      ['سارة', 'كاشير', '4000', '200'], // مكرر داخل الملف
      ['محمد', 'عامل', '3000', '100'], // موجود مسبقاً في DB لنفس الجهاز
    ]);
    final service = StaffExcelImportService(db);
    final preview = await service.preview(path, deviceId: deviceId);
    expect(preview.rows.length, 3);
    // الأول صالح، الثاني والثالث مرفوضين
    expect(preview.rows[0].isValid, isTrue);
    expect(preview.rows[1].isValid, isFalse);
    expect(preview.rows[1].errors.any((e) => e.contains('مكرر داخل الملف')), isTrue);
    expect(preview.rows[2].isValid, isFalse);
    expect(preview.rows[2].errors.any((e) => e.contains('موجود مسبقاً')), isTrue);
  });

  test('validation rejects duplicate staffId already in DB', () async {
    final path = await _createExcelFile([
      ['الاسم', 'الوظيفة', 'المرتب الأساسي', 'رقم البصمة', 'كود الموظف'],
      ['أحمد', 'محاسب', '5000', '201', 'STAFF0001'], // staffId موجود
      ['سارة', 'كاشير', '4000', '202', 'STAFF9999'], // جديد صالح
    ]);
    final service = StaffExcelImportService(db);
    final preview = await service.preview(path, deviceId: deviceId);
    expect(preview.rows[0].isValid, isFalse);
    expect(preview.rows[1].isValid, isTrue);
  });

  test('import writes only valid rows and reports', () async {
    final path = await _createExcelFile([
      ['الاسم', 'الوظيفة', 'المرتب الأساسي', 'رقم البصمة', 'كود الموظف', 'hireDate'],
      ['أحمد', 'محاسب', '5000', '301', '', '2024-01-15'],
      ['سارة', 'كاشير', '4000', '302', 'STAFF0100', ''],
      ['محمد', 'عامل', '3000', '100', '', ''], // مكرر externalId موجود -> مرفوض
      ['منى', '', '3500', '303', '', ''], // وظيفة فاضية -> مرفوض
      ['خالد', 'سائق', '4500', '304', '', ''],
    ]);
    final service = StaffExcelImportService(db);
    final preview = await service.preview(path, deviceId: deviceId);
    expect(preview.validCount, 3);
    expect(preview.invalidCount, 2);

    final result = await service.import(preview, deviceId: deviceId);
    expect(result.addedStaff, 3);
    expect(result.addedMappings, 3);
    expect(result.errors.length, 2);

    final allStaff = await db.staffManagementDao.getAllStaff();
    // كان فيه 1 موجود + 3 جدد = 4
    expect(allStaff.length, 4);
    final mappings = await db.attendanceDeviceDao.getMappingsForDevice(deviceId);
    // كان فيه 1 + 3 = 4
    expect(mappings.length, 4);
  });
}
